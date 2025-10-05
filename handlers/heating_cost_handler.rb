require 'oj'
require 'date'
require_relative '../lib/electricity_projector'
require_relative '../lib/rent_db'

# HeatingCostHandler calculates the cost impact of changing indoor temperature
# based on intelligent electricity cost projections.
#
# Uses ElectricityProjector (same as RentWidget):
# - Trailing 12-month baseline from RentConfig database
# - Multi-year seasonal patterns
# - Never uses stale data
#
# Configuration (adjust in ENV or defaults):
# - HEATING_FRACTION: Portion of electricity that is heating (default: 0.75)
# - HEATING_DEGREES: Comma-separated degrees to show (default: "-2,-1,1,2")
#
# Roommate count: Dynamically loaded from Tenant table (active tenants)
#
# Formula:
# - Base: Current month projected electricity cost (ElectricityProjector)
# - Heating portion: Base × HEATING_FRACTION
# - Cost change for ±N°C: Heating × (1.05^N - 1)
# - Per person: Cost change / Active roommates
#
# @example API Response
#   GET /api/heating/cost_per_degree
#   {
#     "line": "-2 °C ≈ -466 kr/mån (≈ -117 kr/person); -1 °C ≈ -227 kr/mån (≈ -57 kr/person); +1 °C ≈ +227 kr/mån (≈ +57 kr/person); +2 °C ≈ +466 kr/mån (≈ +117 kr/person)",
#     "details": {
#       "base_monthly_cost": 3120,
#       "heating_cost": 2340,
#       "active_roommates": 4,
#       "source": "ElectricityProjector (trailing 12mo + seasonal)",
#       "config": { "heating_fraction": 0.75, "degrees": [-2, -1, 1, 2] }
#     }
#   }
class HeatingCostHandler
  # Configuration with defaults
  HEATING_FRACTION = (ENV['HEATING_FRACTION'] || 0.75).to_f
  DEGREES = (ENV['HEATING_DEGREES'] || '-2,-1,1,2').split(',').map(&:to_i)

  # Constants from ElectricityStatsHandler
  KWH_TRANSFER_PRICE = (0.09 + 0.392) * 1.25  # Elöverföring + energiskatt + moms
  MONTHLY_FEE = 467 + 39  # Månadsavgift för elnät + elhandel

  def call(req)
    # Get current month for projection
    today = Date.today
    current_year = today.year
    current_month = today.month

    # Use ElectricityProjector (same as RentWidget)
    projector = ElectricityProjector.new
    monthly_cost = projector.project(config_year: current_year, config_month: current_month)

    # Get active roommate count from database
    db = RentDb.instance
    tenants = db.get_tenants

    # Count active tenants (no departure date or future departure)
    active_roommates = tenants.count do |t|
      departure_date = t['departureDate']
      departure_date.nil? || Date.parse(departure_date.to_s) >= today
    end

    # Fallback to default if no active tenants found
    active_roommates = 4 if active_roommates == 0

    # Calculate heating portion
    heating_cost = monthly_cost * HEATING_FRACTION

    # Calculate cost for each degree increment (including negative = savings)
    degree_costs = DEGREES.map do |n|
      factor = 1.05 ** n
      cost_change = (heating_cost * (factor - 1)).round
      per_person = (cost_change / active_roommates.to_f).round

      {
        degrees: n,
        total: cost_change,
        per_person: per_person
      }
    end

    # Generate Swedish one-liner (use ± for positive/negative)
    parts = degree_costs.map do |dc|
      sign = dc[:total] >= 0 ? '+' : ''
      sign_pp = dc[:per_person] >= 0 ? '+' : ''
      "#{sign}#{dc[:degrees]} °C ≈ #{sign}#{dc[:total]} kr/mån (≈ #{sign_pp}#{dc[:per_person]} kr/person)"
    end
    line = parts.join('; ')

    # Prepare response
    response = {
      line: line,
      details: {
        base_monthly_cost: monthly_cost.round,
        heating_cost: heating_cost.round,
        active_roommates: active_roommates,
        source: "ElectricityProjector (#{current_year}-#{sprintf('%02d', current_month)})",
        config: {
          heating_fraction: HEATING_FRACTION,
          degrees: DEGREES
        },
        degree_costs: degree_costs
      }
    }

    [200, { 'Content-Type' => 'application/json' }, [Oj.dump(response)]]
  rescue => e
    error_response = {
      error: e.message,
      line: "Kunde inte beräkna värmekostnad (#{e.message})"
    }
    [500, { 'Content-Type' => 'application/json' }, [Oj.dump(error_response)]]
  end

end

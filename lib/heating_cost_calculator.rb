require 'date'
require_relative 'electricity_projector'
require_relative 'rent_db'

# HeatingCostCalculator provides reusable heating cost calculation logic
# Used by both HeatingCostHandler (API endpoint) and RentCalculatorHandler (friendly message)
module HeatingCostCalculator
  # Configuration with defaults
  HEATING_FRACTION = (ENV['HEATING_FRACTION'] || 0.75).to_f
  DEGREES = (ENV['HEATING_DEGREES'] || '2,-2').split(',').map(&:to_i)

  # Calculate heating cost impact for temperature adjustments
  #
  # @param base_monthly_cost [Integer] Base monthly electricity cost in SEK
  # @param active_roommates [Integer] Number of active roommates
  # @return [Hash] Heating cost data including one-liner and details
  def self.calculate(base_monthly_cost:, active_roommates:)
    # Calculate heating portion
    heating_cost = base_monthly_cost * HEATING_FRACTION

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

    # Generate Swedish one-liner with pedagogical language
    parts = degree_costs.map do |dc|
      if dc[:degrees] > 0
        # Positive = cost increase
        "#{dc[:degrees]} °C varmare skulle kosta #{dc[:total]} kr/mån (#{dc[:per_person]} kr/person)"
      else
        # Negative = savings
        "#{dc[:degrees].abs} °C kallare skulle spara #{dc[:total].abs} kr/mån (#{dc[:per_person].abs} kr/person)"
      end
    end
    line = parts.join('; ')

    {
      line: line,
      details: {
        base_monthly_cost: base_monthly_cost.round,
        heating_cost: heating_cost.round,
        active_roommates: active_roommates,
        config: {
          heating_fraction: HEATING_FRACTION,
          degrees: DEGREES
        },
        degree_costs: degree_costs
      }
    }
  end

  # Get active roommate count from database
  #
  # @param db [RentDb] Database instance (optional, defaults to RentDb.instance)
  # @param date [Date] Reference date for active check (optional, defaults to today)
  # @return [Integer] Number of active roommates (minimum 1)
  def self.get_active_roommate_count(db: RentDb.instance, date: Date.today)
    tenants = db.get_tenants

    # Count active tenants (no departure date or future departure)
    active_roommates = tenants.count do |t|
      departure_date = t['departureDate']
      departure_date.nil? || Date.parse(departure_date.to_s) >= date
    end

    # Fallback to default if no active tenants found
    active_roommates == 0 ? 4 : active_roommates
  end

  # Get current month electricity cost projection
  #
  # @param year [Integer] Configuration year
  # @param month [Integer] Configuration month
  # @param projector [ElectricityProjector] Projector instance (optional)
  # @return [Integer] Projected monthly cost in SEK
  def self.get_electricity_projection(year:, month:, projector: nil)
    projector ||= ElectricityProjector.new
    projector.project(config_year: year, config_month: month)
  end
end

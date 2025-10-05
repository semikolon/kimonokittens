require 'oj'
require 'date'

# HeatingCostHandler calculates the cost impact of increasing indoor temperature
# based on actual current electricity consumption and spot prices.
#
# Uses the same data sources as ElectricityStatsHandler:
# - electricity_usage.json (hourly kWh consumption)
# - tibber_price_data.json (spot prices per hour)
#
# Configuration (adjust in ENV or defaults):
# - HEATING_ROOMMATES: Number of roommates to split cost (default: 6)
# - HEATING_FRACTION: Portion of electricity that is heating (default: 0.75)
# - HEATING_DEGREES: Comma-separated degrees to show (default: "1,2")
#
# Formula:
# - Base: Current month projected total electricity cost
# - Heating portion: Base × HEATING_FRACTION
# - Extra cost for +N°C: Heating × (1.05^N - 1)
# - Per person: Extra cost / HEATING_ROOMMATES
#
# @example API Response
#   GET /api/heating/cost_per_degree
#   {
#     "line": "+1 °C ≈ +234 kr/mån (≈ +39 kr/person); +2 °C ≈ +481 kr/mån (≈ +80 kr/person)",
#     "details": {
#       "base_monthly_cost": 3120,
#       "heating_cost": 2340,
#       "source": "Rullande 30 dagar (2025-10-05)",
#       "config": { "roommates": 6, "heating_fraction": 0.75, "degrees": [1, 2] }
#     }
#   }
class HeatingCostHandler
  # Configuration with defaults
  ROOMMATES = (ENV['HEATING_ROOMMATES'] || 6).to_i
  HEATING_FRACTION = (ENV['HEATING_FRACTION'] || 0.75).to_f
  DEGREES = (ENV['HEATING_DEGREES'] || '1,2').split(',').map(&:to_i)

  # Constants from ElectricityStatsHandler
  KWH_TRANSFER_PRICE = (0.09 + 0.392) * 1.25  # Elöverföring + energiskatt + moms
  MONTHLY_FEE = 467 + 39  # Månadsavgift för elnät + elhandel

  def call(req)
    # Calculate current monthly cost (same logic as ElectricityStatsHandler)
    monthly_cost = calculate_monthly_cost

    # Calculate heating portion
    heating_cost = monthly_cost * HEATING_FRACTION

    # Calculate cost for each degree increment
    degree_costs = DEGREES.map do |n|
      factor = 1.05 ** n
      extra_cost = (heating_cost * (factor - 1)).round
      per_person = (extra_cost / ROOMMATES.to_f).round

      {
        degrees: n,
        extra_total: extra_cost,
        per_person: per_person
      }
    end

    # Generate Swedish one-liner
    parts = degree_costs.map do |dc|
      "+#{dc[:degrees]} °C ≈ +#{dc[:extra_total]} kr/mån (≈ +#{dc[:per_person]} kr/person)"
    end
    line = parts.join('; ')

    # Prepare response
    response = {
      line: line,
      details: {
        base_monthly_cost: monthly_cost.round,
        heating_cost: heating_cost.round,
        source: "Rullande 30 dagar (#{Date.today.strftime('%Y-%m-%d')})",
        config: {
          roommates: ROOMMATES,
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
      line: "Kunde inte beräkna värmekostnad (data saknas)"
    }
    [500, { 'Content-Type' => 'application/json' }, [Oj.dump(error_response)]]
  end

  private

  # Calculate current monthly electricity cost using rolling 30-day average
  # (Same approach as ElectricityStatsHandler but focused on rolling average)
  def calculate_monthly_cost
    electricity_usage = Oj.load_file('electricity_usage.json')
    tibber_prices = Oj.load_file('tibber_price_data.json')

    avg_price_per_kwh = tibber_prices.values.sum / tibber_prices.count

    # Calculate cost for each hour
    all_hours = electricity_usage.map do |hour|
      consumption = hour['consumption'] || 0.0
      price_per_kwh = tibber_prices[hour['date']] || avg_price_per_kwh
      price_per_kwh = price_per_kwh + KWH_TRANSFER_PRICE
      consumption * price_per_kwh
    end

    # Use rolling 30-day average (more seasonally relevant than month-to-date)
    # Take last 30 days of complete data
    complete_days = electricity_usage
      .group_by { |h| Date.parse(h['date']).strftime('%Y-%m-%d') }
      .select { |_, hours| hours.count == 24 }  # Only complete days
      .to_a
      .last(30)

    if complete_days.empty?
      raise "No complete daily electricity data available"
    end

    # Calculate average daily cost from last 30 complete days
    daily_costs = complete_days.map do |date, hours|
      hours_data = electricity_usage.select { |h| Date.parse(h['date']).strftime('%Y-%m-%d') == date }
      hours_data.sum do |hour|
        consumption = hour['consumption'] || 0.0
        price_per_kwh = tibber_prices[hour['date']] || avg_price_per_kwh
        price_per_kwh = price_per_kwh + KWH_TRANSFER_PRICE
        consumption * price_per_kwh
      end
    end

    avg_daily_cost = daily_costs.sum / daily_costs.size.to_f

    # Project to full month (30 days) + monthly fees
    (avg_daily_cost * 30) + MONTHLY_FEE
  end
end

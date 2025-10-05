require 'oj'
require 'date'
require_relative '../lib/heating_cost_calculator'

# HeatingCostHandler provides API endpoint for heating cost calculations
#
# Uses HeatingCostCalculator module for core logic (shared with RentCalculatorHandler)
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
  def call(req)
    # Get current month for projection
    today = Date.today
    current_year = today.year
    current_month = today.month

    # Get electricity projection for current month
    monthly_cost = HeatingCostCalculator.get_electricity_projection(
      year: current_year,
      month: current_month
    )

    # Get active roommate count
    active_roommates = HeatingCostCalculator.get_active_roommate_count(date: today)

    # Calculate heating costs using shared module
    result = HeatingCostCalculator.calculate(
      base_monthly_cost: monthly_cost,
      active_roommates: active_roommates
    )

    # Add source info to details
    result[:details][:source] = "ElectricityProjector (#{current_year}-#{sprintf('%02d', current_month)})"

    # Convert symbol keys to string keys for JSON
    response = {
      'line' => result[:line],
      'details' => {
        'base_monthly_cost' => result[:details][:base_monthly_cost],
        'heating_cost' => result[:details][:heating_cost],
        'active_roommates' => result[:details][:active_roommates],
        'source' => result[:details][:source],
        'config' => {
          'heating_fraction' => result[:details][:config][:heating_fraction],
          'degrees' => result[:details][:config][:degrees]
        },
        'degree_costs' => result[:details][:degree_costs].map do |dc|
          {
            'degrees' => dc[:degrees],
            'total' => dc[:total],
            'per_person' => dc[:per_person]
          }
        end
      }
    }

    [200, { 'Content-Type' => 'application/json' }, [response.to_json]]
  rescue => e
    error_response = {
      'error' => e.message,
      'line' => "Kunde inte beräkna värmekostnad (#{e.message})"
    }
    [500, { 'Content-Type' => 'application/json' }, [error_response.to_json]]
  end
end

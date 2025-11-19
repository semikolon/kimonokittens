require 'oj'
require 'date'
require_relative '../lib/electricity_projector'

# Heatpump Schedule Price API
# Provides Tibber-compatible electricity prices with peak/off-peak grid rates
# Designed for Node-RED ps-strategy-lowest-price consumption
#
# Created: November 17, 2025
# Purpose: Replace invalid Tibber API with elprisetjustnu.se + peak/off-peak logic
# Related: docs/HEATPUMP_SCHEDULE_API_PLAN.md, docs/NODE_RED_TIBBER_TO_ELPRISET_MIGRATION.md
#
# ARCHITECTURE: Reuses ElectricityProjector for all pricing logic (DRY principle)
#   - Constants: GRID_TRANSFER_*, ENERGY_TAX_EXCL_VAT (from ElectricityProjector)
#   - Swedish holidays calculation: ElectricityProjector#swedish_holidays
#   - Peak hour detection: ElectricityProjector#is_peak_hour?
#   - Price formula: (spot + grid + tax) × VAT (ElectricityProjector lines 283-288)

class HeatpumpPriceHandler
  def initialize(electricity_price_handler)
    @electricity_price_handler = electricity_price_handler
    @projector = ElectricityProjector.new
  end

  def call(env)
    # Fetch spot prices from elprisetjustnu.se API
    status, headers, body = @electricity_price_handler.call(env)
    return [status, headers, body] unless status == 200

    price_data = Oj.load(body.first)
    spot_prices = price_data['prices'] || []

    # Calculate total price for each hour (spot + grid + tax + VAT)
    # Reuses ElectricityProjector#is_peak_hour? for peak detection
    calculated_prices = spot_prices.map do |hour|
      timestamp = hour['time_start']
      spot_price = hour['price_sek']  # Excludes VAT from elprisetjustnu.se

      # Determine peak/off-peak grid rate using ElectricityProjector logic
      is_peak = @projector.send(:is_peak_hour?, timestamp)
      grid_rate = is_peak ?
        ElectricityProjector::GRID_TRANSFER_PEAK_EXCL_VAT :
        ElectricityProjector::GRID_TRANSFER_OFFPEAK_EXCL_VAT

      # Calculate components (matching Tibber format)
      # energy: spot price only
      # tax: grid transfer + energy tax
      # total: (energy + tax) × VAT
      energy = spot_price
      tax = grid_rate + ElectricityProjector::ENERGY_TAX_EXCL_VAT
      total = (energy + tax) * 1.25  # VAT multiplier

      {
        'total' => total.round(4),
        'energy' => energy.round(4),
        'tax' => tax.round(4),
        'startsAt' => timestamp  # Keep full ISO 8601 with timezone
      }
    end

    # Split into today and tomorrow arrays (matching Tibber structure)
    now = Time.now
    today_start = Time.new(now.year, now.month, now.day, 0, 0, 0, now.utc_offset)
    tomorrow_start = today_start + (24 * 60 * 60)
    day_after_start = tomorrow_start + (24 * 60 * 60)

    today_prices = calculated_prices.select do |p|
      t = Time.parse(p['startsAt'])
      t >= today_start && t < tomorrow_start
    end

    tomorrow_prices = calculated_prices.select do |p|
      t = Time.parse(p['startsAt'])
      t >= tomorrow_start && t < day_after_start
    end

    # Tibber-compatible nested structure
    response = {
      'viewer' => {
        'homes' => [{
          'currentSubscription' => {
            'priceInfo' => {
              'today' => today_prices,
              'tomorrow' => tomorrow_prices
            }
          }
        }]
      }
    }

    [200, { 'Content-Type' => 'application/json' }, [ Oj.dump(response) ]]
  end
end

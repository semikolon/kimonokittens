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

  def call(req)
    # Fetch spot prices from elprisetjustnu.se API
    status, headers, body = @electricity_price_handler.call(req)
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

      # Calculate total price: (spot + grid + tax) × VAT
      # Same formula as ElectricityProjector#project_from_consumption_and_pricing (lines 283-288)
      total_excl_vat = spot_price + grid_rate + ElectricityProjector::ENERGY_TAX_EXCL_VAT
      total_incl_vat = total_excl_vat * 1.25  # VAT multiplier

      {
        'startsAt' => timestamp,              # ISO 8601 timestamp
        'total' => total_incl_vat.round(4),   # Final price incl VAT
        'breakdown' => {
          'spot' => spot_price.round(4),
          'grid' => grid_rate,
          'tax' => ElectricityProjector::ENERGY_TAX_EXCL_VAT,
          'isPeak' => is_peak
        }
      }
    end

    response = {
      'region' => 'SE3',
      'prices' => calculated_prices,
      'generated_at' => Time.now.utc.iso8601,
      'generated_timestamp' => Time.now.to_i
    }

    [200, { 'Content-Type' => 'application/json' }, [ Oj.dump(response) ]]
  end
end

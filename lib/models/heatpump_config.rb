# HeatpumpConfig domain model
#
# Represents heatpump schedule configuration parameters
# Used by schedule generation and override logic
#
# @attr id [String] Unique identifier
# @attr hours_on [Integer] Hours per day to run (5-22)
# @attr max_price [Float] Maximum electricity price threshold (kr/kWh, 1.5-3.0)
# @attr emergency_temp_offset [Float] Temperature offset below target (°C, 0.5-5.0) - emergency override
# @attr min_hotwater [Float] Minimum hot water temperature (°C, 35-50) - emergency override
# @attr created_at [Time] Creation timestamp
# @attr updated_at [Time] Last update timestamp
#
class HeatpumpConfig
  attr_reader :id, :hours_on, :max_price, :emergency_temp_offset, :min_hotwater,
              :created_at, :updated_at

  def initialize(
    id:,
    hours_on:,
    max_price:,
    emergency_temp_offset:,
    min_hotwater:,
    created_at:,
    updated_at:
  )
    @id = id
    @hours_on = hours_on
    @max_price = max_price
    @emergency_temp_offset = emergency_temp_offset
    @min_hotwater = min_hotwater
    @created_at = created_at
    @updated_at = updated_at
  end

  # Convert to hash for API responses
  # @return [Hash]
  def to_h
    {
      id: @id,
      hours_on: @hours_on,
      max_price: @max_price,
      emergency_temp_offset: @emergency_temp_offset,
      min_hotwater: @min_hotwater,
      created_at: @created_at,
      updated_at: @updated_at
    }
  end

  # Validate configuration parameters
  # @param params [Hash] Parameters to validate
  # @return [Array<String>] Array of error messages (empty if valid)
  def self.validate(params)
    errors = []

    if params[:hours_on]
      errors << "hours_on must be between 5 and 22" unless (5..22).cover?(params[:hours_on])
    end

    if params[:max_price]
      errors << "max_price must be between 1.5 and 3.0" unless (1.5..3.0).cover?(params[:max_price])
    end

    if params[:emergency_temp_offset]
      errors << "emergency_temp_offset must be between 0.5 and 5.0" unless (0.5..5.0).cover?(params[:emergency_temp_offset])
    end

    if params[:min_hotwater]
      errors << "min_hotwater must be between 35.0 and 50.0" unless (35.0..50.0).cover?(params[:min_hotwater])
    end

    errors
  end
end

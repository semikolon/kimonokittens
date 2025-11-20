# HeatpumpConfig domain model
#
# Represents heatpump schedule configuration parameters
# Used by schedule generation and override logic
#
# @attr id [String] Unique identifier
# @attr hours_on [Integer] Hours per day to run (5-22)
# @attr max_price [Float] Maximum electricity price threshold (kr/kWh, 1.5-3.0)
# @attr min_temp [Float] Minimum indoor temperature (°C, 15-23) - emergency override
# @attr min_hotwater [Float] Minimum hot water temperature (°C, 35-50) - emergency override
# @attr emergency_price [Float] Emergency price threshold (kr/kWh, 0.1-1.0) - force ON below this
# @attr created_at [Time] Creation timestamp
# @attr updated_at [Time] Last update timestamp
#
class HeatpumpConfig
  attr_reader :id, :hours_on, :max_price, :min_temp, :min_hotwater,
              :emergency_price, :created_at, :updated_at

  def initialize(
    id:,
    hours_on:,
    max_price:,
    min_temp:,
    min_hotwater:,
    emergency_price:,
    created_at:,
    updated_at:
  )
    @id = id
    @hours_on = hours_on
    @max_price = max_price
    @min_temp = min_temp
    @min_hotwater = min_hotwater
    @emergency_price = emergency_price
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
      min_temp: @min_temp,
      min_hotwater: @min_hotwater,
      emergency_price: @emergency_price,
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

    if params[:min_temp]
      errors << "min_temp (indoor) must be between 15.0 and 23.0" unless (15.0..23.0).cover?(params[:min_temp])
    end

    if params[:min_hotwater]
      errors << "min_hotwater must be between 35.0 and 50.0" unless (35.0..50.0).cover?(params[:min_hotwater])
    end

    if params[:emergency_price]
      errors << "emergency_price must be between 0.1 and 1.0" unless (0.1..1.0).cover?(params[:emergency_price])
    end

    errors
  end
end

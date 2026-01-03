# HeatpumpConfig domain model
#
# Represents heatpump schedule configuration parameters
# Used by schedule generation and override logic
#
# @attr id [String] Unique identifier
# @attr hours_on [Integer] Hours per day to run (5-22)
# @attr emergency_temp_offset [Float] Temperature offset below target (°C, 0.5-5.0) - emergency override
# @attr min_hotwater [Float] Minimum hot water temperature (°C, 35-50) - emergency override
# @attr block_distribution [Array<Integer>] Per-block minimum hours: [overnight, morning, afternoon, evening]
# @attr last_auto_adjustment [Time, nil] When auto-tuner last made a change
# @attr created_at [Time] Creation timestamp
# @attr updated_at [Time] Last update timestamp
#
class HeatpumpConfig
  attr_reader :id, :hours_on, :emergency_temp_offset, :min_hotwater,
              :block_distribution, :last_auto_adjustment, :created_at, :updated_at

  # Default block distribution: 2 hours per 6-hour block
  DEFAULT_BLOCK_DISTRIBUTION = [2, 2, 2, 2].freeze

  def initialize(
    id:,
    hours_on:,
    emergency_temp_offset:,
    min_hotwater:,
    block_distribution: DEFAULT_BLOCK_DISTRIBUTION,
    last_auto_adjustment: nil,
    created_at:,
    updated_at:
  )
    @id = id
    @hours_on = hours_on
    @emergency_temp_offset = emergency_temp_offset
    @min_hotwater = min_hotwater
    @block_distribution = block_distribution.is_a?(String) ? JSON.parse(block_distribution) : block_distribution
    @last_auto_adjustment = last_auto_adjustment
    @created_at = created_at
    @updated_at = updated_at
  end

  # Get minimum hours for a specific block
  # @param block_index [Integer] 0=overnight, 1=morning, 2=afternoon, 3=evening
  # @return [Integer]
  def min_hours_for_block(block_index)
    @block_distribution[block_index] || 2
  end

  # Convert to hash for API responses
  # @return [Hash]
  def to_h
    {
      id: @id,
      hours_on: @hours_on,
      emergency_temp_offset: @emergency_temp_offset,
      min_hotwater: @min_hotwater,
      block_distribution: @block_distribution,
      last_auto_adjustment: @last_auto_adjustment,
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

    if params[:emergency_temp_offset]
      errors << "emergency_temp_offset must be between 0.5 and 5.0" unless (0.5..5.0).cover?(params[:emergency_temp_offset])
    end

    if params[:min_hotwater]
      errors << "min_hotwater must be between 35.0 and 50.0" unless (35.0..50.0).cover?(params[:min_hotwater])
    end

    errors
  end
end

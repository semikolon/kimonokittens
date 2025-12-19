# HeatpumpOverride domain model
#
# Records when temperature emergency forced heatpump ON outside normal schedule.
# Only logged for TRUE overrides (schedule said OFF, we forced ON).
# Used for self-learning analysis to optimize hours_on and distribution.
#
# @attr id [String] Unique identifier
# @attr type [String] 'indoor' or 'hotwater' - which threshold triggered
# @attr temperature [Float] Actual temperature when override triggered
# @attr price [Float] Electricity price at that hour (kr/kWh)
# @attr hour_of_day [Integer] Hour 0-23 for time block analysis
# @attr created_at [Time] When override occurred
#
class HeatpumpOverride
  attr_reader :id, :type, :temperature, :price, :hour_of_day, :created_at

  def initialize(
    id:,
    type:,
    temperature:,
    price:,
    hour_of_day:,
    created_at:
  )
    @id = id
    @type = type
    @temperature = temperature
    @price = price
    @hour_of_day = hour_of_day
    @created_at = created_at
  end

  # Convert to hash for API responses
  # @return [Hash]
  def to_h
    {
      id: @id,
      type: @type,
      temperature: @temperature,
      price: @price,
      hour_of_day: @hour_of_day,
      created_at: @created_at
    }
  end
end

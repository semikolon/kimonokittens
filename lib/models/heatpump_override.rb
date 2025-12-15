# HeatpumpOverride domain model
#
# Records when temperature emergency forced heatpump ON outside normal schedule.
# Used for self-learning analysis to optimize hours_on and distribution.
#
# Key insight: scheduledOn distinguishes timing vs capacity issues:
#   - scheduledOn=false → timing problem (gap in schedule, need better distribution)
#   - scheduledOn=true → capacity problem (not enough total hours)
#
# @attr id [String] Unique identifier
# @attr type [String] 'indoor' or 'hotwater' - which threshold triggered
# @attr temperature [Float] Actual temperature when override triggered
# @attr price [Float] Electricity price at that hour (kr/kWh)
# @attr scheduled_on [Boolean] Was heatpump supposed to be ON?
# @attr hour_of_day [Integer] Hour 0-23 for time block analysis
# @attr created_at [Time] When override occurred
#
class HeatpumpOverride
  attr_reader :id, :type, :temperature, :price, :scheduled_on, :hour_of_day, :created_at

  def initialize(
    id:,
    type:,
    temperature:,
    price:,
    scheduled_on:,
    hour_of_day:,
    created_at:
  )
    @id = id
    @type = type
    @temperature = temperature
    @price = price
    @scheduled_on = scheduled_on
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
      scheduled_on: @scheduled_on,
      hour_of_day: @hour_of_day,
      created_at: @created_at
    }
  end

  # Check if this was a timing issue (override during scheduled OFF)
  def timing_issue?
    !@scheduled_on
  end

  # Check if this was a capacity issue (override during scheduled ON)
  def capacity_issue?
    @scheduled_on
  end
end

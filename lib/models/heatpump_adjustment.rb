# HeatpumpAdjustment domain model
#
# Audit log for auto-learning adjustments.
# Every auto-adjustment is logged for transparency and rollback capability.
#
# @attr id [String] Unique identifier
# @attr adjustment_type [String] 'hours_on' or 'block_distribution'
# @attr previous_value [Hash] Previous config values (JSON parsed)
# @attr new_value [Hash] New config values (JSON parsed)
# @attr reason [String] Human-readable explanation
# @attr override_stats [Hash] Stats that triggered this adjustment (JSON parsed)
# @attr created_at [Time] When adjustment was made
#
class HeatpumpAdjustment
  attr_reader :id, :adjustment_type, :previous_value, :new_value,
              :reason, :override_stats, :created_at

  def initialize(
    id:,
    adjustment_type:,
    previous_value:,
    new_value:,
    reason:,
    override_stats:,
    created_at:
  )
    @id = id
    @adjustment_type = adjustment_type
    @previous_value = previous_value.is_a?(String) ? JSON.parse(previous_value) : previous_value
    @new_value = new_value.is_a?(String) ? JSON.parse(new_value) : new_value
    @reason = reason
    @override_stats = override_stats.is_a?(String) ? JSON.parse(override_stats) : override_stats
    @created_at = created_at
  end

  # Convert to hash for API responses
  # @return [Hash]
  def to_h
    {
      id: @id,
      adjustment_type: @adjustment_type,
      previous_value: @previous_value,
      new_value: @new_value,
      reason: @reason,
      override_stats: @override_stats,
      created_at: @created_at
    }
  end

  # Human-readable summary for notifications
  # @return [String]
  def summary
    case @adjustment_type
    when 'hours_on'
      prev = @previous_value['hours_on']
      new_val = @new_value['hours_on']
      "#{prev}→#{new_val}h"
    when 'block_distribution'
      prev = @previous_value['blocks'].join(',')
      new_val = @new_value['blocks'].join(',')
      "[#{prev}]→[#{new_val}]"
    else
      "#{@adjustment_type}: changed"
    end
  end
end

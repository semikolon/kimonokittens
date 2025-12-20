require 'oj'
require_relative '../lib/persistence'

# Heatpump Self-Learning Analysis Handler
#
# Provides analysis of override patterns to optimize scheduling parameters.
# Analyzes data from HeatpumpOverride table to detect:
# - Type patterns (indoor vs hotwater - which is the bottleneck?)
# - Time-of-day patterns (which hours need more coverage)
# - Cost impact (how much are overrides costing?)
#
# Note: Overrides only occur when schedule said OFF but we forced ON.
# If schedule said ON, there's no override - just low temps during scheduled run.
#
# GET /api/heatpump/analysis
#   ?days=7  (default: 7, analyze last N days)
#
# Created: December 2025
#
class HeatpumpAnalysisHandler
  def call(env)
    req = Rack::Request.new(env)
    days = (req.params['days'] || 7).to_i
    days = [[days, 1].max, 90].min  # Clamp to 1-90 days

    # Fetch all aggregations
    by_type = Persistence.heatpump_overrides.count_by_type(days: days)
    by_hour = Persistence.heatpump_overrides.count_by_hour(days: days)
    avg_price = Persistence.heatpump_overrides.average_override_price(days: days)
    recent = Persistence.heatpump_overrides.last_n_days(days)

    # Calculate totals
    total_overrides = by_type.values.sum

    # Analyze hour distribution to find problem blocks
    hour_blocks = analyze_hour_blocks(by_hour)

    # Generate recommendations
    recommendations = generate_recommendations(
      total: total_overrides,
      by_type: by_type,
      hour_blocks: hour_blocks,
      days: days
    )

    # Get current config for context
    config = Persistence.heatpump_config.get_current

    # Get auto-tuner status
    auto_tuner_status = build_auto_tuner_status(config)

    # Get adjustment history
    adjustment_history = Persistence.heatpump_adjustments.recent(limit: 5).map(&:to_h)

    response = {
      'period' => {
        'days' => days,
        'overrides_total' => total_overrides,
        'overrides_per_day' => (total_overrides.to_f / days).round(2)
      },
      'by_type' => by_type,
      'by_hour' => by_hour,
      'hour_blocks' => hour_blocks,
      'cost_analysis' => {
        'average_override_price' => avg_price.round(4),
        'description' => 'Average electricity price during override hours (kr/kWh)'
      },
      'current_config' => {
        'hours_on' => config.hours_on,
        'block_distribution' => config.block_distribution,
        'min_hotwater' => config.min_hotwater,
        'emergency_temp_offset' => config.emergency_temp_offset,
        'last_auto_adjustment' => config.last_auto_adjustment&.iso8601
      },
      'auto_tuner' => auto_tuner_status,
      'adjustment_history' => adjustment_history,
      'recommendations' => recommendations,
      'recent_overrides' => recent.first(10).map(&:to_h)
    }

    [200, { 'Content-Type' => 'application/json' }, [Oj.dump(response)]]
  end

  private

  # Analyze which 6-hour blocks have the most overrides
  def analyze_hour_blocks(by_hour)
    blocks = {
      'overnight' => { range: '00:00-05:59', hours: (0..5).to_a, count: 0 },
      'morning' => { range: '06:00-11:59', hours: (6..11).to_a, count: 0 },
      'afternoon' => { range: '12:00-17:59', hours: (12..17).to_a, count: 0 },
      'evening' => { range: '18:00-23:59', hours: (18..23).to_a, count: 0 }
    }

    by_hour.each do |hour, count|
      blocks.each do |name, data|
        if data[:hours].include?(hour)
          data[:count] += count
        end
      end
    end

    # Find worst block
    worst = blocks.max_by { |_, data| data[:count] }
    blocks['worst_block'] = worst[0] if worst && worst[1][:count] > 0

    # Convert to simpler format for JSON
    blocks.transform_values do |v|
      v.is_a?(Hash) ? { range: v[:range], count: v[:count] } : v
    end
  end

  # Generate actionable recommendations based on analysis
  def generate_recommendations(total:, by_type:, hour_blocks:, days:)
    recommendations = []
    overrides_per_day = total.to_f / days

    # Overall assessment
    if overrides_per_day > 3
      recommendations << {
        'severity' => 'high',
        'message' => "High override frequency (#{overrides_per_day.round(1)}/day). Schedule has too many gaps."
      }
    elsif overrides_per_day > 1
      recommendations << {
        'severity' => 'medium',
        'message' => "Moderate override frequency (#{overrides_per_day.round(1)}/day). Consider increasing hours_on or improving distribution."
      }
    elsif overrides_per_day > 0
      recommendations << {
        'severity' => 'low',
        'message' => "Acceptable override frequency (#{overrides_per_day.round(1)}/day)."
      }
    else
      recommendations << {
        'severity' => 'none',
        'message' => "No overrides in #{days} days. Schedule is working well."
      }
    end

    # Type-specific analysis
    if by_type['hotwater'] > by_type['indoor'] * 3
      recommendations << {
        'severity' => 'info',
        'message' => "Hot water is the primary issue (#{by_type['hotwater']} vs #{by_type['indoor']} indoor). Hot water tank depletes faster than house cools."
      }
    elsif by_type['indoor'] > by_type['hotwater']
      recommendations << {
        'severity' => 'info',
        'message' => "Indoor temperature is the primary issue (#{by_type['indoor']} vs #{by_type['hotwater']} hot water). May need more total heating hours in cold weather."
      }
    end

    # Hour block analysis
    worst_block = hour_blocks['worst_block']
    if worst_block && total > 0
      block_data = hour_blocks[worst_block]
      if block_data && block_data[:count] > total * 0.4
        recommendations << {
          'severity' => 'medium',
          'action' => 'check_block',
          'message' => "#{worst_block.capitalize} block (#{block_data[:range]}) has #{block_data[:count]} overrides (#{(block_data[:count].to_f / total * 100).round(0)}% of total).",
          'suggestion' => "The OFF gaps during #{worst_block} hours are too long. Distribution algorithm should help."
        }
      end
    end

    # Self-learning suggestion if enough data and low overrides
    if total >= 14 && overrides_per_day <= 0.5
      recommendations << {
        'severity' => 'low',
        'action' => 'can_reduce',
        'message' => "Override frequency is very low. Could test reducing hours_on by 1 to optimize cost.",
        'suggestion' => 'Monitor for 1 week after any reduction.'
      }
    end

    recommendations
  end

  # Build auto-tuner status information
  def build_auto_tuner_status(config)
    days_since = Persistence.heatpump_adjustments.days_since_last_adjustment
    adjustments_30d = Persistence.heatpump_adjustments.count_recent(days: 30)

    min_interval_days = 7  # Must match HeatpumpAutoTuner::MIN_ADJUSTMENT_INTERVAL_DAYS

    if days_since.nil?
      # No adjustments ever made
      {
        'enabled' => true,
        'last_adjustment' => nil,
        'next_eligible' => Time.now.iso8601,
        'status' => 'ready',
        'message' => 'Auto-tuner ready (no adjustments yet)',
        'adjustments_last_30_days' => 0
      }
    elsif days_since < min_interval_days
      days_until = (min_interval_days - days_since).ceil
      next_eligible = Time.now + (days_until * 24 * 60 * 60)
      {
        'enabled' => true,
        'last_adjustment' => config.last_auto_adjustment&.iso8601,
        'days_since_last' => days_since.round(1),
        'next_eligible' => next_eligible.iso8601,
        'status' => 'rate_limited',
        'message' => "Rate limited: #{days_until} day(s) until next adjustment eligible",
        'adjustments_last_30_days' => adjustments_30d
      }
    else
      {
        'enabled' => true,
        'last_adjustment' => config.last_auto_adjustment&.iso8601,
        'days_since_last' => days_since.round(1),
        'next_eligible' => Time.now.iso8601,
        'status' => 'ready',
        'message' => 'Auto-tuner ready for next scheduled run',
        'adjustments_last_30_days' => adjustments_30d
      }
    end
  end
end

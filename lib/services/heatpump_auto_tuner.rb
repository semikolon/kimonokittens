require_relative '../persistence'
require_relative '../sms/gateway'

# HeatpumpAutoTuner - Weekly auto-adjustment of heatpump schedule parameters
#
# Analyzes override patterns and adjusts hours_on and block distribution
# to minimize temperature emergencies while keeping costs low.
#
# Layer 2: Weekly hours_on adjustment based on override frequency
# Layer 3: Block-level distribution learning based on where overrides cluster
#
# @example Weekly cron execution
#   tuner = HeatpumpAutoTuner.new
#   result = tuner.run
#   # => { adjusted: true, adjustment_type: 'hours_on', ... }
#
# @example Dry run for testing
#   tuner = HeatpumpAutoTuner.new(dry_run: true)
#   result = tuner.run
#   # => { adjusted: false, would_adjust: true, ... }
#
class HeatpumpAutoTuner
  # Thresholds for adjustment decisions
  INCREASE_THRESHOLD = 1.5        # overrides/day triggers increase
  DECREASE_THRESHOLD = 0.0        # must be zero to decrease
  DECREASE_WAIT_WEEKS = 2         # consecutive zero-override weeks before decrease

  # Guardrails - hard limits
  MIN_HOURS = 10                  # Never below (house gets too cold)
  MAX_HOURS = 20                  # Never above (defeats cost optimization)
  MIN_ADJUSTMENT_INTERVAL_DAYS = 7  # Prevent oscillation

  # Block learning thresholds
  BLOCK_OVERRIDE_THRESHOLD = 0.35  # Block needs attention if >35% of overrides
  MIN_OVERRIDES_FOR_BLOCK_LEARNING = 10  # Need enough data
  MIN_BLOCK_HOURS = 1              # Every block needs at least 1 hour
  MAX_BLOCK_HOURS = 4              # No block should dominate

  # Block definitions (must match schedule handler)
  BLOCK_NAMES = [:overnight, :morning, :afternoon, :evening].freeze
  BLOCK_HOUR_RANGES = [
    (0..5),   # overnight
    (6..11),  # morning
    (12..17), # afternoon
    (18..23)  # evening
  ].freeze

  attr_reader :dry_run, :stats

  # Initialize the auto-tuner
  #
  # @param dry_run [Boolean] If true, log what WOULD change without applying
  def initialize(dry_run: false)
    @dry_run = dry_run
    @stats = nil
  end

  # Main entry point - analyze and optionally adjust
  #
  # @return [Hash] Result with :adjusted, :message, :adjustment_type, etc.
  def run
    # Check rate limiting first
    days_since = days_since_last_adjustment
    if days_since && days_since < MIN_ADJUSTMENT_INTERVAL_DAYS
      return skip_result("Too soon since last adjustment (#{days_since.round(1)} days ago)")
    end

    # Gather statistics
    @stats = analyze_period(days: 7)

    # Try hours_on adjustment (Layer 2)
    hours_result = evaluate_hours_adjustment
    return hours_result if hours_result[:adjusted] || hours_result[:would_adjust]

    # Try block distribution adjustment (Layer 3) - uses 30 days data
    block_result = evaluate_block_adjustment
    return block_result if block_result[:adjusted] || block_result[:would_adjust]

    # No adjustment needed
    no_change_result(@stats)
  end

  private

  # Analyze override statistics for a period
  #
  # @param days [Integer] Number of days to analyze
  # @return [Hash] Statistics including override counts, rates, patterns
  def analyze_period(days:)
    overrides = Persistence.heatpump_overrides.last_n_days(days)

    total_overrides = overrides.count
    overrides_per_day = days > 0 ? total_overrides.to_f / days : 0

    by_type = Persistence.heatpump_overrides.count_by_type(days: days)
    by_hour = Persistence.heatpump_overrides.count_by_hour(days: days)
    avg_price = Persistence.heatpump_overrides.average_override_price(days: days)

    # Count overrides by block
    by_block = count_by_block(by_hour)

    {
      days: days,
      total_overrides: total_overrides,
      overrides_per_day: overrides_per_day,
      by_type: by_type,
      by_hour: by_hour,
      by_block: by_block,
      average_price: avg_price,
      timestamp: Time.now
    }
  end

  # Count overrides by 6-hour block
  #
  # @param by_hour [Hash] Hour counts { 0 => n, 1 => m, ... }
  # @return [Hash] Block counts { overnight: n, morning: m, ... }
  def count_by_block(by_hour)
    BLOCK_NAMES.each_with_index.each_with_object({}) do |(name, idx), result|
      hours = BLOCK_HOUR_RANGES[idx]
      result[name] = hours.sum { |h| by_hour[h] || 0 }
    end
  end

  # Evaluate whether hours_on should be adjusted
  #
  # @return [Hash] Result indicating adjustment decision
  def evaluate_hours_adjustment
    config = Persistence.heatpump_config.get_current
    current_hours = config.hours_on

    if @stats[:overrides_per_day] > INCREASE_THRESHOLD
      # Too many overrides - increase hours
      return adjust_hours_on(
        config,
        +1,
        "High override rate: #{@stats[:overrides_per_day].round(1)}/day"
      )
    end

    if @stats[:overrides_per_day] == 0
      # Zero overrides - check if we can decrease
      zero_weeks = consecutive_zero_weeks
      if zero_weeks >= DECREASE_WAIT_WEEKS
        return adjust_hours_on(
          config,
          -1,
          "Zero overrides for #{zero_weeks} consecutive weeks"
        )
      else
        return no_adjustment_result(
          "Zero overrides but only #{zero_weeks} week(s) - waiting for #{DECREASE_WAIT_WEEKS} weeks"
        )
      end
    end

    # Override rate is acceptable (between 0 and threshold)
    no_adjustment_result(
      "Override rate acceptable: #{@stats[:overrides_per_day].round(2)}/day (threshold: #{INCREASE_THRESHOLD})"
    )
  end

  # Adjust hours_on by delta
  #
  # @param config [HeatpumpConfig] Current configuration
  # @param delta [Integer] Change (+1 or -1)
  # @param reason [String] Human-readable explanation
  # @return [Hash] Result of adjustment
  def adjust_hours_on(config, delta, reason)
    new_hours = (config.hours_on + delta).clamp(MIN_HOURS, MAX_HOURS)

    if new_hours == config.hours_on
      return limit_hit_result(config.hours_on, delta > 0 ? 'max' : 'min')
    end

    if @dry_run
      return dry_run_result('hours_on', config.hours_on, new_hours, reason)
    end

    # Apply the change
    apply_hours_adjustment(config, new_hours, reason)
  end

  # Apply hours_on adjustment to database and notify
  #
  # @param config [HeatpumpConfig] Current configuration
  # @param new_hours [Integer] New hours value
  # @param reason [String] Human-readable explanation
  # @return [Hash] Result of adjustment
  def apply_hours_adjustment(config, new_hours, reason)
    previous_value = { hours_on: config.hours_on }
    new_value = { hours_on: new_hours }

    # Update config
    Persistence.heatpump_config.update(
      config.id,
      hours_on: new_hours,
      last_auto_adjustment: Time.now
    )

    # Log adjustment
    adjustment = Persistence.heatpump_adjustments.record(
      adjustment_type: 'hours_on',
      previous_value: previous_value,
      new_value: new_value,
      reason: reason,
      override_stats: @stats
    )

    # Send notification
    send_adjustment_notification(adjustment)

    {
      adjusted: true,
      adjustment_type: 'hours_on',
      previous_value: previous_value,
      new_value: new_value,
      reason: reason,
      adjustment_id: adjustment.id,
      message: "Adjusted hours_on: #{config.hours_on} → #{new_hours}h (#{reason})"
    }
  end

  # Evaluate whether block distribution should be adjusted (Layer 3)
  #
  # @return [Hash] Result indicating adjustment decision
  def evaluate_block_adjustment
    # Need more data for block learning - use 30 days
    block_stats = analyze_period(days: 30)

    return no_adjustment_result("Not enough overrides for block learning (#{block_stats[:total_overrides]} < #{MIN_OVERRIDES_FOR_BLOCK_LEARNING})") if block_stats[:total_overrides] < MIN_OVERRIDES_FOR_BLOCK_LEARNING

    total = block_stats[:total_overrides]
    problem_blocks = block_stats[:by_block].select { |_, count| count > total * BLOCK_OVERRIDE_THRESHOLD }

    return no_adjustment_result("No problematic blocks detected (none > #{(BLOCK_OVERRIDE_THRESHOLD * 100).to_i}% of overrides)") if problem_blocks.empty?

    config = Persistence.heatpump_config.get_current
    current_distribution = config.block_distribution.dup
    new_distribution = current_distribution.dup

    # Increase hours for problem blocks
    changes_made = []
    problem_blocks.each do |block_name, count|
      block_index = BLOCK_NAMES.index(block_name)
      next unless block_index

      current_hours = new_distribution[block_index]
      if current_hours < MAX_BLOCK_HOURS
        new_distribution[block_index] = current_hours + 1
        changes_made << "#{block_name}: #{current_hours} → #{current_hours + 1}"
      end
    end

    return no_adjustment_result("Problem blocks already at max hours") if changes_made.empty?

    # Cap total distributed hours at hours_on
    distribute_total = new_distribution.sum
    if distribute_total > config.hours_on
      # Find lowest-override block to reduce
      min_block_name = block_stats[:by_block].min_by { |_, v| v }.first
      min_index = BLOCK_NAMES.index(min_block_name)

      if min_index && new_distribution[min_index] > MIN_BLOCK_HOURS
        new_distribution[min_index] -= 1
        changes_made << "#{min_block_name}: reduced to rebalance"
      else
        return no_adjustment_result("Cannot rebalance: all blocks at minimum")
      end
    end

    return no_adjustment_result("No net change to distribution") if new_distribution == current_distribution

    reason = "Block override concentration: #{problem_blocks.map { |b, c| "#{b}=#{((c.to_f / total) * 100).round}%" }.join(', ')}"

    if @dry_run
      return dry_run_result('block_distribution', current_distribution, new_distribution, reason)
    end

    # Apply the change
    apply_block_adjustment(config, current_distribution, new_distribution, reason, block_stats)
  end

  # Apply block distribution adjustment to database and notify
  #
  # @param config [HeatpumpConfig] Current configuration
  # @param previous [Array] Previous distribution
  # @param new_dist [Array] New distribution
  # @param reason [String] Human-readable explanation
  # @param block_stats [Hash] Statistics for logging
  # @return [Hash] Result of adjustment
  def apply_block_adjustment(config, previous, new_dist, reason, block_stats)
    previous_value = { blocks: previous }
    new_value = { blocks: new_dist }

    # Update config
    Persistence.heatpump_config.update(
      config.id,
      block_distribution: new_dist,
      last_auto_adjustment: Time.now
    )

    # Log adjustment
    adjustment = Persistence.heatpump_adjustments.record(
      adjustment_type: 'block_distribution',
      previous_value: previous_value,
      new_value: new_value,
      reason: reason,
      override_stats: block_stats
    )

    # Send notification
    send_adjustment_notification(adjustment)

    {
      adjusted: true,
      adjustment_type: 'block_distribution',
      previous_value: previous_value,
      new_value: new_value,
      reason: reason,
      adjustment_id: adjustment.id,
      message: "Adjusted block distribution: [#{previous.join(',')}] → [#{new_dist.join(',')}] (#{reason})"
    }
  end

  # Count consecutive weeks with zero overrides
  #
  # @return [Integer] Number of consecutive zero-override weeks
  def consecutive_zero_weeks
    weeks = 0
    current_week_start = Time.now - (7 * 24 * 60 * 60)

    8.times do |i|  # Check up to 8 weeks back
      week_end = current_week_start + (7 * 24 * 60 * 60)
      overrides = Persistence.heatpump_overrides.last_n_days(7)

      # Filter to this specific week
      week_overrides = overrides.count { |o| o.created_at >= current_week_start && o.created_at < week_end }

      break if week_overrides > 0
      weeks += 1
      current_week_start -= (7 * 24 * 60 * 60)
    end

    weeks
  end

  # Calculate days since last adjustment
  #
  # @return [Float, nil] Days since last adjustment, or nil if never adjusted
  def days_since_last_adjustment
    Persistence.heatpump_adjustments.days_since_last_adjustment
  end

  # Send SMS notification for adjustment
  #
  # @param adjustment [HeatpumpAdjustment] The adjustment record
  def send_adjustment_notification(adjustment)
    summary = adjustment.summary
    SmsGateway.send_admin_alert("Värmepump auto-justerad: #{summary}")
  rescue => e
    # Don't fail the adjustment if SMS fails
    puts "Warning: Failed to send adjustment SMS: #{e.message}"
  end

  # Result helpers

  def skip_result(reason)
    {
      adjusted: false,
      would_adjust: false,
      skipped: true,
      reason: reason,
      message: "Skipped: #{reason}"
    }
  end

  def no_adjustment_result(reason)
    {
      adjusted: false,
      would_adjust: false,
      reason: reason,
      message: "No adjustment needed: #{reason}"
    }
  end

  def no_change_result(stats)
    {
      adjusted: false,
      would_adjust: false,
      stats: stats,
      message: "No adjustment needed. Override rate: #{stats[:overrides_per_day].round(2)}/day"
    }
  end

  def limit_hit_result(current_value, limit_type)
    {
      adjusted: false,
      would_adjust: true,
      blocked_by: "#{limit_type}_limit",
      current_value: current_value,
      message: "Would adjust but hit #{limit_type} limit (#{current_value}h)"
    }
  end

  def dry_run_result(adjustment_type, previous, new_value, reason)
    {
      adjusted: false,
      would_adjust: true,
      dry_run: true,
      adjustment_type: adjustment_type,
      previous_value: previous,
      new_value: new_value,
      reason: reason,
      message: "[DRY RUN] Would adjust #{adjustment_type}: #{previous} → #{new_value} (#{reason})"
    }
  end
end

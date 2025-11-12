require 'date'
require 'time'

# RentConfig domain model representing rent configuration values
#
# Encapsulates complex business logic for:
# - Key classification (period-specific vs persistent)
# - Default values
# - Carry-forward behavior
# - Temporal querying for configuration periods
#
# PRESERVED LOGIC from rent_db.rb:106-184 (CRITICAL - DO NOT MODIFY)
#
# Key Types:
# - PERIOD_SPECIFIC: Exact period match only (el, drift_rakning, saldo_innan, extra_in)
# - PERSISTENT: Carry forward from most recent (kallhyra, bredband, vattenavgift, va, larm)
#
# CRITICAL TIMING CONCEPT:
#   The month parameter represents the CONFIG PERIOD MONTH, not the rent month.
#   This configuration is used to calculate rent for the FOLLOWING month.
#
# @example Swedish Rent Payment Timing
#   # September 27: Time to pay October rent
#   config = RentConfig.for_period(year: 2025, month: 9, repository: repo)
#   # This config contains:
#   # - September electricity bills (arrears payment)
#   # - October base rent (advance payment)
#   # Result: "Hyran för oktober 2025 ska betalas innan 27 sep"
class RentConfig
  # Configuration key classification based on business logic
  # PRESERVED from rent_db.rb:107-108
  PERIOD_SPECIFIC_KEYS = %w[el drift_rakning saldo_innan extra_in].freeze
  PERSISTENT_KEYS = %w[kallhyra bredband vattenavgift va larm].freeze

  # Default values for persistent keys when no configuration is found
  # Updated Oct 2025 to reflect actual 2025 quarterly invoice average (754 kr/month)
  DEFAULTS = {
    kallhyra: 24530,
    bredband: 400,
    vattenavgift: 343,  # 45.5% of 754 kr/month
    va: 274,            # 36.4% of 754 kr/month
    larm: 137           # 18.2% of 754 kr/month
  }.freeze

  attr_reader :id, :key, :value, :period, :created_at, :updated_at

  def initialize(id: nil, key:, value:, period:, created_at: nil, updated_at: nil)
    @id = id
    @key = key.to_s
    @value = value.to_s
    @period = normalize_period(period)
    @created_at = created_at
    @updated_at = updated_at
    validate!
  end

  # Check if this is a period-specific key
  # @return [Boolean]
  def period_specific?
    PERIOD_SPECIFIC_KEYS.include?(key)
  end

  # Check if this is a persistent key
  # @return [Boolean]
  def persistent?
    PERSISTENT_KEYS.include?(key)
  end

  # Get numeric value (for calculations)
  # @return [Integer]
  def numeric_value
    value.to_i
  end

  # Retrieves rent configuration for a specific CONFIGURATION PERIOD
  #
  # PRESERVED LOGIC from rent_db.rb:152-184 (CRITICAL - DO NOT MODIFY)
  #
  # **AUTO-POPULATION**: Quarterly invoice projections (drift_rakning) are automatically
  # created for quarterly months (Apr/Jul/Oct) when no actual value exists.
  #
  # @param year [Integer] The configuration period year
  # @param month [Integer] The configuration period month (1-12)
  # @param repository [RentConfigRepository] Repository instance
  #
  # @return [Hash] Configuration hash with 'key' and 'value' string fields
  #   (matches current API contract for backward compatibility)
  #
  # @example September config for October rent
  #   config = RentConfig.for_period(year: 2025, month: 9, repository: repo)
  #   config['el']  # => "2424" (September electricity bills)
  #   config['kallhyra']  # => "24530" (October base rent)
  #
  # @example Quarterly projection auto-population
  #   config = RentConfig.for_period(year: 2026, month: 4, repository: repo)
  #   # Auto-creates drift_rakning: 3030 (projected) if not exists
  #   config['drift_rakning']  # => "3030" (growth-adjusted projection)
  def self.for_period(year:, month:, repository:)
    require_relative '../services/quarterly_invoice_projector'

    target_date = Date.new(year, month, 1)
    target_time = Time.utc(year, month, 1)
    end_of_month = (target_date.next_month - 1).to_time.utc

    result = {}

    # Period-specific keys: exact match only, no carry-forward
    # OPTIMIZED: Batch query instead of N queries (4 keys → 1 query)
    #
    # ENHANCED: Auto-populate quarterly invoice projections
    period_configs = repository.find_by_keys_and_period(PERIOD_SPECIFIC_KEYS, target_time)

    PERIOD_SPECIFIC_KEYS.each do |key|
      config = period_configs[key]

      # Auto-populate quarterly invoice projection if missing
      if key == 'drift_rakning' && (!config || config.value.to_i == 0)
        config = auto_populate_quarterly_projection(
          year: year,
          month: month,
          repository: repository,
          target_time: target_time
        )
      end

      value = config ? config.value : '0'
      result[key] = value
    end

    # Persistent keys: use most recent value where period <= target
    # OPTIMIZED: Batch query instead of N queries (5 keys → 1 query)
    persistent_configs = repository.find_latest_for_keys(PERSISTENT_KEYS, end_of_month)

    PERSISTENT_KEYS.each do |key|
      config = persistent_configs[key]
      default_value = DEFAULTS[key.to_sym] || 0
      value = config ? config.value : default_value.to_s
      result[key] = value
    end

    result
  end

  # Auto-populate quarterly invoice projection if needed
  #
  # Creates a projected drift_rakning value for quarterly months (Apr/Jul/Oct)
  # using growth-adjusted calculations from QuarterlyInvoiceProjector.
  #
  # @param year [Integer] Target year
  # @param month [Integer] Target month
  # @param repository [RentConfigRepository] Repository to save projection
  # @param target_time [Time] Normalized period time
  # @return [RentConfig, nil] Created projection config or nil if not needed
  #
  # @example April 2026 projection
  #   config = auto_populate_quarterly_projection(
  #     year: 2026,
  #     month: 4,
  #     repository: repo,
  #     target_time: Time.utc(2026, 4, 1)
  #   )
  #   config.value  # => "3030" (growth-adjusted projection)
  def self.auto_populate_quarterly_projection(year:, month:, repository:, target_time:)
    # Only auto-populate for quarterly months
    return nil unless QuarterlyInvoiceProjector.quarterly_month?(month)

    # Calculate projection
    projection = QuarterlyInvoiceProjector.calculate_projection(year: year, month: month)
    return nil unless projection

    # Create RentConfig domain object
    config = RentConfig.new(
      key: 'drift_rakning',
      value: projection[:amount].to_s,
      period: target_time
    )

    # Save to database with is_projection flag
    saved_config = repository.save_with_projection_flag(config, is_projection: true)

    saved_config
  end

  def to_s
    "#{key}=#{value} (#{period.strftime('%Y-%m')})"
  end

  private

  # Normalize period to month start (UTC)
  # @param period [Date, Time, String] Period input
  # @return [Time] Normalized to month start UTC
  def normalize_period(period)
    case period
    when Time
      Time.utc(period.year, period.month, 1)
    when Date
      Time.utc(period.year, period.month, 1)
    when String
      date = Date.parse(period)
      Time.utc(date.year, date.month, 1)
    else
      raise ArgumentError, "Invalid period type: #{period.class}"
    end
  end

  def validate!
    raise ArgumentError, "Key required" if key.empty?
    raise ArgumentError, "Period required" unless period.is_a?(Time)

    # Validate key is recognized
    unless PERIOD_SPECIFIC_KEYS.include?(key) || PERSISTENT_KEYS.include?(key)
      warn "Warning: Unrecognized config key '#{key}' (not in PERIOD_SPECIFIC or PERSISTENT lists)"
    end
  end
end

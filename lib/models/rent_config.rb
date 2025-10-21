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
  # PRESERVED from rent_db.rb:111-117
  DEFAULTS = {
    kallhyra: 24530,
    bredband: 400,
    vattenavgift: 375,
    va: 300,
    larm: 150
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
  def self.for_period(year:, month:, repository:)
    target_date = Date.new(year, month, 1)
    target_time = Time.utc(year, month, 1)
    end_of_month = (target_date.next_month - 1).to_time.utc

    result = {}

    # Period-specific keys: exact match only, no carry-forward
    # PRESERVED from rent_db.rb:161-168
    PERIOD_SPECIFIC_KEYS.each do |key|
      config = repository.find_by_key_and_period(key, target_time)
      value = config ? config.value : '0'
      result[key] = value
    end

    # Persistent keys: use most recent value where period <= target
    # PRESERVED from rent_db.rb:171-180
    PERSISTENT_KEYS.each do |key|
      config = repository.find_latest_for_key(key, end_of_month)
      default_value = DEFAULTS[key.to_sym] || 0
      value = config ? config.value : default_value.to_s
      result[key] = value
    end

    result
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

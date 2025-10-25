require_relative 'base_repository'
require_relative '../models/rent_config'
require 'cuid'

# RentConfigRepository handles persistence for rent configuration values
#
# Provides:
# - Period-based queries (exact match for period-specific keys)
# - Latest value lookup (carry-forward for persistent keys)
# - Configuration creation with normalization
#
# PRESERVED LOGIC from rent_db.rb:207-220
class RentConfigRepository < BaseRepository
  def table_name
    :RentConfig
  end

  # Find config by exact key and period match
  # Used for period-specific keys (el, drift_rakning, etc.)
  # @param key [String] Configuration key
  # @param period [Time] Period (normalized to month start)
  # @return [RentConfig, nil]
  def find_by_key_and_period(key, period)
    normalized_period = normalize_period(period)
    row = dataset.where(key: key, period: normalized_period).first
    row && hydrate(row)
  end

  # Find most recent config for key before/at given period
  # Used for persistent keys (kallhyra, bredband, etc.)
  # @param key [String] Configuration key
  # @param before_period [Time] Upper bound period
  # @return [RentConfig, nil]
  def find_latest_for_key(key, before_period)
    row = dataset
      .where(key: key)
      .where { period <= before_period }
      .order(Sequel.desc(:period))
      .first

    row && hydrate(row)
  end

  # Find all configs for a specific period
  # @param period [Time] Period to query
  # @return [Array<RentConfig>]
  def find_by_period(period)
    normalized_period = normalize_period(period)
    dataset
      .where(period: normalized_period)
      .order(:key)
      .map { |row| hydrate(row) }
  end

  # Get all distinct keys in the system
  # @return [Array<String>]
  def all_keys
    dataset.select(:key).distinct.order(:key).map { |row| row[:key] }
  end

  # Count configs for a specific key
  # @param key [String] Configuration key
  # @return [Integer]
  def count_for_key(key)
    dataset.where(key: key).count
  end

  # Retrieve all configurations for a given key ordered by period
  # @param key [String]
  # @return [Array<RentConfig>]
  def all_for_key(key)
    dataset
      .where(key: key)
      .order(:period)
      .map { |row| hydrate(row) }
  end

  # Create new configuration record
  #
  # PRESERVED LOGIC from rent_db.rb:207-220
  #
  # @param key [String] Configuration key
  # @param value [Numeric, String] Configuration value
  # @param period [Time, Date] The configuration period (defaults to current month)
  #
  # @return [RentConfig] Created configuration
  #
  # @example Setting October 2025 Rent Configuration
  #   # September electricity bill arrives, set for September period
  #   config = repo.create_config('el', 2424, Time.new(2025, 9, 15))
  #   # Normalized to Sep 1, 2025 00:00:00 UTC
  def create_config(key, value, period = Time.now)
    config = RentConfig.new(
      key: key,
      value: value,
      period: period
    )

    create(config)
  end

  # Create new config from domain object
  # @param config [RentConfig] Configuration to persist
  # @return [RentConfig] Config with ID assigned
  def create(config)
    id = dataset.insert(dehydrate(config))

    RentConfig.new(
      id: id,
      key: config.key,
      value: config.value,
      period: config.period,
      created_at: now_utc,
      updated_at: now_utc
    )
  end

  # Save config with projection flag (for auto-populated quarterly invoices)
  # @param config [RentConfig] Configuration to persist
  # @param is_projection [Boolean] Whether this is a projected value
  # @return [RentConfig] Config with ID assigned
  def save_with_projection_flag(config, is_projection:)
    data = dehydrate(config).merge(isProjection: is_projection)
    id = dataset.insert(data)

    RentConfig.new(
      id: id,
      key: config.key,
      value: config.value,
      period: config.period,
      created_at: now_utc,
      updated_at: now_utc
    )
  end

  # Upsert configuration value for a period (creates or updates existing record)
  #
  # When updating an existing record, automatically clears isProjection flag
  # (manual updates are considered actual values, not projections)
  #
  # @param key [String] Configuration key
  # @param value [String, Numeric] Configuration value
  # @param period [Time, Date, String] Configuration period
  # @return [RentConfig]
  def upsert(key:, value:, period: Time.now.utc)
    normalized_period = normalize_period(period)

    existing = dataset.where(key: key, period: normalized_period).first

    if existing
      dataset.where(id: existing[:id]).update(
        value: value.to_s,
        isProjection: false,  # Manual update = actual value, not projection
        updatedAt: now_utc
      )

      hydrate(dataset.where(id: existing[:id]).first)
    else
      create(
        RentConfig.new(
          key: key,
          value: value,
          period: normalized_period
        )
      )
    end
  end

  # Update existing config
  # @param config [RentConfig] Configuration to update
  # @return [RentConfig] Updated config
  def update(config)
    raise ArgumentError, "Cannot update config without ID" unless config.id

    dataset.where(id: config.id).update(
      key: config.key,
      value: config.value,
      period: config.period,
      updatedAt: now_utc
    )

    config
  end

  # Delete config by ID
  # @param id [String] Config ID
  # @return [Boolean] True if deleted
  def delete(id)
    dataset.where(id: id).delete > 0
  end

  private

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

  # Convert database row to domain object
  # @param row [Hash] Database row
  # @return [RentConfig]
  def hydrate(row)
    RentConfig.new(
      id: row[:id],
      key: row[:key],
      value: row[:value],
      period: row[:period],
      created_at: row[:createdAt],
      updated_at: row[:updatedAt]
    )
  end

  # Convert domain object to database hash
  # @param config [RentConfig] Domain object
  # @return [Hash] Database columns
  def dehydrate(config)
    {
      id: config.id || generate_id,
      key: config.key,
      value: config.value,
      period: config.period,
      createdAt: config.created_at || now_utc,
      updatedAt: config.updated_at || now_utc
    }
  end
end

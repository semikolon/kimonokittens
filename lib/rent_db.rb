require 'sequel'
require 'cuid'
require 'date'

# RentDb provides a unified interface to the PostgreSQL database for the
# Kimonokittens handbook and rent calculation system.
# Now uses Sequel for thread-safe connection pooling, perfect for WebSocket broadcasting.
class RentDb
  # Thread-safe connection with automatic pooling
  def self.db
    @db ||= begin
      # Configure connection pool for multi-threaded Puma/WebSocket environment
      Sequel.connect(
        ENV.fetch('DATABASE_URL'),
        max_connections: 10,    # Allow multiple concurrent WebSocket connections
        pool_timeout: 5,        # Quick timeout for responsive WebSocket data
        test: true,            # Test connections before use
        validate: true         # Validate connections automatically
      )
    end
  end

  # Ensure we have table references for Sequel
  def self.tenants
    db[:Tenant]
  end

  def self.rent_configs
    db[:RentConfig]
  end

  def self.rent_ledger
    db[:RentLedger]
  end

  # Instance methods for backward compatibility with existing code
  def get_tenants
    results = self.class.tenants
      .select(:id, :name, :email, :startDate, :departureDate, :roomAdjustment)
      .order(:name)
      .all

    # Convert symbol keys to string keys to match expected format
    results.map { |row| row.transform_keys(&:to_s) }
  end

  def get_rent_history(year:, month:)
    # Note: Prisma stores dates in UTC. We construct the date range carefully.
    start_date = Time.new(year, month, 1).utc
    end_date = start_date + (31 * 24 * 60 * 60) # A safe way to get to the next month

    self.class.rent_ledger
      .where(period: start_date...end_date)
      .order(:createdAt)
      .all
  end

  # Configuration key classification based on business logic
  PERIOD_SPECIFIC_KEYS = %w[el drift_rakning saldo_innan extra_in].freeze
  PERSISTENT_KEYS = %w[kallhyra bredband vattenavgift va larm].freeze

  # Default values for persistent keys when no configuration is found
  DEFAULTS = {
    kallhyra: 24530,
    bredband: 400,
    vattenavgift: 375,
    va: 300,
    larm: 150
  }.freeze

  def get_rent_config(year:, month:)
    target_date = Date.new(year, month, 1)
    # Use Time.utc for consistent timezone handling
    target_time = Time.utc(year, month, 1)
    end_of_month = (target_date.next_month - 1).to_time.utc

    result = []

    # Period-specific keys: exact match only, no carry-forward
    PERIOD_SPECIFIC_KEYS.each do |key|
      config_record = self.class.rent_configs
        .where(key: key, period: target_time)
        .first

      value = config_record ? config_record[:value] : 0
      result << { 'key' => key, 'value' => value }
    end

    # Persistent keys: use most recent value where period <= target
    PERSISTENT_KEYS.each do |key|
      config_record = self.class.rent_configs
        .where(key: key)
        .where { period <= end_of_month }
        .order(Sequel.desc(:period))
        .first

      value = config_record ? config_record[:value] : (DEFAULTS[key.to_sym] || 0)
      result << { 'key' => key, 'value' => value }
    end

    # Create a mock PG::Result-like object for compatibility
    MockPGResult.new(result)
  end

  def set_config(key, value, period = Time.now)
    # Normalize period to month start for exact matching and uniqueness
    normalized_period = Time.utc(period.year, period.month, 1)

    self.class.rent_configs.insert(
      id: Cuid.generate,
      key: key,
      value: value,
      period: normalized_period,
      createdAt: Time.now.utc,
      updatedAt: Time.now.utc
    )
    $pubsub&.publish("rent_data_updated")
  end

  def find_tenant_by_facebook_id(facebook_id)
    self.class.tenants.where(facebookId: facebook_id).first
  end

  def find_tenant_by_email(email)
    self.class.tenants.where(email: email).first
  end

  def add_tenant(name:, email: nil, facebookId: nil, avatarUrl: nil, start_date: nil, departure_date: nil)
    # Generate a placeholder email if none is provided
    email ||= "#{name.downcase.gsub(/\s+/, '.')}@kimonokittens.com"

    self.class.tenants.insert(
      id: Cuid.generate,
      name: name,
      email: email,
      facebookId: facebookId,
      avatarUrl: avatarUrl,
      startDate: start_date,
      departureDate: departure_date,
      createdAt: Time.now.utc,
      updatedAt: Time.now.utc
    )
  end

  def set_start_date(name:, date:)
    self.class.tenants.where(name: name).update(startDate: date)
    $pubsub&.publish("rent_data_updated")
  end

  def set_departure_date(name:, date:)
    self.class.tenants.where(name: name).update(departureDate: date)
    $pubsub&.publish("rent_data_updated")
  end

  def set_room_adjustment(name:, adjustment:)
    self.class.tenants.where(name: name).update(roomAdjustment: adjustment)
    $pubsub&.publish("rent_data_updated")
  end

  # Singleton compatibility for existing code
  def self.instance
    @instance ||= new
  end
end

# Mock PG::Result for backward compatibility with rent calculator handler
class MockPGResult
  include Enumerable

  def initialize(rows)
    @rows = rows
  end

  def each(&block)
    @rows.each(&block)
  end

  def ntuples
    @rows.length
  end

  def [](index)
    @rows[index]
  end

  def first
    @rows.first
  end
end
require 'sequel'
require 'cuid'
require 'date'
require_relative 'persistence'
require_relative 'models/rent_config'
require_relative 'models/tenant'
require_relative 'models/electricity_bill'
require_relative 'services/apply_electricity_bill'

# RentDb now acts as a thin compatibility wrapper around the new repository
# architecture. It exposes the underlying Sequel connection for low-level
# scripts while delegating all higher-level operations to repositories and
# domain models. New code should prefer using Persistence.* directly.
class RentDb
  # Thread-safe connection with automatic pooling (unchanged)
  def self.db
    @db ||= begin
      Sequel.connect(
        ENV.fetch('DATABASE_URL'),
        max_connections: 10,
        pool_timeout: 5,
        test: true,
        validate: true
      )
    end
  end

  # Dataset accessors retained for legacy scripts that still rely on raw Sequel
  def self.tenants
    db[:Tenant]
  end

  def self.rent_configs
    db[:RentConfig]
  end

  def self.rent_ledger
    db[:RentLedger]
  end

  def self.electricity_bills
    db[:ElectricityBill]
  end

  # Compatibility helpers -------------------------------------------------

  def get_tenants
    Persistence.tenants.all.map(&:to_h)
  end

  def get_rent_history(year:, month:)
    Persistence.rent_ledger.get_rent_history(year: year, month: month)
  end

  def get_rent_config(year:, month:)
    data = RentConfig.for_period(
      year: year,
      month: month,
      repository: Persistence.rent_configs
    )

    rows = data.map do |key, value|
      { 'key' => key, 'value' => value.to_s }
    end

    MockPGResult.new(rows)
  end

  def set_config(key, value, period = Time.now)
    Persistence.rent_configs.upsert(
      key: key,
      value: value,
      period: period
    )
    $pubsub&.publish('rent_data_updated')
  end

  def find_tenant_by_facebook_id(facebook_id)
    tenant = Persistence.tenants.find_by_facebook_id(facebook_id)
    tenant&.to_h
  end

  def find_tenant_by_email(email)
    tenant = Persistence.tenants.find_by_email(email)
    tenant&.to_h
  end

  def add_tenant(name:, email: nil, facebookId: nil, avatarUrl: nil, start_date: nil, departure_date: nil)
    email ||= "#{name.downcase.gsub(/\s+/, '.')}@kimonokittens.com"

    tenant = Tenant.new(
      name: name,
      email: email,
      facebook_id: facebookId,
      avatar_url: avatarUrl,
      start_date: start_date,
      departure_date: departure_date
    )

    created = Persistence.tenants.create(tenant)
    $pubsub&.publish('rent_data_updated')
    created.id
  end

  def set_start_date(name:, date:)
    update_tenant_date(name: name, date: date, action: :set_start_date)
  end

  def set_departure_date(name:, date:)
    update_tenant_date(name: name, date: date, action: :set_departure_date)
  end

  def set_room_adjustment(name:, adjustment:)
    tenant = Persistence.tenants.find_by_name(name)
    return false unless tenant

    updated = Persistence.tenants.set_room_adjustment(tenant.id, adjustment)
    $pubsub&.publish('rent_data_updated') if updated
    updated
  end

  def store_electricity_bill(provider:, amount:, due_date:)
    result = ApplyElectricityBill.call(
      provider: provider,
      amount: amount,
      due_date: due_date,
      electricity_repo: Persistence.electricity_bills,
      config_repo: Persistence.rent_configs
    )

    {
      inserted: result[:inserted],
      bill_period: result[:bill_period],
      reason: result[:reason],
      aggregated_total: result[:aggregated_total],
      config_updated: result[:config_updated]
    }
  end

  # Delegate to domain logic for compatibility
  def self.calculate_bill_period(due_date)
    ElectricityBill.calculate_bill_period(due_date)
  end

  def self.instance
    @instance ||= new
  end

  private

  def update_tenant_date(name:, date:, action:)
    tenant = Persistence.tenants.find_by_name(name)
    return false unless tenant

    updated = case action
    when :set_start_date
      Persistence.tenants.set_start_date(tenant.id, date)
    when :set_departure_date
      Persistence.tenants.set_departure_date(tenant.id, date)
    else
      false
    end

    $pubsub&.publish('rent_data_updated') if updated
    updated
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

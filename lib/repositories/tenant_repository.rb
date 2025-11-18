require_relative 'base_repository'
require_relative '../models/tenant'
require 'cuid'

# TenantRepository handles persistence for tenant records
#
# Provides:
# - CRUD operations
# - Active tenant queries
# - Email/Facebook ID lookups
#
# PRESERVED LOGIC from rent_db.rb (tenant queries)
class TenantRepository < BaseRepository
  def table_name
    :Tenant
  end

  # Find tenant by ID
  # @param id [String] Tenant ID
  # @return [Tenant, nil]
  def find_by_id(id)
    row = dataset.where(id: id).first
    row && hydrate(row)
  end

  # Find tenant by email
  # @param email [String] Email address
  # @return [Tenant, nil]
  def find_by_email(email)
    row = dataset.where(email: email).first
    row && hydrate(row)
  end

  # Find tenant by personnummer (ignores formatting characters)
  # @param value [String] Personnummer plain or formatted
  # @return [Tenant, nil]
  def find_by_personnummer(value)
    normalized = normalize_personnummer(value)
    return nil if normalized.empty?

    row = dataset.where(personnummer: value).first
    row ||= dataset.where(personnummer: normalized).first

    unless row
      row = dataset
        .exclude(personnummer: nil)
        .all
        .find { |entry| normalize_personnummer(entry[:personnummer]) == normalized }
    end

    row && hydrate(row)
  end

  # Find tenant by Facebook ID
  # @param facebook_id [String] Facebook ID
  # @return [Tenant, nil]
  def find_by_facebook_id(facebook_id)
    row = dataset.where(facebookId: facebook_id).first
    row && hydrate(row)
  end

  # Find tenant by name
  # @param name [String] Tenant name
  # @return [Tenant, nil]
  def find_by_name(name)
    row = dataset.where(name: name).first
    row && hydrate(row)
  end

  # Find tenant by phone number (E.164 format)
  # @param phone [String] Phone number in E.164 format (e.g., "+46701234567")
  # @return [Tenant, nil]
  def find_by_phone_e164(phone)
    row = dataset.where(phoneE164: phone).first
    row && hydrate(row)
  end

  # Find all tenants active on a specific date
  # @param date [Date] Date to check
  # @return [Array<Tenant>]
  def find_active_on(date)
    dataset
      .where { (Sequel.qualify(:Tenant, :startDate) <= date) | (Sequel.qualify(:Tenant, :startDate) =~ nil) }
      .where { (Sequel.qualify(:Tenant, :departureDate) >= date) | (Sequel.qualify(:Tenant, :departureDate) =~ nil) }
      .order(:name)
      .map { |row| hydrate(row) }
  end

  # Find all currently active tenants (no departure date)
  # @return [Array<Tenant>]
  def find_active
    dataset
      .where(Sequel.qualify(:Tenant, :departureDate) => nil)
      .order(:name)
      .map { |row| hydrate(row) }
  end

  # Get all tenants ordered by name
  #
  # PRESERVED LOGIC from rent_db.rb:77-85 (get_tenants)
  #
  # @return [Array<Tenant>]
  def all
    dataset
      .select(:id, :name, :email, :startDate, :departureDate, :roomAdjustment, :room, :status,
              :personnummer, :phone, :deposit, :furnishingDeposit,
              :facebookId, :avatarUrl, :createdAt, :updatedAt)
      .order(:name)
      .map { |row| hydrate(row) }
  end

  # Count total tenants
  # @return [Integer]
  def count
    dataset.count
  end

  # Create new tenant
  # @param tenant [Tenant] Tenant to persist
  # @return [Tenant] Tenant with ID assigned
  def create(tenant)
    id = dataset.insert(dehydrate(tenant))

    Tenant.new(
      id: id,
      name: tenant.name,
      email: tenant.email,
      facebook_id: tenant.facebook_id,
      avatar_url: tenant.avatar_url,
      room_adjustment: tenant.room_adjustment,
      room: tenant.room,
      start_date: tenant.start_date,
      departure_date: tenant.departure_date,
      status: tenant.status,
      created_at: now_utc,
      updated_at: now_utc,
      # Contract fields
      personnummer: tenant.personnummer,
      phone: tenant.phone,
      deposit: tenant.deposit,
      furnishing_deposit: tenant.furnishing_deposit
    )
  end

  # Update existing tenant
  # @param tenant [Tenant] Tenant to update
  # @return [Tenant] Updated tenant
  def update(tenant)
    raise ArgumentError, "Cannot update tenant without ID" unless tenant.id

    # Verify record exists before attempting update
    existing = dataset.where(id: tenant.id).first
    raise ArgumentError, "Tenant not found: #{tenant.id}" unless existing

    rows_affected = dataset.where(id: tenant.id).update(
      name: tenant.name,
      email: tenant.email,
      facebookId: tenant.facebook_id,
      avatarUrl: tenant.avatar_url,
      roomAdjustment: tenant.room_adjustment,
      room: tenant.room,
      startDate: tenant.start_date,
      departureDate: tenant.departure_date,
      status: tenant.status,
      updatedAt: now_utc,
      # Contract fields
      personnummer: tenant.personnummer,
      phone: tenant.phone,
      deposit: tenant.deposit,
      furnishingDeposit: tenant.furnishing_deposit,
      # SMS reminder fields
      smsOptOut: tenant.sms_opt_out,
      paydayStartDay: tenant.payday_start_day
    )

    raise "Update failed: database returned 0 rows affected for tenant #{tenant.id} (record exists but update was rejected)" if rows_affected == 0

    tenant
  end

  # Update tenant's start date
  # @param tenant_id [String] Tenant ID
  # @param date [Date] Start date
  # @return [Boolean] True if updated
  def set_start_date(tenant_id, date)
    dataset.where(id: tenant_id).update(startDate: date, updatedAt: now_utc) > 0
  end

  # Update tenant's departure date
  # @param tenant_id [String] Tenant ID
  # @param date [Date] Departure date
  # @return [Boolean] True if updated
  def set_departure_date(tenant_id, date)
    dataset.where(id: tenant_id).update(departureDate: date, updatedAt: now_utc) > 0
  end

  # Update tenant's room adjustment
  # @param tenant_id [String] Tenant ID
  # @param adjustment [Float] Room adjustment amount
  # @return [Boolean] True if updated
  def set_room_adjustment(tenant_id, adjustment)
    dataset.where(id: tenant_id).update(roomAdjustment: adjustment, updatedAt: now_utc) > 0
  end

  # Delete tenant by ID
  # @param id [String] Tenant ID
  # @return [Boolean] True if deleted
  def delete(id)
    dataset.where(id: id).delete > 0
  end

  private

  # Convert database row to domain object
  # @param row [Hash] Database row
  # @return [Tenant]
  def hydrate(row)
    Tenant.new(
      id: row[:id],
      name: row[:name],
      email: row[:email],
      facebook_id: row[:facebookId],
      avatar_url: row[:avatarUrl],
      room_adjustment: row[:roomAdjustment],
      room: row[:room],
      start_date: row[:startDate],
      departure_date: row[:departureDate],
      status: row[:status],
      created_at: row[:createdAt],
      updated_at: row[:updatedAt],
      # Contract fields
      personnummer: row[:personnummer],
      phone: row[:phone],
      phone_e164: row[:phoneE164],
      deposit: row[:deposit],
      furnishing_deposit: row[:furnishingDeposit],
      # SMS reminder fields
      sms_opt_out: row[:smsOptOut] || false,
      payday_start_day: row[:paydayStartDay] || 25
    )
  end

  def normalize_personnummer(value)
    value.to_s.gsub(/\D/, '')
  end

  # Convert domain object to database hash
  # @param tenant [Tenant] Domain object
  # @return [Hash] Database columns
  def dehydrate(tenant)
    {
      id: tenant.id || generate_id,
      name: tenant.name,
      email: tenant.email,
      facebookId: tenant.facebook_id,
      avatarUrl: tenant.avatar_url,
      roomAdjustment: tenant.room_adjustment,
      room: tenant.room,
      startDate: tenant.start_date,
      departureDate: tenant.departure_date,
      status: tenant.status,
      createdAt: tenant.created_at || now_utc,
      updatedAt: tenant.updated_at || now_utc,
      # Contract fields
      personnummer: tenant.personnummer,
      phone: tenant.phone,
      deposit: tenant.deposit,
      furnishingDeposit: tenant.furnishing_deposit,
      # SMS reminder fields
      smsOptOut: tenant.sms_opt_out,
      paydayStartDay: tenant.payday_start_day
    }
  end
end

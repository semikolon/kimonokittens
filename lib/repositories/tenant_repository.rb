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
      .select(:id, :name, :email, :startDate, :departureDate, :roomAdjustment)
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
      start_date: tenant.start_date,
      departure_date: tenant.departure_date,
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

    dataset.where(id: tenant.id).update(
      name: tenant.name,
      email: tenant.email,
      facebookId: tenant.facebook_id,
      avatarUrl: tenant.avatar_url,
      roomAdjustment: tenant.room_adjustment,
      startDate: tenant.start_date,
      departureDate: tenant.departure_date,
      updatedAt: now_utc,
      # Contract fields
      personnummer: tenant.personnummer,
      phone: tenant.phone,
      deposit: tenant.deposit,
      furnishingDeposit: tenant.furnishing_deposit
    )

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
      start_date: row[:startDate],
      departure_date: row[:departureDate],
      created_at: row[:createdAt],
      updated_at: row[:updatedAt],
      # Contract fields
      personnummer: row[:personnummer],
      phone: row[:phone],
      deposit: row[:deposit],
      furnishing_deposit: row[:furnishingDeposit]
    )
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
      startDate: tenant.start_date,
      departureDate: tenant.departure_date,
      createdAt: tenant.created_at || now_utc,
      updatedAt: tenant.updated_at || now_utc,
      # Contract fields
      personnummer: tenant.personnummer,
      phone: tenant.phone,
      deposit: tenant.deposit,
      furnishingDeposit: tenant.furnishing_deposit
    }
  end
end

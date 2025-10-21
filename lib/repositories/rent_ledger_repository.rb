require_relative 'base_repository'
require_relative '../models/rent_ledger'
require 'cuid'

# RentLedgerRepository handles persistence for rent ledger entries
#
# Provides:
# - Ledger entry creation (immutable records)
# - Period-based queries
# - Tenant payment history
#
# PRESERVED LOGIC from rent_db.rb (ledger queries)
class RentLedgerRepository < BaseRepository
  def table_name
    :RentLedger
  end

  # Find ledger entry by ID
  # @param id [String] Ledger entry ID
  # @return [RentLedger, nil]
  def find_by_id(id)
    row = dataset.where(id: id).first
    row && hydrate(row)
  end

  # Find ledger entry for specific tenant and period
  # @param tenant_id [String] Tenant ID
  # @param period [Time, Date] Rent period
  # @return [RentLedger, nil]
  def find_by_tenant_and_period(tenant_id, period)
    normalized_period = normalize_period(period)
    row = dataset.where(tenantId: tenant_id, period: normalized_period).first
    row && hydrate(row)
  end

  # Find all ledger entries for a specific period
  # @param period [Time, Date] Rent period
  # @return [Array<RentLedger>]
  def find_by_period(period)
    normalized_period = normalize_period(period)
    dataset
      .where(period: normalized_period)
      .order(:tenantId)
      .map { |row| hydrate(row) }
  end

  # Find all ledger entries for a specific tenant
  # @param tenant_id [String] Tenant ID
  # @return [Array<RentLedger>] Ordered by period (most recent first)
  def find_by_tenant(tenant_id)
    dataset
      .where(tenantId: tenant_id)
      .order(Sequel.desc(:period))
      .map { |row| hydrate(row) }
  end

  # Get rent history for a specific period
  #
  # PRESERVED LOGIC from rent_db.rb:95-104 (get_rent_history)
  #
  # @param year [Integer] The rent period year
  # @param month [Integer] The rent period month (1-12)
  # @return [Array<RentLedger>] Array of rent ledger records for the period
  def get_rent_history(year:, month:)
    # Construct date range (same as original)
    start_date = Time.new(year, month, 1).utc
    end_date = start_date + (31 * 24 * 60 * 60) # Safe way to get to next month

    dataset
      .where(period: start_date...end_date)
      .order(:createdAt)
      .map { |row| hydrate(row) }
  end

  # Find unpaid entries for a tenant
  # @param tenant_id [String] Tenant ID
  # @return [Array<RentLedger>]
  def find_unpaid_by_tenant(tenant_id)
    dataset
      .where(tenantId: tenant_id)
      .where { amountPaid < amountDue }
      .order(:period)
      .map { |row| hydrate(row) }
  end

  # Count ledger entries
  # @return [Integer]
  def count
    dataset.count
  end

  # Create new ledger entry
  # @param ledger_entry [RentLedger] Entry to persist
  # @return [RentLedger] Entry with ID assigned
  def create(ledger_entry)
    # Ledger entries are immutable - generate ID now
    id = ledger_entry.id || generate_id

    dataset.insert(dehydrate(ledger_entry.dup.tap { |e|
      e.instance_variable_set(:@id, id)
    }))

    # Return with ID
    RentLedger.new(
      id: id,
      tenant_id: ledger_entry.tenant_id,
      period: ledger_entry.period,
      amount_due: ledger_entry.amount_due,
      amount_paid: ledger_entry.amount_paid,
      payment_date: ledger_entry.payment_date,
      days_stayed: ledger_entry.days_stayed,
      room_adjustment: ledger_entry.room_adjustment,
      base_monthly_rent: ledger_entry.base_monthly_rent,
      calculation_title: ledger_entry.calculation_title,
      calculation_date: ledger_entry.calculation_date,
      created_at: ledger_entry.created_at
    )
  end

  # Update payment information (only allowed field to change)
  # @param ledger_id [String] Ledger entry ID
  # @param amount_paid [Float] Amount paid
  # @param payment_date [Time] Payment date
  # @return [Boolean] True if updated
  def record_payment(ledger_id, amount_paid, payment_date)
    dataset.where(id: ledger_id).update(
      amountPaid: amount_paid,
      paymentDate: payment_date
    ) > 0
  end

  # Delete ledger entry by ID
  # WARNING: Ledger should be immutable - delete only for corrections
  # @param id [String] Ledger entry ID
  # @return [Boolean] True if deleted
  def delete(id)
    dataset.where(id: id).delete > 0
  end

  private

  # Normalize period to month start (UTC Time)
  # @param period [Date, Time] Period input
  # @return [Time] Normalized time
  def normalize_period(period)
    case period
    when Time
      Time.utc(period.year, period.month, 1)
    when Date
      Time.utc(period.year, period.month, 1)
    else
      raise ArgumentError, "Invalid period type: #{period.class}"
    end
  end

  # Convert database row to domain object
  # @param row [Hash] Database row
  # @return [RentLedger]
  def hydrate(row)
    RentLedger.new(
      id: row[:id],
      tenant_id: row[:tenantId],
      period: row[:period],
      amount_due: row[:amountDue],
      amount_paid: row[:amountPaid],
      payment_date: row[:paymentDate],
      days_stayed: row[:daysStayed],
      room_adjustment: row[:roomAdjustment],
      base_monthly_rent: row[:baseMonthlyRent],
      calculation_title: row[:calculationTitle],
      calculation_date: row[:calculationDate],
      created_at: row[:createdAt]
    )
  end

  # Convert domain object to database hash
  # @param ledger_entry [RentLedger] Domain object
  # @return [Hash] Database columns
  def dehydrate(ledger_entry)
    {
      id: ledger_entry.id,
      tenantId: ledger_entry.tenant_id,
      period: ledger_entry.period,
      amountDue: ledger_entry.amount_due,
      amountPaid: ledger_entry.amount_paid,
      paymentDate: ledger_entry.payment_date,
      daysStayed: ledger_entry.days_stayed,
      roomAdjustment: ledger_entry.room_adjustment,
      baseMonthlyRent: ledger_entry.base_monthly_rent,
      calculationTitle: ledger_entry.calculation_title,
      calculationDate: ledger_entry.calculation_date,
      createdAt: ledger_entry.created_at
    }
  end
end

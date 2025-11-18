require_relative 'base_repository'
require_relative '../models/rent_receipt'
require 'cuid'
require 'bigdecimal'

# RentReceiptRepository handles persistence for rent payment receipts
#
# Provides:
# - Receipt creation and retrieval
# - Tenant/month-based queries
# - Payment aggregation calculations
#
# Schema mapping (actual Prisma schema):
# - month: String ("2025-11" format)
# - tenantId: String (FK to Tenant)
# - matchedTxId: String (nullable FK to BankTransaction)
# - matchedVia: String ("reference" | "amount+name" | "manual")
# - partial: Boolean (default false)
# - paidAt: DateTime
# - amount: Decimal(12,2)
#
# NO BUSINESS LOGIC - Pure persistence
# Business rules belong in models or services
class RentReceiptRepository < BaseRepository
  def table_name
    :RentReceipt
  end

  # Find receipt by ID
  # @param id [String] Receipt ID
  # @return [RentReceipt, nil]
  def find_by_id(id)
    row = dataset.where(id: id).first
    row && hydrate(row)
  end

  # Find all receipts for a tenant in a specific month
  # @param tenant_id [String] Tenant ID
  # @param year [Integer] Year (2025)
  # @param month [Integer] Month (1-12)
  # @return [Array<RentReceipt>]
  def find_by_tenant(tenant_id, year:, month:)
    month_str = format('%04d-%02d', year, month)
    dataset
      .where(tenantId: tenant_id, month: month_str)
      .order(Sequel.desc(:paidAt))
      .map { |row| hydrate(row) }
  end

  # Calculate total paid for tenant in specific month
  # @param tenant_id [String] Tenant ID
  # @param year [Integer] Year
  # @param month [Integer] Month (1-12)
  # @return [Float] Total amount paid
  def total_paid_for_tenant_month(tenant_id, year:, month:)
    month_str = format('%04d-%02d', year, month)
    result = dataset
      .where(tenantId: tenant_id, month: month_str)
      .sum(:amount)

    result ? result.to_f : 0.0
  end

  # Retrieve all receipts ordered by paid_at descending
  # @return [Array<RentReceipt>]
  def all
    dataset
      .order(Sequel.desc(:paidAt))
      .map { |row| hydrate(row) }
  end

  # Create new receipt from domain object
  # @param receipt [RentReceipt] Receipt to persist
  # @return [RentReceipt] Receipt with ID assigned
  def create(receipt)
    id = dataset.insert(dehydrate(receipt))

    RentReceipt.new(
      id: id,
      tenant_id: receipt.tenant_id,
      month: receipt.month,
      amount: receipt.amount,
      paid_at: receipt.paid_at,
      matched_via: receipt.matched_via,
      matched_tx_id: receipt.matched_tx_id,
      partial: receipt.partial,
      created_at: now_utc
    )
  end

  # Delete receipt by ID
  # @param id [String] Receipt ID
  # @return [Boolean] True if deleted
  def delete(id)
    dataset.where(id: id).delete > 0
  end

  private

  # Convert database row to domain object
  # @param row [Hash] Database row
  # @return [RentReceipt]
  def hydrate(row)
    RentReceipt.new(
      id: row[:id],
      tenant_id: row[:tenantId],
      month: row[:month],
      amount: row[:amount].to_f,
      paid_at: row[:paidAt],
      matched_via: row[:matchedVia],
      matched_tx_id: row[:matchedTxId],
      partial: row[:partial],
      created_at: row[:createdAt]
    )
  end

  # Convert domain object to database hash
  # @param receipt [RentReceipt] Domain object
  # @return [Hash] Database columns
  def dehydrate(receipt)
    {
      id: receipt.id || generate_id,
      tenantId: receipt.tenant_id,
      month: receipt.month,
      amount: BigDecimal(receipt.amount.to_s),
      paidAt: receipt.paid_at,
      matchedVia: receipt.matched_via,
      matchedTxId: receipt.matched_tx_id,
      partial: receipt.partial,
      createdAt: receipt.created_at || now_utc
    }
  end
end

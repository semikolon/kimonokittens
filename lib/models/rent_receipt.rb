require 'time'

# RentReceipt domain model representing a rent payment receipt
#
# Links bank transactions to tenant rent payments (double-entry ledger pattern)
#
# Business Logic:
# - Payment matching classification (reference, phone, amount+name, manual)
# - Partial payment detection
# - Payment completion verification
# - Month-based payment tracking
#
# Schema fields (actual database):
# - month: "2025-11" (ISO month string)
# - matchedTxId: Foreign key to BankTransaction (nullable)
# - matchedVia: "reference" | "phone" | "amount+name" | "manual"
# - partial: Boolean flag for partial payments
#
# NO DATABASE ACCESS - Pure domain model
# Use RentReceiptRepository for persistence
class RentReceipt
  VALID_MATCHED_VIA = %w[reference phone amount+name manual].freeze

  attr_reader :id, :tenant_id, :month, :amount, :paid_at, :matched_via,
              :matched_tx_id, :partial, :created_at

  def initialize(
    id: nil,
    tenant_id:,
    month:,
    amount:,
    paid_at:,
    matched_via:,
    matched_tx_id: nil,
    partial: false,
    created_at: nil
  )
    @id = id
    @tenant_id = tenant_id
    @month = month
    @amount = amount
    @paid_at = paid_at
    @matched_via = matched_via
    @matched_tx_id = matched_tx_id
    @partial = partial
    @created_at = created_at
    validate!
  end

  # Check if this was matched by reference code
  # @return [Boolean]
  def reference_match?
    matched_via == 'reference'
  end

  # Check if this was matched by phone number (Swish)
  # @return [Boolean]
  def phone_match?
    matched_via == 'phone'
  end

  # Check if this was matched by amount and name fuzzy matching
  # @return [Boolean]
  def fuzzy_match?
    matched_via == 'amount+name'
  end

  # Check if this was manually created (not from bank transaction)
  # @return [Boolean]
  def manual_entry?
    matched_via == 'manual'
  end

  # Check if this is linked to a bank transaction
  # @return [Boolean]
  def has_bank_transaction?
    !matched_tx_id.nil?
  end

  # Check if this is a partial payment
  # @return [Boolean]
  def partial_payment?
    partial
  end

  # Check if this receipt completes the payment for the ledger
  # (requires checking all receipts for the month)
  # @param total_amount_due [Numeric] The total amount due for the month
  # @param other_receipts [Array<RentReceipt>] Other receipts for this month
  # @return [Boolean]
  def completes_payment?(total_amount_due, other_receipts = [])
    total_paid = amount + other_receipts.sum(&:amount)
    total_paid >= total_amount_due
  end

  def to_s
    "RentReceipt[#{id}] #{month} - #{amount} SEK (#{matched_via}#{partial ? ', partial' : ''})"
  end

  private

  def validate!
    raise ArgumentError, "tenant_id required" if tenant_id.nil? || tenant_id.empty?
    raise ArgumentError, "month required" if month.nil? || month.empty?
    raise ArgumentError, "month must be YYYY-MM format" unless month.match?(/^\d{4}-\d{2}$/)
    raise ArgumentError, "amount required" if amount.nil?
    raise ArgumentError, "amount must be positive" if amount <= 0
    raise ArgumentError, "paid_at required" if paid_at.nil?
    raise ArgumentError, "matched_via must be one of: #{VALID_MATCHED_VIA.join(', ')}" unless VALID_MATCHED_VIA.include?(matched_via)
  end
end

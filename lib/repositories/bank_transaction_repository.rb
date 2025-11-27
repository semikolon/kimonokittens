require_relative 'base_repository'
require_relative '../models/bank_transaction'
require 'cuid'
require 'json'

# BankTransactionRepository handles persistence for bank transaction records
#
# Provides:
# - CRUD operations
# - Upsert by external_id (deduplication from Lunch Flow API)
# - Unreconciled transaction queries
# - Reconciliation marking (links to RentReceipt)
#
# PRESERVED LOGIC from implementation plan (bank sync + reconciliation)
class BankTransactionRepository < BaseRepository
  def table_name
    :BankTransaction
  end

  # Find transaction by ID
  # @param id [String] Transaction ID
  # @return [BankTransaction, nil]
  def find_by_id(id)
    row = dataset.where(id: id).first
    row && hydrate(row)
  end

  # Find transaction by external_id (Lunch Flow transaction ID)
  # @param external_id [String] Lunch Flow transaction ID
  # @return [BankTransaction, nil]
  def find_by_external_id(external_id)
    row = dataset.where(externalId: external_id).first
    row && hydrate(row)
  end

  # Get all transactions
  # @return [Array<BankTransaction>]
  def all
    dataset.all.map { |row| hydrate(row) }
  end

  # Find all unreconciled transactions (not yet matched to rent receipts)
  #
  # PRESERVED LOGIC from implementation plan (reconciliation flow)
  #
  # @param limit [Integer] Maximum number of transactions to return
  # @return [Array<BankTransaction>]
  def find_unreconciled(limit: 50)
    dataset
      .where(reconciledAt: nil)
      .order(Sequel.desc(:bookedAt))
      .limit(limit)
      .map { |row| hydrate(row) }
  end

  # Create new transaction
  # @param transaction [BankTransaction] Transaction to persist
  # @return [BankTransaction] Transaction with ID assigned
  def create(transaction)
    id = dataset.insert(dehydrate(transaction))

    BankTransaction.new(
      id: id,
      external_id: transaction.external_id,
      account_id: transaction.account_id,
      booked_at: transaction.booked_at,
      amount: transaction.amount,
      currency: transaction.currency,
      description: transaction.description,
      counterparty: transaction.counterparty,
      raw_json: transaction.raw_json,
      created_at: now_utc
    )
  end

  # Upsert transaction by external_id (insert if new, update if exists)
  #
  # PRESERVED LOGIC from implementation plan (bank sync deduplication)
  #
  # @param external_id [String] Lunch Flow transaction ID
  # @param account_id [String] Account ID
  # @param booked_at [DateTime] When transaction posted
  # @param amount [Float] Transaction amount
  # @param currency [String] Currency code
  # @param description [String] Transaction description
  # @param counterparty [String, nil] Counterparty name
  # @param raw_json [Hash] Full API response
  # @return [BankTransaction] Created or updated transaction
  def upsert(external_id:, account_id:, booked_at:, amount:, currency:,
             description: nil, counterparty: nil, raw_json:)
    existing = find_by_external_id(external_id)

    if existing
      # Update existing transaction (Sequel auto-converts hash to JSONB)
      dataset.where(externalId: external_id).update(
        accountId: account_id,
        bookedAt: booked_at,
        amount: amount,
        currency: currency,
        description: description,
        counterparty: counterparty,
        rawJson: raw_json.to_json
      )

      find_by_external_id(external_id)
    else
      # Insert new transaction
      create(BankTransaction.new(
        external_id: external_id,
        account_id: account_id,
        booked_at: booked_at,
        amount: amount,
        currency: currency,
        description: description,
        counterparty: counterparty,
        raw_json: raw_json
      ))
    end
  end

  # Mark transaction as reconciled (linked to rent receipt)
  #
  # PRESERVED LOGIC from implementation plan (payment matching flow)
  #
  # @param id [String] Transaction ID
  # @param rent_receipt_id [String] Rent receipt ID
  # @return [Boolean] True if updated
  def mark_reconciled(id, rent_receipt_id)
    rows_affected = dataset.where(id: id).update(
      reconciledAt: now_utc,
      rentReceiptId: rent_receipt_id
    )

    rows_affected > 0
  end

  private

  # Convert database row to domain object
  # @param row [Hash] Database row
  # @return [BankTransaction]
  def hydrate(row)
    BankTransaction.new(
      id: row[:id],
      external_id: row[:externalId],
      account_id: row[:accountId],
      booked_at: row[:bookedAt],
      amount: row[:amount],
      currency: row[:currency],
      description: row[:description],
      counterparty: row[:counterparty],
      raw_json: row[:rawJson],
      created_at: row[:createdAt]
    )
  end

  # Convert domain object to database hash
  # @param transaction [BankTransaction] Domain object
  # @return [Hash] Database columns
  def dehydrate(transaction)
    {
      id: transaction.id || generate_id,
      externalId: transaction.external_id,
      accountId: transaction.account_id,
      bookedAt: transaction.booked_at,
      amount: transaction.amount,
      currency: transaction.currency,
      description: transaction.description,
      counterparty: transaction.counterparty,
      rawJson: transaction.raw_json.to_json,  # Sequel auto-converts JSON string to JSONB
      createdAt: transaction.created_at || now_utc
    }
  end
end

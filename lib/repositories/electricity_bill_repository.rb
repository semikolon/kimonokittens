require_relative 'base_repository'
require_relative '../models/electricity_bill'
require 'cuid'
require 'date'

# ElectricityBillRepository handles persistence for electricity bills
#
# Provides:
# - CRUD operations via Sequel
# - Deduplication (provider + billDate + amount composite key)
# - Period-based queries for aggregation
#
# PRESERVED LOGIC from rent_db.rb:277-310
class ElectricityBillRepository < BaseRepository
  def table_name
    :ElectricityBill
  end

  # Find bill by ID
  # @param id [String] Bill ID
  # @return [ElectricityBill, nil]
  def find_by_id(id)
    row = dataset.where(id: id).first
    row && hydrate(row)
  end

  # Find all bills for a specific billing period
  # @param period [Date, Time] Billing period (first day of month)
  # @return [Array<ElectricityBill>]
  def find_by_period(period)
    # Normalize to Date for comparison
    period_date = period.is_a?(Date) ? period : period.to_date

    dataset
      .where(billPeriod: period_date)
      .order(:billDate)
      .map { |row| hydrate(row) }
  end

  # Find all bills (for reporting/analysis)
  # @return [Array<ElectricityBill>]
  def all
    dataset.order(Sequel.desc(:billDate)).map { |row| hydrate(row) }
  end

  # Count total bills
  # @return [Integer]
  def count
    dataset.count
  end

  # Store electricity bill with automatic deduplication
  #
  # PRESERVED LOGIC from rent_db.rb:277-310
  #
  # @param provider [String] Provider name (e.g., "Vattenfall", "Fortum")
  # @param amount [Float] Bill amount in kronor
  # @param due_date [Date, String] Due date (will be parsed if string)
  #
  # @return [Hash] Result with :inserted (boolean), :bill (ElectricityBill), and :bill_period (Date)
  #
  # @example Store a Vattenfall invoice
  #   result = repo.store_with_deduplication(
  #     provider: 'Vattenfall',
  #     amount: 1685.69,
  #     due_date: Date.new(2025, 11, 3)
  #   )
  #   # => { inserted: true, bill: #<ElectricityBill>, bill_period: #<Date: 2025-09-01> }
  def store_with_deduplication(provider:, amount:, due_date:)
    # Parse due_date if it's a string
    due_date = Date.parse(due_date) if due_date.is_a?(String)

    # Calculate billing period using domain model logic
    bill_period = ElectricityBill.calculate_bill_period(due_date)

    # Check for duplicate (same provider + period)
    # Only ONE bill per provider per config period allowed
    existing = dataset
      .where(
        provider: provider,
        billPeriod: bill_period
      )
      .first

    if existing
      # Only update bills for current or future months (preserve historical rent calculations)
      current_month = Date.new(Date.today.year, Date.today.month, 1)

      if bill_period >= current_month
        # Update existing bill with new due_date and amount
        # (handles corrections or due date variations like Sept 30 vs Oct 1)
        dataset
          .where(id: existing[:id])
          .update(
            billDate: due_date,
            amount: amount,
            updatedAt: Time.now.utc
          )

        updated_bill = hydrate(dataset.where(id: existing[:id]).first)

        {
          inserted: false,
          bill: updated_bill,
          bill_period: bill_period,
          reason: 'updated'
        }
      else
        # Past bill - preserve historical data, don't update
        {
          inserted: false,
          bill: hydrate(existing),
          bill_period: bill_period,
          reason: 'historical_preserved'
        }
      end
    else
      # Create new bill
      bill = ElectricityBill.new(
        provider: provider,
        bill_date: due_date,
        amount: amount,
        bill_period: bill_period
      )

      # Insert and return
      created_bill = create(bill)

      {
        inserted: true,
        bill: created_bill,
        bill_period: bill_period
      }
    end
  end

  # Create new bill record
  # @param bill [ElectricityBill] Bill to persist
  # @return [ElectricityBill] Bill with ID assigned
  def create(bill)
    id = dataset.insert(dehydrate(bill))

    # Return new instance with ID
    ElectricityBill.new(
      id: id,
      provider: bill.provider,
      bill_date: bill.bill_date,
      amount: bill.amount,
      bill_period: bill.bill_period,
      created_at: now_utc,
      updated_at: now_utc
    )
  end

  # Update existing bill
  # @param bill [ElectricityBill] Bill to update
  # @return [ElectricityBill] Updated bill
  def update(bill)
    raise ArgumentError, "Cannot update bill without ID" unless bill.id

    dataset.where(id: bill.id).update(
      provider: bill.provider,
      billDate: bill.bill_date,
      amount: bill.amount,
      billPeriod: bill.bill_period,
      updatedAt: now_utc
    )

    bill
  end

  # Delete bill by ID
  # @param id [String] Bill ID
  # @return [Boolean] True if deleted
  def delete(id)
    dataset.where(id: id).delete > 0
  end

  private

  # Convert database row to domain object
  # @param row [Hash] Database row
  # @return [ElectricityBill]
  def hydrate(row)
    ElectricityBill.new(
      id: row[:id],
      provider: row[:provider],
      bill_date: normalize_date(row[:billDate]),
      amount: row[:amount],
      bill_period: normalize_date(row[:billPeriod]),
      created_at: row[:createdAt],
      updated_at: row[:updatedAt]
    )
  end

  # Convert domain object to database hash
  # @param bill [ElectricityBill] Domain object
  # @return [Hash] Database columns
  def dehydrate(bill)
    {
      id: bill.id || generate_id,
      provider: bill.provider,
      billDate: bill.bill_date,
      amount: bill.amount,
      billPeriod: bill.bill_period,
      createdAt: bill.created_at || now_utc,
      updatedAt: bill.updated_at || now_utc
    }
  end

  def normalize_date(value)
    case value
    when Date
      value
    when Time
      value.to_date
    when String
      Date.parse(value)
    else
      value
    end
  end
end

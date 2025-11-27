require_relative '../persistence'
require_relative '../models/bank_transaction'

# PaymentAggregator finds multi-day partial payment combinations
# that sum to expected rent amount.
#
# Handles cases like:
# - Nov 18: 3,000 kr (partial)
# - Nov 24: 3,303 kr (completing)
# - Total: 6,303 kr = full rent
#
# Rules:
# - Only considers payments in rent-paying window (day 15-31)
#   - Rent due on 27th, but allows late payments through end of month
# - Max 14 days between any two payments in a group
# - Tolerance: max(100 kr, expected_rent × 1%)
# - Prefers latter combinations (exact match more likely in last payment)
#
# @example
#   PaymentAggregator.find_partial_groups(tenant, Date.new(2025, 11, 1))
class PaymentAggregator
  RENT_PAYING_WINDOW_START = 15  # Day of month
  RENT_PAYING_WINDOW_END = 31    # Allow late payments through end of month
  MAX_DAYS_BETWEEN_PAYMENTS = 14

  def self.find_partial_groups(tenant, month_start)
    new(tenant, month_start).find_groups
  end

  def initialize(tenant, month_start)
    @tenant = tenant
    @month_start = month_start
    # Calculate last day of month using plain Ruby (no ActiveSupport)
    @month_end = Date.new(month_start.year, month_start.month, -1)
  end

  def find_groups
    unmatched = get_unmatched_transactions
    return [] if unmatched.empty?

    expected_rent = get_expected_rent
    return [] unless expected_rent

    tolerance = [100, expected_rent * 0.01].max
    matched_groups = []

    # Try 2-payment combinations
    unmatched.combination(2).each do |tx1, tx2|
      next unless within_time_window?(tx1, tx2)

      total = tx1.amount + tx2.amount
      diff = (total - expected_rent).abs

      if diff <= tolerance
        matched_groups << [tx1, tx2]
      end
    end

    # Remove matched transactions from pool
    matched_txs = matched_groups.flatten
    remaining = unmatched - matched_txs

    # Try 3-payment combinations (remaining unmatched)
    remaining.combination(3).each do |tx1, tx2, tx3|
      next unless within_time_window?(tx1, tx2, tx3)

      total = tx1.amount + tx2.amount + tx3.amount
      diff = (total - expected_rent).abs

      if diff <= tolerance
        matched_groups << [tx1, tx2, tx3]
      end
    end

    # Prefer latter combinations (exact match more likely in last payment)
    # Sort by: exact match first, then latest booked_at, then earliest booked_at
    sorted_groups = matched_groups.sort_by do |group|
      total = group.sum(&:amount)
      exact_match = (total - expected_rent).abs < 1
      # Convert DateTime to seconds since epoch for numeric comparison
      latest_time = group.max_by(&:booked_at).booked_at.to_time.to_i
      earliest_time = group.min_by(&:booked_at).booked_at.to_time.to_i
      # Prefer: exact match first, latest date later, earliest date later (tiebreaker)
      [exact_match ? 0 : 1, -latest_time, -earliest_time]
    end

    # Return only best match to avoid overlapping combinations
    sorted_groups.empty? ? [] : [sorted_groups.first]
  end

  private

  def get_unmatched_transactions
    # Get all incoming Swish in rent-paying window (day 15-27)
    # Plain Ruby date arithmetic: Date + Integer = Date
    start_date = @month_start + (RENT_PAYING_WINDOW_START - 1)
    end_date = @month_start + (RENT_PAYING_WINDOW_END - 1)

    all_txs = Persistence.bank_transactions.all.select do |tx|
      tx.incoming_swish_payment? &&
      tx.booked_at.to_date >= start_date &&
      tx.booked_at.to_date <= end_date &&
      tx.phone_matches?(@tenant)
    end

    # Filter out already matched transactions (have receipts)
    year = @month_start.year
    month = @month_start.month
    existing_receipt_tx_ids = Persistence.rent_receipts
      .find_by_tenant(@tenant.id, year: year, month: month)
      .map(&:matched_tx_id)
      .compact

    all_txs.reject { |tx| existing_receipt_tx_ids.include?(tx.id) }
  end

  def get_expected_rent
    ledger = Persistence.rent_ledger.find_by_tenant_and_period(
      @tenant.id,
      @month_start
    )
    ledger&.amount_due
  end

  def within_time_window?(*transactions)
    dates = transactions.map { |tx| tx.booked_at.to_date }
    date_range = dates.max - dates.min
    date_range.to_i <= MAX_DAYS_BETWEEN_PAYMENTS
  end
end

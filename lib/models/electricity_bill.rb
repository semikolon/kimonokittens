require 'date'
require_relative 'period'

# ElectricityBill domain model representing a provider invoice
#
# Encapsulates business logic for:
# - Billing period calculation from due dates
# - Provider bill deduplication
# - Aggregation for rent configuration
#
# CRITICAL TIMING LOGIC (preserved from rent_db.rb):
# Due date day-of-month determines when bill arrived:
# - Day 25-31: Bill arrived same month as due
# - Day 1-24: Bill arrived month BEFORE due
# - Consumption = arrival month - 1 month
#
# @example November 3 due date (Vattenfall)
#   bill = ElectricityBill.new(
#     provider: 'Vattenfall',
#     bill_date: Date.new(2025, 11, 3),
#     amount: 1685.69
#   )
#   bill.bill_period  # => 2025-09-01 (Sept consumption)
#
# @example September 30 due date (Vattenfall)
#   bill = ElectricityBill.new(
#     provider: 'Vattenfall',
#     bill_date: Date.new(2025, 9, 30),
#     amount: 1632.0
#   )
#   bill.bill_period  # => 2025-08-01 (Aug consumption)
class ElectricityBill
  attr_reader :id, :provider, :bill_date, :amount, :bill_period, :created_at, :updated_at

  def initialize(id: nil, provider:, bill_date:, amount:, bill_period: nil, created_at: nil, updated_at: nil)
    @id = id
    @provider = provider.to_s
    @bill_date = bill_date.is_a?(String) ? Date.parse(bill_date) : bill_date
    @amount = amount.to_f
    @bill_period = bill_period || self.class.calculate_bill_period(@bill_date)
    @created_at = created_at
    @updated_at = updated_at
    validate!
  end

  # Calculate billing period from invoice due date
  #
  # PRESERVED LOGIC from rent_db.rb:57-74 (CRITICAL - DO NOT MODIFY)
  #
  # Based on CLAUDE.md documentation ("Electricity Bill Due Date Timing"):
  #   - End-of-month bills (day 25-31): Bill arrived same month as due
  #   - Start-of-month bills (day 1-24): Bill arrived month before due
  #   - Consumption period is 1 month before arrival
  #
  # @param due_date [Date] The invoice due date
  # @return [Date] First day of the consumption/billing period month
  #
  # @example November 3 due date (Vattenfall)
  #   ElectricityBill.calculate_bill_period(Date.new(2025, 11, 3))
  #   # => 2025-09-01 (day 3 → arrived Oct → consumption Sept)
  #
  # @example September 30 due date (Vattenfall)
  #   ElectricityBill.calculate_bill_period(Date.new(2025, 9, 30))
  #   # => 2025-08-01 (day 30 → arrived Sept → consumption Aug)
  def self.calculate_bill_period(due_date)
    day = due_date.day

    # Determine when bill arrived based on due date day-of-month
    if day >= 25
      # End-of-month bill: arrived same month as due
      arrival_month = due_date
    else
      # Start-of-month bill: arrived month before due
      arrival_month = due_date << 1  # Subtract 1 month
    end

    # Consumption period is 1 month before arrival
    consumption_month = arrival_month << 1  # Subtract 1 month

    # Return first day of consumption month
    Date.new(consumption_month.year, consumption_month.month, 1)
  end

  # Aggregate bills for a specific period
  #
  # @param period [Date, Time] Billing period to aggregate
  # @param repository [ElectricityBillRepository] Repository instance
  # @return [Float] Total amount for period
  def self.aggregate_for_period(period, repository:)
    bills = repository.find_by_period(period)
    bills.sum(&:amount)
  end

  # Format amount as Swedish currency string
  # @return [String] Formatted amount (e.g., "1 685,69 kr")
  def formatted_amount
    parts = amount.round(2).to_s.split('.')
    integer = parts[0].reverse.gsub(/(\d{3})(?=\d)/, '\\1 ').reverse
    decimal = parts[1] || '00'
    "#{integer},#{decimal} kr"
  end

  # Check if bill is duplicate of another
  # @param other [ElectricityBill] Another bill
  # @return [Boolean]
  def duplicate_of?(other)
    provider == other.provider &&
    bill_date == other.bill_date &&
    amount == other.amount
  end

  def to_s
    "#{provider} #{formatted_amount} due #{bill_date}"
  end

  private

  def validate!
    raise ArgumentError, "Provider required" if provider.empty?
    raise ArgumentError, "Amount must be positive" unless amount > 0
    raise ArgumentError, "Bill date required" unless bill_date.is_a?(Date)
    raise ArgumentError, "Bill period required" unless bill_period.is_a?(Date)
  end
end

require 'date'
require 'time'

# RentLedger domain model representing a rent payment record
#
# Immutable ledger entry capturing:
# - Who owes what (tenant_id, amount_due)
# - What was paid (amount_paid, payment_date)
# - Why (audit trail: days_stayed, room_adjustment, calculation_title)
#
# Financial best practice: Immutable historical record
# - Cannot retroactively change past bills
# - Complete audit trail of HOW amount was calculated
# - Preserves context even if rules/prices change later
#
# IMPORTANT: Period semantics (unified with RentConfig)
# - period field = config month (when costs were incurred)
# - Rent month = period + 1 month (paid in advance)
# - Use .period_swedish or .config_to_rent_month for display
#
# @example Create ledger entry for April 2025 rent (paid in March)
#   entry = RentLedger.new(
#     tenant_id: 'cuid123',
#     period: Time.utc(2025, 3, 1),      # March config period
#     amount_due: 7045,
#     days_stayed: 31,
#     room_adjustment: 0,
#     calculation_title: 'April 2025'    # April rent
#   )
#   entry.period_swedish  # => "April 2025" (converts config→rent month)
class RentLedger
  attr_reader :id, :tenant_id, :period, :amount_due, :amount_paid,
              :payment_date, :days_stayed, :room_adjustment,
              :base_monthly_rent, :calculation_title, :calculation_date,
              :created_at

  def initialize(id: nil, tenant_id:, period:, amount_due:, amount_paid: 0,
                 payment_date: nil, days_stayed: nil, room_adjustment: nil,
                 base_monthly_rent: nil, calculation_title: nil, calculation_date: nil,
                 created_at: nil)
    @id = id
    @tenant_id = tenant_id.to_s
    @period = normalize_period(period)
    @amount_due = amount_due.to_f
    @amount_paid = amount_paid.to_f
    @payment_date = parse_datetime(payment_date)
    @days_stayed = days_stayed.to_f if days_stayed
    @room_adjustment = room_adjustment.to_f if room_adjustment
    @base_monthly_rent = base_monthly_rent.to_f if base_monthly_rent
    @calculation_title = calculation_title.to_s if calculation_title
    @calculation_date = parse_datetime(calculation_date)
    @created_at = created_at || Time.now.utc
    validate!
  end

  # Check if rent has been fully paid
  # @return [Boolean]
  def paid?
    amount_paid >= amount_due
  end

  # Check if partially paid
  # @return [Boolean]
  def partially_paid?
    amount_paid > 0 && amount_paid < amount_due
  end

  # Calculate outstanding amount
  # @return [Float] Amount still owed
  def outstanding
    [amount_due - amount_paid, 0].max
  end

  # Calculate overpayment (if any)
  # @return [Float] Amount overpaid
  def overpaid
    [amount_paid - amount_due, 0].max
  end

  # Get payment status as string
  # @return [String] "paid", "partially_paid", "unpaid"
  def payment_status
    return 'paid' if paid?
    return 'partially_paid' if partially_paid?
    'unpaid'
  end

  # Convert config period to rent month
  # Since rent is paid in advance, the rent month is always period + 1 month
  # @param config_period [Time, Date] Config period (month when costs incurred)
  # @return [Time] Rent month (month of housing being paid for)
  # @example
  #   RentLedger.config_to_rent_month(Time.utc(2025, 11, 1))
  #   # => 2025-12-01 (November config → December rent)
  def self.config_to_rent_month(config_period)
    date = config_period.to_date
    next_month = date.next_month
    Time.utc(next_month.year, next_month.month, 1)
  end

  # Get Swedish month name for the rent month (config period + 1)
  # @param config_period [Time, Date] Config period
  # @return [String] Swedish rent month name, e.g., "December 2025"
  # @example
  #   RentLedger.swedish_rent_month(Time.utc(2025, 11, 1))
  #   # => "December 2025" (November config → December rent)
  def self.swedish_rent_month(config_period)
    rent_month = config_to_rent_month(config_period)
    months = {
      1 => 'Januari', 2 => 'Februari', 3 => 'Mars', 4 => 'April',
      5 => 'Maj', 6 => 'Juni', 7 => 'Juli', 8 => 'Augusti',
      9 => 'September', 10 => 'Oktober', 11 => 'November', 12 => 'December'
    }
    "#{months[rent_month.month]} #{rent_month.year}"
  end

  # Get period as Swedish rent month name
  # Note: After migration, period = config month, so we convert to rent month
  # @return [String] e.g., "December 2025" (for November config period)
  def period_swedish
    self.class.swedish_rent_month(period)
  end

  # Check if this is a full month stay
  # @param total_days_in_month [Integer] Total days in the month
  # @return [Boolean]
  def full_month?(total_days_in_month)
    days_stayed && days_stayed == total_days_in_month
  end

  # Check if this is a partial month stay
  # @return [Boolean]
  def partial_month?
    days_stayed && days_stayed > 0 && days_stayed < 31
  end

  def to_s
    "#{period_swedish}: #{amount_due} kr (#{payment_status})"
  end

  # Serialize ledger entry to hash for API responses. Matches the historical
  # structure (snake_case keys) returned by RentDb#get_rent_history.
  def to_h
    {
      id: id,
      tenantId: tenant_id,
      period: period,
      amountDue: amount_due,
      amountPaid: amount_paid,
      paymentDate: payment_date,
      daysStayed: days_stayed,
      roomAdjustment: room_adjustment,
      baseMonthlyRent: base_monthly_rent,
      calculationTitle: calculation_title,
      calculationDate: calculation_date,
      createdAt: created_at
    }
  end

  private

  # Normalize period to month start (UTC Time)
  # @param value [Date, Time, String] Period input
  # @return [Time] Normalized time
  def normalize_period(value)
    case value
    when Time
      Time.utc(value.year, value.month, 1)
    when Date
      Time.utc(value.year, value.month, 1)
    when String
      date = Date.parse(value)
      Time.utc(date.year, date.month, 1)
    else
      raise ArgumentError, "Invalid period type: #{value.class}"
    end
  end

  # Parse datetime from various input types
  # @param value [Time, Date, String, nil] Datetime input
  # @return [Time, nil]
  def parse_datetime(value)
    return nil if value.nil?
    return value if value.is_a?(Time)
    return value.to_time if value.is_a?(Date)
    Time.parse(value.to_s)
  end

  def validate!
    raise ArgumentError, "Tenant ID required" if tenant_id.empty?
    raise ArgumentError, "Period required" unless period.is_a?(Time)
    raise ArgumentError, "Amount due must be non-negative" if amount_due < 0
    raise ArgumentError, "Amount paid must be non-negative" if amount_paid < 0

    # Validate days stayed is reasonable
    if days_stayed && (days_stayed < 0 || days_stayed > 31)
      raise ArgumentError, "Days stayed (#{days_stayed}) must be between 0 and 31"
    end
  end
end

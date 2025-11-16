require 'date'
require_relative 'period'

# Tenant domain model representing a household member
#
# Encapsulates business logic for:
# - Days stayed calculations (partial months, move-in/out)
# - Room adjustment proration
# - Active status determination
#
# PRESERVED LOGIC from rent.rb (room adjustment calculations)
#
# Room Adjustments:
# - Adjustments (like discounts for smaller rooms) are prorated by days stayed
# - Prorated adjustment = full_adjustment * (days_stayed / total_days)
# - The total adjustment amount is redistributed among all roommates
#
# @example Calculate days stayed for partial month
#   tenant = Tenant.new(
#     name: 'Adam',
#     email: 'adam@example.com',
#     start_date: Date.new(2025, 3, 16),
#     departure_date: Date.new(2025, 3, 31)
#   )
#   tenant.days_stayed_in_period(Date.new(2025, 3, 1), Date.new(2025, 3, 31))
#   # => 16 days (from March 16 to March 31, inclusive)
class Tenant
  attr_reader :id, :name, :email, :facebook_id, :avatar_url,
              :room_adjustment, :room, :start_date, :departure_date,
              :status, :created_at, :updated_at,
              # Contract fields:
              :personnummer, :phone,
              :deposit, :furnishing_deposit

  # Writer methods for mutable contract fields
  attr_writer :personnummer, :phone, :deposit, :furnishing_deposit, :room, :departure_date

  def initialize(id: nil, name:, email:, facebook_id: nil, avatar_url: nil,
                 room_adjustment: nil, room: nil, start_date: nil, departure_date: nil,
                 status: nil, created_at: nil, updated_at: nil,
                 # Contract fields:
                 personnummer: nil, phone: nil,
                 deposit: nil, furnishing_deposit: nil)
    @id = id
    @name = name.to_s
    @email = email.to_s
    @facebook_id = facebook_id
    @avatar_url = avatar_url
    @room_adjustment = room_adjustment.to_f if room_adjustment
    @room = room
    @start_date = parse_date(start_date)
    @departure_date = parse_date(departure_date)
    @status = status || 'active'
    @created_at = created_at
    @updated_at = updated_at
    # Contract fields
    @personnummer = personnummer
    @phone = phone
    @deposit = parse_decimal(deposit)
    @furnishing_deposit = parse_decimal(furnishing_deposit)
    validate!
  end

  # Calculate days stayed in a given period
  #
  # PRESERVED LOGIC from rent.rb (days calculation)
  #
  # Handles:
  # - Tenant moved in before/during period
  # - Tenant moved out before/during period
  # - Tenant stayed entire period
  # - Partial month stays
  #
  # @param period_start [Date] Start of period (inclusive)
  # @param period_end [Date] End of period (inclusive)
  # @return [Integer] Days stayed (0 if not present during period)
  #
  # @example Full month stay
  #   tenant.days_stayed_in_period(Date.new(2025, 3, 1), Date.new(2025, 3, 31))
  #   # => 31 (stayed entire month)
  #
  # @example Partial month (moved in mid-month)
  #   tenant = Tenant.new(..., start_date: Date.new(2025, 3, 16))
  #   tenant.days_stayed_in_period(Date.new(2025, 3, 1), Date.new(2025, 3, 31))
  #   # => 16 (March 16-31)
  #
  # @example Partial month (moved out mid-month)
  #   tenant = Tenant.new(..., departure_date: Date.new(2025, 3, 15))
  #   tenant.days_stayed_in_period(Date.new(2025, 3, 1), Date.new(2025, 3, 31))
  #   # => 15 (March 1-15)
  def days_stayed_in_period(period_start, period_end)
    # Tenant left before period started
    return 0 if departure_date && departure_date < period_start

    # Tenant hasn't moved in yet
    return 0 if start_date && start_date > period_end

    # Calculate actual start/end dates accounting for tenant's move-in/out
    actual_start = [start_date || period_start, period_start].max
    actual_end = [departure_date || period_end, period_end].min

    # Days = inclusive count
    (actual_end - actual_start).to_i + 1
  end

  # Calculate prorated room adjustment for a period
  #
  # PRESERVED LOGIC from rent.rb:232 (prorated adjustment calculation)
  #
  # @param total_days_in_month [Integer] Total days in the month
  # @param days_stayed [Integer] Days tenant stayed
  # @return [Float] Prorated adjustment amount
  #
  # @example Astrid's room adjustment (-1400 kr/month) for half month
  #   tenant = Tenant.new(..., room_adjustment: -1400)
  #   tenant.prorated_adjustment(31, 15.5)
  #   # => -700.0 (half month discount)
  def prorated_adjustment(total_days_in_month, days_stayed)
    return 0.0 unless room_adjustment
    room_adjustment * (days_stayed.to_f / total_days_in_month)
  end

  # Check if tenant was active on a specific date
  # @param date [Date] Date to check
  # @return [Boolean]
  def active_on?(date)
    (start_date.nil? || start_date <= date) &&
    (departure_date.nil? || departure_date >= date)
  end

  # Check if tenant is currently active (no departure date)
  # @return [Boolean]
  def active?
    departure_date.nil?
  end

  # Check if tenant has a room adjustment
  # @return [Boolean]
  def has_room_adjustment?
    !room_adjustment.nil? && room_adjustment != 0
  end

  # Check if deposit paid
  # @return [Boolean]
  def deposit_paid?
    !deposit.nil? && deposit > 0
  end

  # Check if furnishing deposit paid
  # @return [Boolean]
  def furnishing_deposit_paid?
    !furnishing_deposit.nil? && furnishing_deposit > 0
  end

  # Calculate total deposits paid
  # @return [Float] Total of both deposits
  def total_deposits_paid
    (deposit || 0) + (furnishing_deposit || 0)
  end

  # Calculate expected deposit based on number of active tenants
  #
  # The total house deposit is FIXED at 24,884 kr (the original amount paid).
  # This is split evenly among all active tenants.
  #
  # Principle: Total deposit amount never exceeds what was originally paid,
  # regardless of tenant count.
  #
  # Formula: Fixed total deposit / number of active tenants
  # Examples:
  #   - 4 people → 24,884 / 4 = 6,221 kr per person
  #   - 5 people → 24,884 / 5 = 4,977 kr per person
  #   - 3 people → 24,884 / 3 = 8,295 kr per person
  #
  # @param num_active_tenants [Integer] Number of active tenants
  # @param total_house_deposit [Integer] Total fixed deposit for apartment (default: 24,884 kr)
  # @return [Integer] Expected deposit amount per person (rounded)
  def self.calculate_deposit(num_active_tenants, total_house_deposit: 24_884)
    (total_house_deposit / num_active_tenants.to_f).round
  end

  def to_s
    status = active? ? 'active' : "departed #{departure_date}"
    "#{name} <#{email}> (#{status})"
  end

  # Serialize tenant to hash for API responses / JSON serialization.
  # Matches the historical structure returned by RentDb#get_tenants.
  def to_h
    {
      id: id,
      name: name,
      email: email,
      facebookId: facebook_id,
      avatarUrl: avatar_url,
      roomAdjustment: room_adjustment,
      room: room,
      startDate: start_date,
      departureDate: departure_date,
      status: status,
      createdAt: created_at,
      updatedAt: updated_at,
      # Contract fields
      personnummer: personnummer,
      phone: phone,
      deposit: deposit,
      furnishingDeposit: furnishing_deposit
    }
  end

  private

  # Parse date from various input types
  # @param value [Date, String, nil] Date input
  # @return [Date, nil]
  def parse_date(value)
    return nil if value.nil?
    return value if value.is_a?(Date)
    return value.to_date if value.is_a?(Time)
    Date.parse(value.to_s)
  end

  # Parse decimal from various input types (for currency values)
  # @param value [Numeric, String, nil] Decimal input
  # @return [Float, nil]
  def parse_decimal(value)
    return nil if value.nil?
    return value.to_f if value.is_a?(Numeric)
    value.to_s.to_f
  end

  def validate!
    raise ArgumentError, "Name required" if name.empty?
    raise ArgumentError, "Email required" if email.empty?

    # Validate date logic
    if start_date && departure_date && start_date > departure_date
      raise ArgumentError, "Start date (#{start_date}) cannot be after departure date (#{departure_date})"
    end

    # Validate deposits (cannot be negative)
    if deposit && deposit < 0
      raise ArgumentError, "Deposit cannot be negative"
    end

    if furnishing_deposit && furnishing_deposit < 0
      raise ArgumentError, "Furnishing deposit cannot be negative"
    end
  end
end

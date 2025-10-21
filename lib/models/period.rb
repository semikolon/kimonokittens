require 'date'

# Period value object representing a time range
#
# Used throughout the rent calculation system for:
# - Billing periods (electricity consumption months)
# - Rent periods (which month's rent we're calculating)
# - Tenant stay periods (partial month calculations)
#
# Immutable value object - create new instances for different periods.
#
# @example
#   period = Period.new(Date.new(2025, 9, 1), Date.new(2025, 9, 30))
#   period.days  # => 30
class Period
  attr_reader :start_date, :end_date

  def initialize(start_date, end_date)
    @start_date = start_date
    @end_date = end_date
    validate!
  end

  # Number of days in the period (inclusive)
  # @return [Integer] Days in period
  def days
    (end_date - start_date).to_i + 1
  end

  # Check if period is valid (start before/equal end, both are dates)
  # @return [Boolean]
  def valid?
    start_date.is_a?(Date) &&
    end_date.is_a?(Date) &&
    start_date <= end_date
  end

  # Check if another period overlaps with this one
  # @param other [Period] Another period to check against
  # @return [Boolean]
  def overlaps?(other)
    start_date <= other.end_date && end_date >= other.start_date
  end

  # Check if a date falls within this period
  # @param date [Date] Date to check
  # @return [Boolean]
  def includes?(date)
    date >= start_date && date <= end_date
  end

  def to_s
    "#{start_date} to #{end_date}"
  end

  def ==(other)
    other.is_a?(Period) &&
    start_date == other.start_date &&
    end_date == other.end_date
  end

  private

  def validate!
    raise ArgumentError, "Invalid period: #{start_date} to #{end_date}" unless valid?
  end
end

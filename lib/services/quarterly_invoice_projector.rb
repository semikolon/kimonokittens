# frozen_string_literal: true

##
# QuarterlyInvoiceProjector
#
# Calculates growth-adjusted projections for quarterly building operations invoices (drifträkning).
#
# **Strategy**: Uses historical average + YoY growth rate to project future quarterly invoices.
#
# **Pattern**: Quarterly invoices occur 3× yearly (April, July, October)
#
# **Growth Rate**: 8.7% annual growth (2024 → 2025: 7,689 kr → 8,361 kr)
#
# **Base Amount**: 2,787 kr (2025 average including all drifträkningar)
#
# **Example**:
#   - 2025 average: 2,787 kr
#   - 2026 April projection: 2,787 × 1.087 = 3,030 kr
#   - 2027 April projection: 3,030 × 1.087 = 3,294 kr
#
# @example Calculate projection for April 2026
#   QuarterlyInvoiceProjector.calculate_projection(year: 2026, month: 4)
#   # => { amount: 3030, is_projection: true, base_year: 2025, growth_rate: 0.087 }
#
class QuarterlyInvoiceProjector
  # Months where quarterly invoices are expected (Apr, Jul, Oct)
  QUARTERLY_MONTHS = [4, 7, 10].freeze

  # Base year for historical data
  BASE_YEAR = 2025

  # Base amount: 2025 average of all drifträkningar (2,927 + 572 + 2,637 + 2,797) / 4
  BASE_AMOUNT = 2787.0  # kr

  # Annual growth rate: (8,361 - 7,689) / 7,689 = 0.0874
  GROWTH_RATE = 0.087  # 8.7% annual growth

  ##
  # Check if a given month is a quarterly invoice month
  #
  # @param month [Integer] Month number (1-12)
  # @return [Boolean] True if month is Apr/Jul/Oct
  #
  def self.quarterly_month?(month)
    QUARTERLY_MONTHS.include?(month)
  end

  ##
  # Calculate growth-adjusted projection for a given period
  #
  # @param year [Integer] Target year
  # @param month [Integer] Target month
  # @return [Hash, nil] Projection details or nil if not a quarterly month
  #
  # @example
  #   QuarterlyInvoiceProjector.calculate_projection(year: 2026, month: 4)
  #   # => {
  #   #   amount: 3030,
  #   #   is_projection: true,
  #   #   base_year: 2025,
  #   #   base_amount: 2787,
  #   #   growth_rate: 0.087,
  #   #   years_forward: 1,
  #   #   formula: "2787 × (1.087 ^ 1)"
  #   # }
  #
  def self.calculate_projection(year:, month:)
    return nil unless quarterly_month?(month)

    years_forward = year - BASE_YEAR
    return nil if years_forward < 0  # Cannot project backwards

    # Growth-adjusted projection: base × (1 + growth)^years
    projected_amount = BASE_AMOUNT * ((1 + GROWTH_RATE) ** years_forward)

    {
      amount: projected_amount.round,
      is_projection: true,
      base_year: BASE_YEAR,
      base_amount: BASE_AMOUNT.to_i,
      growth_rate: GROWTH_RATE,
      years_forward: years_forward,
      formula: "#{BASE_AMOUNT.to_i} × (#{1 + GROWTH_RATE} ^ #{years_forward})"
    }
  end

  ##
  # Get projected amount for a period (simplified interface)
  #
  # @param year [Integer] Target year
  # @param month [Integer] Target month
  # @return [Integer, nil] Projected amount in kr, or nil if not a quarterly month
  #
  def self.projected_amount(year:, month:)
    projection = calculate_projection(year: year, month: month)
    projection&.dig(:amount)
  end

  ##
  # Check if projection is needed for a given period
  #
  # Returns true if:
  # - Month is a quarterly month (Apr/Jul/Oct)
  # - Year is current year or future
  #
  # @param year [Integer] Target year
  # @param month [Integer] Target month
  # @return [Boolean]
  #
  def self.projection_needed?(year:, month:)
    return false unless quarterly_month?(month)
    year >= BASE_YEAR
  end
end

require 'date'
require_relative 'persistence'

# ElectricityProjector provides intelligent electricity cost forecasting for rent calculations.
#
# **The Challenge:**
# - We need to project future electricity costs before bills arrive
# - Bills have a 2-month lag: October consumption → bills arrive mid-November
# - Can't blindly use last year's data (prices change year-to-year)
# - Can't use hardcoded defaults (too inaccurate)
#
# **The Solution:**
# Combines three key insights:
# 1. **Trailing 12-month baseline**: Captures current year price trends (not calendar year!)
# 2. **Multi-year seasonal patterns**: Knows October is typically cooler than February
# 3. **Single source of truth**: RentConfig database (migrated from JSON + text files)
#
# **Why Trailing 12 Months (Not Calendar Year)?**
# - January projection needs full year context (not just 1 month)
# - Eliminates artificial calendar boundaries
# - Always has sufficient data for robust averaging
# - See DEVELOPMENT.md:84-94 for electricity bill timeline explanation
#
# **Data Source:**
# RentConfig table (key='el') - Complete historical data migrated from:
# - Historical JSON files (data/rent_history/*.json)
# - Electricity bill text file (electricity_bills_history.txt)
# - See deployment/historical_config_migration.rb for migration details
#
# **Timing Model:**
# Config month N includes electricity from consumption month N-1 (2-month lag):
# - September consumption → bills arrive October → included in October config → November rent
# - See rent_calculator_handler.rb:336-347 for config period explanation
#
# @example Projecting November 2025 Rent (October config)
#   projector = ElectricityProjector.new
#   # Target: October consumption (bills due mid-November, not yet available)
#   cost = projector.project(config_year: 2025, config_month: 10)
#   # Returns: ~2200 kr (2025 price trend × October seasonal multiplier)
#
# @example How It Works Internally
#   # 1. Trailing period: Nov 2024 - Oct 2025 (12 months ending at target)
#   # 2. Baseline: avg(Nov24-Oct25) = 2200 kr/month (captures 2025 prices)
#   # 3. Seasonal: all_oct_ever.avg / all_months_ever.avg = 0.85
#   # 4. Projection: 2200 × 0.85 = 1870 kr
class ElectricityProjector
  # Repository reference for querying RentConfig
  attr_reader :repo

  def initialize(repo: Persistence.rent_configs)
    @repo = repo
  end

  # Projects electricity cost for a given configuration period
  #
  # @param config_year [Integer] Configuration period year
  # @param config_month [Integer] Configuration period month (1-12)
  # @return [Integer] Projected electricity cost in SEK (rounded)
  #
  # IMPORTANT: config_month represents the CONFIG PERIOD, not the consumption month!
  # The method automatically handles the 2-month lag internally.
  #
  # @example
  #   project(config_year: 2025, config_month: 10)
  #   # Projects Oct consumption for Nov rent (config period = Oct)
  def project(config_year:, config_month:)
    # Config month N includes consumption from month N-1 (bills lag by 1-2 months)
    target_month = config_month - 1
    target_year = config_year
    if target_month < 1
      target_month = 12
      target_year -= 1
    end

    # Get all available historical data points from database
    data_points = get_all_historical_data

    # Calculate trailing 12-month baseline (current price trend)
    baseline = calculate_baseline(data_points, target_year, target_month)

    # Calculate seasonal multiplier from multi-year patterns
    seasonal_multiplier = calculate_seasonal_multiplier(data_points, target_month)

    # Apply seasonality to baseline
    projection = (baseline * seasonal_multiplier).round

    puts "DEBUG Projection for #{target_year}-#{target_month}:"
    puts "  Baseline (trailing 12mo avg): #{baseline.round} kr"
    puts "  Seasonal multiplier: #{seasonal_multiplier.round(3)}"
    puts "  Final projection: #{projection} kr"

    projection
  end

  private

  # Fetches all historical electricity data from RentConfig table
  #
  # @return [Array<Hash>] Array of data points with keys:
  #   - year [Integer]: Config period year
  #   - month [Integer]: Config period month (1-12)
  #   - cost [Integer]: Total cost in SEK
  #
  # Historical data was migrated from:
  # - JSON files (data/rent_history/*.json - what was actually used in calculations)
  # - Text file (electricity_bills_history.txt - raw provider bills)
  #
  # See deployment/historical_config_migration.rb for migration process.
  def get_all_historical_data
    repo
      .all_for_key('el')
      .reject { |config| config.value.to_s == '0' }
      .map do |config|
        period = config.period # Time UTC month start
        {
          year: period.year,
          month: period.month,
          cost: config.value.to_f.round
        }
      end
  end

  # Calculates baseline cost from trailing 12 months
  #
  # @param data_points [Array<Hash>] All historical data
  # @param target_year [Integer] Target consumption year
  # @param target_month [Integer] Target consumption month
  # @return [Float] Average monthly cost in trailing period
  #
  # Trailing period logic:
  # - Projecting Oct 2025 → look at Nov 2024 - Oct 2025 (12 months)
  # - This captures current year price trends, not last year's prices
  def calculate_baseline(data_points, target_year, target_month)
    # Define trailing 12-month range ending at target month
    end_date = Date.new(target_year, target_month, 1)
    start_date = end_date << 12 # 12 months back

    # Filter data points within trailing period
    trailing_points = data_points.select do |p|
      point_date = Date.new(p[:year], p[:month], 1)
      point_date >= start_date && point_date <= end_date
    end

    if trailing_points.empty?
      # Fallback: use all available data
      puts "WARNING: No data in trailing 12mo, using all available data"
      trailing_points = data_points
    end

    return 0 if trailing_points.empty?

    # Return average
    trailing_points.sum { |p| p[:cost] } / trailing_points.size.to_f
  end

  # Calculates seasonal multiplier for a given month
  #
  # @param data_points [Array<Hash>] All historical data
  # @param target_month [Integer] Month to calculate multiplier for (1-12)
  # @return [Float] Seasonal multiplier (e.g., 0.85 for low-consumption months)
  #
  # Example:
  # - October avg across all years: 1500 kr
  # - All months avg across all years: 1800 kr
  # - October multiplier: 1500 / 1800 = 0.83
  #
  # This captures seasonal consumption patterns (heating in winter, cooling in summer)
  # independent of year-to-year price changes.
  def calculate_seasonal_multiplier(data_points, target_month)
    return 1.0 if data_points.empty?

    # All data points for target month across all years
    target_month_points = data_points.select { |p| p[:month] == target_month }

    return 1.0 if target_month_points.empty?

    # Calculate averages
    target_month_avg = target_month_points.sum { |p| p[:cost] } / target_month_points.size.to_f
    overall_avg = data_points.sum { |p| p[:cost] } / data_points.size.to_f

    return 1.0 if overall_avg == 0

    target_month_avg / overall_avg
  end
end

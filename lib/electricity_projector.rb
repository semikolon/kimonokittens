require 'date'
require 'json'
require 'httparty'
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
  # 2025 Electricity Rate Constants
  # Updated: October 24, 2025 (verified from actual invoices)
  # Review annually: https://www.vattenfalleldistribution.se/kund-i-elnatet/elnatspriser/energiskatt/

  # Energy tax (energiskatt) - verified from Skatteverket and invoices
  ENERGY_TAX_EXCL_VAT = 0.439  # kr/kWh (43.9 öre/kWh)
  ENERGY_TAX_INCL_VAT = 0.54875  # kr/kWh (54.875 öre/kWh) = 0.439 × 1.25

  # Grid transfer (elöverföring) - from Vattenfall invoices Aug/Sep 2025
  # Actual rate: 21.40 öre/kWh excluding VAT
  GRID_TRANSFER_EXCL_VAT = 0.214  # kr/kWh excluding VAT (from invoices)

  # Fixed monthly fees (verified from invoices)
  # Vattenfall: 7,080 kr/year = 590 kr/month (grid connection)
  # Fortum: 31.20 kr/mån + VAT = 39 kr (trading service)
  # Priskollen: 39.20 kr/mån + VAT = 49 kr (optional add-on we subscribe to)
  VATTENFALL_MONTHLY_FEE = 590  # Grid connection fee (from invoice)
  FORTUM_MONTHLY_FEE = 88       # Trading service (39 kr) + Priskollen (49 kr)
  MONTHLY_FEE = VATTENFALL_MONTHLY_FEE + FORTUM_MONTHLY_FEE  # 678 kr

  # API endpoint for spot prices (SE3 region - Stockholm)
  ELPRISET_API_BASE = 'https://www.elprisetjustnu.se/api/v1/prices'
  REGION = 'SE3'  # Stockholm area

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
    # First check if actual bills have arrived for this period
    bills = Persistence.electricity_bills.find_by_period(
      Date.new(config_year, config_month, 1)
    )

    if bills.any?
      # Use actual aggregated bills (both Vattenfall + Fortum)
      actual_total = bills.sum(&:amount).round
      puts "DEBUG Using actual bills for #{config_year}-#{sprintf('%02d', config_month)}: #{actual_total} kr"
      return actual_total
    end

    # No bills yet - fall back to smart projection
    puts "DEBUG No bills found for #{config_year}-#{sprintf('%02d', config_month)}, using smart projection..."

    # Try consumption × pricing projection first
    begin
      projection = project_from_consumption_and_pricing(config_year, config_month)
      puts "  Smart projection (consumption × pricing): #{projection} kr"
      return projection
    rescue => e
      puts "  ⚠️  Smart projection failed: #{e.message}"
      puts "  Falling back to seasonal baseline projection..."
    end

    # Fallback to original seasonal baseline method
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

  # Smart projection using actual consumption × actual pricing
  #
  # @param config_year [Integer] Configuration period year
  # @param config_month [Integer] Configuration period month
  # @return [Integer] Projected electricity cost in SEK
  #
  # Formula: Σ(consumption[hour] × (spot_price[hour] + transfer_rate)) + monthly_fees
  def project_from_consumption_and_pricing(config_year, config_month)
    # Calculate consumption month (config month - 1)
    consumption_month = config_month - 1
    consumption_year = config_year
    if consumption_month < 1
      consumption_month = 12
      consumption_year -= 1
    end

    puts "    → Loading consumption data for #{consumption_year}-#{sprintf('%02d', consumption_month)}..."

    # Load hourly consumption data
    consumption_data = load_consumption_for_month(consumption_year, consumption_month)
    total_kwh = consumption_data.sum { |h| h[:kwh] }
    puts "      Found #{consumption_data.size} hours, total #{total_kwh.round(1)} kWh"

    # Load spot prices for the same period
    puts "    → Loading spot prices for #{consumption_year}-#{sprintf('%02d', consumption_month)}..."
    spot_prices = load_spot_prices_for_month(consumption_year, consumption_month)
    puts "      Found #{spot_prices.size} hourly prices"

    # Calculate variable cost (consumption × pricing for each hour)
    variable_cost = 0.0
    hours_calculated = 0

    consumption_data.each do |hour|
      timestamp = hour[:timestamp]
      consumption_kwh = hour[:kwh]

      # Get spot price for this hour (EXCLUDES VAT from API)
      spot_price = spot_prices[timestamp]

      if spot_price.nil?
        # No spot price data for this hour - skip it
        next
      end

      # Calculate total price per kWh: (spot + transfer + tax) × VAT
      # All three components exclude VAT, so add them first then apply 25% VAT
      price_per_kwh = (spot_price + GRID_TRANSFER_EXCL_VAT + ENERGY_TAX_EXCL_VAT) * 1.25

      # Calculate cost for this hour
      hour_cost = consumption_kwh * price_per_kwh
      variable_cost += hour_cost
      hours_calculated += 1
    end

    puts "      Calculated costs for #{hours_calculated}/#{consumption_data.size} hours"
    puts "      Variable cost: #{variable_cost.round(2)} kr"
    puts "      Fixed fees: #{MONTHLY_FEE} kr"

    # Add fixed monthly fees
    total_cost = variable_cost + MONTHLY_FEE

    puts "      Total projected: #{total_cost.round} kr"

    total_cost.round
  end

  # Load hourly consumption data for a specific month
  #
  # @param year [Integer] Year
  # @param month [Integer] Month (1-12)
  # @return [Array<Hash>] Array of {timestamp: String, kwh: Float}
  def load_consumption_for_month(year, month)
    # Load electricity_usage.json
    unless File.exist?('electricity_usage.json')
      raise "electricity_usage.json not found - run vattenfall.rb first"
    end

    data = JSON.parse(File.read('electricity_usage.json'))

    # Filter for the target month
    # Data format: [{"date": "2024-10-01T00:00:00+02:00", "consumption": 0.123, "status": "012"}, ...]
    month_data = data.select do |hour|
      date = DateTime.parse(hour['date'])
      date.year == year && date.month == month
    end

    # Convert to our format (normalize to UTC for consistent matching)
    month_data.map do |hour|
      {
        timestamp: DateTime.parse(hour['date']).new_offset(0).iso8601,
        kwh: hour['consumption'].to_f
      }
    end
  end

  # Load spot prices for a specific month from elprisetjustnu.se API
  #
  # @param year [Integer] Year
  # @param month [Integer] Month (1-12)
  # @return [Hash<String, Float>] Hash of timestamp => price_kr_per_kwh (incl VAT)
  def load_spot_prices_for_month(year, month)
    prices = {}

    # Calculate date range for the month
    start_date = Date.new(year, month, 1)
    end_date = Date.new(year, month, -1)  # Last day of month

    # Fetch prices for each day in the month
    (start_date..end_date).each do |date|
      date_str = date.strftime('%Y/%m-%d')  # Format: 2025/10-24
      url = "#{ELPRISET_API_BASE}/#{date_str}_#{REGION}.json"

      begin
        response = HTTParty.get(url, timeout: 10)

        if response.code == 200
          day_prices = JSON.parse(response.body)

          # API returns: [{"time_start": "2025-10-24T00:00:00+02:00", "SEK_per_kWh": 0.542}, ...]
          day_prices.each do |hour_data|
            # Normalize to UTC for consistent matching with consumption data
            timestamp = DateTime.parse(hour_data['time_start']).new_offset(0).iso8601
            price = hour_data['SEK_per_kWh'].to_f  # Excludes VAT (will be added in formula)
            prices[timestamp] = price
          end
        else
          puts "      ⚠️  Failed to fetch prices for #{date_str}: HTTP #{response.code}"
        end
      rescue => e
        puts "      ⚠️  Error fetching prices for #{date_str}: #{e.message}"
      end
    end

    if prices.empty?
      raise "No spot price data available for #{year}-#{sprintf('%02d', month)}"
    end

    prices
  end
end

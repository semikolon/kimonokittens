require 'date'

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
# 3. **Dual data sources**: RentConfig table + text file ensures no gaps
#
# **Why Trailing 12 Months (Not Calendar Year)?**
# - January projection needs full year context (not just 1 month)
# - Eliminates artificial calendar boundaries
# - Always has sufficient data for robust averaging
# - See DEVELOPMENT.md:84-94 for electricity bill timeline explanation
#
# **Data Sources (Priority Order):**
# 1. RentConfig table (key='el') - Authoritative source, includes:
#    - Actual bills used in past rent calculations
#    - Manual overrides when needed
# 2. electricity_bills_history.txt - Raw Vattenfall + Fortum bill data
# 3. Never returns 0 - always provides intelligent projection
#
# **Timing Model:**
# Config month N includes electricity from consumption month N-1 (2-month lag):
# - September consumption → bills arrive October → included in October config → November rent
# - See rent_calculator_handler.rb:416-464 for current (flawed) implementation
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
  # Database reference for querying RentConfig
  attr_reader :db

  def initialize(db: RentDb.instance)
    @db = db
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

    # Get all available historical data points
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

  # Fetches all historical electricity data from three sources
  #
  # @return [Array<Hash>] Array of data points with keys:
  #   - year [Integer]: Config period year
  #   - month [Integer]: Config period month (1-12)
  #   - cost [Integer]: Total cost in SEK
  #   - source [String]: 'rent_config', 'json_file', or 'text_file'
  #
  # Sources (priority order):
  # 1. RentConfig - Recent manually-set values
  # 2. Historical JSON files - Actual config used in past calculations
  # 3. Text file - Raw provider bills as final fallback
  def get_all_historical_data
    data_points = []

    # Source 1: RentConfig table (highest priority - manual overrides)
    data_points += fetch_from_rent_config

    # Source 2: Historical JSON files (what was actually used in calculations)
    data_points += fetch_from_json_files

    # Source 3: Text file (lowest priority - raw provider bills)
    data_points += fetch_from_text_file

    # Merge and deduplicate by priority
    merge_data_points(data_points)
  end

  # Queries RentConfig table for historical 'el' values
  #
  # @return [Array<Hash>] Data points from database
  #
  # IMPORTANT: RentConfig stores values by CONFIG PERIOD, not consumption period.
  # Config period month N includes electricity from consumption month N-1.
  # See deployment/production_migration.rb:50-61 for how RentConfig is populated.
  def fetch_from_rent_config
    points = []

    # Query all 'el' configs with period information
    configs = db.class.rent_configs
      .where(key: 'el')
      .where { Sequel.~(value: '0') } # Exclude zeros (not set)
      .order(Sequel.desc(:period))
      .all

    configs.each do |config|
      period = config[:period]
      cost = config[:value].to_f

      points << {
        year: period.year,
        month: period.month,
        cost: cost.round,
        source: 'rent_config'
      }
    end

    points
  rescue => e
    puts "WARNING: Could not fetch from RentConfig: #{e.message}"
    []
  end

  # Parses historical JSON files for electricity values used in past calculations
  #
  # @return [Array<Hash>] Data points from JSON files
  #
  # Historical JSON files (data/rent_history/*.json) contain complete rent calculations
  # including the config that was used. Example structure:
  #
  #   {
  #     "constants": {
  #       "year": 2025,
  #       "month": 2,      ← CONFIG PERIOD MONTH
  #       "el": 5945,      ← Total electricity cost used in calculation
  #       "kallhyra": 24530,
  #       ...
  #     },
  #     "final_results": { "Fredrik": 7045, ... }
  #   }
  #
  # These JSON files were NOT migrated to RentConfig (see deployment/production_migration.rb:70-137).
  # They exist only as files but contain authoritative historical data.
  #
  # Multiple versions may exist for same period (e.g., 2025_02_v1.json through 2025_02_v10.json).
  # We take the highest version number as the final/authoritative calculation.
  def fetch_from_json_files
    history_dir = File.expand_path('../../data/rent_history', __FILE__)
    return [] unless Dir.exist?(history_dir)

    points = []

    # Group files by period to handle multiple versions
    files_by_period = Hash.new { |h, k| h[k] = [] }

    Dir.glob("#{history_dir}/*.json").each do |json_file|
      # Extract year, month, version from filename (e.g., "2025_02_v10.json")
      filename = File.basename(json_file)
      match = filename.match(/^(\d{4})_(\d{2})_v(\d+)\.json$/)
      next unless match

      year = match[1].to_i
      month = match[2].to_i
      version = match[3].to_i

      files_by_period[[year, month]] << { file: json_file, version: version }
    end

    # Process highest version for each period
    files_by_period.each do |(year, month), versions|
      # Take highest version number (most recent calculation)
      latest = versions.max_by { |v| v[:version] }

      begin
        data = JSON.parse(File.read(latest[:file]))

        # Extract electricity cost from constants
        el_cost = data.dig('constants', 'el')
        next unless el_cost && el_cost > 0

        points << {
          year: year,
          month: month,
          cost: el_cost.to_i,
          source: 'json_file'
        }
      rescue => e
        puts "WARNING: Could not parse #{File.basename(latest[:file])}: #{e.message}"
      end
    end

    points
  rescue => e
    puts "WARNING: Could not read JSON files: #{e.message}"
    []
  end

  # Parses electricity_bills_history.txt for historical bills
  #
  # @return [Array<Hash>] Data points from text file
  #
  # Text file format (see electricity_bills_history.txt):
  #   # Vattenfall (elnätsleverantör)
  #   2025-10-01  1632 kr
  #
  #   # Fortum (elförbrukning)
  #   2025-10-01  792 kr
  #
  # Bills are grouped by due date. We sum Vattenfall + Fortum for each month.
  def fetch_from_text_file
    history_file = File.expand_path('../../electricity_bills_history.txt', __FILE__)
    return [] unless File.exist?(history_file)

    lines = File.readlines(history_file)
    monthly_totals = Hash.new(0) # { "2025-10" => 2424 }
    in_fortum_section = false

    lines.each do |line|
      next if line.strip.empty?

      # Track which provider section we're in
      if line.include?('Fortum')
        in_fortum_section = true
        next
      elsif line.include?('Vattenfall')
        in_fortum_section = false
        next
      end

      # Parse bill lines: "2025-10-01  1632 kr"
      next unless line =~ /^(\d{4})-(\d{2})-\d{2}\s+(\d+)/
      year = $1.to_i
      month = $2.to_i
      cost = $3.to_i

      month_key = "#{year}-#{sprintf('%02d', month)}"
      monthly_totals[month_key] += cost
    end

    # Convert hash to data points
    monthly_totals.map do |month_key, cost|
      year, month = month_key.split('-').map(&:to_i)
      {
        year: year,
        month: month,
        cost: cost,
        source: 'text_file'
      }
    end
  rescue => e
    puts "WARNING: Could not parse text file: #{e.message}"
    []
  end

  # Merges data points from multiple sources with priority order
  #
  # @param points [Array<Hash>] Mixed data points
  # @return [Array<Hash>] Deduplicated and sorted data points
  #
  # Priority order (highest to lowest):
  # 1. rent_config - Manual overrides, most authoritative
  # 2. json_file - Actual values used in historical calculations
  # 3. text_file - Raw provider bills, fallback only
  def merge_data_points(points)
    # Group by (year, month)
    grouped = points.group_by { |p| [p[:year], p[:month]] }

    # For each month, prefer by source priority
    merged = grouped.map do |(year, month), month_points|
      # Define priority: lower number = higher priority
      priority = { 'rent_config' => 1, 'json_file' => 2, 'text_file' => 3 }

      # Sort by priority and take first
      sorted = month_points.sort_by { |p| priority[p[:source]] || 999 }
      sorted.first
    end

    # Sort by date
    merged.sort_by { |p| [p[:year], p[:month]] }
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

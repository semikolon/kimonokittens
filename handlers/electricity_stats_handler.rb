require 'oj'
require 'awesome_print'
require 'httparty'
require 'date'
# require 'pry'  # Temporarily disabled due to gem conflict
# require 'pry-nav'  # Temporarily disabled due to gem conflict

# 2025 Electricity Rate Constants (matches ElectricityProjector)
# Updated: October 24-26, 2025 (peak/off-peak + anomaly cost accuracy)
# Review annually: https://www.vattenfalleldistribution.se/kund-i-elnatet/elnatspriser/energiskatt/

# Energy tax (energiskatt) - verified from Skatteverket and invoices
ENERGY_TAX_EXCL_VAT = 0.439  # kr/kWh (43.9 öre/kWh)

# Grid transfer (elöverföring) - Vattenfall Tidstariff T4 (time-of-use pricing)
# Peak (höglasttid): Mon-Fri 06:00-22:00 in Jan/Feb/Mar/Nov/Dec (excl holidays)
# Off-peak (övrig tid): All other times + entire summer (Apr-Oct)
GRID_TRANSFER_PEAK_EXCL_VAT = 0.536     # kr/kWh (53.60 öre/kWh) - peak hours
GRID_TRANSFER_OFFPEAK_EXCL_VAT = 0.214  # kr/kWh (21.40 öre/kWh) - off-peak hours

# Fixed monthly fees (verified from invoices)
# Vattenfall: 7,080 kr/year = 590 kr/month (grid connection)
# Fortum: 31.20 kr/mån + VAT = 39 kr (trading service)
# Priskollen: 39.20 kr/mån + VAT = 49 kr (optional add-on we subscribe to)
VATTENFALL_MONTHLY_FEE = 590  # Grid connection fee (from invoice)
FORTUM_MONTHLY_FEE = 88       # Trading service (39 kr) + Priskollen (49 kr)
MONTHLY_FEE = VATTENFALL_MONTHLY_FEE + FORTUM_MONTHLY_FEE  # 678 kr

WDAY = {
  'Mon': 'Mån',
  'Tue': 'Tis',
  'Wed': 'Ons',
  'Thu': 'Tor',
  'Fri': 'Fre',
  'Sat': 'Lör',
  'Sun': 'Sön'
}

class ElectricityStatsHandler
  def initialize(electricity_price_handler)
    @electricity_price_handler = electricity_price_handler
  end

  def call(req)
    electricity_usage = Oj.load_file('electricity_usage.json')

    # Fetch live prices from API instead of stale tibber JSON
    status, headers, body = @electricity_price_handler.call(req)
    return [status, headers, body] unless status == 200

    price_data = Oj.load(body.first)
    spot_prices = price_data['prices'] || []

    # Convert API format to lookup hash: "YYYY-MM-DDTHH:00:00+TZ" => price_sek
    tibber_prices = {}
    spot_prices.each do |price_entry|
      tibber_prices[price_entry['time_start']] = price_entry['price_sek']
    end

    avg_price_per_kwh = tibber_prices.values.sum / tibber_prices.count

    all_hours = electricity_usage.map do |hour|
      consumption = hour['consumption'] || 0.0

      date = DateTime.parse(hour['date'])
      short_date = date.strftime("%b %-d")
      weekday = WDAY[date.strftime("%a").to_sym]

      # Get spot price (excludes VAT from API)
      spot_price = tibber_prices[hour['date']]
      spot_price ||= avg_price_per_kwh

      # Determine grid transfer rate based on peak/off-peak classification
      grid_rate = is_peak_hour?(hour['date']) ? GRID_TRANSFER_PEAK_EXCL_VAT : GRID_TRANSFER_OFFPEAK_EXCL_VAT

      # Calculate total price per kWh: (spot + transfer + tax) × VAT
      # All three components exclude VAT, so add them first then apply 25% VAT
      price_per_kwh = (spot_price + grid_rate + ENERGY_TAX_EXCL_VAT) * 1.25

      price = consumption * price_per_kwh

      {
        date: short_date,
        short_date: short_date,
        weekday: weekday,
        full_date: "#{weekday} #{short_date} #{date.strftime("%H.%M")}",
        hour_of_day: date.strftime("%H").to_i,
        price_per_kwh: price_per_kwh,
        consumption: consumption,
        price: price
      }
    end
    
    #ap all_hours

    price_so_far = all_hours.sum { |hour| hour[:price] }
    average_hour = price_so_far / all_hours.count
    projected_total = ((average_hour * 31 * 24).to_f)
    
    peak_hours = all_hours.sort_by { |hour| hour[:price] }.last(24).reverse!
    # Select the peak hours where the price_per_kwh was above the average price_per_kwh
    avg_price_per_kwh = peak_hours.sum { |hour| hour[:price_per_kwh] } / peak_hours.count
    peak_pricey_hours = peak_hours.select { |hour| hour[:price_per_kwh] > avg_price_per_kwh }

    # Filter out hours with null/zero consumption (future dates or reporting lag)
    # Fetch 90 days for robust anomaly detection, but only display last 14
    hours_with_data = all_hours.select { |hour| hour[:consumption] && hour[:consumption] > 0 }
    all_historical_days = hours_with_data.last(24 * 90).group_by { |hour| hour[:date] }
    last_days = hours_with_data.last(24 * 14).group_by { |hour| hour[:date] }
    
    # last_days.each do |date, date_hours|
    #   if date_hours.count.between?(18, 24)
    #     # Make an educated guess as to what the price will be for the remaining hours
    #     # by taking the average price of the same hours for the last month
    #     last_month_same_hours = all_hours.select { |hour| hour[:hour_of_day] == date_hours.first[:hour_of_day] }
    #     avg_price_per_kwh = last_month_same_hours.sum { |hour| hour[:price_per_kwh] } / last_month_same_hours.count
    #     remaining_hours = 24 - date_hours.count
    #     remaining_price = avg_price_per_kwh * remaining_hours
    #     date_hours << {
    #       date: date,
    #       short_date: date,
    #       weekday: date_hours.first[:weekday],
    #       full_date: "#{date_hours.first[:weekday]} #{date}",
    #       hour_of_day: date_hours.first[:hour_of_day],
    #       price_per_kwh: avg_price_per_kwh,
    #       consumption: 0,
    #       price: remaining_price
    #     }
    #   end
    # end
    # Remove incomplete days from both datasets
    all_historical_days.reject! { |date, date_hours| date_hours.count < 24 }
    last_days.reject! { |date, date_hours| date_hours.count < 24 }

    # Aggregate all historical days (for regression)
    all_historical_summed = all_historical_days.map do |date, date_hours|
      consumption_sum = date_hours.sum { |hour| hour[:consumption] }
      first_hour = date_hours.first
      {
        date: date,
        weekday: first_hour[:weekday],
        consumption: consumption_sum
      }
    end

    puts "DEBUG: Historical days aggregated: #{all_historical_summed.length}"
    puts "DEBUG: Last days aggregated: #{last_days.length}"

    # Aggregate last 14 days (for display)
    last_days_summed = last_days.map do |date, date_hours|
      price_sum = date_hours.sum { |hour| hour[:price] }.ceil
      consumption_sum = date_hours.sum { |hour| hour[:consumption] }
      first_hour = date_hours.first
      {
        date: date,
        weekday: first_hour[:weekday],
        full_date: "#{first_hour[:weekday]} #{first_hour[:short_date]}",
        price: price_sum,
        title: "= #{price_sum} kr (#{first_hour[:weekday]})",
        long_title: "#{consumption_sum} kWh = #{price_sum} kr (#{first_hour[:weekday]})",
        consumption: consumption_sum
      }
    end.reverse

    # Exclude the current day (the first one) from last_days_summary
    last_days_summary = last_days_summed[1..-1].map do |date|
      "#{date[:weekday]}: #{date[:price]} kr\n"
    end.join
    
    # Fetch historical outdoor temperatures for ALL historical days (90 days)
    # We need temperature for regression, even if we only display 14 days
    all_days_for_date_range = all_historical_summed + last_days_summed
    all_days_for_date_range.uniq! { |d| d[:date] }

    if all_days_for_date_range.any?
      # Parse dates and find date range
      date_objects = all_days_for_date_range.map { |day_data| Date.parse("#{day_data[:date]} 2025") }
      start_date = date_objects.min.strftime("%Y-%m-%d")
      end_date = date_objects.max.strftime("%Y-%m-%d")

      # Fetch historical weather data from Open-Meteo (free, no API key required)
      # Huddinge coordinates: 59.2372°N, 18.1339°E
      begin
        weather_response = HTTParty.get(
          "https://archive-api.open-meteo.com/v1/archive",
          query: {
            latitude: 59.2372,
            longitude: 18.1339,
            start_date: start_date,
            end_date: end_date,
            daily: 'temperature_2m_max,temperature_2m_min',
            timezone: 'Europe/Stockholm'
          },
          timeout: 10
        )

        if weather_response.success?
          daily_data = weather_response.parsed_response['daily']
          # Build a hash mapping date string to average temperature
          temp_by_date = {}
          daily_data['time'].each_with_index do |date_str, index|
            max_temp = daily_data['temperature_2m_max'][index]
            min_temp = daily_data['temperature_2m_min'][index]
            avg_temp = (max_temp + min_temp) / 2.0
            temp_by_date[date_str] = avg_temp.round(1)
          end

          # Assign temperatures directly to BOTH original arrays (not the combined copy)
          all_historical_summed.each do |day_data|
            iso_date = Date.parse("#{day_data[:date]} 2025").strftime("%Y-%m-%d")
            day_data[:avg_temp_c] = temp_by_date[iso_date] if temp_by_date[iso_date]
          end

          last_days_summed.each do |day_data|
            iso_date = Date.parse("#{day_data[:date]} 2025").strftime("%Y-%m-%d")
            day_data[:avg_temp_c] = temp_by_date[iso_date] if temp_by_date[iso_date]
          end
        end
      rescue => e
        # Silently fail if temperature fetch fails - sparkline will just show electricity
        puts "Failed to fetch temperature data: #{e.message}"
      end
    end

    # Build daily average price lookup for cost impact calculation
    # Group hourly prices by date and calculate daily average
    daily_avg_prices = {}
    all_hours.group_by { |h| h[:date] }.each do |date, hours|
      avg_price = hours.sum { |h| h[:price_per_kwh] } / hours.length
      daily_avg_prices[date] = avg_price.round(3)
    end

    # Detect anomalous electricity usage (high consumption relative to heating needs)
    # Use ALL historical data (90 days) for robust regression model
    historical_with_temp = all_historical_summed.select { |d| d[:consumption] && d[:avg_temp_c] }

    if historical_with_temp.length >= 10
      # Calculate simple linear regression: consumption vs temperature on ALL historical data
      # Expectation: colder temps (lower °C) = higher consumption
      temps = historical_with_temp.map { |d| d[:avg_temp_c] }
      consumptions = historical_with_temp.map { |d| d[:consumption] }

      n = temps.length
      sum_temp = temps.sum
      sum_consumption = consumptions.sum
      sum_temp_sq = temps.map { |t| t * t }.sum
      sum_temp_consumption = temps.zip(consumptions).map { |t, c| t * c }.sum

      # Linear regression: consumption = slope * temp + intercept
      slope = (n * sum_temp_consumption - sum_temp * sum_consumption) / (n * sum_temp_sq - sum_temp * sum_temp)
      intercept = (sum_consumption - slope * sum_temp) / n

      # Check ALL 90 days for anomalies (for reporting)
      all_anomalies = []
      historical_with_temp.each do |day|
        expected_consumption = slope * day[:avg_temp_c] + intercept
        actual_consumption = day[:consumption]

        # Anomaly: actual is significantly different from expected for this temperature
        # High anomaly: >20% above expected, Low anomaly: <20% below expected
        excess_pct = ((actual_consumption / expected_consumption - 1) * 100).round(1)

        if actual_consumption > expected_consumption * 1.20 || actual_consumption < expected_consumption * 0.80
          # Calculate cost impact using daily average price
          price_per_kwh = daily_avg_prices[day[:date]] || avg_price_per_kwh + KWH_TRANSFER_PRICE
          consumption_diff = actual_consumption - expected_consumption
          cost_impact = (consumption_diff * price_per_kwh).round(1)

          all_anomalies << {
            date: day[:date],
            consumption: actual_consumption.round(1),
            expected: expected_consumption.round(1),
            temp_c: day[:avg_temp_c],
            excess_pct: excess_pct,  # Can be positive (high) or negative (low)
            price_per_kwh: price_per_kwh.round(3),
            cost_impact: cost_impact  # In SEK, can be positive (cost) or negative (savings)
          }
        end
      end

      puts "Anomaly check: #{all_anomalies.length} anomalous days found in 90-day period (threshold: 20%)"
      all_anomalies.each do |a|
        cost_str = a[:cost_impact] >= 0 ? "+#{a[:cost_impact]}" : "#{a[:cost_impact]}"
        puts "  #{a[:date]}: #{a[:consumption]} kWh (expected #{a[:expected]}, #{a[:excess_pct] >= 0 ? '+' : ''}#{a[:excess_pct]}% at #{a[:temp_c]}°C, #{cost_str} kr)"
      end

      # Flag anomalies ONLY on the displayed days (last 14 days)
      # Return excess percentage for proportional glow intensity
      last_days_summed.each do |day|
        next unless day[:avg_temp_c] && day[:consumption]

        expected_consumption = slope * day[:avg_temp_c] + intercept
        actual_consumption = day[:consumption]

        # Anomaly: actual is significantly different from expected for this temperature
        excess_pct = ((actual_consumption / expected_consumption - 1) * 100).round(1)

        if actual_consumption > expected_consumption * 1.20 || actual_consumption < expected_consumption * 0.80
          day[:anomalous_usage_pct] = excess_pct  # Can be positive (high) or negative (low)
        end
      end
    end

    # Prepare full regression data for sparkline (all 90 days, not just anomalies)
    regression_data = if defined?(slope) && defined?(intercept) && defined?(historical_with_temp)
      historical_with_temp.map do |day|
        expected_consumption = slope * day[:avg_temp_c] + intercept
        actual_consumption = day[:consumption]
        excess_pct = ((actual_consumption / expected_consumption - 1) * 100).round(1)

        {
          date: day[:date],
          excess_pct: excess_pct
        }
      end
    else
      nil
    end

    last_days_summed.prepend({
      price_so_far: price_so_far.ceil + MONTHLY_FEE,
      projected_total: projected_total.ceil + MONTHLY_FEE,
      average_hour: average_hour.round(3),
      peak_pricey_hours: peak_pricey_hours,
      last_days_summary: last_days_summary,
      anomaly_summary: defined?(all_anomalies) ? {
        total_anomalies: all_anomalies.length,
        anomalous_days: all_anomalies
      } : nil,
      regression_data: regression_data
    })

    # Savings calculations
    
    # Calculate the average price for the previous month
    # avg_prev_month_price = average_price_previous_month(tibber_prices)

    # Calculate daily savings
    # daily_savings = calculate_daily_savings(tibber_prices, electricity_usage, avg_prev_month_price)

    # Calculate monthly savings
    # monthly_savings_summary = calculate_monthly_savings(daily_savings)

    stats = {
      'electricity_stats' => last_days_summed
      # daily_savings: daily_savings,
      # monthly_savings_summary: monthly_savings_summary
    }

    [200, { 'Content-Type' => 'application/json' }, [ Oj.dump(stats, mode: :compat) ]]
  end

  # Helper method to get the average price for the previous month
  def average_price_previous_month(tibber_prices)
    current_month = Date.today.month
    previous_month_prices = tibber_prices.select do |date_string, _|
      # Extract the date part from the date-time string
      date_part = date_string.split("T").first
      Date.parse(date_part).month == current_month - 1
    end
    previous_month_prices.values.sum / previous_month_prices.size
  end

  # Helper method to calculate savings for each day
  def calculate_daily_savings(tibber_prices, electricity_usage, average_previous_month_price)
    daily_savings = []

    electricity_usage.each do |day_data|
      date = day_data['date']
      consumption = day_data['consumption']

      # Calculate cost based on dynamic pricing
      dynamic_cost = tibber_prices[date] * consumption

      # Calculate cost based on fixed price
      fixed_cost = average_previous_month_price * consumption

      # Calculate savings for the day
      savings = fixed_cost - dynamic_cost

      daily_savings << { 'date' => date, 'savings' => savings }
    end

    daily_savings
  end

  # Helper method to calculate monthly savings
  def calculate_monthly_savings(daily_savings)
    monthly_savings = {}

    daily_savings.each do |day_data|
      month = Date.parse(day_data['date']).strftime('%B %Y')  # e.g., "April 2023"
      monthly_savings[month] ||= 0
      monthly_savings[month] += day_data['savings']
    end

    monthly_savings
  end

  # Swedish holidays (red days - no peak pricing applies)
  # Includes fixed holidays and calculated movable holidays for 2024-2027
  # Simplified version of ElectricityProjector#swedish_holidays
  def swedish_holidays(year)
    holidays = []

    # Fixed holidays
    holidays << Date.new(year, 1, 1)   # New Year's Day
    holidays << Date.new(year, 1, 6)   # Epiphany
    holidays << Date.new(year, 5, 1)   # Labor Day
    holidays << Date.new(year, 12, 24) # Christmas Eve
    holidays << Date.new(year, 12, 25) # Christmas Day
    holidays << Date.new(year, 12, 26) # Boxing Day
    holidays << Date.new(year, 12, 31) # New Year's Eve

    # Movable holidays (Easter-based) - hardcoded for 2024-2027
    easter_dates = {
      2024 => Date.new(2024, 3, 31),
      2025 => Date.new(2025, 4, 20),
      2026 => Date.new(2026, 4, 5),
      2027 => Date.new(2027, 3, 28)
    }

    if easter_dates[year]
      easter = easter_dates[year]
      holidays << easter - 2          # Good Friday
      holidays << easter              # Easter Sunday
      holidays << easter + 1          # Easter Monday
      holidays << easter + 39         # Ascension Day
      holidays << easter + 49         # Pentecost Sunday
      holidays << easter + 50         # Whit Monday
    end

    # Midsummer (Friday between June 19-25)
    midsummer_start = Date.new(year, 6, 19)
    7.times do |i|
      candidate = midsummer_start + i
      if candidate.friday?
        holidays << candidate       # Midsummer Eve
        holidays << candidate + 1   # Midsummer Day
        break
      end
    end

    # All Saints' Day (Saturday between Oct 31 - Nov 6)
    all_saints_start = Date.new(year, 10, 31)
    7.times do |i|
      candidate = all_saints_start + i
      if candidate.saturday?
        holidays << candidate
        break
      end
    end

    holidays
  end

  # Determines if a given timestamp falls during peak pricing hours
  # Simplified version of ElectricityProjector#is_peak_hour?
  #
  # Peak hours (Vattenfall Tidstariff T4):
  # - Months: January, February, March, November, December
  # - Days: Monday-Friday (excluding Swedish holidays)
  # - Hours: 06:00-22:00 (local time)
  def is_peak_hour?(timestamp)
    dt = DateTime.parse(timestamp)

    # Summer months (Apr-Oct) have NO peak pricing
    return false unless [1, 2, 3, 11, 12].include?(dt.month)

    # Weekends have NO peak pricing
    return false if [0, 6].include?(dt.wday)  # Sunday=0, Saturday=6

    # Swedish holidays have NO peak pricing
    date_only = Date.new(dt.year, dt.month, dt.day)
    return false if swedish_holidays(dt.year).include?(date_only)

    # Peak hours: 06:00-22:00 (local time)
    # Note: timestamp is in UTC, but we need local hour for classification
    # Sweden is UTC+1 (winter) or UTC+2 (summer DST)
    local_dt = dt.new_offset('+01:00')  # Conservative: use winter offset
    local_dt.hour >= 6 && local_dt.hour < 22
  end

end
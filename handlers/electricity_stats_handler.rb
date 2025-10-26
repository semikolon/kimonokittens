require 'oj'
require 'awesome_print'
require 'httparty'
require 'date'
# require 'pry'  # Temporarily disabled due to gem conflict
# require 'pry-nav'  # Temporarily disabled due to gem conflict

# I maj 2023 använde vi 900 kWh och betalade 616 kr till elhandelsbolaget.
# Samt till elnätsbolaget 1299 kr - varav 467 kr är en statisk månadsavgift.

# Den variabla delen av elnätskostnaden får vi genom att subtrahera den fasta
# abonnemangsavgiften från den totala elnätskostnaden:
# 1299 kr - 467 kr = 832 kr
# Detta är alltså kostnaden för elnätet baserat på förbrukningen.

# Nu kan vi räkna ut den totala kostnaden för elen, vilket är summan av kostnaden
# för elhandeln och den variabla delen av elnätskostnaden:
# 616 kr (elhandel) + 832 kr (variabel elnätskostnad) = 1448 kr

# Slutligen, för att räkna ut elpriset per kWh, delar vi den totala kostnaden med antalet kWh:
# 1448 kr / 900 kWh = 1.61 kr/kWh

KWH_PRICE = 1.61
# KWH_TRANSFER_PRICE = (0.244 + 0.392) * 1.25 # Elöverföring + energiskatt + moms (Vattenfall)
KWH_TRANSFER_PRICE = (0.09 + 0.392) * 1.25 # Elöverföring + energiskatt + moms (Vattenfall)
# https://www.vattenfalleldistribution.se/kund-i-elnatet/elnatspriser/elnatspriser-och-avtalsvillkor/
# https://www.vattenfalleldistribution.se/kund-i-elnatet/elnatspriser/energiskatt/
MONTHLY_FEE = 467 + 39 # Månadsavgift för elnät + elhandel

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

      price_per_kwh = tibber_prices[hour['date']]
      price_per_kwh ||= avg_price_per_kwh
      price_per_kwh = price_per_kwh + KWH_TRANSFER_PRICE
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
    # Then take last 7 days worth of hours with actual data
    hours_with_data = all_hours.select { |hour| hour[:consumption] && hour[:consumption] > 0 }
    last_days = hours_with_data.last(24 * 7).group_by { |hour| hour[:date] }
    
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
    last_days.reject! { |date, date_hours| date_hours.count < 24 } # Remove days that are not complete
    
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
    
    # Fetch historical outdoor temperatures for each day
    last_days_summed.each do |day_data|
      next unless day_data[:date] # Skip the summary item at the beginning

      # Parse the date (e.g., "Oct 23" -> "2025-10-23")
      date_obj = Date.parse("#{day_data[:date]} 2025")
      iso_date = date_obj.strftime("%Y-%m-%d")

      # Fetch historical weather data from weatherapi.com
      begin
        weather_response = HTTParty.get(
          "https://api.weatherapi.com/v1/history.json",
          query: {
            key: ENV['WEATHER_API_KEY'],
            q: 'Huddinge',
            dt: iso_date
          },
          timeout: 5
        )

        if weather_response.success?
          day_weather = weather_response.parsed_response['forecast']['forecastday'][0]['day']
          # Calculate average temperature from max and min
          avg_temp = (day_weather['maxtemp_c'] + day_weather['mintemp_c']) / 2.0
          day_data[:avg_temp_c] = avg_temp.round(1)
        end
      rescue => e
        # Silently fail if temperature fetch fails - sparkline will just show electricity
        puts "Failed to fetch temperature for #{iso_date}: #{e.message}"
      end
    end

    last_days_summed.prepend({
      price_so_far: price_so_far.ceil + MONTHLY_FEE,
      projected_total: projected_total.ceil + MONTHLY_FEE,
      average_hour: average_hour.round(3),
      peak_pricey_hours: peak_pricey_hours,
      last_days_summary: last_days_summary
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

end
#!/usr/bin/env ruby
# Debug timestamp matching between consumption and spot prices

require 'dotenv/load'
require 'json'
require 'date'
require 'httparty'

puts "=" * 80
puts "TIMESTAMP DEBUG - November 2024"
puts "=" * 80
puts ""

# Load consumption data for Nov 2024
consumption_file = JSON.parse(File.read('electricity_usage.json'))
nov_consumption = consumption_file.select do |hour|
  date = DateTime.parse(hour['date'])
  date.year == 2024 && date.month == 11
end

puts "Consumption data (Nov 2024):"
puts "  Total hours: #{nov_consumption.size}"
puts "  First 5 timestamps:"
nov_consumption.first(5).each do |hour|
  timestamp = DateTime.parse(hour['date']).iso8601
  puts "    #{timestamp}"
end
puts ""

# Load spot prices for Nov 2024
ELPRISET_API_BASE = 'https://www.elprisetjustnu.se/api/v1/prices'
REGION = 'SE3'

prices = {}
start_date = Date.new(2024, 11, 1)
end_date = Date.new(2024, 11, 30)

# Just fetch first day for debugging
date = start_date
date_str = date.strftime('%Y/%m-%d')
url = "#{ELPRISET_API_BASE}/#{date_str}_#{REGION}.json"

response = HTTParty.get(url, timeout: 10)
if response.code == 200
  day_prices = JSON.parse(response.body)
  puts "Spot price data (Nov 1, 2024):"
  puts "  Total hours: #{day_prices.size}"
  puts "  First 5 timestamps:"
  day_prices.first(5).each do |hour_data|
    timestamp = DateTime.parse(hour_data['time_start']).iso8601
    prices[timestamp] = hour_data['SEK_per_kWh'].to_f
    puts "    #{timestamp}"
  end
end

puts ""
puts "=" * 80
puts "TIMESTAMP COMPARISON"
puts "=" * 80

# Check if any consumption timestamps match spot price timestamps
consumption_timestamps = nov_consumption.first(24).map { |h| DateTime.parse(h['date']).iso8601 }
spot_timestamps = prices.keys

puts "Consumption format: #{consumption_timestamps.first}"
puts "Spot price format:  #{spot_timestamps.first}"
puts ""

matches = consumption_timestamps & spot_timestamps
puts "Matches in first 24 hours: #{matches.size}"

if matches.empty?
  puts ""
  puts "NO MATCHES! Investigating format differences..."
  puts ""

  c_sample = DateTime.parse(nov_consumption.first['date'])
  s_sample = DateTime.parse(day_prices.first['time_start'])

  puts "Consumption sample:"
  puts "  Original: #{nov_consumption.first['date']}"
  puts "  Parsed:   #{c_sample}"
  puts "  ISO8601:  #{c_sample.iso8601}"
  puts "  Zone:     #{c_sample.zone}"
  puts ""

  puts "Spot price sample:"
  puts "  Original: #{day_prices.first['time_start']}"
  puts "  Parsed:   #{s_sample}"
  puts "  ISO8601:  #{s_sample.iso8601}"
  puts "  Zone:     #{s_sample.zone}"
end

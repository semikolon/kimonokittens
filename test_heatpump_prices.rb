#!/usr/bin/env ruby
# Quick test script for heatpump_price_handler
require 'dotenv/load'
require_relative 'handlers/electricity_price_handler'
require_relative 'handlers/heatpump_price_handler'
require 'oj'
require 'rack'

puts "🧪 Testing Heatpump Price Handler"
puts "=" * 50

# Create mock request
env = {
  'REQUEST_METHOD' => 'GET',
  'PATH_INFO' => '/api/heatpump/prices',
  'rack.input' => StringIO.new
}
req = Rack::Request.new(env)

# Initialize handlers
electricity_price_handler = ElectricityPriceHandler.new
heatpump_price_handler = HeatpumpPriceHandler.new(electricity_price_handler)

# Call handler
puts "\n📡 Calling handler..."
status, headers, body = heatpump_price_handler.call(req)

puts "Status: #{status}"
puts "Headers: #{headers.inspect}"

if status == 200
  data = Oj.load(body.first)

  puts "\n✅ SUCCESS!"
  puts "\nResponse structure:"
  puts "  Region: #{data['region']}"
  puts "  Generated at: #{data['generated_at']}"
  puts "  Number of prices: #{data['prices'].length}"

  if data['prices'].length > 0
    puts "\n📊 First 3 hours:"
    data['prices'].first(3).each do |price|
      puts "  #{price['startsAt']}: #{price['total'].round(2)} kr (peak: #{price['breakdown']['isPeak']})"
    end

    puts "\n📊 Peak hour statistics:"
    peak_count = data['prices'].count { |p| p['breakdown']['isPeak'] }
    offpeak_count = data['prices'].length - peak_count
    puts "  Peak hours: #{peak_count}"
    puts "  Off-peak hours: #{offpeak_count}"

    puts "\n📊 Price range:"
    prices = data['prices'].map { |p| p['total'] }
    puts "  Min: #{prices.min.round(2)} kr"
    puts "  Max: #{prices.max.round(2)} kr"
    puts "  Avg: #{(prices.sum / prices.length).round(2)} kr"
  end
else
  puts "\n❌ FAILED!"
  puts "Body: #{body.first}"
end

puts "\n" + "=" * 50
puts "Test complete!"

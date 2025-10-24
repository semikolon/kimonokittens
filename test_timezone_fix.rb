#!/usr/bin/env ruby
# Test timezone normalization fix

require 'dotenv/load'
require_relative 'lib/electricity_projector'

puts "=" * 80
puts "TESTING TIMEZONE FIX - November 2024"
puts "=" * 80
puts ""

projector = ElectricityProjector.new

# Test Nov 2024 (should now match consumption with spot prices)
puts "Testing November 2024 projection..."
puts "-" * 80

begin
  projection = projector.send(
    :project_from_consumption_and_pricing,
    2024,
    11  # Config month Nov = Oct consumption
  )

  puts ""
  puts "✅ SUCCESS!"
  puts "   Projected: #{projection} kr"

  # Compare with actual
  bills = Persistence.electricity_bills.find_by_period(Date.new(2024, 11, 1))
  actual = bills.sum(&:amount).round

  puts "   Actual:    #{actual} kr"
  puts "   Difference: #{projection - actual} kr (#{((projection - actual).abs * 100.0 / actual).round(1)}%)"

rescue => e
  puts "❌ FAILED: #{e.message}"
end

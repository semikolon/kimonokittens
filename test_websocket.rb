#!/usr/bin/env ruby

require 'dotenv/load'
require_relative 'lib/rent_db'

puts "Testing WebSocket real-time updates..."

db = RentDb.instance

# Update a configuration value to trigger the WebSocket broadcast
unique_key = "test_value_#{Time.now.to_i}"
test_value = rand(1000..9999).to_s

puts "Setting test configuration value: #{unique_key} = #{test_value}"
db.set_config(unique_key, test_value, Time.now)

puts "Configuration updated. Check the frontend to see if it reloaded automatically!"
puts "The WebSocket should have broadcasted 'rent_data_updated' message." 
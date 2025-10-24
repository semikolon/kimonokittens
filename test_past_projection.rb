#!/usr/bin/env ruby
# Test smart projection with past month (complete data)

require 'dotenv/load'
require_relative 'lib/electricity_projector'

puts "=" * 80
puts "TESTING SMART PROJECTION - SEPTEMBER 2024"
puts "=" * 80
puts ""

projector = ElectricityProjector.new

# Project for October 2024 rent (September config)
# September consumption with actual spot prices from historical API
puts "Test: October 2024 rent (September config period)"
puts "Should calculate Sept consumption × Sept spot prices"
puts "-" * 80

september_projection = projector.project(config_year: 2024, config_month: 9)

puts ""
puts "Result: #{september_projection} kr"
puts ""
puts "=" * 80

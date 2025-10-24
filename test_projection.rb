#!/usr/bin/env ruby
# Test script for smart adaptive projection

require 'dotenv/load'
require_relative 'lib/electricity_projector'
require_relative 'lib/persistence'

puts "=" * 80
puts "TESTING SMART ADAPTIVE PROJECTION"
puts "=" * 80
puts ""

projector = ElectricityProjector.new

# Test 1: Project for November 2025 (October config)
# Should use actual bills if available, otherwise smart projection
puts "Test 1: November 2025 rent (October config period)"
puts "-" * 80
october_projection = projector.project(config_year: 2025, config_month: 10)
puts "Result: #{october_projection} kr"
puts ""

# Test 2: Project for December 2025 (November config)
# Likely no bills yet - should use smart projection
puts "Test 2: December 2025 rent (November config period)"
puts "-" * 80
november_projection = projector.project(config_year: 2025, config_month: 11)
puts "Result: #{november_projection} kr"
puts ""

# Test 3: Project for January 2026 (December config)
# Definitely no bills yet - should use smart projection
puts "Test 3: January 2026 rent (December config period)"
puts "-" * 80
december_projection = projector.project(config_year: 2025, config_month: 12)
puts "Result: #{december_projection} kr"
puts ""

puts "=" * 80
puts "TEST COMPLETE"
puts "=" * 80

#!/usr/bin/env ruby

require 'dotenv/load'
require_relative 'lib/rent_db'
require_relative 'rent'

puts '='*60
puts 'DEBUGGING FRIENDLY MESSAGE API ISSUE'
puts 'Expected: 7,045 kr, Actual: 7,492 kr'
puts '='*60

# Simulate exactly what the handler does
def simulate_handler_extract_config(year:, month:)
  puts "\n=== SIMULATING HANDLER extract_config(year: #{year}, month: #{month}) ==="

  db = RentDb.instance
  config = db.get_rent_config(year: year, month: month)

  puts "Raw config from database:"
  config.each { |row| puts "  #{row['key']}: #{row['value']}" }

  # Simulate handler processing
  config_hash = config.to_a.map do |row|
    key = row['key']
    value = row['value']
    [key.to_sym, value.to_f]
  end.compact.to_h

  puts "\nProcessed config_hash:"
  config_hash.each { |k, v| puts "  #{k}: #{v}" }

  # Check for quarterly invoice logic
  if config_hash[:drift_rakning] && config_hash[:drift_rakning] > 0
    puts "\n🚨 QUARTERLY INVOICE DETECTED: #{config_hash[:drift_rakning]} kr"
    puts "  Removing monthly fees: vattenavgift, va, larm"
    config_hash.delete(:vattenavgift)
    config_hash.delete(:va)
    config_hash.delete(:larm)
  else
    puts "\n✅ No quarterly invoice detected"
  end

  # Apply defaults (like handler does)
  defaults = {
    year: year,
    month: month,
    kallhyra: 24530,
    el: 0,
    bredband: 400,
    vattenavgift: 375,
    va: 300,
    larm: 150,
    drift_rakning: 0,
    saldo_innan: 0,
    extra_in: 0
  }

  final_config = defaults.merge(config_hash)

  puts "\nFinal config after defaults merge:"
  final_config.each { |k, v| puts "  #{k}: #{v}" }

  final_config
end

def simulate_roommates_extraction(year:, month:)
  puts "\n=== SIMULATING ROOMMATES EXTRACTION ==="

  # Default roommates (like the handler would extract)
  roommates = {
    'Fredrik' => { days: 30, room_adjustment: 0 },
    'Adam' => { days: 30, room_adjustment: 0 },
    'Amanda' => { days: 30, room_adjustment: 0 },
    'Rasmus' => { days: 30, room_adjustment: 0 }
  }

  puts "Roommates:"
  roommates.each { |name, info| puts "  #{name}: #{info[:days]} days, adjustment: #{info[:room_adjustment]}" }

  roommates
end

# Current month (what the dashboard is requesting)
now = Time.now
year = now.year
month = now.month

puts "Current request: year=#{year}, month=#{month} (#{Date::MONTHNAMES[month]})"

# Step 1: Extract config (like handler does)
config = simulate_handler_extract_config(year: year, month: month)

# Step 2: Extract roommates (like handler does)
roommates = simulate_roommates_extraction(year: year, month: month)

# Step 3: Calculate rent
puts "\n=== RENT CALCULATION ==="
breakdown = RentCalculator.rent_breakdown(roommates: roommates, config: config)

puts "Breakdown results:"
puts "  Total: #{breakdown['Total']} kr"
puts "  Per person: #{breakdown['Rent per Roommate'].values.first} kr"

# Step 4: Generate friendly message
puts "\n=== FRIENDLY MESSAGE GENERATION ==="
friendly_text = RentCalculator.friendly_message(roommates: roommates, config: config)
puts "Generated message:"
puts "\"#{friendly_text}\""

# Step 5: Compare with expected
puts "\n=== COMPARISON ==="
expected = 7045
actual = breakdown['Rent per Roommate'].values.first

if actual == expected
  puts "✅ MATCHES EXPECTED: #{actual} kr"
else
  puts "❌ MISMATCH:"
  puts "  Expected: #{expected} kr"
  puts "  Actual: #{actual} kr"
  puts "  Difference: #{actual - expected} kr"

  # Try to identify the source of extra cost
  puts "\n🔍 ANALYZING DIFFERENCE:"

  # Check if quarterly invoice is the culprit
  if config[:drift_rakning] && config[:drift_rakning] > 0
    puts "  💡 Quarterly invoice detected: #{config[:drift_rakning]} kr"
    puts "     This replaces monthly fees, adding extra cost"
  end

  # Calculate what it should be without quarterly invoice
  clean_config = config.dup
  clean_config[:drift_rakning] = 0
  clean_config[:vattenavgift] = 375
  clean_config[:va] = 300
  clean_config[:larm] = 150

  clean_breakdown = RentCalculator.rent_breakdown(roommates: roommates, config: clean_config)
  puts "  Without quarterly invoice: #{clean_breakdown['Rent per Roommate'].values.first} kr"
end

puts "\n" + "="*60
puts "DEBUG COMPLETE"
puts "="*60
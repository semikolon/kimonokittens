#!/usr/bin/env ruby

require 'dotenv/load'
require_relative 'lib/rent_db'
require_relative 'rent'

# Save October 2025 rent configuration with ACTUAL electricity bills
# Fortum: 792 kr + Vattenfall: 1632 kr = 2424 kr total

puts "Saving October 2025 configuration with actual electricity bills..."

# Initialize database connection
db = RentDb.instance

# October 2025 - set period to October 1st, 2025
october_2025 = Time.new(2025, 10, 1)

# Save actual electricity cost to database
# This will override the historical projection and mark it as "actual bills"
db.set_config('el', 2424, october_2025)
puts "✅ Saved electricity cost: 2424 kr for October 2025"

# Save other configuration values for completeness
db.set_config('kallhyra', 24530, october_2025)
db.set_config('bredband', 400, october_2025)
db.set_config('vattenavgift', 375, october_2025)
db.set_config('va', 300, october_2025)
db.set_config('larm', 150, october_2025)

puts "✅ Saved complete October 2025 configuration to database"

# Now calculate and display the actual rent
config = {
  year: 2025,
  month: 10,
  kallhyra: 24530,
  el: 2424,  # Actual bills: Fortum 792 + Vattenfall 1632
  bredband: 400,
  vattenavgift: 375,
  va: 300,
  larm: 150,
  saldo_innan: 0,
  extra_in: 0
}

roommates = {
  'Fredrik' => {},
  'Adam' => {},
  'Amanda' => {},
  'Rasmus' => {}
}

puts "\n" + "="*50
puts "OCTOBER 2025 RENT CALCULATION (ACTUAL BILLS)"
puts "="*50

breakdown = RentCalculator.rent_breakdown(roommates: roommates, config: config)
puts "Total rent: #{breakdown['Total']} kr"
puts "Individual rent:"
breakdown['Rent per Roommate'].each do |name, amount|
  puts "  #{name}: #{amount} kr"
end

puts "\n" + "="*50
puts "FRIENDLY MESSAGE:"
puts "="*50
puts RentCalculator.friendly_message(roommates: roommates, config: config)

puts "\n✅ Configuration saved! Dashboard should now show actual bills."
puts "📋 Data source should now say: 'Baserad på aktuella elräkningar'"
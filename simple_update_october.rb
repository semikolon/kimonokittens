#!/usr/bin/env ruby

require 'dotenv/load'
require_relative 'lib/rent_db'
require_relative 'rent'

puts "Updating October 2025 electricity cost with actual bills..."

# Initialize database connection
db = RentDb.instance

# October 2025 - set period to October 1st, 2025
october_2025 = Time.new(2025, 10, 1)

# Update electricity cost to actual bills: 792 + 1632 = 2424
db.class.rent_configs.where(key: 'el').update(
  value: 2424,
  period: october_2025.utc,
  updatedAt: Time.now.utc
)

puts "✅ Updated electricity cost: 2424 kr for October 2025"

# Test the configuration extraction
puts "\nTesting configuration extraction for October 2025..."
config_result = db.get_rent_config(year: 2025, month: 10)
config_hash = {}
config_result.each do |row|
  config_hash[row['key'].to_sym] = row['value'].to_i
end

puts "Extracted config from database:"
config_hash.each do |key, value|
  puts "  #{key}: #{value}"
end

# Calculate actual rent with updated config
roommates = {
  'Fredrik' => {},
  'Adam' => {},
  'Amanda' => {},
  'Rasmus' => {}
}

final_config = {
  year: 2025,
  month: 10,
  kallhyra: config_hash[:kallhyra] || 24530,
  el: config_hash[:el] || 2424,  # This should now be 2424 from database
  bredband: config_hash[:bredband] || 400,
  vattenavgift: config_hash[:vattenavgift] || 375,
  va: 300,
  larm: 150,
  saldo_innan: 0,
  extra_in: 0
}

puts "\n" + "="*50
puts "OCTOBER 2025 RENT (ACTUAL BILLS)"
puts "="*50

breakdown = RentCalculator.rent_breakdown(roommates: roommates, config: final_config)
puts "Total rent: #{breakdown['Total']} kr"
puts "Individual rent per person:"
breakdown['Rent per Roommate'].each do |name, amount|
  puts "  #{name}: #{amount} kr"
end

puts "\n" + "="*30
puts "COMPARISON:"
puts "="*30
puts "Previous (projected): 7,286 kr per person"
puts "Actual (2424 kr el):  #{breakdown['Rent per Roommate'].values.first} kr per person"
difference = breakdown['Rent per Roommate'].values.first - 7286
puts "Difference: #{difference > 0 ? '+' : ''}#{difference} kr per person"

puts "\n✅ Database updated! Dashboard should now show actual bills."
puts "📋 Data source should change to: 'Baserad på aktuella elräkningar'"
puts "🔄 Refresh the dashboard to see the changes."
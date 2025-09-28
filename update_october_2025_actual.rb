#!/usr/bin/env ruby

require 'dotenv/load'
require_relative 'lib/rent_db'
require_relative 'rent'

# Update October 2025 rent configuration with ACTUAL electricity bills
# Fortum: 792 kr + Vattenfall: 1632 kr = 2424 kr total

puts "Updating October 2025 configuration with actual electricity bills..."

# Initialize database connection
db = RentDb.instance

# October 2025 - set period to October 1st, 2025
october_2025 = Time.new(2025, 10, 1)

# Update existing electricity cost in database
# This will override the historical projection and mark it as "actual bills"
puts "Current 'el' config:"
current_el = db.class.rent_configs.where(key: 'el').first
puts "  Value: #{current_el[:value]}, Period: #{current_el[:period]}"

# Update the existing record
db.class.rent_configs.where(key: 'el').update(
  value: 2424,
  period: october_2025.utc,
  updatedAt: Time.now.utc
)

puts "✅ Updated electricity cost: 2424 kr for October 2025"

# Update other necessary configs for October 2025
['kallhyra', 'bredband', 'vattenavgift'].each do |key|
  existing = db.class.rent_configs.where(key: key).first
  if existing
    case key
    when 'kallhyra'
      db.class.rent_configs.where(key: key).update(value: 24530, period: october_2025.utc, updatedAt: Time.now.utc)
    when 'bredband'
      db.class.rent_configs.where(key: key).update(value: 400, period: october_2025.utc, updatedAt: Time.now.utc)
    when 'vattenavgift'
      db.class.rent_configs.where(key: key).update(value: 375, period: october_2025.utc, updatedAt: Time.now.utc)
    end
    puts "✅ Updated #{key} for October 2025"
  end
end

# Add missing config keys if they don't exist
['va', 'larm'].each do |key|
  existing = db.class.rent_configs.where(key: key).first
  unless existing
    value = key == 'va' ? 300 : 150
    db.class.rent_configs.insert(
      id: require('cuid').generate,
      key: key,
      value: value,
      period: october_2025.utc,
      createdAt: Time.now.utc,
      updatedAt: Time.now.utc
    )
    puts "✅ Added #{key}: #{value} kr for October 2025"
  end
end

puts "\n" + "="*50
puts "DATABASE CONFIGURATION UPDATED"
puts "="*50

# Test the configuration extraction
puts "Testing configuration extraction for October 2025..."
config_result = db.get_rent_config(year: 2025, month: 10)
config_hash = {}
config_result.each do |row|
  config_hash[row['key'].to_sym] = row['value'].to_i
end

puts "Extracted config:"
config_hash.each do |key, value|
  puts "  #{key}: #{value}"
end

# Now calculate and display the actual rent
roommates = {
  'Fredrik' => {},
  'Adam' => {},
  'Amanda' => {},
  'Rasmus' => {}
}

puts "\n" + "="*50
puts "OCTOBER 2025 RENT CALCULATION (ACTUAL BILLS)"
puts "="*50

# Use the extracted config
final_config = {
  year: 2025,
  month: 10,
  kallhyra: config_hash[:kallhyra] || 24530,
  el: config_hash[:el] || 2424,
  bredband: config_hash[:bredband] || 400,
  vattenavgift: config_hash[:vattenavgift] || 375,
  va: config_hash[:va] || 300,
  larm: config_hash[:larm] || 150,
  saldo_innan: 0,
  extra_in: 0
}

breakdown = RentCalculator.rent_breakdown(roommates: roommates, config: final_config)
puts "Total rent: #{breakdown['Total']} kr"
puts "Individual rent:"
breakdown['Rent per Roommate'].each do |name, amount|
  puts "  #{name}: #{amount} kr"
end

puts "\n" + "="*50
puts "FRIENDLY MESSAGE:"
puts "="*50
puts RentCalculator.friendly_message(roommates: roommates, config: final_config)

puts "\n✅ Configuration updated! Dashboard should now show actual bills."
puts "📋 Data source should now say: 'Baserad på aktuella elräkningar'"
puts "🔄 You may need to refresh the dashboard to see changes."
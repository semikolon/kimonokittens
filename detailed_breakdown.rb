#!/usr/bin/env ruby

require 'dotenv/load'
require_relative 'lib/rent_db'
require_relative 'rent'
require 'awesome_print'

puts '='*60
puts 'COMPLETE OCTOBER 2025 RENT CALCULATION BREAKDOWN'
puts '='*60

# Get current roommates from database
db = RentDb.instance
roommates_data = {}
db.get_tenants.each do |tenant|
  roommates_data[tenant['name']] = {
    days: 31,  # Full month
    room_adjustment: tenant['roomAdjustment'] || 0
  }
end

puts 'CURRENT ROOMMATES:'
roommates_data.each do |name, info|
  adjustment_text = info[:room_adjustment] != 0 ? " (#{info[:room_adjustment]} kr adjustment)" : ''
  puts "  #{name}: #{info[:days]} days#{adjustment_text}"
end

# Get configuration from database
config_result = db.get_rent_config(year: 2025, month: 10)
config_hash = {}
config_result.each do |row|
  config_hash[row['key'].to_sym] = row['value'].to_i
end

puts "\n" + '='*40
puts 'CONFIGURATION FROM DATABASE:'
puts '='*40
config_hash.each do |key, value|
  puts "  #{key}: #{value} kr"
end

# Build complete config
final_config = {
  year: 2025,
  month: 10,
  kallhyra: config_hash[:kallhyra] || 24530,
  el: config_hash[:el] || 2424,
  bredband: config_hash[:bredband] || 400,
  vattenavgift: config_hash[:vattenavgift] || 375,
  va: 300,
  larm: 150,
  drift_rakning: config_hash[:drift_rakning],
  saldo_innan: 0,
  extra_in: 0,
  gas: 0
}

puts "\n" + '='*40
puts 'COMPLETE CONFIGURATION USED:'
puts '='*40
final_config.each do |key, value|
  next if value.nil?
  puts "  #{key}: #{value} kr"
end

# Calculate detailed breakdown
breakdown = RentCalculator.rent_breakdown(roommates: roommates_data, config: final_config)

puts "\n" + '='*40
puts 'DETAILED COST BREAKDOWN:'
puts '='*40
puts "Base rent (kallhyra): #{breakdown['Kallhyra']} kr"
puts "Electricity (el): #{breakdown['El']} kr"
puts "Internet (bredband): #{breakdown['Bredband']} kr"

if breakdown['Kvartalsfaktura drift']
  puts "Quarterly invoice (drift): #{breakdown['Kvartalsfaktura drift']} kr"
else
  puts "Water fee (vattenavgift): #{breakdown['Vattenavgift']} kr" if breakdown['Vattenavgift']
  puts "Sewage (va): #{breakdown['VA']} kr" if breakdown['VA']
  puts "Alarm (larm): #{breakdown['Larm']} kr" if breakdown['Larm']
end

puts "Operational costs total: #{breakdown['Drift total']} kr"
puts "Previous balance (saldo): #{final_config[:saldo_innan]} kr"
puts "Extra income: #{final_config[:extra_in]} kr"

puts "\n" + '-'*30
puts "TOTAL RENT TO DISTRIBUTE: #{breakdown['Total']} kr"
puts '-'*30

puts "\n" + '='*40
puts 'CALCULATION DETAILS:'
puts '='*40
details = breakdown['calculation_details']
puts "Total weight: #{details['total_weight']}"
puts "Rent per weight point: #{details['rent_per_weight_point']} kr"
puts "Total adjustments: #{details['total_adjustment']} kr"
puts "Distributable rent: #{details['distributable_rent']} kr"

puts "\nProrated adjustments:"
details['prorated_adjustments'].each do |name, adjustment|
  puts "  #{name}: #{adjustment} kr"
end

puts "\n" + '='*40
puts 'FINAL INDIVIDUAL RENT:'
puts '='*40
breakdown['Rent per Roommate'].each do |name, amount|
  puts "  #{name}: #{amount} kr"
end

puts "\n" + '='*40
puts 'VERIFICATION:'
puts '='*40
total_paid = breakdown['Rent per Roommate'].values.sum
puts "Sum of individual payments: #{total_paid} kr"
puts "Total rent to distribute: #{breakdown['Total']} kr"
puts "Difference: #{total_paid - breakdown['Total']} kr (should be 0)"

puts "\n" + '='*40
puts 'ELECTRICITY BREAKDOWN:'
puts '='*40
puts "Fortum (consumption): 792 kr"
puts "Vattenfall (grid): 1632 kr"
puts "Total electricity: #{792 + 1632} kr"
puts "System electricity: #{breakdown['El']} kr"
puts "Match: #{breakdown['El'] == 2424 ? '✅' : '❌'}"

puts "\n" + '='*40
puts 'COST STRUCTURE ANALYSIS:'
puts '='*40
total = breakdown['Total'].to_f
puts "Base rent: #{breakdown['Kallhyra']} kr (#{(breakdown['Kallhyra']/total*100).round(1)}%)"
puts "Electricity: #{breakdown['El']} kr (#{(breakdown['El']/total*100).round(1)}%)"
puts "Internet: #{breakdown['Bredband']} kr (#{(breakdown['Bredband']/total*100).round(1)}%)"
if breakdown['Kvartalsfaktura drift']
  drift = breakdown['Kvartalsfaktura drift']
  puts "Quarterly fees: #{drift} kr (#{(drift/total*100).round(1)}%)"
else
  water_total = (breakdown['Vattenavgift'] || 0) + (breakdown['VA'] || 0) + (breakdown['Larm'] || 0)
  puts "Water/sewage/alarm: #{water_total} kr (#{(water_total/total*100).round(1)}%)"
end

puts "\n" + '='*60
puts 'SUMMARY'
puts '='*60
puts "October 2025 rent per person: #{breakdown['Rent per Roommate'].values.first} kr"
puts "Due date: September 27, 2025"
puts "Payment method: Actual electricity bills (not projected)"
puts "Number of roommates: #{breakdown['Rent per Roommate'].size}"
puts "Data source: Database configuration (actual bills)"
puts '='*60
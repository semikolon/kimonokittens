#!/usr/bin/env ruby

require 'dotenv/load'
require_relative 'lib/rent_db'

puts "Normalizing existing periods to month start..."

db = RentDb.instance

# Get all current records
current_records = db.class.rent_configs.all

puts "Found #{current_records.length} records to normalize:"

current_records.each do |record|
  old_period = record[:period]
  normalized_period = Time.utc(old_period.year, old_period.month, 1)

  puts "  #{record[:key]}: #{old_period} -> #{normalized_period}"

  # Update the record with normalized period
  db.class.rent_configs.where(id: record[:id]).update(
    period: normalized_period,
    updatedAt: Time.now.utc
  )
end

puts "✅ All periods normalized to month start"

# Verify the normalization
puts "\nVerification:"
db.class.rent_configs.all.each do |record|
  period = record[:period]
  month_start = Time.utc(period.year, period.month, 1)
  is_normalized = (period.to_i == month_start.to_i)
  status = is_normalized ? "✅" : "❌"
  puts "  #{record[:key]}: #{period} #{status}"
end
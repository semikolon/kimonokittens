#!/usr/bin/env ruby
# Electricity Bill Migration: Text File → ElectricityBill Table
#
# Purpose: Migrate individual electricity bills from text file to database
#          for better querying, aggregation, and future API automation.
#
# Source: electricity_bills_history.txt
# Target: ElectricityBill table
#
# Usage: ruby deployment/electricity_bill_migration.rb

require 'dotenv/load'
require_relative '../lib/rent_db'
require 'date'

puts "=" * 80
puts "ELECTRICITY BILL MIGRATION: Text File → Database"
puts "=" * 80
puts "Date: #{Time.now.strftime('%Y-%m-%d %H:%M:%S')}"
puts

db = RentDb.instance

# Track statistics
stats = {
  vattenfall_bills: 0,
  fortum_bills: 0,
  total_amount: 0,
  skipped_duplicates: 0
}

begin
  text_file = 'electricity_bills_history.txt'

  unless File.exist?(text_file)
    puts "❌ ERROR: #{text_file} not found!"
    exit 1
  end

  lines = File.readlines(text_file)
  puts "📄 Reading #{text_file} (#{lines.size} lines)"
  puts

  # Track current provider section
  current_provider = nil

  lines.each_with_index do |line, idx|
    line = line.strip
    next if line.empty?

    # Detect provider section headers
    if line.include?('Vattenfall')
      current_provider = 'vattenfall'
      puts "📊 Processing Vattenfall bills:"
      next
    elsif line.include?('Fortum')
      current_provider = 'fortum'
      puts
      puts "📊 Processing Fortum bills:"
      next
    end

    # Skip non-bill lines
    next unless line =~ /^(\d{4})-(\d{2})-(\d{2})\s+(\d+)/

    year, month, day = $1.to_i, $2.to_i, $3.to_i
    amount = $4.to_i
    due_date = Date.new(year, month, day)

    unless current_provider
      puts "   ⚠️  Line #{idx + 1}: No provider detected, skipping: #{line}"
      next
    end

    # Calculate consumption period from due date
    # Same logic as RentConfig migration (see CLAUDE.md "Electricity Bill Due Date Timing")
    if day >= 25
      # Bill arrived same month as due date
      consumption_month = month
      consumption_year = year
    else
      # Bill arrived month before due date
      consumption_month = month - 1
      consumption_year = year
    end

    if consumption_month < 1
      consumption_month = 12
      consumption_year -= 1
    end

    bill_period = Date.new(consumption_year, consumption_month, 1)

    # Check for duplicates (same provider, due date, amount)
    existing = db.class.db[:ElectricityBill]
      .where(provider: current_provider, billDate: due_date, amount: amount)
      .first

    if existing
      stats[:skipped_duplicates] += 1
      next
    end

    # Insert bill
    db.class.db[:ElectricityBill].insert(
      id: Cuid.generate,
      provider: current_provider,
      billDate: due_date,
      amount: amount,
      billPeriod: bill_period,
      createdAt: Time.now.utc,
      updatedAt: Time.now.utc
    )

    puts "   ✅ #{due_date.strftime('%Y-%m-%d')}: #{amount} kr (#{bill_period.strftime('%Y-%m')} consumption)"

    # Update stats
    if current_provider == 'vattenfall'
      stats[:vattenfall_bills] += 1
    else
      stats[:fortum_bills] += 1
    end
    stats[:total_amount] += amount
  end

  puts
  puts "=" * 80
  puts "✅ MIGRATION COMPLETE"
  puts "=" * 80
  puts
  puts "📊 Statistics:"
  puts "   Vattenfall bills: #{stats[:vattenfall_bills]}"
  puts "   Fortum bills: #{stats[:fortum_bills]}"
  puts "   Total bills: #{stats[:vattenfall_bills] + stats[:fortum_bills]}"
  puts "   Total amount: #{stats[:total_amount]} kr"
  puts "   Skipped duplicates: #{stats[:skipped_duplicates]}"
  puts

  # Verification: Check aggregation matches RentConfig
  puts "🔍 Verification - Compare with RentConfig:"
  puts

  # Sample periods where we have both ElectricityBill and RentConfig
  test_periods = [
    Time.utc(2025, 9, 1),  # Sept config (Oct rent)
    Time.utc(2025, 8, 1),  # Aug config (Sept rent)
    Time.utc(2025, 7, 1)   # July config (Aug rent)
  ]

  test_periods.each do |period|
    # Sum from ElectricityBill
    bill_total = db.class.db[:ElectricityBill]
      .where(billPeriod: period)
      .sum(:amount) || 0

    # Get from RentConfig
    config = db.class.rent_configs
      .where(key: 'el', period: period)
      .first

    config_value = config ? config[:value].to_i : 0

    match = bill_total == config_value ? '✅' : '⚠️'
    puts "   #{period.strftime('%Y-%m')}: Bills #{bill_total} kr vs Config #{config_value} kr #{match}"
  end

  puts
  puts "📌 Next Steps:"
  puts "   1. Verify aggregations match RentConfig (above)"
  puts "   2. Run in production"
  puts "   3. Delete electricity_bills_history.txt (preserved in git)"
  puts "   4. Update ElectricityProjector if needed (already uses RentConfig)"
  puts

rescue => e
  puts "❌ MIGRATION FAILED: #{e.message}"
  puts e.backtrace.first(10)
  exit 1
end

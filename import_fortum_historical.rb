#!/usr/bin/env ruby
# frozen_string_literal: true

# Import Fortum bills from electricity_bills_history.txt
# This replaces any incorrect database entries with verified historical data

require 'dotenv/load'
require_relative 'lib/persistence'
require_relative 'lib/services/apply_electricity_bill'
require 'date'

puts '=' * 80
puts 'FORTUM HISTORICAL DATA IMPORT'
puts '=' * 80

# Step 1: Delete all existing Fortum bills
puts ''
puts '→ Deleting existing Fortum bills...'
deleted = Persistence.electricity_bills.dataset
  .where(provider: 'fortum')
  .delete

puts "  ✓ Deleted #{deleted} bills"

# Step 2: Parse historical file
puts ''
puts '→ Parsing electricity_bills_history.txt...'

historical_bills = []
in_fortum_section = false

File.readlines('electricity_bills_history.txt').each do |line|
  line = line.strip
  next if line.empty?

  # Detect Fortum section
  if line.match(/Fortum.*elförbrukning/i)
    in_fortum_section = true
    next
  end

  # Skip non-Fortum sections
  next unless in_fortum_section

  # Stop at next section (but not the Fortum header itself)
  break if line.start_with?('#') && !line.match(/Fortum/i)

  # Skip comments
  next if line.start_with?('#')

  # Parse bill lines: 2025-10-01	792 kr
  if match = line.match(/^(\d{4}-\d{2}-\d{2})\s+(\d+)\s*kr/)
    due_date_str, amount_str = match.captures
    historical_bills << {
      due_date: Date.parse(due_date_str),
      amount: amount_str.to_f
    }
  end
end

puts "  ✓ Parsed #{historical_bills.size} Fortum bills"

# Step 3: Import bills using ApplyElectricityBill service
puts ''
puts '→ Importing bills to database...'

inserted_count = 0
skipped_count = 0

historical_bills.each do |bill|
  result = ApplyElectricityBill.call(
    provider: 'fortum',
    amount: bill[:amount],
    due_date: bill[:due_date]
  )

  period = result[:bill_period]&.strftime('%Y-%m') || 'unknown'

  if result[:inserted]
    puts "  ✓ #{bill[:due_date]} | #{bill[:amount].to_i} kr → period #{period}"
    inserted_count += 1
  else
    puts "  ⊘ Skipped duplicate: #{bill[:due_date]} | #{bill[:amount].to_i} kr"
    skipped_count += 1
  end
end

puts ''
puts '=' * 80
puts "SUMMARY: #{inserted_count} inserted, #{skipped_count} skipped"
puts '=' * 80

# Step 4: Verify total count
total_fortum = Persistence.electricity_bills.dataset
  .where(provider: 'fortum')
  .count

puts ''
puts "Total Fortum bills in database: #{total_fortum}"

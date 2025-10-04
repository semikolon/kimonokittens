#!/usr/bin/env ruby
# Historical Configuration Migration Script
#
# Purpose: Consolidate historical data from JSON files and text files into RentConfig table
# This enables simplified ElectricityProjector (database-only queries) and eventual deletion
# of legacy data files.
#
# Data Sources:
# 1. data/rent_history/*.json - Historical rent calculations with full config (PRIORITY 1)
# 2. electricity_bills_history.txt - Raw provider bills (PRIORITY 2 - fill gaps)
#
# Usage: ruby deployment/historical_config_migration.rb

require 'dotenv/load'
require_relative '../lib/rent_db'
require 'json'
require 'date'

puts "=== HISTORICAL CONFIGURATION MIGRATION ==="
puts "Date: #{Time.now.strftime('%Y-%m-%d %H:%M:%S')}"
puts

db = RentDb.instance

# Track what we insert for reporting
inserted_configs = Hash.new(0)
skipped_duplicates = 0

begin
  # PHASE 1: Import from JSON files (highest priority - actual historical calculations)
  puts "📊 PHASE 1: Importing from JSON files (data/rent_history/)"
  puts "=" * 70

  history_dir = 'data/rent_history'

  unless Dir.exist?(history_dir)
    puts "⚠️  Warning: #{history_dir} directory not found, skipping JSON import"
  else
    # Group files by period to handle multiple versions
    files_by_period = Hash.new { |h, k| h[k] = [] }

    Dir.glob("#{history_dir}/*.json").each do |json_file|
      filename = File.basename(json_file)
      match = filename.match(/^(\d{4})_(\d{2})_v(\d+)\.json$/)

      if match
        year = match[1].to_i
        month = match[2].to_i
        version = match[3].to_i
        files_by_period[[year, month]] << { file: json_file, version: version }
      else
        puts "   ⚠️  Skipping #{filename} (doesn't match version pattern)"
      end
    end

    # Process highest version for each period
    files_by_period.sort.each do |(year, month), versions|
      latest = versions.max_by { |v| v[:version] }
      filename = File.basename(latest[:file])

      begin
        data = JSON.parse(File.read(latest[:file]))
        constants = data['constants']

        unless constants
          puts "   ⚠️  #{filename}: No constants found, skipping"
          next
        end

        # CRITICAL: Use constants.month for config period, NOT filename!
        # Filename = rent month, constants.month = config month
        # Example: 2025_08_v1.json (Aug rent) has constants.month=7 (July config)
        config_year = constants['year'].to_i
        config_month = constants['month'].to_i
        config_period = Time.utc(config_year, config_month, 1)
        puts "   📅 Processing #{filename} (config period: #{config_year}-#{sprintf('%02d', config_month)})"

        # Extract all configuration keys from constants
        # Period-specific: el, drift_rakning
        # Persistent: kallhyra, bredband, vattenavgift, va, larm
        config_keys = %w[el drift_rakning kallhyra bredband vattenavgift va larm saldo_innan extra_in]

        config_keys.each do |key|
          value = constants[key]
          next unless value # Skip if key not present in JSON
          next if value == 0 # Skip zero values

          # Check if this config already exists
          existing = db.class.rent_configs
            .where(key: key, period: config_period)
            .first

          if existing
            # Update if value differs
            if existing[:value].to_s != value.to_s
              db.class.rent_configs
                .where(id: existing[:id])
                .update(
                  value: value.to_s,
                  updatedAt: Time.now.utc
                )
              puts "      ✏️  Updated #{key}=#{value} (was #{existing[:value]})"
              inserted_configs[key] += 1
            else
              skipped_duplicates += 1
            end
          else
            # Insert new config
            db.class.rent_configs.insert(
              id: Cuid.generate,
              key: key,
              value: value.to_s,
              period: config_period,
              createdAt: Time.now.utc,
              updatedAt: Time.now.utc
            )
            puts "      ✅ Inserted #{key}=#{value}"
            inserted_configs[key] += 1
          end
        end

      rescue => e
        puts "   ❌ Error processing #{filename}: #{e.message}"
      end
    end
  end

  puts
  puts "📄 PHASE 2: Importing from electricity_bills_history.txt"
  puts "=" * 70

  text_file = 'electricity_bills_history.txt'

  unless File.exist?(text_file)
    puts "⚠️  Warning: #{text_file} not found, skipping text file import"
  else
    lines = File.readlines(text_file)

    # CRITICAL: Aggregate bills by CONFIG PERIOD, not due date
    # Multiple due dates can map to same config period (e.g., July 31 + Aug 1 → July config)
    bills_by_config_period = Hash.new { |h, k| h[k] = { total: 0, bills: [] } }

    lines.each do |line|
      next if line.strip.empty?
      next if line.include?('Vattenfall') || line.include?('Fortum') # Skip section headers

      # Parse bill lines: "2025-10-01  1632 kr"
      next unless line =~ /^(\d{4})-(\d{2})-(\d{2})\s+(\d+)/

      year, month, day = $1.to_i, $2.to_i, $3.to_i
      cost = $4.to_i
      due_date = "#{year}-#{sprintf('%02d', month)}-#{sprintf('%02d', day)}"

      # Calculate config period from due date
      # See CLAUDE.md "Electricity Bill Due Date Timing" for full explanation
      if day >= 25
        # Bill due end of month → arrived same month
        config_month = month
        config_year = year
      else
        # Bill due start of month → arrived previous month
        config_month = month - 1
        config_year = year
      end

      if config_month < 1
        config_month += 12
        config_year -= 1
      end

      config_period = Time.utc(config_year, config_month, 1)

      # Aggregate by config period
      bills_by_config_period[config_period][:total] += cost
      bills_by_config_period[config_period][:bills] << "#{due_date}: #{cost} kr"
    end

    # Insert aggregated bills by config period
    bills_by_config_period.sort.each do |config_period, data|
      # Check if el config already exists for this period (JSON might have it)
      existing = db.class.rent_configs
        .where(key: 'el', period: config_period)
        .first

      if existing
        puts "   ⏭️  Skipped #{config_period.strftime('%Y-%m')} (#{data[:total]} kr) - already have el config"
        skipped_duplicates += 1
      else
        db.class.rent_configs.insert(
          id: Cuid.generate,
          key: 'el',
          value: data[:total].to_s,
          period: config_period,
          createdAt: Time.now.utc,
          updatedAt: Time.now.utc
        )
        puts "   ✅ Inserted el=#{data[:total]} for #{config_period.strftime('%Y-%m')} (#{data[:bills].join(', ')})"
        inserted_configs['el'] += 1
      end
    end
  end

  puts
  puts "=" * 70
  puts "✅ MIGRATION COMPLETE"
  puts
  puts "📊 Summary:"
  inserted_configs.each do |key, count|
    puts "   #{key.ljust(20)} #{count} records"
  end
  puts "   Skipped duplicates: #{skipped_duplicates}"
  puts
  puts "🗄️  Total RentConfig records now: #{db.class.rent_configs.count}"
  puts
  puts "📌 Next Steps:"
  puts "   1. Simplify ElectricityProjector to database-only queries"
  puts "   2. Test rent projections still work correctly"
  puts "   3. After verification, can delete:"
  puts "      - electricity_bills_history.txt"
  puts "      - data/rent_history/*.json (backup first!)"

rescue => e
  puts "❌ Migration failed: #{e.message}"
  puts e.backtrace.first(5)
  exit 1
end

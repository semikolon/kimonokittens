#!/usr/bin/env ruby
# Complete Rent Data Migration: JSON Files → RentLedger Audit Trail
#
# Purpose: Populate RentLedger audit fields (daysStayed, roomAdjustment, etc)
#          from historical JSON files to enable single source of truth in database.
#
# Background:
# - RentLedger entries already exist (created by production_migration.rb)
# - They have amountDue/amountPaid but lack audit trail (HOW amount was calculated)
# - JSON files contain complete context: days stayed, adjustments, calculation dates
#
# This script enriches existing RentLedger records with historical audit data.
#
# Usage: ruby deployment/complete_rent_data_migration.rb

require 'dotenv/load'
require_relative '../lib/rent_db'
require 'json'
require 'date'

puts "=" * 80
puts "COMPLETE RENT DATA MIGRATION: JSON → RentLedger Audit Trail"
puts "=" * 80
puts "Date: #{Time.now.strftime('%Y-%m-%d %H:%M:%S')}"
puts

# Safety check: Verify backup exists
latest_backup = Dir.glob('deployment/backups/dev_db_backup_*.sql').sort.last
unless latest_backup
  puts "❌ ERROR: No database backup found!"
  puts "   Run: pg_dump $DATABASE_URL > deployment/backups/dev_db_backup_$(date +%Y%m%d_%H%M%S).sql"
  exit 1
end
puts "✅ Backup verified: #{File.basename(latest_backup)} (#{(File.size(latest_backup) / 1024.0).round(2)} KB)"
puts

db = RentDb.instance

# Build tenant name → ID mapping
tenant_map = {}
db.class.tenants.all.each do |tenant|
  tenant_map[tenant[:name]] = tenant[:id]
end
puts "📋 Tenant mapping: #{tenant_map.keys.join(', ')}"
puts

# Track statistics
stats = {
  json_files_processed: 0,
  ledger_entries_updated: 0,
  ledger_entries_created: 0,
  skipped_no_ledger: 0,
  skipped_no_tenant: 0
}

begin
  history_dir = 'data/rent_history'

  unless Dir.exist?(history_dir)
    puts "❌ ERROR: #{history_dir} directory not found!"
    exit 1
  end

  # Group JSON files by period, take highest version
  files_by_period = Hash.new { |h, k| h[k] = [] }

  Dir.glob("#{history_dir}/*.json").each do |json_file|
    filename = File.basename(json_file)

    # Match pattern: YYYY_MM_vN.json
    if filename =~ /^(\d{4})_(\d{2})_v(\d+)\.json$/
      rent_year = $1.to_i
      rent_month = $2.to_i
      version = $3.to_i
      files_by_period[[rent_year, rent_month]] << { file: json_file, version: version }
    else
      puts "⚠️  Skipping #{filename} (doesn't match version pattern)"
    end
  end

  # Process highest version for each period
  files_by_period.sort.each do |(rent_year, rent_month), versions|
    latest = versions.max_by { |v| v[:version] }
    json_file = latest[:file]
    filename = File.basename(json_file)

    puts "📄 Processing #{filename} (v#{latest[:version]})"

    begin
      data = JSON.parse(File.read(json_file))

      # Extract metadata
      metadata = data['metadata'] || {}
      constants = data['constants'] || {}
      roommates = data['roommates'] || {}

      # CRITICAL: Config month from JSON constants, not filename!
      # Filename = rent month, constants.month = config month
      # See CLAUDE.md "Rent Calculation Timing Quirks" for explanation
      config_month = constants['month']
      config_year = constants['year']

      unless config_month && config_year
        puts "   ⚠️  No config period found in constants, using filename"
        # Rent month in filename → config month is month - 1
        config_month = rent_month - 1
        config_year = rent_year
        if config_month < 1
          config_month = 12
          config_year -= 1
        end
      end

      # Period for RentLedger is RENT MONTH (when payment is due)
      # NOT config month (when calculation was done)
      ledger_period = Time.utc(rent_year, rent_month, 1)

      calculation_date = metadata['calculation_date'] ? Time.parse(metadata['calculation_date']) : nil
      calculation_title = metadata['title'] || "Rent #{rent_year}-#{sprintf('%02d', rent_month)}"

      # Base monthly rent per person (kallhyra split equally)
      base_rent_total = constants['kallhyra'] || 0
      roommate_count = roommates.size
      base_monthly_rent = roommate_count > 0 ? base_rent_total / roommate_count.to_f : 0

      puts "   Config period: #{config_year}-#{sprintf('%02d', config_month)}"
      puts "   Ledger period: #{ledger_period.strftime('%Y-%m')}"
      puts "   Title: #{calculation_title}"
      puts "   Roommates: #{roommate_count}"

      # Process final_results first (create RentLedger entries if missing)
      final_results = data['final_results'] || {}

      final_results.each do |tenant_name, amount|
        tenant_id = tenant_map[tenant_name]

        unless tenant_id
          puts "   ⚠️  Tenant '#{tenant_name}' not found in database, skipping"
          stats[:skipped_no_tenant] += 1
          next
        end

        # Check if ledger entry exists
        ledger_entry = db.class.rent_ledger
          .where(tenantId: tenant_id, period: ledger_period)
          .first

        # Extract roommate config for audit data
        roommate_config = roommates[tenant_name] || {}
        days_stayed = roommate_config['days']
        room_adjustment = roommate_config['room_adjustment'] || 0

        if ledger_entry
          # Update existing entry with audit trail
          db.class.rent_ledger
            .where(id: ledger_entry[:id])
            .update(
              daysStayed: days_stayed,
              roomAdjustment: room_adjustment,
              baseMonthlyRent: base_monthly_rent,
              calculationTitle: calculation_title,
              calculationDate: calculation_date
            )
          puts "   ✅ Updated #{tenant_name}: #{amount} kr, #{days_stayed} days, adj #{room_adjustment} kr"
          stats[:ledger_entries_updated] += 1
        else
          # Create new entry with audit trail
          db.class.rent_ledger.insert(
            id: Cuid.generate,
            tenantId: tenant_id,
            period: ledger_period,
            amountDue: amount,
            amountPaid: amount, # Assume historical entries are paid
            paymentDate: calculation_date,
            createdAt: calculation_date || Time.now.utc,
            daysStayed: days_stayed,
            roomAdjustment: room_adjustment,
            baseMonthlyRent: base_monthly_rent,
            calculationTitle: calculation_title,
            calculationDate: calculation_date
          )
          puts "   ✅ Created #{tenant_name}: #{amount} kr, #{days_stayed} days, adj #{room_adjustment} kr"
          stats[:ledger_entries_created] += 1
        end
      end

      stats[:json_files_processed] += 1
      puts

    rescue => e
      puts "   ❌ Error processing #{filename}: #{e.message}"
      puts "   #{e.backtrace.first}"
      puts
    end
  end

  puts "=" * 80
  puts "✅ MIGRATION COMPLETE"
  puts "=" * 80
  puts
  puts "📊 Statistics:"
  puts "   JSON files processed:      #{stats[:json_files_processed]}"
  puts "   Ledger entries updated:    #{stats[:ledger_entries_updated]}"
  puts "   Skipped (no ledger):       #{stats[:skipped_no_ledger]}"
  puts "   Skipped (tenant not found): #{stats[:skipped_no_tenant]}"
  puts

  # Verification queries
  puts "🔍 Verification:"
  puts

  # Count ledger entries with audit data
  with_audit = db.class.rent_ledger.exclude(daysStayed: nil).count
  total_ledger = db.class.rent_ledger.count
  puts "   RentLedger entries with audit data: #{with_audit} / #{total_ledger}"

  if with_audit < total_ledger
    puts "   ⚠️  #{total_ledger - with_audit} entries still missing audit data"
    puts "      (This is OK if they're from periods without JSON files)"
  end

  puts
  puts "📌 Next Steps:"
  puts "   1. Run verification queries (see below)"
  puts "   2. Spot check critical records"
  puts "   3. If all verified, can delete JSON files"
  puts "   4. Update rent.rb to save to database instead of JSON"
  puts
  puts "=" * 80
  puts "VERIFICATION QUERIES"
  puts "=" * 80
  puts
  puts "# Check Adam's half-month rent (March 2025):"
  puts "ruby -e \"require 'dotenv/load'; require_relative 'lib/rent_db'; \\"
  puts "  db = RentDb.instance; \\"
  puts "  adam = db.class.tenants.where(name: 'Adam').first; \\"
  puts "  ledger = db.class.rent_ledger.where(tenantId: adam[:id], period: Time.utc(2025, 3, 1)).first; \\"
  puts "  puts 'Adam March 2025: ' + ledger[:daysStayed].to_s + ' days, ' + ledger[:amountDue].to_s + ' kr'\""
  puts
  puts "# List all entries with partial months:"
  puts "ruby -e \"require 'dotenv/load'; require_relative 'lib/rent_db'; \\"
  puts "  RentDb.instance.class.rent_ledger.where { daysStayed < 31 }.each { |r| \\"
  puts "    tenant = RentDb.instance.class.tenants.where(id: r[:tenantId]).first; \\"
  puts "    puts tenant[:name] + ': ' + r[:daysStayed].to_s + ' days in ' + r[:period].strftime('%Y-%m') }\""
  puts
  puts "# Show all unique calculation titles:"
  puts "ruby -e \"require 'dotenv/load'; require_relative 'lib/rent_db'; \\"
  puts "  RentDb.instance.class.rent_ledger.select(:calculationTitle).distinct.each { |r| puts r[:calculationTitle] }\""
  puts

rescue => e
  puts "❌ MIGRATION FAILED: #{e.message}"
  puts e.backtrace.first(10)
  puts
  puts "💾 Database can be restored from: #{latest_backup}"
  puts "   psql $DATABASE_URL < #{latest_backup}"
  exit 1
end

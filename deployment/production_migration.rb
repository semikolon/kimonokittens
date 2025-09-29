#!/usr/bin/env ruby
# Production Database Migration Script
# Usage: ruby deployment/production_migration.rb

require 'dotenv/load'
require_relative '../lib/rent_db'
require 'json'
require 'securerandom'

puts "=== KIMONOKITTENS PRODUCTION DATABASE MIGRATION ==="
puts "Date: #{Time.now.strftime('%Y-%m-%d %H:%M:%S')}"

# Load export data
export_file = 'deployment/production_database_20250928.json'
unless File.exist?(export_file)
  puts "❌ Export file not found: #{export_file}"
  exit 1
end

data = JSON.parse(File.read(export_file))
db = RentDb.instance

puts "📦 Loading data from: #{data['export_date']}"
puts "🗄️  Database version: #{data['database_version']}"

begin
  # Clear existing data (production deployment)
  puts "\n🧹 Clearing existing data..."
  db.class.rent_ledger.delete
  db.class.rent_configs.delete
  db.class.tenants.delete

  # Import Tenants
  puts "👥 Importing tenants..."
  data['tenants'].each do |tenant|
    db.class.tenants.insert(
      id: tenant['id'],
      name: tenant['name'],
      email: tenant['email'],
      facebookId: tenant['facebookId'],
      avatarUrl: tenant['avatarUrl'],
      roomAdjustment: tenant['roomAdjustment'],
      startDate: tenant['startDate'] ? Time.parse(tenant['startDate']) : nil,
      departureDate: tenant['departureDate'] ? Time.parse(tenant['departureDate']) : nil,
      createdAt: tenant['createdAt'] ? Time.parse(tenant['createdAt']) : Time.now.utc,
      updatedAt: tenant['updatedAt'] ? Time.parse(tenant['updatedAt']) : Time.now.utc
    )
  end

  # Import RentConfig
  puts "⚙️  Importing rent configurations..."
  data['rent_configs'].each do |config|
    db.class.rent_configs.insert(
      id: SecureRandom.uuid,
      key: config['key'],
      value: config['value'],
      period: Time.parse(config['period']),
      createdAt: Time.parse(config['created_at']),
      updatedAt: Time.parse(config['updated_at'])
    )
  end

  # Create tenant name to ID mapping for historical data
  puts "📋 Creating tenant mapping..."
  tenant_mapping = {}
  data['tenants'].each do |tenant|
    tenant_mapping[tenant['name']] = tenant['id']
  end

  # Import Historical RentLedger data from JSON files
  puts "📊 Importing historical rent ledger from JSON files..."
  history_dir = 'data/rent_history'
  historical_count = 0

  if Dir.exist?(history_dir)
    Dir.glob("#{history_dir}/*.json").sort.each do |json_file|
      puts "   Processing: #{File.basename(json_file)}"

      begin
        historical_data = JSON.parse(File.read(json_file))

        # Extract period information (using corrected CONFIG PERIOD MONTH semantics)
        year = historical_data['constants']['year']
        config_month = historical_data['constants']['month']

        # Skip files without proper year/month information
        if year.nil? || config_month.nil?
          puts "   ⚠️  Warning: Missing year/month in #{File.basename(json_file)}, skipping"
          next
        end

        # Convert config period month to rent period month
        # Config month 7 → August rent (month 8)
        # Config month 10 → November rent (month 11)
        rent_month = config_month + 1
        rent_year = year

        # Handle year rollover (December config → January rent)
        if rent_month > 12
          rent_month = 1
          rent_year += 1
        end

        # Use calculation_date as payment_date
        calculation_date = Time.parse(historical_data['metadata']['calculation_date'])

        # Process each tenant's final result
        historical_data['final_results'].each do |tenant_name, amount|
          tenant_id = tenant_mapping[tenant_name]

          if tenant_id
            db.class.rent_ledger.insert(
              id: SecureRandom.uuid,
              tenantId: tenant_id,
              period: Time.new(rent_year, rent_month, 1),
              amountDue: amount,
              amountPaid: amount, # Assume fully paid for historical data
              paymentDate: calculation_date,
              createdAt: calculation_date,
              updatedAt: calculation_date
            )
            historical_count += 1
          else
            puts "   ⚠️  Warning: Could not find tenant ID for '#{tenant_name}' in #{File.basename(json_file)}"
          end
        end

      rescue => e
        puts "   ❌ Error processing #{File.basename(json_file)}: #{e.message}"
      end
    end
  else
    puts "   ⚠️  Historical data directory not found: #{history_dir}"
  end

  puts "\n✅ MIGRATION COMPLETE"
  puts "📊 Imported:"
  puts "   - Tenants: #{data['tenants'].length}"
  puts "   - RentConfig: #{data['rent_configs'].length}"
  puts "   - RentLedger: #{historical_count} (from historical JSON files)"

rescue => e
  puts "❌ Migration failed: #{e.message}"
  puts e.backtrace.first(3)
  exit 1
end
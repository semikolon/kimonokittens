#!/usr/bin/env ruby
require 'dotenv/load'
require_relative '../lib/rent_db'
require 'json'

puts "=== EXPORTING PRODUCTION DATABASE STATE ==="
puts "Date: #{Time.now.strftime('%Y-%m-%d %H:%M:%S')}"

db = RentDb.instance

# Export RentConfig data
rent_configs = db.class.rent_configs.all.map do |config|
  {
    key: config[:key],
    value: config[:value],
    period: config[:period].to_s,
    created_at: config[:createdAt].to_s,
    updated_at: config[:updatedAt].to_s
  }
end

# Export Tenant data
tenants = db.get_tenants

# Export structure
export_data = {
  export_date: Time.now.iso8601,
  database_version: "kimonokittens_production_v1",
  rent_configs: rent_configs,
  tenants: tenants,
  rent_ledger: [] # Empty for now
}

# Write to JSON file
File.write('deployment/production_database_20250928.json', JSON.pretty_generate(export_data))

puts "✅ Database exported to: deployment/production_database_20250928.json"
puts "📊 Exported:"
puts "   - RentConfig records: #{rent_configs.length}"
puts "   - Tenant records: #{tenants.length}"
puts "   - RentLedger records: 0"
#!/usr/bin/env ruby
require 'json'
require 'dotenv/load'
require_relative '../lib/repositories/tenant_repository'
require_relative '../lib/models/tenant'

# Import Sanna and Frida from export file to production database
export_file = File.expand_path('../deployment/contract_tenants_export.json', __dir__)
data = JSON.parse(File.read(export_file), symbolize_names: true)

repo = TenantRepository.new

puts "Importing #{data[:tenants].length} tenants exported at #{data[:exported_at]}..."

data[:tenants].each do |tenant_data|
  # Check if tenant already exists
  existing = repo.find_by_id(tenant_data[:id])

  if existing
    puts "⚠️  Tenant already exists: #{tenant_data[:name]} (#{tenant_data[:id]})"
    puts "   Skipping import. Use update script if changes needed."
    next
  end

  # Create tenant
  tenant = Tenant.new(
    id: tenant_data[:id],
    name: tenant_data[:name],
    email: tenant_data[:email],
    personnummer: tenant_data[:personnummer],
    phone: tenant_data[:phone],
    deposit: tenant_data[:deposit],
    furnishing_deposit: tenant_data[:furnishing_deposit],
    start_date: tenant_data[:start_date] ? Date.parse(tenant_data[:start_date]) : nil,
    room_adjustment: tenant_data[:room_adjustment]
  )

  saved = repo.save(tenant)

  if saved
    puts "✅ Imported: #{tenant.name}"
    puts "   ID: #{tenant.id}"
    puts "   Email: #{tenant.email}"
    puts "   Phone: #{tenant.phone}"
    puts "   Personnummer: #{tenant.personnummer}"
    puts "   Deposit: #{tenant.deposit} kr"
    puts "   Furnishing: #{tenant.furnishing_deposit} kr"
    puts "   Start: #{tenant.start_date}"
  else
    puts "❌ Failed to import: #{tenant_data[:name]}"
  end
end

puts "\n✅ Import complete!"

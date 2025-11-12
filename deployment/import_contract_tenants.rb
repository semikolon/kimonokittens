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
    # Update existing tenant
    puts "📝 Updating existing tenant: #{tenant_data[:name]}"
    puts "   Before:"
    puts "     Phone: #{existing.phone || '[EMPTY]'}"
    puts "     Personnummer: #{existing.personnummer || '[EMPTY]'}"
    puts "     Deposits: #{existing.deposit || 0} + #{existing.furnishing_deposit || 0} kr"

    # Update fields
    existing.phone = tenant_data[:phone]
    existing.personnummer = tenant_data[:personnummer]
    existing.deposit = tenant_data[:deposit]
    existing.furnishing_deposit = tenant_data[:furnishing_deposit]

    begin
      updated = repo.update(existing)
      puts "   After:"
      puts "     Phone: #{updated.phone}"
      puts "     Personnummer: #{updated.personnummer}"
      puts "     Deposits: #{updated.deposit} + #{updated.furnishing_deposit} kr"
      puts "   ✅ Updated successfully"
    rescue => e
      puts "   ❌ Update failed: #{e.message}"
    end
  else
    # Create new tenant
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

    begin
      created = repo.create(tenant)
      puts "✅ Created: #{created.name}"
      puts "   ID: #{created.id}"
      puts "   Email: #{created.email}"
      puts "   Phone: #{created.phone}"
      puts "   Personnummer: #{created.personnummer}"
      puts "   Deposit: #{created.deposit} kr"
      puts "   Furnishing: #{created.furnishing_deposit} kr"
      puts "   Start: #{created.start_date}"
    rescue => e
      puts "❌ Failed to create: #{tenant_data[:name]}"
      puts "   Error: #{e.message}"
    end
  end
end

puts "\n✅ Import complete!"

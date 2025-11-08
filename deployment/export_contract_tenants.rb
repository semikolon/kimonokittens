#!/usr/bin/env ruby
require 'json'
require 'dotenv/load'
require_relative '../lib/repositories/tenant_repository'

# Export Sanna and Frida records to JSON for production import
# IDs verified from database query: psql -d kimonokittens -c "SELECT id, name FROM \"Tenant\""
repo = TenantRepository.new

sanna = repo.find_by_id('cmhqe9enc0000wopipuxgc3kw')  # Sanna Juni Benemar
frida = repo.find_by_id('cmhqlmryv00004ipixj2zdkhj')  # Frida Johansson

raise "Sanna record not found!" unless sanna
raise "Frida record not found!" unless frida

export_data = {
  exported_at: Time.now.iso8601,
  tenants: [
    {
      id: sanna.id,
      name: sanna.name,
      email: sanna.email,
      personnummer: sanna.personnummer,
      phone: sanna.phone,
      deposit: sanna.deposit.to_f,
      furnishing_deposit: sanna.furnishing_deposit.to_f,
      start_date: sanna.start_date&.iso8601,
      status: 'active',
      room_adjustment: sanna.room_adjustment&.to_f
    },
    {
      id: frida.id,
      name: frida.name,
      email: frida.email,
      personnummer: frida.personnummer,
      phone: frida.phone,
      deposit: frida.deposit.to_f,
      furnishing_deposit: frida.furnishing_deposit.to_f,
      start_date: frida.start_date&.iso8601,
      status: 'pending',
      room_adjustment: frida.room_adjustment&.to_f
    }
  ]
}

output_path = File.expand_path('../deployment/contract_tenants_export.json', __dir__)
File.write(output_path, JSON.pretty_generate(export_data))

puts "✅ Exported 2 tenant records to: #{output_path}"
puts "\nSanna: #{sanna.name} (#{sanna.personnummer})"
puts "  Deposit: #{sanna.deposit} kr, Furnishing: #{sanna.furnishing_deposit} kr"
puts "  Start: #{sanna.start_date}"
puts "\nFrida: #{frida.name} (#{frida.personnummer})"
puts "  Deposit: #{frida.deposit} kr, Furnishing: #{frida.furnishing_deposit} kr"
puts "  Start: #{frida.start_date}"

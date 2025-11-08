#!/usr/bin/env ruby
require_relative '../lib/contract_generator_dashboard_style'
require 'date'

# Sanna's contract data
sanna_data = {
  name: 'Sanna Juni Benemar',
  personnummer: '8706220020',
  email: 'sanna_benemar@hotmail.com',
  phone: '070 289 44 37',
  move_in_date: Date.new(2025, 11, 1)
}

output_path = File.join(
  File.dirname(__FILE__),
  '../contracts/generated/Sanna_Benemar_Hyresavtal_Dashboard_Style.pdf'
)

puts "Generating Sanna's contract (DASHBOARD STYLE)..."
puts "Output: #{output_path}"

generator = ContractGeneratorDashboardStyle.new
result = generator.generate(tenant: sanna_data, output_path: output_path)

puts "✅ Dashboard-style contract generated successfully!"
puts "📄 File: #{result}"
puts "📊 Size: #{File.size(result)} bytes"

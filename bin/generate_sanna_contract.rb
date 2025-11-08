#!/usr/bin/env ruby
require_relative '../lib/contract_generator'
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
  '../contracts/generated/Sanna_Benemar_Hyresavtal_2025-11-01.pdf'
)

puts "Generating Sanna's contract..."
puts "Output: #{output_path}"

generator = ContractGenerator.new
result = generator.generate(tenant: sanna_data, output_path: output_path)

puts "✅ Contract generated successfully!"
puts "📄 File: #{result}"
puts "📊 Size: #{File.size(result)} bytes"

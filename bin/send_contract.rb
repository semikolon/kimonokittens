#!/usr/bin/env ruby
require 'dotenv/load'
require 'optparse'
require 'date'
require_relative '../lib/contract_signer'

# CLI script for sending contracts for e-signing via Zigned
#
# Usage:
#   # Send Sanna's contract in test mode
#   ./bin/send_contract.rb --name "Sanna Juni Benemar" \
#                          --personnummer 8706220020 \
#                          --email sanna_benemar@hotmail.com \
#                          --phone "070 289 44 37" \
#                          --move-in 2025-11-01 \
#                          --test
#
#   # Send in production mode (real BankID signatures)
#   ./bin/send_contract.rb --name "Frida Johansson" \
#                          --personnummer 890622-3386 \
#                          --email frida@example.com \
#                          --phone "070 123 45 67" \
#                          --move-in 2025-12-03
#
#   # Check status of existing case
#   ./bin/send_contract.rb --status zcs_abc123
#
#   # Download signed PDF
#   ./bin/send_contract.rb --download zcs_abc123 --tenant-name "Sanna Juni Benemar"

options = {
  test_mode: false,
  send_emails: true
}

OptionParser.new do |opts|
  opts.banner = "Usage: send_contract.rb [options]"
  opts.separator ""
  opts.separator "Send contract for e-signing:"

  opts.on("--name NAME", "Tenant full name (required)") do |v|
    options[:name] = v
  end

  opts.on("--personnummer PERSONNUMMER", "Swedish personnummer (YYMMDD-XXXX)") do |v|
    options[:personnummer] = v
  end

  opts.on("--email EMAIL", "Tenant email address") do |v|
    options[:email] = v
  end

  opts.on("--phone PHONE", "Tenant phone number") do |v|
    options[:phone] = v
  end

  opts.on("--move-in DATE", "Move-in date (YYYY-MM-DD)") do |v|
    options[:move_in_date] = Date.parse(v)
  end

  opts.on("--test", "Use test mode (free, no real signatures)") do
    options[:test_mode] = true
  end

  opts.on("--no-emails", "Don't send email invitations (you share links manually)") do
    options[:send_emails] = false
  end

  opts.separator ""
  opts.separator "Check signing status:"

  opts.on("--status CASE_ID", "Check status of signing case") do |v|
    options[:status_case_id] = v
  end

  opts.separator ""
  opts.separator "Download signed PDF:"

  opts.on("--download CASE_ID", "Download signed PDF for completed case") do |v|
    options[:download_case_id] = v
  end

  opts.on("--tenant-name NAME", "Tenant name (for filename when downloading)") do |v|
    options[:tenant_name] = v
  end

  opts.separator ""
  opts.separator "Cancel signing case:"

  opts.on("--cancel CASE_ID", "Cancel pending signing case") do |v|
    options[:cancel_case_id] = v
  end

  opts.separator ""
  opts.separator "Other options:"

  opts.on("-h", "--help", "Show this help message") do
    puts opts
    exit
  end
end.parse!

# Initialize ContractSigner
begin
  signer = ContractSigner.new(test_mode: options[:test_mode])
rescue => e
  puts "❌ Error initializing: #{e.message}"
  puts "\nMake sure ZIGNED_API_KEY is set in .env file"
  exit 1
end

# Handle different operations
if options[:status_case_id]
  # Check status
  puts "📊 Checking status for case: #{options[:status_case_id]}\n\n"

  begin
    status = signer.check_status(options[:status_case_id])

    puts "Title: #{status[:title]}"
    puts "Status: #{status[:status]}"
    puts "Created: #{status[:created_at]}"
    puts "Expires: #{status[:expires_at]}"
    puts "Signed at: #{status[:signed_at] || 'Not yet signed'}"
    puts "\nSigners:"

    status[:signers].each do |signer_info|
      status_icon = signer_info[:signed] ? '✅' : '⏳'
      puts "  #{status_icon} #{signer_info[:name]} (#{signer_info[:personnummer]})"
      puts "     Signed: #{signer_info[:signed_at] || 'Pending'}"
    end

    if status[:status] == 'completed'
      puts "\n✅ All parties have signed! Use --download to get the signed PDF."
    elsif status[:status] == 'expired'
      puts "\n⚠️  This case has expired."
    elsif status[:status] == 'cancelled'
      puts "\n⚠️  This case was cancelled."
    else
      puts "\n⏳ Waiting for signatures..."
    end

  rescue => e
    puts "❌ Error: #{e.message}"
    exit 1
  end

elsif options[:download_case_id]
  # Download signed PDF
  unless options[:tenant_name]
    puts "❌ Error: --tenant-name required when downloading"
    exit 1
  end

  puts "📥 Downloading signed PDF for case: #{options[:download_case_id]}\n\n"

  begin
    signed_path = signer.download_signed_contract(
      options[:download_case_id],
      options[:tenant_name]
    )

    puts "\n✅ Success!"
    puts "Signed PDF: #{signed_path}"

  rescue => e
    puts "❌ Error: #{e.message}"
    exit 1
  end

elsif options[:cancel_case_id]
  # Cancel case
  puts "🚫 Cancelling case: #{options[:cancel_case_id]}\n\n"

  begin
    if signer.cancel_contract(options[:cancel_case_id])
      puts "✅ Case cancelled successfully"
    else
      puts "❌ Failed to cancel case"
      exit 1
    end

  rescue => e
    puts "❌ Error: #{e.message}"
    exit 1
  end

else
  # Send new contract
  required_fields = [:name, :personnummer, :email, :phone, :move_in_date]
  missing_fields = required_fields.reject { |field| options[field] }

  unless missing_fields.empty?
    puts "❌ Error: Missing required fields: #{missing_fields.join(', ')}"
    puts "\nRun with --help for usage information"
    exit 1
  end

  # Display summary
  puts "📋 Contract Summary:"
  puts "  Tenant: #{options[:name]}"
  puts "  Personnummer: #{options[:personnummer]}"
  puts "  Email: #{options[:email]}"
  puts "  Phone: #{options[:phone]}"
  puts "  Move-in: #{options[:move_in_date]}"
  puts "  Mode: #{options[:test_mode] ? 'TEST (free, no real signatures)' : 'PRODUCTION (real BankID)'}"
  puts "  Emails: #{options[:send_emails] ? 'Enabled' : 'Disabled'}"
  puts ""

  # Confirm if production mode
  unless options[:test_mode]
    print "⚠️  This will send a REAL contract for BankID signing. Continue? (yes/no): "
    response = gets.chomp.downcase
    unless response == 'yes'
      puts "Cancelled."
      exit 0
    end
  end

  # Send contract
  tenant_data = {
    name: options[:name],
    personnummer: options[:personnummer],
    email: options[:email],
    phone: options[:phone],
    move_in_date: options[:move_in_date]
  }

  begin
    puts "\n🚀 Sending contract...\n\n"

    result = signer.sign_contract(
      tenant: tenant_data,
      send_emails: options[:send_emails]
    )

    puts "\n✅ Success!"
    puts "\nCase ID: #{result[:case_id]}"
    puts "PDF: #{result[:pdf_path]}"
    puts "Metadata: #{result[:metadata_path]}"
    puts "Expires: #{result[:expires_at]}"
    puts "\nUse the following command to check status:"
    puts "  ./bin/send_contract.rb --status #{result[:case_id]}"

  rescue => e
    puts "\n❌ Error: #{e.message}"
    puts e.backtrace.join("\n") if ENV['DEBUG']
    exit 1
  end
end

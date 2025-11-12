#!/usr/bin/env ruby
# frozen_string_literal: true

# Utility script to remove older, incomplete duplicate contracts for tenants
# who already have a fully completed contract. Designed for the Frida/Sanna
# cleanup on production. Run with `bundle exec ruby scripts/cleanup_signed_contract_duplicates.rb`
# and supply `--apply` once you have reviewed the dry-run output.

require 'optparse'
require 'time'
require 'dotenv/load'
require_relative '../lib/persistence'
require_relative '../lib/rent_db'

TARGET_TENANTS = [
  'Sanna Juni Benemar',
  'Frida Johansson'
].freeze

options = {
  apply: false,
  tenant: nil
}

OptionParser.new do |opts|
  opts.banner = 'Usage: bundle exec ruby scripts/cleanup_signed_contract_duplicates.rb [options]'

  opts.on('--tenant NAME', 'Only process a single tenant (exact name match)') do |name|
    options[:tenant] = name
  end

  opts.on('--apply', 'Actually delete the matching contracts (default: dry run)') do
    options[:apply] = true
  end

  opts.on('-h', '--help', 'Show this help') do
    puts opts
    exit 0
  end
end.parse!

tenant_repo = Persistence.tenants
contract_repo = Persistence.signed_contracts

tenant_names = if options[:tenant]
  [options[:tenant]]
else
  TARGET_TENANTS
end

deleted_contracts = []
errors = []

tenant_names.each do |tenant_name|
  puts "\n=== #{tenant_name} ==="

  tenant = tenant_repo.find_by_name(tenant_name)
  unless tenant
    warning = "Tenant not found, skipping"
    puts "  ! #{warning}"
    errors << { tenant: tenant_name, error: warning }
    next
  end

  contracts = contract_repo.find_by_tenant_id(tenant.id)
  if contracts.empty?
    warning = "No contracts found for tenant"
    puts "  ! #{warning}"
    errors << { tenant: tenant_name, error: warning }
    next
  end

  completed = contracts.select(&:completed?)
  if completed.empty?
    warning = "Tenant has no completed contract; aborting to avoid deleting needed records"
    puts "  ! #{warning}"
    errors << { tenant: tenant_name, error: warning }
    next
  end

  anchor_contract = completed.max_by(&:created_at)
  anchor_time = anchor_contract&.created_at
  unless anchor_time
    warning = "Completed contract missing created_at timestamp"
    puts "  ! #{warning}"
    errors << { tenant: tenant_name, error: warning }
    next
  end

  candidates = contracts.select do |contract|
    next false if contract.completed?
    next false unless contract.created_at
    contract.created_at < anchor_time
  end

  if candidates.empty?
    puts '  No stale incomplete contracts detected; nothing to do.'
    next
  end

  puts "  Found #{contracts.size} total contracts (#{completed.size} completed)."
  puts "  ➤ Keeping completed contract #{anchor_contract.id} (created #{anchor_time})."
  puts "  ➤ Stale/incomplete candidates:"

  candidates.sort_by(&:created_at).each do |contract|
    puts format('    - %s | %s | created %s | case_id=%s',
                contract.id,
                contract.status,
                contract.created_at,
                contract.case_id)
  end

  if options[:apply]
    RentDb.db.transaction do
      candidates.each do |contract|
        contract_repo.delete(contract.id)
        deleted_contracts << { tenant: tenant_name, id: contract.id, status: contract.status }
      end
    end
    puts "  ✅ Deleted #{candidates.size} stale contract(s)."
  else
    puts '  (dry run) Pass --apply to delete the above contracts.'
  end
end

puts "\nSummary:"
if deleted_contracts.empty?
  puts '  No contracts deleted (dry run or no matches).'
else
  deleted_contracts.each do |entry|
    puts format('  - %s: removed %s (%s)', entry[:tenant], entry[:id], entry[:status])
  end
end

unless errors.empty?
  puts "\nWarnings:"
  errors.each do |error|
    puts format('  - %s: %s', error[:tenant], error[:error])
  end
end

if !options[:apply]
  puts "\nDry run complete. Re-run with --apply once you have verified the candidates."
end

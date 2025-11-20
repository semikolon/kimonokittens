#!/usr/bin/env ruby
require 'dotenv/load'
require 'date'
require 'json'
require_relative '../lib/persistence'

# Extract historical bills from DEVELOPMENT database for test fixtures
# This script queries the development database to create a snapshot of
# historical electricity bills for use in accuracy validation tests.

def fetch_bills_from_database
  Persistence.electricity_bills.all.map do |bill|
    {
      provider: bill.provider,
      bill_date: bill.bill_date,
      amount: bill.amount,
      bill_period: bill.bill_period,
      consumption_month: Date.new(
        bill.bill_period.year,
        bill.bill_period.month == 1 ? 12 : bill.bill_period.month - 1,
        1
      )
    }
  end
end

def aggregate_by_period(bills)
  periods = {}

  bills.each do |bill|
    period_key = bill[:bill_period].strftime('%Y-%m')

    periods[period_key] ||= {
      bill_period: bill[:bill_period].strftime('%Y-%m-%d'),
      consumption_month: bill[:consumption_month].strftime('%Y-%m-%d'),
      vattenfall: 0,
      fortum: 0,
      total: 0,
      config_year: bill[:bill_period].year,
      config_month: bill[:bill_period].month
    }

    case bill[:provider].downcase
    when 'vattenfall'
      periods[period_key][:vattenfall] += bill[:amount].to_i
    when 'fortum'
      periods[period_key][:fortum] += bill[:amount].to_i
    end

    periods[period_key][:total] += bill[:amount].to_i
  end

  periods.values.sort_by { |p| p[:bill_period] }
end

# Generate fixture from development database
bills = fetch_bills_from_database
aggregated = aggregate_by_period(bills)

# Output as JSON for use in specs
puts JSON.pretty_generate(aggregated)

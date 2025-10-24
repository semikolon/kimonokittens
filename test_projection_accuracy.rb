#!/usr/bin/env ruby
# Validate smart projection accuracy against actual historical bills

require 'dotenv/load'
require_relative 'lib/electricity_projector'
require_relative 'lib/persistence'

puts "=" * 80
puts "PROJECTION ACCURACY VALIDATION"
puts "=" * 80
puts ""

# Get all historical bills grouped by period
bills_by_period = Persistence.electricity_bills
  .all
  .group_by { |bill| bill.bill_period.strftime('%Y-%m') }
  .select { |period, bills| bills.sum(&:amount) > 0 }
  .sort_by { |period, _| period }

puts "Found #{bills_by_period.size} periods with bills"
puts ""

projector = ElectricityProjector.new

results = []

bills_by_period.each do |period_str, bills|
  year, month = period_str.split('-').map(&:to_i)
  actual_total = bills.sum(&:amount).round

  puts "-" * 80
  puts "Period: #{period_str} (#{actual_total} kr actual)"

  begin
    # Directly call smart projection, bypassing actual bill check
    projected = projector.send(
      :project_from_consumption_and_pricing,
      year,
      month
    )

    difference = projected - actual_total
    percentage = ((difference.abs / actual_total.to_f) * 100).round(1)

    results << {
      period: period_str,
      actual: actual_total,
      projected: projected,
      difference: difference,
      percentage: percentage
    }

    status = difference.abs <= 50 ? "✅" : "⚠️"
    puts "  Actual:    #{actual_total} kr"
    puts "  Projected: #{projected} kr"
    puts "  #{status} Difference: #{difference > 0 ? '+' : ''}#{difference} kr (#{percentage}%)"

  rescue => e
    puts "  ❌ Projection failed: #{e.message}"
    results << {
      period: period_str,
      actual: actual_total,
      projected: nil,
      difference: nil,
      percentage: nil,
      error: e.message
    }
  end

  puts ""
end

puts "=" * 80
puts "SUMMARY"
puts "=" * 80

successful = results.select { |r| r[:projected] }
failed = results.select { |r| r[:error] }

if successful.any?
  avg_difference = successful.sum { |r| r[:difference].abs } / successful.size.to_f
  avg_percentage = successful.sum { |r| r[:percentage] } / successful.size.to_f

  puts "Successful projections: #{successful.size}/#{results.size}"
  puts "Average absolute difference: #{avg_difference.round} kr"
  puts "Average percentage error: #{avg_percentage.round(1)}%"
  puts ""

  within_50 = successful.count { |r| r[:difference].abs <= 50 }
  within_100 = successful.count { |r| r[:difference].abs <= 100 }
  within_200 = successful.count { |r| r[:difference].abs <= 200 }

  puts "Accuracy bands:"
  puts "  Within ±50 kr:  #{within_50}/#{successful.size} (#{(within_50 * 100.0 / successful.size).round}%)"
  puts "  Within ±100 kr: #{within_100}/#{successful.size} (#{(within_100 * 100.0 / successful.size).round}%)"
  puts "  Within ±200 kr: #{within_200}/#{successful.size} (#{(within_200 * 100.0 / successful.size).round}%)"
end

if failed.any?
  puts ""
  puts "Failed projections: #{failed.size}/#{results.size}"
  puts "Reasons:"
  failed.group_by { |r| r[:error] }.each do |error, items|
    puts "  #{items.size}× #{error}"
  end
end

puts ""
puts "=" * 80

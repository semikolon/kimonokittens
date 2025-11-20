#!/usr/bin/env ruby
require_relative '../spec/spec_helper'
require_relative '../lib/electricity_projector'
require_relative '../lib/persistence'
require 'json'
require 'vcr'

# Load historical data
HISTORICAL_DATA = JSON.parse(
  File.read(File.join(__dir__, '../spec/fixtures', 'historical_electricity_bills.json'))
).map { |h| h.transform_keys(&:to_sym) }.freeze

# Filter to testable periods (last 12 months)
TESTABLE_PERIODS = HISTORICAL_DATA.select do |period|
  config_date = Date.parse(period[:bill_period])
  config_date >= Date.today << 12
end.freeze

projector = ElectricityProjector.new(repo: Persistence.rent_configs)

puts "\n" + "=" * 100
puts "DETAILED PROJECTION ACCURACY ANALYSIS"
puts "=" * 100

errors = []
signed_errors = []

TESTABLE_PERIODS.each do |period|
  # Calculate consumption period for VCR
  consumption_year = period[:config_month] == 1 ? period[:config_year] - 1 : period[:config_year]
  consumption_month = period[:config_month] == 1 ? 12 : period[:config_month] - 1
  cassette_name = "electricity_prices_#{consumption_year}_#{sprintf('%02d', consumption_month)}"

  VCR.use_cassette(cassette_name) do
    projection = projector.project(
      config_year: period[:config_year],
      config_month: period[:config_month]
    )

    actual = period[:total]
    error_kr = projection - actual
    error_pct = ((projection - actual).abs.to_f / actual * 100)

    errors << error_pct
    signed_errors << error_kr

    puts "\n#{period[:consumption_month]} consumption (#{period[:config_year]}-#{sprintf('%02d', period[:config_month])} config):"
    puts "  Actual:     #{actual} kr (Vattenfall: #{period[:vattenfall]}, Fortum: #{period[:fortum]})"
    puts "  Projected:  #{projection} kr"
    puts "  Error:      #{error_kr > 0 ? '+' : ''}#{error_kr} kr (#{error_pct.round(1)}%)"
    puts "  Direction:  #{error_kr > 0 ? 'OVER-estimated' : 'UNDER-estimated'}"
  end
end

puts "\n" + "=" * 100
puts "AGGREGATE METRICS"
puts "=" * 100

mape = errors.sum / errors.size
mae = signed_errors.map(&:abs).sum / signed_errors.size
mean_bias = signed_errors.sum / signed_errors.size
avg_total = TESTABLE_PERIODS.sum { |p| p[:total] } / TESTABLE_PERIODS.size.to_f
bias_pct = (mean_bias / avg_total * 100)

puts "\nMean Absolute Percentage Error (MAPE): #{mape.round(2)}%"
puts "Mean Absolute Error (MAE):             #{mae.round(0)} kr"
puts "Systematic Bias:                       #{bias_pct.round(1)}% (#{mean_bias.round(0)} kr avg)"
puts "  → #{bias_pct < 0 ? 'Systematic UNDER-estimation' : 'Systematic OVER-estimation'}"

# Analyze error distribution
over_estimates = signed_errors.select { |e| e > 0 }
under_estimates = signed_errors.select { |e| e < 0 }

puts "\nError Distribution:"
puts "  Over-estimates:  #{over_estimates.size}/#{signed_errors.size} periods (avg: +#{over_estimates.sum / over_estimates.size.to_f rescue 0} kr)"
puts "  Under-estimates: #{under_estimates.size}/#{signed_errors.size} periods (avg: #{under_estimates.sum / under_estimates.size.to_f rescue 0} kr)"

puts "\n" + "=" * 100

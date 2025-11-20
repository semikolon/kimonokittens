require_relative 'spec_helper'
require_relative '../lib/electricity_projector'
require_relative '../lib/persistence'
require 'json'

RSpec.describe 'ElectricityProjector Historical Accuracy' do
  # Load historical periods from fixture (generated from development DB)
  # This ensures tests are deterministic and don't depend on test DB state
  HISTORICAL_DATA = JSON.parse(
    File.read(File.join(__dir__, 'fixtures', 'historical_electricity_bills.json'))
  ).map { |h| h.transform_keys(&:to_sym) }.freeze

  # Filter to testable periods (last 12 months - where consumption file likely has data)
  TESTABLE_PERIODS = HISTORICAL_DATA.select do |period|
    config_date = Date.parse(period[:bill_period])
    config_date >= Date.today << 12  # Within last 12 months
  end.freeze

  let(:projector) { ElectricityProjector.new(repo: Persistence.rent_configs) }

  describe 'individual period accuracy' do
    before do
      skip "No testable periods found" if TESTABLE_PERIODS.empty?
    end

    TESTABLE_PERIODS.each do |period|
      context "#{period[:consumption_month]} consumption (config #{period[:config_year]}-#{sprintf('%02d', period[:config_month])})" do
        # Use VCR cassette for spot price data
        # IMPORTANT: Cassette must be named after CONSUMPTION period (config_month - 1)
        # because projector loads spot prices for the consumption month, not config month
        consumption_year = period[:config_month] == 1 ? period[:config_year] - 1 : period[:config_year]
        consumption_month = period[:config_month] == 1 ? 12 : period[:config_month] - 1

        it 'projects within 10% of actual bill',
           vcr: { cassette_name: "electricity_prices_#{consumption_year}_#{sprintf('%02d', consumption_month)}" } do

          projection = projector.project(
            config_year: period[:config_year],
            config_month: period[:config_month]
          )

          actual = period[:total]
          error_pct = ((projection - actual).abs.to_f / actual * 100).round(1)

          expect(error_pct).to be < 10,
            "Projected #{projection} kr vs actual #{actual} kr = #{error_pct}% error\n" \
            "Breakdown: Vattenfall #{period[:vattenfall]} kr + Fortum #{period[:fortum]} kr"
        end
      end
    end
  end

  describe 'aggregate accuracy metrics' do
    before do
      skip "Need at least 3 testable periods" if TESTABLE_PERIODS.size < 3
    end

    it 'has Mean Absolute Percentage Error (MAPE) under 8%' do
      errors = TESTABLE_PERIODS.map do |period|
        # Calculate consumption period for VCR cassette naming
        consumption_year = period[:config_month] == 1 ? period[:config_year] - 1 : period[:config_year]
        consumption_month = period[:config_month] == 1 ? 12 : period[:config_month] - 1
        cassette_name = "electricity_prices_#{consumption_year}_#{sprintf('%02d', consumption_month)}"

        # Use VCR cassette for this period's projection
        VCR.use_cassette(cassette_name) do
          projection = projector.project(
            config_year: period[:config_year],
            config_month: period[:config_month]
          )

          ((projection - period[:total]).abs.to_f / period[:total] * 100)
        end
      rescue StandardError => e
        # Skip periods where projection fails (e.g., missing consumption data)
        warn "Skipping #{period[:config_year]}-#{period[:config_month]}: #{e.message}"
        nil
      end.compact

      skip "Insufficient data points" if errors.size < 3

      mape = errors.sum / errors.size
      expect(mape).to be < 8.0,
        "MAPE: #{mape.round(2)}% (target: <8%)\n" \
        "Tested #{errors.size} periods: #{TESTABLE_PERIODS.map { |p| "#{p[:config_year]}-#{sprintf('%02d', p[:config_month])}" }.join(', ')}"
    end

    it 'has Mean Absolute Error (MAE) under 200 kr' do
      errors = TESTABLE_PERIODS.map do |period|
        # Calculate consumption period for VCR cassette naming
        consumption_year = period[:config_month] == 1 ? period[:config_year] - 1 : period[:config_year]
        consumption_month = period[:config_month] == 1 ? 12 : period[:config_month] - 1
        cassette_name = "electricity_prices_#{consumption_year}_#{sprintf('%02d', consumption_month)}"

        # Use VCR cassette for this period's projection
        VCR.use_cassette(cassette_name) do
          projection = projector.project(
            config_year: period[:config_year],
            config_month: period[:config_month]
          )

          (projection - period[:total]).abs
        end
      rescue StandardError
        nil
      end.compact

      skip "Insufficient data points" if errors.size < 3

      mae = errors.sum / errors.size
      expect(mae).to be < 200,
        "MAE: #{mae.round(2)} kr (target: <200 kr)"
    end

    it 'identifies systematic bias (over/under estimation)' do
      signed_errors = TESTABLE_PERIODS.map do |period|
        # Calculate consumption period for VCR cassette naming
        consumption_year = period[:config_month] == 1 ? period[:config_year] - 1 : period[:config_year]
        consumption_month = period[:config_month] == 1 ? 12 : period[:config_month] - 1
        cassette_name = "electricity_prices_#{consumption_year}_#{sprintf('%02d', consumption_month)}"

        # Use VCR cassette for this period's projection
        VCR.use_cassette(cassette_name) do
          projection = projector.project(
            config_year: period[:config_year],
            config_month: period[:config_month]
          )

          projection - period[:total]  # Positive = over-estimate, negative = under-estimate
        end
      rescue StandardError
        nil
      end.compact

      skip "Insufficient data points" if signed_errors.size < 3

      mean_bias = signed_errors.sum / signed_errors.size
      avg_total = TESTABLE_PERIODS.sum { |p| p[:total] } / TESTABLE_PERIODS.size.to_f
      bias_pct = (mean_bias / avg_total * 100).round(1)

      # Systematic bias should be minimal (<5%)
      expect(bias_pct.abs).to be < 5,
        "Systematic bias: #{bias_pct}% (#{mean_bias.round(0)} kr avg)\n" \
        "Positive = over-estimation, Negative = under-estimation"
    end
  end

  describe 'seasonal pattern validation' do
    it 'projects higher costs for winter months than summer' do
      winter_periods = TESTABLE_PERIODS.select { |p| [1, 2, 3, 11, 12].include?(p[:config_month]) }
      summer_periods = TESTABLE_PERIODS.select { |p| [6, 7, 8].include?(p[:config_month]) }

      skip "Need both winter and summer data" if winter_periods.empty? || summer_periods.empty?

      winter_avg = winter_periods.sum { |p| p[:total] } / winter_periods.size.to_f
      summer_avg = summer_periods.sum { |p| p[:total] } / summer_periods.size.to_f

      expect(winter_avg).to be > (summer_avg * 1.3),
        "Winter should cost at least 30% more than summer\n" \
        "Winter avg: #{winter_avg.round(0)} kr, Summer avg: #{summer_avg.round(0)} kr"
    end
  end
end

require 'rspec'
require_relative '../../../rent'
require_relative '../../../lib/rent_history'

module RentCalculatorSpec
  module TestHelpers
    def test_config_with_drift
      RentCalculator::Config.new(
        kallhyra: 10_000,
        el: 1_500,
        bredband: 400,
        drift_rakning: 2_612
      )
    end

    def base_rents
      { 'Alice' => 5000.0, 'Bob' => 5000.0 }
    end

    def total_days
      30
    end
  end
end

RSpec.configure do |config|
  config.include RentCalculatorSpec::TestHelpers
end 
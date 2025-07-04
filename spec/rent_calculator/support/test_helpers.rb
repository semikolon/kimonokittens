require 'rspec'
require_relative '../../../rent'
require_relative '../../../lib/rent_history'

module RentCalculatorSpec
  module TestHelpers
    def test_config_with_drift(year: nil, month: nil)
      RentCalculator::Config.new(
        year: year, month: month,
        kallhyra: 10_000,
        el: 1_500,
        bredband: 400,
        drift_rakning: 2_612
      )
    end

    def test_config_with_monthly_fees(year: nil, month: nil)
      RentCalculator::Config.new(
        year: year, month: month,
        kallhyra: 10_000,
        el: 1_500,
        bredband: 400,
        vattenavgift: 375,
        va: 300,
        larm: 150
      )
    end

    def test_config_for_november_v2
      RentCalculator::Config.new(
        year: 2024, month: 11, kallhyra: 24_530, el: 1_600,
        bredband: 400, drift_rakning: 2_612
      )
    end

    def november_2024_v2_roommates
      {
        'Fredrik' => { days: 30, room_adjustment: 0 },
        'Rasmus' => { days: 30, room_adjustment: 0 },
        'Frans-Lukas' => { days: 30, room_adjustment: 0 },
        'Astrid' => { days: 30, room_adjustment: -1400 },
        'Malin' => { days: 21, room_adjustment: 0 },
        'Elvira' => { days: 8, room_adjustment: 0 }
      }
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
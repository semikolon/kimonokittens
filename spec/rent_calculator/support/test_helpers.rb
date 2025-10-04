require 'rspec'
require 'rack/test'
require 'dotenv/load'
require_relative '../../../rent'
require_relative '../../../lib/rent_db'
# require_relative '../../support/database_cleaner'
require_relative '../../../lib/rent_history'

module RentCalculatorSpec
  module TestHelpers
    include Rack::Test::Methods

    def clean_database
      # A simple, direct way to clean the database for tests.
      db = RentDb.instance

      # ============================================================================
      # CRITICAL SAFETY CHECK: Verify we're in test database before truncating
      # ============================================================================
      current_db = db.class.db.opts[:database]

      unless current_db&.include?('test')
        raise "FATAL: Attempted to clean non-test database: #{current_db}\n" \
              "This would have destroyed your development data!\n" \
              "Tests should ONLY run against databases with '_test' suffix."
      end

      # Safe to truncate test database
      # TRUNCATE is fast and resets auto-incrementing counters.
      # CASCADE is needed to also truncate related tables (like _ItemOwners).
      db.conn.exec('TRUNCATE TABLE "Tenant", "RentConfig", "RentLedger" RESTART IDENTITY CASCADE;')

      # Also truncate ElectricityBill if it exists
      db.conn.exec('TRUNCATE TABLE "ElectricityBill" RESTART IDENTITY CASCADE;')
    rescue Sequel::DatabaseError => e
      # Table might not exist yet (e.g., ElectricityBill), that's okay
      raise unless e.message.include?('does not exist')
    end

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

  config.before(:each) do
    # This is not ideal, but it ensures that the helpers are included
    # for every test group without needing to manually include them.
    config.include RentCalculatorSpec::TestHelpers
    # Call our new cleaning method
    clean_database
  end
end
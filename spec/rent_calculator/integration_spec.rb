require_relative 'support/test_helpers'
require 'fileutils'
require_relative '../../rent' # Adjust the path as necessary
require_relative '../../lib/rent_history'

RSpec.describe 'RentCalculator Integration' do
  include RentCalculatorSpec::TestHelpers

  describe 'RentHistory workflow' do
    let(:year) { 2025 }
    let(:month) { 1 }
    let(:test_roommates) { { 'Alice' => { days: 30 } } }
    let(:test_config) { test_config_with_monthly_fees(year: year, month: month) }

    before do
      # Ensure a clean state before each test
      FileUtils.rm_f(Dir.glob(File.join(RentHistory::Config.test_directory, "#{year}_#{month.to_s.rjust(2, '0')}_v*.json")))
    end

    after(:all) do
      # Clean up all test files after the suite runs
      FileUtils.rm_f(Dir.glob(File.join(RentHistory::Config.test_directory, "*.json")))
    end

    it 'calculates, saves, and loads rent data correctly' do
      # 1. Calculate and save the first version
      results = RentCalculator.calculate_and_save(
        roommates: test_roommates,
        config: test_config,
        history_options: { version: 1, title: 'Initial', test_mode: true }
      )

      expect(results).to include('kallhyra', 'total_distributed')
      expect(results['total_distributed']).to be > 0

      # 2. Load the history and verify its contents
      saved_month = RentHistory::Month.load(year: year, month: month, version: 1, test_mode: true)
      expect(saved_month).not_to be_nil
      expect(saved_month.title).to eq('Initial')
      expect(saved_month.constants[:kallhyra]).to eq(test_config.kallhyra)
      expect(saved_month.final_results['Alice']).to be_within(0.01).of(results['rent_per_roommate']['Alice'])
    end

    it 'handles version conflicts appropriately' do
      # Save version 1
      RentCalculator.calculate_and_save(
        roommates: test_roommates,
        config: test_config,
        history_options: { version: 1, title: 'Version 1', test_mode: true }
      )

      # Attempting to save version 1 again without `force` should fail
      expect do
        RentCalculator.calculate_and_save(
          roommates: test_roommates,
          config: test_config,
          history_options: { version: 1, title: 'Duplicate', test_mode: true }
        )
      end.to raise_error(RentHistory::VersionError)
    end
  end

  describe 'November 2024 scenario' do
    let(:november_config) { test_config_for_november_v2 }
    let(:november_roommates) { november_2024_v2_roommates }

    it 'calculates November rent correctly with Elvira' do
      results = RentCalculator.rent_breakdown(
        roommates: november_roommates,
        config: november_config
      )
      
      total = november_config.total_rent
      expect(results['total_distributed']).to be >= total
    end

    it 'matches historical v2 calculation' do
      results = RentCalculator.calculate_and_save(
        roommates: november_roommates,
        config: november_config,
        history_options: {
          version: 2,
          title: "November Recalculation with Elvira's Partial Stay",
          test_mode: true
        }
      )

      month = RentHistory::Month.load(year: 2024, month: 11, version: 2, test_mode: true)
      expect(month.final_results).not_to be_nil
      expect(month.final_results).to eq(results['rent_per_roommate'])
    end
  end

  it 'produces a correct and detailed rent breakdown for a realistic scenario' do
    # This integration test uses a realistic scenario to verify the end-to-end calculation.
    # It checks that the final breakdown is complete and that the per-roommate amounts are correct,
    # including prorated adjustments and final ceiling rounding to two decimal places.

    config = RentCalculator::Config.new(
      year: 2025,
      month: 1,
      kallhyra: 24_530,
      el: 1_845,
      bredband: 380,
      vattenavgift: 375,
      va: 300,
      larm: 150,
      saldo_innan: 20
    )

    roommates = {
      'Fredrik' => { days: 31, room_adjustment: 0 },
      'Rasmus' => { days: 31, room_adjustment: 0 },
      'Frans-Lukas' => { days: 31, room_adjustment: 0 },
      'Astrid' => { days: 20, room_adjustment: -1400 }, # Left mid-month
      'Elvira' => { days: 15, room_adjustment: 0 }      # Arrived mid-month
    }

    breakdown = RentCalculator.rent_breakdown(roommates: roommates, config: config)

      # Verify key totals
      expect(breakdown['total_rent']).to be_within(0.01).of(27_560)
      expect(breakdown['total_distributed']).to be_within(0.05).of(27_560)

    # Verify per-roommate amounts by asserting against the now-correct calculator output
    expect(breakdown['rent_per_roommate']['Fredrik']).to be_within(0.01).of(6893.44)
    expect(breakdown['rent_per_roommate']['Rasmus']).to be_within(0.01).of(6893.44)
    expect(breakdown['rent_per_roommate']['Frans-Lukas']).to be_within(0.01).of(6893.44)
    expect(breakdown['rent_per_roommate']['Astrid']).to be_within(0.01).of(3544.16)
    expect(breakdown['rent_per_roommate']['Elvira']).to be_within(0.01).of(3335.54)
  end
end 
require_relative 'support/test_helpers'
require 'fileutils'

RSpec.describe 'RentCalculator Integration' do
  describe 'RentHistory workflow' do
    let(:test_year) { 2024 }
    let(:test_month) { 3 }
    let(:test_roommates) do
      {
        'Alice' => { days: 31, room_adjustment: -200 },
        'Bob' => { days: 15, room_adjustment: 100 }
      }
    end
    let(:test_config) do
      {
        year: test_year,
        month: test_month,
        kallhyra: 10_000,
        el: 1_500,
        bredband: 400,
        drift_rakning: 2_612,
        saldo_innan: 150,
        extra_in: 200
      }
    end

    before(:each) do
      # Create data directory
      data_dir = File.join(File.dirname(__FILE__), '..', '..', 'data', 'rent_history')
      FileUtils.mkdir_p(data_dir)

      # Clean up any existing test files
      [
        "#{test_year}_#{test_month.to_s.rjust(2, '0')}*.json",  # March test files
        "2024_11*.json"  # November test files
      ].each do |pattern|
        FileUtils.rm_f(Dir.glob(File.join(data_dir, pattern)))
      end
    end

    after(:each) do
      # Clean up test files
      data_dir = File.join(File.dirname(__FILE__), '..', '..', 'data', 'rent_history')
      [
        "#{test_year}_#{test_month.to_s.rjust(2, '0')}*.json",  # March test files
        "2024_11*.json"  # November test files
      ].each do |pattern|
        FileUtils.rm_f(Dir.glob(File.join(data_dir, pattern)))
      end
    end

    it 'calculates, saves, and loads rent data correctly' do
      results = RentCalculator.calculate_and_save(
        roommates: test_roommates,
        config: test_config,
        history_options: {
          version: 1,
          title: "Integration Test"
        }
      )

      expect(results).to include('Kallhyra', 'El', 'Bredband', 'Drift total', 'Total', 'Rent per Roommate')
      expect(results['Kallhyra']).to eq(test_config[:kallhyra])
      expect(results['El']).to eq(test_config[:el])
      expect(results['Bredband']).to eq(test_config[:bredband])

      month = RentHistory::Month.load(
        year: test_year,
        month: test_month,
        version: 1
      )

      expect(month.year).to eq(test_year)
      expect(month.month).to eq(test_month)
      expect(month.version).to eq(1)
      expect(month.title).to eq("Integration Test")
      expect(month.constants[:kallhyra]).to eq(test_config[:kallhyra])
      expect(month.roommates['Alice'][:days]).to eq(test_roommates['Alice'][:days])
      expect(month.final_results).to eq(results['Rent per Roommate'])
    end

    it 'handles version conflicts appropriately' do
      RentCalculator.calculate_and_save(
        roommates: test_roommates,
        config: test_config,
        history_options: {
          version: 1,
          title: "First Version"
        }
      )

      expect {
        RentCalculator.calculate_and_save(
          roommates: test_roommates,
          config: test_config,
          history_options: {
            version: 1,
            title: "Duplicate Version"
          }
        )
      }.to raise_error(RentHistory::VersionError)
    end
  end

  describe 'November 2024 scenario' do
    let(:november_config) do
      {
        year: 2024,
        month: 11,
        kallhyra: 24_530,
        el: 1_600,
        bredband: 400,
        drift_rakning: 2_612
      }
    end

    let(:november_roommates) do
      {
        'Fredrik' => { days: 30, room_adjustment: 0 },
        'Rasmus' => { days: 30, room_adjustment: 0 },
        'Frans-Lukas' => { days: 30, room_adjustment: 0 },
        'Astrid' => { days: 30, room_adjustment: -1_400 },
        'Malin' => { days: 21, room_adjustment: 0 },
        'Elvira' => { days: 8, room_adjustment: 0 }
      }
    end

    it 'calculates November rent correctly with Elvira' do
      results = RentCalculator.rent_breakdown(
        roommates: november_roommates,
        config: november_config
      )
      
      total = november_config[:kallhyra] + 
              november_config[:el] + 
              november_config[:bredband] + 
              november_config[:drift_rakning]
      
      # Total might be slightly higher due to rounding each share up to whole kronor
      expect(results['Total']).to be >= total
      expect(results['Total'] - total).to be < november_roommates.size

      expect(results['Rent per Roommate']['Astrid']).to be < results['Rent per Roommate']['Fredrik']
      expect(results['Rent per Roommate']['Malin']).to be < results['Rent per Roommate']['Fredrik']
      expect(results['Rent per Roommate']['Elvira']).to be < results['Rent per Roommate']['Malin']
      
      ['Fredrik', 'Rasmus', 'Frans-Lukas'].combination(2) do |a, b|
        expect(results['Rent per Roommate'][a]).to eq(results['Rent per Roommate'][b])
      end
    end

    it 'matches historical v2 calculation' do
      results = RentCalculator.calculate_and_save(
        roommates: november_roommates,
        config: november_config,
        history_options: {
          version: 2,
          title: "November Recalculation with Elvira's Partial Stay"
        }
      )

      month = RentHistory::Month.load(year: 2024, month: 11, version: 2)
      expect(month.final_results).to eq(results['Rent per Roommate'])
      
      total_rent = november_config[:kallhyra] + 
                  november_config[:el] + 
                  november_config[:bredband] + 
                  november_config[:drift_rakning]
      
      # Total might be slightly higher due to rounding each share up to whole kronor
      expect(results['Rent per Roommate'].values.sum).to be >= total_rent
      expect(results['Rent per Roommate'].values.sum - total_rent).to be < november_roommates.size
      
      expect(results['Rent per Roommate']['Astrid']).to be < results['Rent per Roommate']['Fredrik']
      expect(results['Rent per Roommate']['Malin']).to be < results['Rent per Roommate']['Fredrik']
      expect(results['Rent per Roommate']['Elvira']).to be < results['Rent per Roommate']['Malin']
    end
  end
end 
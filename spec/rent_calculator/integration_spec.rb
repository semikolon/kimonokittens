require_relative 'support/test_helpers'
require_relative '../../handlers/rent_calculator_handler'
require 'rack/test'

RSpec.describe 'RentCalculator Integration' do
  include Rack::Test::Methods

  def app
    # This is a minimal Rack app that routes requests to our handler.
    # We map to the parent path to ensure PATH_INFO is passed correctly.
    Rack::Builder.new do
      map "/api/rent" do
        run RentCalculatorHandler.new
      end
    end
  end

  let(:db) { RentDb.instance }

  describe 'GET /api/rent/forecast (forecast)' do
    it 'generates a correct forecast for a future month' do
      # --- Setup ---
      # Add tenants with specific start and departure dates
      db.add_tenant(name: 'Fredrik', start_date: '2023-02-01')
      db.add_tenant(name: 'Rasmus', start_date: '2023-06-01')
      db.add_tenant(name: 'Elvira', start_date: '2024-11-24')
      db.add_tenant(name: 'Adam', start_date: '2025-03-01')
      # This tenant should be excluded from the July 2025 forecast
      db.add_tenant(name: 'Frans-Lukas', start_date: '2023-12-01', departure_date: '2025-03-01')

      # Set some config values, but leave water/fees to test defaults
      db.set_config('kallhyra', '25000', Time.new(2025, 7))
      db.set_config('bredband', '400', Time.new(2025, 7))
      db.set_config('el', '1200', Time.new(2025, 7)) # Forecasted electricity

      # --- Action ---
      get '/api/rent/forecast?year=2025&month=7'

      # --- Assertions ---
      expect(last_response.ok?).to be true
      forecast_data = JSON.parse(last_response.body)

      # The forecast is returned as a single element in an array
      expect(forecast_data).not_to be_nil
      
      final_results = forecast_data['final_results']
      expect(final_results).not_to be_nil

      # 1. Correct tenants are included
      expect(final_results['roommates'].keys).to contain_exactly('Fredrik', 'Rasmus', 'Elvira', 'Adam')
      expect(final_results['roommates'].keys).not_to include('Frans-Lukas')

      # 2. Correct default fees are used
      config = final_results['config']
      expect(config['vattenavgift']).to eq(375)
      expect(config['va']).to eq(300)
      expect(config['larm']).to eq(150)

      # 3. Correct total is calculated
      expected_total = 25000 + 400 + 1200 + 375 + 300 + 150
      expect(final_results['total']).to eq(expected_total)
    end
  end

  describe 'Database-driven workflow' do
    before(:each) do
      clean_database
      # This test simulates a month WITHOUT a quarterly invoice (drift_rakning)
      db.set_config('kallhyra', '10001', Time.new(2024, 1))
      db.set_config('bredband', '400', Time.new(2024, 1))
      db.set_config('el', '1500', Time.new(2024, 1))
      db.set_config('vattenavgift', '375', Time.new(2024, 1))
      db.set_config('va', '300', Time.new(2024, 1))
      db.set_config('larm', '150', Time.new(2024, 1))
      
      db.add_tenant(name: 'Alice')
      db.add_tenant(name: 'Bob')
    end

    it 'calculates rent using data from the database' do
      config = RentCalculatorHandler.new.send(:extract_config, year: 2024, month: 1)
      roommates = RentCalculatorHandler.new.send(:extract_roommates, year: 2024, month: 1)

      expect(config[:kallhyra]).to eq(10001)
      expect(roommates.keys).to contain_exactly('Alice', 'Bob')

      results = RentCalculator.rent_breakdown(roommates: roommates, config: config)
      
      expected_total = 10001 + 400 + 1500 + 375 + 300 + 150
      expect(results['Total']).to be_within(1).of(expected_total)
      expect(results['Rent per Roommate']['Alice']).to eq(results['Rent per Roommate']['Bob'])
    end
  end

  describe 'November 2024 scenario' do
    before(:each) do
      clean_database
      # This test simulates a month WITH a quarterly invoice (drift_rakning)
      db.set_config('kallhyra', '24530', Time.new(2024, 11))
      db.set_config('el', '1600', Time.new(2024, 11))
      db.set_config('bredband', '400', Time.new(2024, 11))
      db.set_config('drift_rakning', '2612', Time.new(2024, 11))
      db.set_config('vattenavgift', '9999', Time.new(2024, 11))
      
      db.add_tenant(name: 'Fredrik', start_date: '2023-02-01')
      db.add_tenant(name: 'Rasmus', start_date: '2023-06-01')
      db.add_tenant(name: 'Frans-Lukas', start_date: '2023-12-01')
      db.add_tenant(name: 'Malin', start_date: '2023-02-01', departure_date: '2024-11-21')
      db.add_tenant(name: 'Elvira', start_date: '2024-11-22')
      db.add_tenant(name: 'Astrid', start_date: '2024-02-01', departure_date: '2024-11-30')
      db.set_room_adjustment(name: 'Astrid', adjustment: -1400)
    end

    it 'calculates November rent correctly using data from the database' do
      config = RentCalculatorHandler.new.send(:extract_config, year: 2024, month: 11)
      roommates = RentCalculatorHandler.new.send(:extract_roommates, year: 2024, month: 11)

      results = RentCalculator.rent_breakdown(roommates: roommates, config: config)
      
      expected_total = 24530 + 1600 + 400 + 2612
      
      expect(results['Total']).to be_within(1).of(expected_total)
      expect(results['Rent per Roommate']['Astrid']).to be < results['Rent per Roommate']['Fredrik']
      expect(results['Rent per Roommate']['Elvira']).to be < results['Rent per Roommate']['Malin']
    end
  end
end 
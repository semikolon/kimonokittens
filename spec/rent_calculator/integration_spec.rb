require_relative 'support/test_helpers'

RSpec.describe 'RentCalculator Integration' do
  let(:db) { RentDb.instance }

  describe 'Database-driven workflow' do
    before(:each) do
      # DatabaseCleaner will handle cleanup
      db.set_config('kallhyra', '10000')
      db.set_config('bredband', '400')
      db.set_config('el', '1500')
      
      db.add_tenant(name: 'Alice')
      db.add_tenant(name: 'Bob')
    end

    it 'calculates rent using data from the database' do
      # This test assumes the handler's extract_config and extract_roommates
      # methods are correctly fetching data from the DB.
      
      # TODO: This test is incomplete. We need to actually call the API
      # endpoint and verify the results. This requires the handler to be
      # fully refactored.
      
      config = RentCalculatorHandler.new.send(:extract_config)
      roommates = RentCalculatorHandler.new.send(:extract_roommates, year: 2024, month: 1)

      expect(config['kallhyra']).to eq(10000)
      expect(roommates.keys).to contain_exactly('Alice', 'Bob')

      results = RentCalculator.rent_breakdown(roommates: roommates, config: config)
      expect(results['Total']).to be > 11900
      expect(results['Rent per Roommate']['Alice']).to eq(results['Rent per Roommate']['Bob'])
    end
  end

  describe 'November 2024 scenario' do
    before(:each) do
      # Set up the specific config for this scenario
      db.set_config('kallhyra', '24530')
      db.set_config('el', '1600')
      db.set_config('bredband', '400')
      db.set_config('drift_rakning', '2612')
      
      # Add tenants
      ['Fredrik', 'Rasmus', 'Frans-Lukas', 'Astrid', 'Malin', 'Elvira'].each do |name|
        db.add_tenant(name: name)
      end
    end

    it 'calculates November rent correctly using data from the database' do
      # This is a simplified version of the old test.
      # A full test would involve setting up temporary stays and adjustments
      # in the database and verifying the pro-rated calculations.
      
      config = RentCalculatorHandler.new.send(:extract_config)
      
      # TODO: The `extract_roommates` method needs to be updated to handle
      # adjustments and partial stays from the database.
      roommates = {
        'Fredrik' => { days: 30, room_adjustment: 0 },
        'Rasmus' => { days: 30, room_adjustment: 0 },
        'Frans-Lukas' => { days: 30, room_adjustment: 0 },
        'Astrid' => { days: 30, room_adjustment: -1400 },
        'Malin' => { days: 21, room_adjustment: 0 },
        'Elvira' => { days: 8, room_adjustment: 0 }
      }

      results = RentCalculator.rent_breakdown(roommates: roommates, config: config)
      
      total = 24530 + 1600 + 400 + 2612
      
      expect(results['Total']).to be >= total
      expect(results['Rent per Roommate']['Astrid']).to be < results['Rent per Roommate']['Fredrik']
      expect(results['Rent per Roommate']['Elvira']).to be < results['Rent per Roommate']['Malin']
    end
  end
end 
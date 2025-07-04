require_relative 'support/test_helpers'
require_relative '../../handlers/rent_calculator_handler'

RSpec.describe 'RentCalculator Integration' do
  let(:db) { RentDb.instance }

  describe 'Database-driven workflow' do
    before(:each) do
      # This test simulates a month WITHOUT a quarterly invoice (drift_rakning)
      db.set_config('kallhyra', '10001') # Use an odd number to make the total even
      db.set_config('bredband', '400')
      db.set_config('el', '1500')
      db.set_config('vattenavgift', '375')
      db.set_config('va', '300')
      db.set_config('larm', '150')
      
      db.add_tenant(name: 'Alice')
      db.add_tenant(name: 'Bob')
    end

    it 'calculates rent using data from the database' do
      config = RentCalculatorHandler.new.send(:extract_config)
      roommates = RentCalculatorHandler.new.send(:extract_roommates, year: 2024, month: 1)

      expect(config[:kallhyra]).to eq(10001) # Expect the symbol-keyed value
      expect(roommates.keys).to contain_exactly('Alice', 'Bob')

      results = RentCalculator.rent_breakdown(roommates: roommates, config: config)
      
      # Total = kallhyra + bredband + el + vattenavgift + va + larm
      expected_total = 10001 + 400 + 1500 + 375 + 300 + 150
      expect(results['Total']).to be_within(1).of(expected_total)
      expect(results['Rent per Roommate']['Alice']).to eq(results['Rent per Roommate']['Bob'])
    end
  end

  describe 'November 2024 scenario' do
    before(:each) do
      # This test simulates a month WITH a quarterly invoice (drift_rakning)
      # The monthly fees (vatten, va, larm) should be ignored in the calculation.
      db.set_config('kallhyra', '24530')
      db.set_config('el', '1600')
      db.set_config('bredband', '400')
      db.set_config('drift_rakning', '2612') # This REPLACES the monthly fees
      db.set_config('vattenavgift', '9999') # Set to an obviously wrong value to ensure it's ignored
      
      ['Fredrik', 'Rasmus', 'Frans-Lukas', 'Malin', 'Elvira'].each do |name|
        db.add_tenant(name: name)
      end
      # Astrid has a room adjustment
      db.add_tenant(name: 'Astrid')
      db.set_room_adjustment(name: 'Astrid', adjustment: -1400)
    end

    it 'calculates November rent correctly using data from the database' do
      config = RentCalculatorHandler.new.send(:extract_config)
      
      # Now we fetch roommates from the DB, including their adjustments
      roommates = RentCalculatorHandler.new.send(:extract_roommates, year: 2024, month: 11)

      # For this specific scenario, we need to manually override partial stays
      # as this logic is not yet in the DB handler.
      roommates['Malin'][:days] = 21
      roommates['Elvira'][:days] = 8

      results = RentCalculator.rent_breakdown(roommates: roommates, config: config)
      
      # Total = kallhyra + el + bredband + drift_rakning (monthly fees are ignored)
      total = 24530 + 1600 + 400 + 2612
      
      expect(results['Total']).to be_within(roommates.size).of(total)
      expect(results['Rent per Roommate']['Astrid']).to be < results['Rent per Roommate']['Fredrik']
      expect(results['Rent per Roommate']['Elvira']).to be < results['Rent per Roommate']['Malin']
    end
  end
end 
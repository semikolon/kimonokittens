require_relative 'support/test_helpers'
# frozen_string_literal: true

require_relative '../../rent' # Adjust the path as necessary

RSpec.describe RentCalculator do
  include RentCalculatorSpec::TestHelpers

  let(:basic_config) { { kallhyra: 10_000, el: 1500, bredband: 400, vattenavgift: 0, va: 0, larm: 0, drift_rakning: 0, saldo_innan: 0, extra_in: 0 } }
  let(:full_config) do
    RentCalculator::Config.new(
      year: 2025, month: 1, kallhyra: 24_530, el: 1_600, bredband: 400,
      vattenavgift: 375, va: 300, larm: 150, drift_rakning: 2_612
    )
  end

  describe '.calculate_rent' do
    context 'when all roommates stay the full month' do
      let(:roommates) do
        {
          'Alice' => { days: 30, room_adjustment: 0 },
          'Bob' => { days: 30, room_adjustment: 0 }
        }
      end

      it 'integrates weight calculation with total rent distribution' do
        rents = described_class.calculate_rent(
          roommates: roommates,
          config: test_config_with_drift
        )
        
        expected_per_person = test_config_with_drift.total_rent / 2.0
        expect(rents['Alice']).to eq(expected_per_person)
        expect(rents['Bob']).to eq(expected_per_person)
        expect(rents.values.sum).to eq(test_config_with_drift.total_rent)
      end
    end

    context 'when roommates have different occupancy durations' do
      let(:roommates) do
        {
          'Alice' => { days: 30, room_adjustment: 0 },
          'Bob' => { days: 15, room_adjustment: 0 }
        }
      end

      it 'integrates weight calculation with total rent distribution' do
        rents = described_class.calculate_rent(
          roommates: roommates,
          config: test_config_with_drift
        )
        
        total_weight = (30.0 + 15.0) / 30.0  # 1.5
        expected_alice = (30.0/30.0 / total_weight) * test_config_with_drift.total_rent
        expected_bob = (15.0/30.0 / total_weight) * test_config_with_drift.total_rent
        
        expect(rents['Alice']).to be_within(0.01).of(expected_alice)
        expect(rents['Bob']).to be_within(0.01).of(expected_bob)
        expect(rents.values.sum).to be_within(0.01).of(test_config_with_drift.total_rent)
      end
    end

    context 'when roommates have room adjustments' do
      let(:roommates) do
        {
          'Alice' => { days: 30, room_adjustment: -200 },
          'Bob' => { days: 30, room_adjustment: 0 },
          'Charlie' => { days: 30, room_adjustment: 0 }
        }
      end

      it 'applies adjustments correctly without redistribution' do
        rents = described_class.calculate_rent(
          roommates: roommates,
          config: test_config_with_drift
        )
        
        total_rent = test_config_with_drift.total_rent
        total_adjustments = -200  # Alice's adjustment
        adjusted_total = total_rent - total_adjustments
        standard_rent = adjusted_total / 3.0  # Equal weights
        
        # Alice should pay standard rent plus her adjustment
        expect(rents['Alice']).to be_within(0.01).of(standard_rent - 200)
        # Others should pay standard rent
        expect(rents['Bob']).to be_within(0.01).of(standard_rent)
        expect(rents['Charlie']).to be_within(0.01).of(standard_rent)
        
        # Total should match original
        expect(rents.values.sum).to be_within(0.01).of(total_rent)
        # Verify Alice pays exactly 200 less than others
        expect(rents['Bob'] - rents['Alice']).to be_within(0.01).of(200)
      end

      context 'with multiple adjustments' do
        let(:roommates) do
          {
            'Alice' => { days: 30, room_adjustment: -200 },
            'Bob' => { days: 30, room_adjustment: -100 },
            'Charlie' => { days: 30, room_adjustment: 0 },
            'David' => { days: 30, room_adjustment: 0 }
          }
        end

        it 'handles multiple adjustments correctly' do
          rents = described_class.calculate_rent(
            roommates: roommates,
            config: test_config_with_drift
          )
          
          total_rent = test_config_with_drift.total_rent
          total_adjustments = -200 + (-100)  # Sum of all adjustments
          adjusted_total = total_rent - total_adjustments
          standard_rent = adjusted_total / 4.0  # Equal weights
          
          # Each person should pay standard rent plus their adjustment
          expect(rents['Alice']).to be_within(0.01).of(standard_rent - 200)
          expect(rents['Bob']).to be_within(0.01).of(standard_rent - 100)
          expect(rents['Charlie']).to be_within(0.01).of(standard_rent)
          expect(rents['David']).to be_within(0.01).of(standard_rent)
          
          # Total should match original
          expect(rents.values.sum).to be_within(0.01).of(total_rent)
          # Verify adjustments are exact
          expect(rents['Charlie'] - rents['Alice']).to be_within(0.01).of(200)
          expect(rents['Charlie'] - rents['Bob']).to be_within(0.01).of(100)
        end
      end

      context 'with partial stays and adjustments' do
        let(:roommates) do
          {
            'Alice' => { days: 30, room_adjustment: -200 },  # Full month with deduction
            'Bob' => { days: 15, room_adjustment: 0 },       # Half month, no deduction
            'Charlie' => { days: 30, room_adjustment: 0 }    # Full month, no deduction
          }
        end

        it 'handles partial stays and adjustments correctly' do
          rents = described_class.calculate_rent(
            roommates: roommates,
            config: test_config_with_drift
          )
          
          total_rent = test_config_with_drift.total_rent
          total_adjustments = -200  # Alice's adjustment
          adjusted_total = total_rent - total_adjustments
          total_weight = (30.0 + 15.0 + 30.0) / 30.0  # 2.5
          standard_rent_per_weight = adjusted_total / total_weight
          
          # Calculate expected rents
          alice_weight = 30.0/30.0  # 1.0
          bob_weight = 15.0/30.0    # 0.5
          charlie_weight = 30.0/30.0 # 1.0
          
          expect(rents['Alice']).to be_within(0.01).of(standard_rent_per_weight * alice_weight - 200)
          expect(rents['Bob']).to be_within(0.01).of(standard_rent_per_weight * bob_weight)
          expect(rents['Charlie']).to be_within(0.01).of(standard_rent_per_weight * charlie_weight)
          
          # Total should match original
          expect(rents.values.sum).to be_within(0.01).of(total_rent)
          # Verify Alice pays exactly 200 less than her weighted equivalent
          expect(rents['Charlie'] - rents['Alice']).to be_within(0.01).of(200)
        end
      end
    end
  end

  describe '.rent_breakdown' do
    let(:roommates) { { 'Alice' => { days: 30 }, 'Bob' => { days: 30 } } }
    let(:config) { basic_config }

    it 'returns a detailed breakdown of all costs and final rents' do
      breakdown = described_class.rent_breakdown(roommates: roommates, config: config)

      expect(breakdown['kallhyra']).to eq(10_000)
      expect(breakdown['el']).to eq(1500)
      expect(breakdown['bredband']).to eq(400)
      expect(breakdown['drift_total']).to eq(1900)
      expect(breakdown['total_rent']).to eq(11_900)
      expect(breakdown['total_distributed']).to be_within(0.01).of(11_900)

      expect(breakdown['rent_per_roommate']['Alice']).to be_within(0.01).of(5950)
      expect(breakdown['rent_per_roommate']['Bob']).to be_within(0.01).of(5950)
    end

    it 'rounds final results appropriately' do
      config = basic_config.merge(kallhyra: 1001)
      breakdown = described_class.rent_breakdown(
        roommates: { 'A' => { days: 20 }, 'B' => { days: 10 } },
        config: config
      )
      per_roommate = breakdown['rent_per_roommate']
      expect(per_roommate.values.all? { |v| v.to_s.split('.').last.length <= 2 }).to be true
      expect(per_roommate.values.sum).to be >= 1001
    end

    context 'when using monthly fees' do
      it 'includes all operational costs in the output' do
        config = test_config_with_monthly_fees
        results = described_class.rent_breakdown(
          roommates: { 'A' => { days: 30 } },
          config: config
        )
        expect(results['kallhyra']).to eq(config.kallhyra)
        expect(results['drift_total']).to eq(config.drift_total)
      end
    end

    context 'when using drift_rakning' do
      it 'includes drift_rakning instead of monthly fees' do
        config = test_config_with_drift
        results = described_class.rent_breakdown(
          roommates: { 'A' => { days: 30 } },
          config: config
        )
        expect(results['kallhyra']).to eq(config.kallhyra)
        expect(results['drift_total']).to eq(config.drift_total)
      end
    end
  end

  describe '.friendly_message' do
    let(:config) { full_config }
    context 'when all roommates pay the same amount' do
      let(:roommates) { { 'Alice' => { days: 31 }, 'Bob' => { days: 31 } } }

      it 'formats message correctly for equal rents' do
        message = described_class.friendly_message(roommates: roommates, config: config)
        expect(message).to include('*Hyran för februari 2025*')
        expect(message).to include('ska betalas innan 27 jan')
        expect(message).to include('*14571.00 kr* för alla')
      end
    end

    context 'when one roommate has a discount' do
      let(:roommates) do
        {
          'Astrid' => { days: 31, room_adjustment: -1400 },
          'Fredrik' => { days: 31, room_adjustment: 0 },
          'Bob' => { days: 31, room_adjustment: 0 }
        }
      end

      it 'formats message correctly with different rents' do
        message = described_class.friendly_message(roommates: roommates, config: config)
        expect(message).to include('*Hyran för februari 2025*')
        expect(message).to include('ska betalas innan 27 jan')
        expect(message).to include('*10180.67 kr* för Fredrik och Bob och *8780.67 kr* för Astrid')
      end
    end
  end
end 
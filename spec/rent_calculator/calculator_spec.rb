require_relative '../spec_helper'
require_relative 'support/test_helpers'

RSpec.describe RentCalculator do
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
    let(:roommates) do
      {
        'Alice' => { days: 30, room_adjustment: 0 },
        'Bob' => { days: 30, room_adjustment: 0 }
      }
    end

    context 'when using monthly fees' do
      it 'includes all operational costs in the output' do
        config = RentCalculator::Config.new(
          kallhyra: 24_530,
          el: 1_600,
          bredband: 400,
          vattenavgift: 375,
          va: 300,
          larm: 150,
          saldo_innan: 100,
          extra_in: 50
        )

        results = described_class.rent_breakdown(
          roommates: roommates,
          config: config
        )

        # Base costs
        expect(results['Kallhyra']).to eq(24_530)
        expect(results['El']).to eq(1_600)
        expect(results['Bredband']).to eq(400)

        # Monthly fees (no drift_rakning)
        expect(results['Vattenavgift']).to eq(375)
        expect(results['VA']).to eq(300)
        expect(results['Larm']).to eq(150)
        expect(results).not_to include('Kvartalsfaktura drift')

        # Balances
        expect(results['Saldo innan']).to eq(100)
        expect(results['Extra in']).to eq(50)

        # Totals
        expect(results['Drift total']).to eq(config.drift_total)
        # Allow 1 kr difference due to rounding
        expect(results['Total']).to be_within(1).of(results['Rent per Roommate'].values.sum)
      end
    end

    context 'when using drift_rakning' do
      it 'includes drift_rakning instead of monthly fees' do
        config = RentCalculator::Config.new(
          kallhyra: 24_530,
          el: 1_600,
          bredband: 400,
          drift_rakning: 2_612,
          saldo_innan: 100,
          extra_in: 50
        )

        results = described_class.rent_breakdown(
          roommates: roommates,
          config: config
        )

        # Base costs
        expect(results['Kallhyra']).to eq(24_530)
        expect(results['El']).to eq(1_600)
        expect(results['Bredband']).to eq(400)

        # Should show drift_rakning instead of monthly fees
        expect(results['Kvartalsfaktura drift']).to eq(2_612)
        expect(results).not_to include('Vattenavgift', 'VA', 'Larm')

        # Balances
        expect(results['Saldo innan']).to eq(100)
        expect(results['Extra in']).to eq(50)

        # Totals
        expect(results['Drift total']).to eq(config.drift_total)
        # Allow 1 kr difference due to rounding
        expect(results['Total']).to be_within(1).of(results['Rent per Roommate'].values.sum)
      end
    end

    it 'returns complete breakdown with all components' do
      results = described_class.rent_breakdown(
        roommates: roommates,
        config: test_config_with_drift
      )
      
      expect(results).to include(
        'Kallhyra',
        'El',
        'Bredband',
        'Drift total',
        'Total',
        'Rent per Roommate'
      )
      
      expect(results['Kallhyra']).to eq(test_config_with_drift.kallhyra)
      expect(results['El']).to eq(test_config_with_drift.el)
      expect(results['Bredband']).to eq(test_config_with_drift.bredband)
      expect(results['Total']).to eq(results['Rent per Roommate'].values.sum)
    end

    it 'rounds final results appropriately' do
      # Note: drift_rakning: 0 still uses default utilities (825 kr)
      config = RentCalculator::Config.new(
        kallhyra: 1001,  # Odd number to force rounding
        el: 0,
        bredband: 0,
        drift_rakning: 0
      )

      results = described_class.rent_breakdown(
        roommates: roommates,
        config: config
      )

      per_roommate = results['Rent per Roommate']
      expected_base = 1001 + 825  # kallhyra + default utilities
      # Total might be higher than original due to rounding each share up
      expect(per_roommate.values.sum).to be >= expected_base
      expect(per_roommate.values.sum - expected_base).to be < roommates.size  # Max diff is number of roommates
      
      per_roommate.values.each do |amount|
        expect(amount).to eq(amount.ceil)  # Should be rounded up to whole kronor
        expect(amount % 1).to eq(0)  # Should be a whole number
      end
    end

    it 'omits zero balances from output' do
      config = RentCalculator::Config.new(
        kallhyra: 24_530,
        el: 1_600,
        bredband: 400,
        saldo_innan: 0,
        extra_in: 0
      )

      results = described_class.rent_breakdown(
        roommates: roommates,
        config: config
      )

      expect(results).not_to include('Saldo innan', 'Extra in')
    end
  end

  describe '.friendly_message' do
    let(:config) do
      {
        year: 2025,
        month: 1,  # January
        kallhyra: 24_530,
        el: 1_600,
        bredband: 400,
        drift_rakning: 2_612
      }
    end

    context 'when all roommates pay the same amount' do
      let(:roommates) do
        {
          'Alice' => { days: 31, room_adjustment: 0 },
          'Bob' => { days: 31, room_adjustment: 0 }
        }
      end

      it 'formats message correctly for equal rents' do
        message = described_class.friendly_message(roommates: roommates, config: config)
        expect(message).to include('*Hyran för februari 2025*')  # Shows next month
        expect(message).to include('ska betalas innan 27 jan')   # Due in current month
        expect(message).to match(/\*\d+ kr\* för alla/)
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
        expect(message).to include('*Hyran för februari 2025*')  # Shows next month
        expect(message).to include('ska betalas innan 27 jan')   # Due in current month
        # Message format changed - now shows names grouped by amount
        expect(message).to include('Astrid')
        expect(message).to include('Fredrik')
        expect(message).to match(/\d+\s+kr/)  # Contains amounts in kr
      end
    end
  end
end 
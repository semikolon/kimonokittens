require_relative 'support/test_helpers'

RSpec.describe RentCalculator::AdjustmentCalculator do
  let(:total_days) { 30 }

  describe '#calculate_adjustments' do
    it 'applies single negative adjustment correctly' do
      roommates = {
        'Alice' => { days: 30, room_adjustment: -300 },
        'Bob' => { days: 30, room_adjustment: 0 }
      }
      weights = { 'Alice' => 1.0, 'Bob' => 1.0 }
      total_weight = 2.0
      base_rents = { 'Alice' => 5000.0, 'Bob' => 5000.0 }

      calculator = described_class.new(roommates, weights, total_weight, total_days)
      adjusted = calculator.calculate_adjustments(base_rents)

      total_rent = base_rents.values.sum
      total_adjustments = -300  # Total adjustment
      adjusted_total = total_rent - total_adjustments  # This increases the total
      standard_rent = adjusted_total / total_weight  # Per weight unit

      # Alice should pay her share of adjusted total plus her adjustment
      expect(adjusted['Alice']).to be_within(0.01).of(standard_rent + (-300))
      # Bob should pay his share of adjusted total
      expect(adjusted['Bob']).to be_within(0.01).of(standard_rent)
      # Total should match original
      expect(adjusted.values.sum).to be_within(0.01).of(total_rent)
      # Verify Alice pays exactly 300 less than Bob
      expect(adjusted['Bob'] - adjusted['Alice']).to be_within(0.01).of(300)
    end

    it 'applies single positive adjustment correctly' do
      roommates = {
        'Alice' => { days: 30, room_adjustment: 300 },
        'Bob' => { days: 30, room_adjustment: 0 }
      }
      weights = { 'Alice' => 1.0, 'Bob' => 1.0 }
      total_weight = 2.0
      base_rents = { 'Alice' => 5000.0, 'Bob' => 5000.0 }

      calculator = described_class.new(roommates, weights, total_weight, total_days)
      adjusted = calculator.calculate_adjustments(base_rents)

      total_rent = base_rents.values.sum
      adjusted_total = total_rent - 300  # Total adjustment
      standard_rent = adjusted_total / total_weight  # Per weight unit

      # Alice should pay her share of adjusted total plus her adjustment
      expect(adjusted['Alice']).to be_within(0.01).of(standard_rent + 300)
      # Bob should pay his share of adjusted total
      expect(adjusted['Bob']).to be_within(0.01).of(standard_rent)
      # Total should match original
      expect(adjusted.values.sum).to be_within(0.01).of(total_rent)
    end

    it 'handles multiple adjustments with mixed signs' do
      roommates = {
        'Alice' => { days: 30, room_adjustment: -300 },  # Small room discount
        'Bob' => { days: 30, room_adjustment: 200 },     # Extra storage space
        'Charlie' => { days: 30, room_adjustment: -100 }, # Shared bathroom
        'David' => { days: 30, room_adjustment: 0 }      # Standard room
      }
      weights = { 'Alice' => 1.0, 'Bob' => 1.0, 'Charlie' => 1.0, 'David' => 1.0 }
      total_weight = 4.0
      base_rents = { 'Alice' => 2500.0, 'Bob' => 2500.0, 'Charlie' => 2500.0, 'David' => 2500.0 }

      calculator = described_class.new(roommates, weights, total_weight, total_days)
      adjusted = calculator.calculate_adjustments(base_rents)

      total_rent = base_rents.values.sum
      total_adjustments = -300 + 200 + (-100)  # Sum of all adjustments
      adjusted_total = total_rent - total_adjustments
      standard_rent = adjusted_total / total_weight  # Per weight unit

      # Each person should pay their share of adjusted total plus their adjustment
      expect(adjusted['Alice']).to be_within(0.01).of(standard_rent + (-300))
      expect(adjusted['Bob']).to be_within(0.01).of(standard_rent + 200)
      expect(adjusted['Charlie']).to be_within(0.01).of(standard_rent + (-100))
      expect(adjusted['David']).to be_within(0.01).of(standard_rent)
      
      # Total should match original
      expect(adjusted.values.sum).to be_within(0.01).of(total_rent)
    end

    it 'handles partial stays with adjustments' do
      roommates = {
        'Alice' => { days: 30, room_adjustment: -300 },  # Full month, discount
        'Bob' => { days: 15, room_adjustment: 200 },     # Half month, extra charge
        'Charlie' => { days: 30, room_adjustment: 0 }    # Full month, no adjustment
      }
      weights = { 'Alice' => 1.0, 'Bob' => 0.5, 'Charlie' => 1.0 }
      total_weight = 2.5
      base_rents = { 'Alice' => 4000.0, 'Bob' => 2000.0, 'Charlie' => 4000.0 }

      calculator = described_class.new(roommates, weights, total_weight, total_days)
      adjusted = calculator.calculate_adjustments(base_rents)

      total_rent = base_rents.values.sum
      # Bob's adjustment is prorated: 200 * (15/30) = 100
      total_adjustments = -300 + 100  # Sum of all adjustments
      adjusted_total = total_rent - total_adjustments
      standard_rent = adjusted_total / total_weight  # Per weight unit

      # Each person should pay their share of adjusted total plus their adjustment
      expect(adjusted['Alice']).to be_within(0.01).of(standard_rent * 1.0 + (-300))
      expect(adjusted['Bob']).to be_within(0.01).of(standard_rent * 0.5 + 100)
      expect(adjusted['Charlie']).to be_within(0.01).of(standard_rent * 1.0)
      
      # Total should match original
      expect(adjusted.values.sum).to be_within(0.01).of(total_rent)
    end

    it 'handles very small adjustments precisely' do
      roommates = {
        'Alice' => { days: 30, room_adjustment: -0.01 },
        'Bob' => { days: 30, room_adjustment: 0 }
      }
      weights = { 'Alice' => 1.0, 'Bob' => 1.0 }
      total_weight = 2.0
      base_rents = { 'Alice' => 5000.0, 'Bob' => 5000.0 }

      calculator = described_class.new(roommates, weights, total_weight, total_days)
      adjusted = calculator.calculate_adjustments(base_rents)

      total_rent = base_rents.values.sum
      adjusted_total = total_rent - (-0.01)  # Total adjustment
      standard_rent = adjusted_total / total_weight  # Per weight unit

      # Alice should pay her share of adjusted total plus her tiny adjustment
      expect(adjusted['Alice']).to be_within(0.001).of(standard_rent + (-0.01))
      # Bob should pay his share of adjusted total
      expect(adjusted['Bob']).to be_within(0.001).of(standard_rent)
      # Total should match original
      expect(adjusted.values.sum).to be_within(0.001).of(total_rent)
    end
  end
end 
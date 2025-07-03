require_relative 'support/test_helpers'

RSpec.describe RentCalculator::WeightCalculator do
  describe '#calculate' do
    it 'calculates weights for equal stays' do
      roommates = {
        'Alice' => { days: 30, room_adjustment: 0 },
        'Bob' => { days: 30, room_adjustment: 0 }
      }
      calculator = described_class.new(roommates, 30)
      weights, total_weight = calculator.calculate
      
      expect(weights['Alice']).to eq(1.0)
      expect(weights['Bob']).to eq(1.0)
      expect(total_weight).to eq(2.0)
    end

    it 'calculates weights for partial stays' do
      roommates = {
        'Alice' => { days: 30, room_adjustment: 0 },
        'Bob' => { days: 15, room_adjustment: 0 }
      }
      calculator = described_class.new(roommates, 30)
      weights, total_weight = calculator.calculate
      
      expect(weights['Alice']).to eq(1.0)
      expect(weights['Bob']).to eq(0.5)
      expect(total_weight).to eq(1.5)
    end

    it 'handles multiple partial stays' do
      roommates = {
        'Alice' => { days: 20, room_adjustment: 0 },
        'Bob' => { days: 15, room_adjustment: 0 },
        'Charlie' => { days: 10, room_adjustment: 0 }
      }
      calculator = described_class.new(roommates, 30)
      weights, total_weight = calculator.calculate
      
      expect(weights['Alice']).to be_within(0.001).of(20.0/30.0)
      expect(weights['Bob']).to be_within(0.001).of(15.0/30.0)
      expect(weights['Charlie']).to be_within(0.001).of(10.0/30.0)
      expect(total_weight).to be_within(0.001).of(1.5)
    end
  end

  describe 'validation' do
    it 'raises error for empty roommates' do
      expect {
        described_class.new({}, 30)
      }.to raise_error(RentCalculator::ValidationError, "No roommates provided")
    end

    it 'raises error for invalid days' do
      roommates = {
        'Alice' => { days: 0, room_adjustment: 0 }
      }
      expect {
        described_class.new(roommates, 30)
      }.to raise_error(RentCalculator::ValidationError, /Invalid days for Alice/)
    end

    it 'raises error for days exceeding month length' do
      roommates = {
        'Alice' => { days: 31, room_adjustment: 0 }
      }
      expect {
        described_class.new(roommates, 30)
      }.to raise_error(RentCalculator::ValidationError, /Invalid days for Alice/)
    end
  end
end 
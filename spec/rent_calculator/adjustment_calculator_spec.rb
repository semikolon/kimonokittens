# frozen_string_literal: true

require_relative 'support/test_helpers'
require_relative '../../rent'

RSpec.describe RentCalculator::AdjustmentCalculator do
  include RentCalculatorSpec::TestHelpers

  let(:weights) { { 'Alice' => 1.0, 'Bob' => 1.0 } }
  let(:total_weight) { 2.0 }
  let(:total_days) { 30 }

  describe '#calculate_prorated_adjustments' do
    it 'applies single negative adjustment correctly' do
      roommates = { 'Alice' => { room_adjustment: -200 }, 'Bob' => {} }
      calculator = described_class.new(roommates, weights, total_weight, total_days)
      prorated, total = calculator.calculate_prorated_adjustments

      expect(prorated['Alice']).to eq(-200)
      expect(prorated['Bob']).to eq(0)
      expect(total).to eq(-200)
    end

    it 'applies single positive adjustment correctly' do
      roommates = { 'Alice' => { room_adjustment: 150 }, 'Bob' => {} }
      calculator = described_class.new(roommates, weights, total_weight, total_days)
      prorated, total = calculator.calculate_prorated_adjustments

      expect(prorated['Alice']).to eq(150)
      expect(total).to eq(150)
    end

    it 'handles multiple adjustments with mixed signs' do
      roommates = {
        'Alice' => { room_adjustment: -200 },
        'Bob' => { room_adjustment: 100 }
      }
      calculator = described_class.new(roommates, weights, total_weight, total_days)
      prorated, total = calculator.calculate_prorated_adjustments
      
      expect(prorated['Alice']).to eq(-200)
      expect(prorated['Bob']).to eq(100)
      expect(total).to eq(-100)
    end

    it 'handles partial stays with adjustments' do
      roommates = { 'Alice' => { days: 15, room_adjustment: -300 } }
      calculator = described_class.new(roommates, weights, total_weight, total_days)
      prorated, total = calculator.calculate_prorated_adjustments

      expect(prorated['Alice']).to be_within(0.01).of(-150)
      expect(total).to be_within(0.01).of(-150)
    end

    it 'handles very small adjustments precisely' do
      roommates = { 'Alice' => { room_adjustment: 0.01 } }
      calculator = described_class.new(roommates, weights, total_weight, total_days)
      prorated, total = calculator.calculate_prorated_adjustments
      
      expect(prorated['Alice']).to be_within(0.001).of(0.01)
      expect(total).to be_within(0.001).of(0.01)
    end
  end
end 
# frozen_string_literal: true

require_relative '../spec_helper'
require_relative 'support/test_helpers'
require_relative '../../rent'

RSpec.describe RentCalculator::AdjustmentCalculator do
  include RentCalculatorSpec::TestHelpers

  let(:weights) { { 'Alice' => 1.0, 'Bob' => 1.0 } }
  let(:total_weight) { 2.0 }
  let(:total_days) { 30 }

  describe '#calculate' do
    it 'applies single negative adjustment correctly' do
      roommates = { 'Alice' => { days: 30, room_adjustment: -100 } }
      weights = { 'Alice' => 1.0 }
      total_weight = 1.0
      calculator = described_class.new(roommates, total_days)
      prorated, total = calculator.calculate
      expect(prorated['Alice']).to eq(-100)
      expect(total).to eq(-100)
    end

    it 'applies single positive adjustment correctly' do
      roommates = { 'Alice' => { days: 30, room_adjustment: 50 } }
      weights = { 'Alice' => 1.0 }
      total_weight = 1.0
      calculator = described_class.new(roommates, total_days)
      prorated, total = calculator.calculate
      expect(prorated['Alice']).to eq(50)
      expect(total).to eq(50)
    end

    it 'handles multiple adjustments with mixed signs' do
      roommates = {
        'Alice' => { days: 30, room_adjustment: -200 },
        'Bob' => { days: 30, room_adjustment: 150 }
      }
      weights = { 'Alice' => 1.0, 'Bob' => 1.0 }
      total_weight = 2.0
      calculator = described_class.new(roommates, total_days)
      prorated, total = calculator.calculate
      expect(prorated['Alice']).to eq(-200)
      expect(prorated['Bob']).to eq(150)
      expect(total).to eq(-50)
    end

    it 'handles partial stays with adjustments' do
      roommates = { 'Alice' => { days: 15, room_adjustment: -100 } }
      weights = { 'Alice' => 0.5 }
      total_weight = 0.5
      calculator = described_class.new(roommates, total_days)
      prorated, total = calculator.calculate
      expect(prorated['Alice']).to be_within(0.01).of(-50)
      expect(total).to be_within(0.01).of(-50)
    end

    it 'handles very small adjustments precisely' do
      roommates = { 'Alice' => { days: 30, room_adjustment: 0.55 } }
      weights = { 'Alice' => 1.0 }
      total_weight = 1.0
      calculator = described_class.new(roommates, total_days)
      prorated, total = calculator.calculate
      expect(prorated['Alice']).to eq(0.55)
      expect(total).to eq(0.55)
    end
  end
end 
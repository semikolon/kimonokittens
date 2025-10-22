require_relative '../spec_helper'
require_relative '../../lib/models/electricity_bill'

RSpec.describe ElectricityBill do
  describe '.calculate_bill_period' do
    it 'returns same-month consumption for end-of-month due dates' do
      period = described_class.calculate_bill_period(Date.new(2025, 9, 30))
      expect(period).to eq(Date.new(2025, 8, 1))
    end

    it 'returns one-month-back consumption for start-of-month due dates' do
      period = described_class.calculate_bill_period(Date.new(2025, 11, 3))
      expect(period).to eq(Date.new(2025, 9, 1))
    end
  end

  describe '.aggregate_for_period' do
    let(:repository) { double('repo') }

    it 'sums amounts from repository bills' do
      allow(repository).to receive(:find_by_period).and_return([
        described_class.new(provider: 'Vattenfall', bill_date: Date.new(2025, 11, 3), amount: 1200),
        described_class.new(provider: 'Fortum', bill_date: Date.new(2025, 11, 4), amount: 800)
      ])

      total = described_class.aggregate_for_period(Date.new(2025, 9, 1), repository: repository)
      expect(total).to eq(2000)
    end
  end

  describe '#duplicate_of?' do
    it 'matches another bill with same provider/date/amount' do
      bill = described_class.new(provider: 'Vattenfall', bill_date: Date.new(2025, 11, 3), amount: 1685.69)
      other = described_class.new(provider: 'Vattenfall', bill_date: Date.new(2025, 11, 3), amount: 1685.69)
      expect(bill.duplicate_of?(other)).to be true
    end

    it 'differs when amount is different' do
      bill = described_class.new(provider: 'Vattenfall', bill_date: Date.new(2025, 11, 3), amount: 1685.69)
      other = described_class.new(provider: 'Vattenfall', bill_date: Date.new(2025, 11, 3), amount: 1500)
      expect(bill.duplicate_of?(other)).to be false
    end
  end
end

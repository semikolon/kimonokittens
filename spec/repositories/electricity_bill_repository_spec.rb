require_relative '../spec_helper'
require_relative '../../lib/repositories/electricity_bill_repository'
require_relative '../../lib/models/electricity_bill'
require_relative '../rent_calculator/support/test_helpers'

RSpec.describe ElectricityBillRepository do
  include RentCalculatorSpec::TestHelpers
  let(:repo) { described_class.new }

  before do
    clean_database
  end

  describe '#store_with_deduplication' do
    let(:due_date) { Date.new(2025, 11, 3) }
    let(:amount) { 1685.69 }

    it 'inserts new bill and returns inserted result' do
      result = repo.store_with_deduplication(provider: 'Vattenfall', amount: amount, due_date: due_date)
      expect(result[:inserted]).to be true
      expect(result[:bill]).to be_a(ElectricityBill)
      expect(result[:bill].amount).to eq(amount)
      expect(result[:bill_period]).to eq(Date.new(2025, 9, 1))
    end

    it 'skips duplicates based on provider/date/amount' do
      repo.store_with_deduplication(provider: 'Vattenfall', amount: amount, due_date: due_date)
      result = repo.store_with_deduplication(provider: 'Vattenfall', amount: amount, due_date: due_date)
      expect(result[:inserted]).to be false
      expect(result[:reason]).to eq('duplicate')
    end
  end

  describe '#find_by_period' do
    it 'returns bills for a specific consumption period' do
      repo.store_with_deduplication(provider: 'Vattenfall', amount: 1000, due_date: Date.new(2025, 11, 3))
      repo.store_with_deduplication(provider: 'Fortum', amount: 800, due_date: Date.new(2025, 11, 5))
      repo.store_with_deduplication(provider: 'Vattenfall', amount: 900, due_date: Date.new(2025, 10, 15))

      bills = repo.find_by_period(Date.new(2025, 9, 1))
      expect(bills.map(&:amount)).to contain_exactly(1000.0, 800.0)
    end
  end
end

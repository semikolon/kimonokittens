require_relative '../spec_helper'
require_relative '../../lib/services/apply_electricity_bill'
require_relative '../../lib/models/electricity_bill'
require_relative '../rent_calculator/support/test_helpers'

RSpec.describe ApplyElectricityBill do
  include RentCalculatorSpec::TestHelpers
  let(:electricity_repo) { ElectricityBillRepository.new }
  let(:config_repo) { RentConfigRepository.new }

  before do
    clean_database
  end

  it 'stores bill, aggregates period total, and upserts rent config' do
    result = described_class.call(
      provider: 'Vattenfall',
      amount: 1685.69,
      due_date: Date.new(2025, 11, 3),
      electricity_repo: electricity_repo,
      config_repo: config_repo
    )

    expect(result[:inserted]).to be true
    expect(result[:aggregated_total]).to eq(1685)

    config = config_repo.find_by_key_and_period('el', Time.utc(2025, 9, 1))
    expect(config.value).to eq('1685')
  end

  it 'skips duplicates but still returns aggregated total' do
    described_class.call(
      provider: 'Vattenfall',
      amount: 1200,
      due_date: Date.new(2025, 11, 3),
      electricity_repo: electricity_repo,
      config_repo: config_repo
    )

    result = described_class.call(
      provider: 'Vattenfall',
      amount: 1200,
      due_date: Date.new(2025, 11, 3),
      electricity_repo: electricity_repo,
      config_repo: config_repo
    )

    expect(result[:inserted]).to be false
    expect(result[:reason]).to eq('duplicate')
    expect(result[:aggregated_total]).to eq(1200)
  end
end

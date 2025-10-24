require_relative '../spec_helper'
require_relative '../../lib/repositories/rent_config_repository'
require_relative '../../lib/models/rent_config'
require_relative '../rent_calculator/support/test_helpers'

RSpec.describe RentConfigRepository do
  include RentCalculatorSpec::TestHelpers
  let(:repo) { described_class.new }

  before do
    clean_database
  end

  describe '#create_config' do
    it 'normalizes period to month start' do
      config = repo.create_config('el', 2424, Time.new(2025, 9, 15))
      expect(config.period).to eq(Time.utc(2025, 9, 1))
    end
  end

  describe '#find_by_key_and_period' do
    it 'returns exact matches for period-specific keys' do
      repo.create_config('el', 1685, Time.utc(2025, 9, 1))
      repo.create_config('el', 1500, Time.utc(2025, 10, 1))

      config = repo.find_by_key_and_period('el', Time.utc(2025, 9, 1))
      expect(config.value).to eq('1685')
    end
  end

  describe '#find_latest_for_key' do
    it 'returns the latest config before the target period' do
      repo.create_config('kallhyra', 24000, Time.utc(2025, 1, 1))
      repo.create_config('kallhyra', 24530, Time.utc(2025, 6, 1))

      result = repo.find_latest_for_key('kallhyra', Time.utc(2025, 7, 31))
      expect(result.value).to eq('24530')
    end
  end
end

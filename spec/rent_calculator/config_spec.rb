require_relative '../spec_helper'
require_relative 'support/test_helpers'

RSpec.describe RentCalculator::Config do
  describe '#initialize' do
    it 'accepts and stores valid parameters' do
      config = described_class.new(
        kallhyra: 24_530,
        el: 1_600,
        bredband: 400,
        drift_rakning: 2_612
      )
      
      expect(config.kallhyra).to eq(24_530)
      expect(config.el).to eq(1_600)
      expect(config.bredband).to eq(400)
      expect(config.drift_rakning).to eq(2_612)
    end

    it 'uses defaults for unspecified parameters' do
      config = described_class.new(kallhyra: 10_000)
      
      expect(config.kallhyra).to eq(10_000)
      expect(config.el).to eq(1_324 + 276)  # Default from DEFAULTS
      expect(config.bredband).to eq(400)     # Default from DEFAULTS
    end
  end

  describe '#drift_total' do
    it 'calculates total drift with monthly fees when no drift_rakning' do
      config = described_class.new(
        el: 1_600,
        bredband: 400,
        vattenavgift: 375,
        va: 300,
        larm: 150
      )

      # Virtual pot: monthly fees + gas baseline (83 kr)
      expected = 1_600 + 400 + 375 + 300 + 150 + 83
      expect(config.drift_total).to eq(expected)
    end

    it 'ignores drift_rakning and uses monthly accruals (virtual pot system)' do
      config = described_class.new(
        el: 1_600,
        bredband: 400,
        vattenavgift: 375,  # Used (not ignored - virtual pot system)
        va: 300,            # Used (not ignored - virtual pot system)
        larm: 150,          # Used (not ignored - virtual pot system)
        drift_rakning: 2_612  # STORED but NOT used in calculations
      )

      # Virtual pot system: NEVER use drift_rakning amount, always use monthly accruals
      expected = 1_600 + 400 + 375 + 300 + 150 + 83
      expect(config.drift_total).to eq(expected)
    end
  end

  describe '#total_rent' do
    it 'calculates total rent correctly with virtual pot system' do
      config = described_class.new(
        kallhyra: 24_530,
        el: 1_600,
        bredband: 400,
        drift_rakning: 2_612,  # STORED but NOT used (virtual pot)
        saldo_innan: 150,
        extra_in: 200
      )

      # Virtual pot: drift_rakning ignored, defaults apply for building ops (754) + gas (83)
      expected = 24_530 + 1_600 + 400 + 754 + 83 - 150 - 200
      expect(config.total_rent).to eq(expected)
    end
  end

  describe '#days_in_month' do
    it 'returns 30 when year/month not specified' do
      config = described_class.new
      expect(config.days_in_month).to eq(30)
    end

    it 'calculates correct days for specific month' do
      config = described_class.new(year: 2024, month: 2)
      expect(config.days_in_month).to eq(29)  # Leap year February
    end
  end
end 
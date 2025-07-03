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
      
      expected = 1_600 + 400 + 375 + 300 + 150
      expect(config.drift_total).to eq(expected)
    end

    it 'uses drift_rakning instead of monthly fees when present' do
      config = described_class.new(
        el: 1_600,
        bredband: 400,
        vattenavgift: 375,  # Should be ignored
        va: 300,            # Should be ignored
        larm: 150,          # Should be ignored
        drift_rakning: 2_612
      )
      
      expected = 1_600 + 400 + 2_612
      expect(config.drift_total).to eq(expected)
    end
  end

  describe '#total_rent' do
    it 'calculates total rent correctly' do
      config = described_class.new(
        kallhyra: 24_530,
        el: 1_600,
        bredband: 400,
        drift_rakning: 2_612,
        saldo_innan: 150,
        extra_in: 200
      )
      
      expected = 24_530 + 1_600 + 400 + 2_612 - 150 - 200
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
require_relative '../spec_helper'
require_relative '../../lib/models/tenant'

RSpec.describe Tenant, 'deposit tracking' do
  describe 'initialization' do
    it 'accepts deposit and furnishing_deposit' do
      tenant = Tenant.new(
        name: 'Test',
        email: 'test@example.com',
        deposit: 6200,
        furnishing_deposit: 2200
      )

      expect(tenant.deposit).to eq(6200.0)
      expect(tenant.furnishing_deposit).to eq(2200.0)
    end

    it 'allows nil deposits' do
      tenant = Tenant.new(name: 'Test', email: 'test@example.com')
      expect(tenant.deposit).to be_nil
      expect(tenant.furnishing_deposit).to be_nil
    end

    it 'parses decimal strings to floats' do
      tenant = Tenant.new(
        name: 'Test',
        email: 'test@example.com',
        deposit: '6200.50',
        furnishing_deposit: '2200.75'
      )

      expect(tenant.deposit).to eq(6200.50)
      expect(tenant.furnishing_deposit).to eq(2200.75)
    end

    it 'rejects negative deposits' do
      expect {
        Tenant.new(
          name: 'Test',
          email: 'test@example.com',
          deposit: -100
        )
      }.to raise_error(ArgumentError, "Deposit cannot be negative")
    end

    it 'rejects negative furnishing deposits' do
      expect {
        Tenant.new(
          name: 'Test',
          email: 'test@example.com',
          furnishing_deposit: -50
        )
      }.to raise_error(ArgumentError, "Furnishing deposit cannot be negative")
    end
  end

  describe '#deposit_paid?' do
    it 'returns true when deposit set' do
      tenant = Tenant.new(name: 'Test', email: 'test@example.com', deposit: 6200)
      expect(tenant.deposit_paid?).to be true
    end

    it 'returns false when deposit nil' do
      tenant = Tenant.new(name: 'Test', email: 'test@example.com')
      expect(tenant.deposit_paid?).to be false
    end

    it 'returns false when deposit zero' do
      tenant = Tenant.new(name: 'Test', email: 'test@example.com', deposit: 0)
      expect(tenant.deposit_paid?).to be false
    end
  end

  describe '#furnishing_deposit_paid?' do
    it 'returns true when furnishing deposit set' do
      tenant = Tenant.new(name: 'Test', email: 'test@example.com', furnishing_deposit: 2200)
      expect(tenant.furnishing_deposit_paid?).to be true
    end

    it 'returns false when furnishing deposit nil' do
      tenant = Tenant.new(name: 'Test', email: 'test@example.com')
      expect(tenant.furnishing_deposit_paid?).to be false
    end

    it 'returns false when furnishing deposit zero' do
      tenant = Tenant.new(name: 'Test', email: 'test@example.com', furnishing_deposit: 0)
      expect(tenant.furnishing_deposit_paid?).to be false
    end
  end

  describe '#total_deposits_paid' do
    it 'sums both deposits' do
      tenant = Tenant.new(
        name: 'Test',
        email: 'test@example.com',
        deposit: 6200,
        furnishing_deposit: 2200
      )
      expect(tenant.total_deposits_paid).to eq(8400.0)
    end

    it 'handles nil values' do
      tenant = Tenant.new(name: 'Test', email: 'test@example.com')
      expect(tenant.total_deposits_paid).to eq(0.0)
    end

    it 'handles partial deposits' do
      tenant = Tenant.new(name: 'Test', email: 'test@example.com', deposit: 6200)
      expect(tenant.total_deposits_paid).to eq(6200.0)
    end
  end

  describe '.calculate_deposit' do
    it 'splits total house deposit evenly among tenants' do
      deposit = Tenant.calculate_deposit(4, total_house_deposit: 24_884)
      # 24884 / 4 = 6221
      expect(deposit).to eq(6221)
    end

    it 'handles different occupancy levels (more people = lower per-person deposit)' do
      deposit_4_people = Tenant.calculate_deposit(4)
      deposit_5_people = Tenant.calculate_deposit(5)

      # More people means each pays less (total stays constant)
      expect(deposit_4_people).to be > deposit_5_people
    end

    it 'uses default total house deposit when not specified' do
      deposit = Tenant.calculate_deposit(4)
      # Should use default 24_884 kr total → 6221 kr per person
      expect(deposit).to eq(6221)
    end

    it 'handles custom total deposit amount' do
      deposit = Tenant.calculate_deposit(3, total_house_deposit: 30_000)
      # 30000 / 3 = 10000
      expect(deposit).to eq(10000)
    end

    it 'ensures total deposit never exceeds original amount paid' do
      # Original: 6221 kr/person × 4 people = 24,884 kr total
      total_4_people = Tenant.calculate_deposit(4) * 4
      total_5_people = Tenant.calculate_deposit(5) * 5
      total_3_people = Tenant.calculate_deposit(3) * 3

      # All should be approximately 24,884 kr (±1 kr due to rounding)
      expect(total_4_people).to eq(24_884)
      expect(total_5_people).to be_within(1).of(24_884)
      expect(total_3_people).to be_within(1).of(24_884)
    end
  end

  describe '#to_h' do
    it 'includes deposit fields' do
      tenant = Tenant.new(
        name: 'Test',
        email: 'test@example.com',
        personnummer: '1234567890',
        phone: '070-123 45 67',
        deposit: 6200,
        furnishing_deposit: 2200
      )

      hash = tenant.to_h
      expect(hash[:personnummer]).to eq('1234567890')
      expect(hash[:phone]).to eq('070-123 45 67')
      expect(hash[:deposit]).to eq(6200.0)
      expect(hash[:furnishingDeposit]).to eq(2200.0)
    end

    it 'handles nil deposit fields' do
      tenant = Tenant.new(name: 'Test', email: 'test@example.com')

      hash = tenant.to_h
      expect(hash[:personnummer]).to be_nil
      expect(hash[:phone]).to be_nil
      expect(hash[:deposit]).to be_nil
      expect(hash[:furnishingDeposit]).to be_nil
    end
  end
end

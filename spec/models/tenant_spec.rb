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
    it 'calculates 110% of per-person base rent' do
      deposit = Tenant.calculate_deposit(4, total_base_rent: 24_530)
      # (24530 / 4) * 1.1 = 6745.75 → rounded to 6746
      expect(deposit).to eq(6746)
    end

    it 'handles different occupancy levels' do
      deposit_4_people = Tenant.calculate_deposit(4)
      deposit_5_people = Tenant.calculate_deposit(5)

      expect(deposit_4_people).to be > deposit_5_people
    end

    it 'uses default base rent when not specified' do
      deposit = Tenant.calculate_deposit(4)
      # Should use default 24_530 kr
      expect(deposit).to eq(6746)
    end

    it 'handles custom base rent' do
      deposit = Tenant.calculate_deposit(3, total_base_rent: 30_000)
      # (30000 / 3) * 1.1 = 11000
      expect(deposit).to eq(11000)
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

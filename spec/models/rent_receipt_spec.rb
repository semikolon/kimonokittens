require_relative '../spec_helper'
require_relative '../../lib/models/rent_receipt'

RSpec.describe RentReceipt do
  describe '#initialize' do
    it 'creates a rent receipt with required fields' do
      receipt = RentReceipt.new(
        tenant_id: 'tenant_123',
        month: '2025-11',
        amount: 7045.0,
        paid_at: Time.utc(2025, 11, 25, 10, 30),
        matched_via: 'reference'
      )

      expect(receipt.tenant_id).to eq('tenant_123')
      expect(receipt.month).to eq('2025-11')
      expect(receipt.amount).to eq(7045.0)
      expect(receipt.paid_at).to eq(Time.utc(2025, 11, 25, 10, 30))
      expect(receipt.matched_via).to eq('reference')
    end

    it 'accepts optional matched_tx_id' do
      receipt = RentReceipt.new(
        tenant_id: 'tenant_123',
        month: '2025-11',
        amount: 7045.0,
        paid_at: Time.now,
        matched_via: 'amount+name',
        matched_tx_id: 'tx_abc123'
      )

      expect(receipt.matched_tx_id).to eq('tx_abc123')
    end

    it 'defaults partial to false' do
      receipt = RentReceipt.new(
        tenant_id: 'tenant_123',
        month: '2025-11',
        amount: 7045.0,
        paid_at: Time.now,
        matched_via: 'reference'
      )

      expect(receipt.partial).to be false
    end

    it 'accepts partial flag as true' do
      receipt = RentReceipt.new(
        tenant_id: 'tenant_123',
        month: '2025-11',
        amount: 3000.0,
        paid_at: Time.now,
        matched_via: 'reference',
        partial: true
      )

      expect(receipt.partial).to be true
    end
  end

  describe '#reference_match?' do
    it 'returns true for reference-matched payments' do
      receipt = RentReceipt.new(
        tenant_id: 'tenant_123',
        month: '2025-11',
        amount: 7045.0,
        paid_at: Time.now,
        matched_via: 'reference'
      )

      expect(receipt.reference_match?).to be true
    end

    it 'returns false for fuzzy-matched payments' do
      receipt = RentReceipt.new(
        tenant_id: 'tenant_123',
        month: '2025-11',
        amount: 7045.0,
        paid_at: Time.now,
        matched_via: 'amount+name'
      )

      expect(receipt.reference_match?).to be false
    end
  end

  describe '#fuzzy_match?' do
    it 'returns true for fuzzy-matched payments' do
      receipt = RentReceipt.new(
        tenant_id: 'tenant_123',
        month: '2025-11',
        amount: 7045.0,
        paid_at: Time.now,
        matched_via: 'amount+name'
      )

      expect(receipt.fuzzy_match?).to be true
    end

    it 'returns false for reference-matched payments' do
      receipt = RentReceipt.new(
        tenant_id: 'tenant_123',
        month: '2025-11',
        amount: 7045.0,
        paid_at: Time.now,
        matched_via: 'reference'
      )

      expect(receipt.fuzzy_match?).to be false
    end
  end

  describe '#manual_entry?' do
    it 'returns true for manual entries' do
      receipt = RentReceipt.new(
        tenant_id: 'tenant_123',
        month: '2025-11',
        amount: 7045.0,
        paid_at: Time.now,
        matched_via: 'manual'
      )

      expect(receipt.manual_entry?).to be true
    end

    it 'returns false for automated matches' do
      receipt = RentReceipt.new(
        tenant_id: 'tenant_123',
        month: '2025-11',
        amount: 7045.0,
        paid_at: Time.now,
        matched_via: 'reference'
      )

      expect(receipt.manual_entry?).to be false
    end
  end

  describe '#has_bank_transaction?' do
    it 'returns true when matched_tx_id is present' do
      receipt = RentReceipt.new(
        tenant_id: 'tenant_123',
        month: '2025-11',
        amount: 7045.0,
        paid_at: Time.now,
        matched_via: 'reference',
        matched_tx_id: 'tx_abc123'
      )

      expect(receipt.has_bank_transaction?).to be true
    end

    it 'returns false when matched_tx_id is nil' do
      receipt = RentReceipt.new(
        tenant_id: 'tenant_123',
        month: '2025-11',
        amount: 7045.0,
        paid_at: Time.now,
        matched_via: 'manual'
      )

      expect(receipt.has_bank_transaction?).to be false
    end
  end

  describe '#partial_payment?' do
    it 'returns true when partial flag is set' do
      receipt = RentReceipt.new(
        tenant_id: 'tenant_123',
        month: '2025-11',
        amount: 3000.0,
        paid_at: Time.now,
        matched_via: 'reference',
        partial: true
      )

      expect(receipt.partial_payment?).to be true
    end

    it 'returns false when partial flag is not set' do
      receipt = RentReceipt.new(
        tenant_id: 'tenant_123',
        month: '2025-11',
        amount: 7045.0,
        paid_at: Time.now,
        matched_via: 'reference',
        partial: false
      )

      expect(receipt.partial_payment?).to be false
    end
  end

  describe '#completes_payment?' do
    it 'returns true when single receipt equals amount due' do
      receipt = RentReceipt.new(
        id: 'receipt_1',
        tenant_id: 'tenant_123',
        month: '2025-11',
        amount: 7045.0,
        paid_at: Time.now,
        matched_via: 'reference'
      )

      expect(receipt.completes_payment?(7045.0)).to be true
    end

    it 'returns true when combined receipts equal amount due' do
      receipt1 = RentReceipt.new(
        id: 'receipt_1',
        tenant_id: 'tenant_123',
        month: '2025-11',
        amount: 3000.0,
        paid_at: Time.now,
        matched_via: 'reference',
        partial: true
      )

      receipt2 = RentReceipt.new(
        id: 'receipt_2',
        tenant_id: 'tenant_123',
        month: '2025-11',
        amount: 4045.0,
        paid_at: Time.now,
        matched_via: 'amount+name'
      )

      # Check if receipt2 completes payment given receipt1
      expect(receipt2.completes_payment?(7045.0, [receipt1])).to be true
    end

    it 'returns false when combined receipts are less than amount due' do
      receipt1 = RentReceipt.new(
        id: 'receipt_1',
        tenant_id: 'tenant_123',
        month: '2025-11',
        amount: 3000.0,
        paid_at: Time.now,
        matched_via: 'reference',
        partial: true
      )

      receipt2 = RentReceipt.new(
        id: 'receipt_2',
        tenant_id: 'tenant_123',
        month: '2025-11',
        amount: 2000.0,
        paid_at: Time.now,
        matched_via: 'manual',
        partial: true
      )

      expect(receipt2.completes_payment?(7045.0, [receipt1])).to be false
    end
  end

  describe 'validation' do
    it 'requires tenant_id' do
      expect {
        RentReceipt.new(
          month: '2025-11',
          amount: 7045.0,
          paid_at: Time.now,
          matched_via: 'reference'
        )
      }.to raise_error(ArgumentError, /tenant_id/)
    end

    it 'requires month' do
      expect {
        RentReceipt.new(
          tenant_id: 'tenant_123',
          amount: 7045.0,
          paid_at: Time.now,
          matched_via: 'reference'
        )
      }.to raise_error(ArgumentError, /month/)
    end

    it 'validates month format (YYYY-MM)' do
      expect {
        RentReceipt.new(
          tenant_id: 'tenant_123',
          month: '2025/11',
          amount: 7045.0,
          paid_at: Time.now,
          matched_via: 'reference'
        )
      }.to raise_error(ArgumentError, /month must be YYYY-MM format/)
    end

    it 'requires amount' do
      expect {
        RentReceipt.new(
          tenant_id: 'tenant_123',
          month: '2025-11',
          paid_at: Time.now,
          matched_via: 'reference'
        )
      }.to raise_error(ArgumentError, /amount/)
    end

    it 'requires positive amount' do
      expect {
        RentReceipt.new(
          tenant_id: 'tenant_123',
          month: '2025-11',
          amount: -100.0,
          paid_at: Time.now,
          matched_via: 'reference'
        )
      }.to raise_error(ArgumentError, /amount must be positive/)
    end

    it 'requires paid_at' do
      expect {
        RentReceipt.new(
          tenant_id: 'tenant_123',
          month: '2025-11',
          amount: 7045.0,
          matched_via: 'reference'
        )
      }.to raise_error(ArgumentError, /paid_at/)
    end

    it 'requires valid matched_via' do
      expect {
        RentReceipt.new(
          tenant_id: 'tenant_123',
          month: '2025-11',
          amount: 7045.0,
          paid_at: Time.now,
          matched_via: 'invalid_method'
        )
      }.to raise_error(ArgumentError, /matched_via must be/)
    end
  end
end

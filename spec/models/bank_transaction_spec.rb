require_relative '../spec_helper'
require_relative '../../lib/models/bank_transaction'

RSpec.describe BankTransaction, 'domain model' do
  describe 'initialization' do
    it 'creates transaction with required fields' do
      tx = BankTransaction.new(
        id: 'test123',
        external_id: 'lf_tx_abc123',
        account_id: '4065',
        booked_at: DateTime.new(2025, 11, 15, 10, 30),
        amount: 7045.0,
        currency: 'SEK',
        description: 'SWISH SANNA BENEMAR KK-2025-11-Sanna-cmhqe9enc',
        counterparty: 'Sanna Benemar',
        raw_json: { id: 'lf_tx_abc123', merchant: 'Swish' }
      )

      expect(tx.id).to eq('test123')
      expect(tx.external_id).to eq('lf_tx_abc123')
      expect(tx.amount).to eq(7045.0)
      expect(tx.description).to eq('SWISH SANNA BENEMAR KK-2025-11-Sanna-cmhqe9enc')
    end

    it 'allows nil counterparty' do
      tx = BankTransaction.new(
        external_id: 'lf_tx_abc123',
        account_id: '4065',
        booked_at: DateTime.now,
        amount: 100.0,
        currency: 'SEK',
        description: 'Test transaction',
        raw_json: {}
      )

      expect(tx.counterparty).to be_nil
    end

    it 'parses string amounts to float' do
      tx = BankTransaction.new(
        external_id: 'lf_tx_abc123',
        account_id: '4065',
        booked_at: DateTime.now,
        amount: '7045.50',
        currency: 'SEK',
        description: 'Test',
        raw_json: {}
      )

      expect(tx.amount).to eq(7045.50)
    end

    it 'requires external_id' do
      expect {
        BankTransaction.new(
          account_id: '4065',
          booked_at: DateTime.now,
          amount: 100.0,
          currency: 'SEK',
          description: 'Test',
          raw_json: {}
        )
      }.to raise_error(ArgumentError, /missing keyword.*external_id/i)
    end

    it 'requires booked_at' do
      expect {
        BankTransaction.new(
          external_id: 'lf_tx_abc123',
          account_id: '4065',
          amount: 100.0,
          currency: 'SEK',
          description: 'Test',
          raw_json: {}
        )
      }.to raise_error(ArgumentError, /missing keyword.*booked_at/i)
    end

    it 'requires amount' do
      expect {
        BankTransaction.new(
          external_id: 'lf_tx_abc123',
          account_id: '4065',
          booked_at: DateTime.now,
          currency: 'SEK',
          description: 'Test',
          raw_json: {}
        )
      }.to raise_error(ArgumentError, /missing keyword.*amount/i)
    end
  end

  describe '#swish_payment?' do
    it 'returns true when description contains SWISH' do
      tx = BankTransaction.new(
        external_id: 'lf_tx_abc123',
        account_id: '4065',
        booked_at: DateTime.now,
        amount: 7045.0,
        currency: 'SEK',
        description: 'SWISH SANNA BENEMAR KK-2025-11-Sanna-cmhqe9enc',
        raw_json: {}
      )

      expect(tx.swish_payment?).to be true
    end

    it 'returns true when description contains swish (case insensitive)' do
      tx = BankTransaction.new(
        external_id: 'lf_tx_abc123',
        account_id: '4065',
        booked_at: DateTime.now,
        amount: 7045.0,
        currency: 'SEK',
        description: 'Swish payment from Adam',
        raw_json: {}
      )

      expect(tx.swish_payment?).to be true
    end

    it 'returns false when description does not contain swish' do
      tx = BankTransaction.new(
        external_id: 'lf_tx_abc123',
        account_id: '4065',
        booked_at: DateTime.now,
        amount: 100.0,
        currency: 'SEK',
        description: 'Grocery store purchase',
        raw_json: {}
      )

      expect(tx.swish_payment?).to be false
    end

    it 'returns false when description is nil' do
      tx = BankTransaction.new(
        external_id: 'lf_tx_abc123',
        account_id: '4065',
        booked_at: DateTime.now,
        amount: 100.0,
        currency: 'SEK',
        raw_json: {}
      )

      expect(tx.swish_payment?).to be false
    end
  end

  describe '#matches_rent?' do
    it 'returns true when amount matches expected rent (within tolerance)' do
      tx = BankTransaction.new(
        external_id: 'lf_tx_abc123',
        account_id: '4065',
        booked_at: DateTime.now,
        amount: 7045.0,
        currency: 'SEK',
        description: 'SWISH payment',
        raw_json: {}
      )

      expect(tx.matches_rent?(7045.0)).to be true
    end

    it 'returns true when amount within ±1 SEK tolerance' do
      tx = BankTransaction.new(
        external_id: 'lf_tx_abc123',
        account_id: '4065',
        booked_at: DateTime.now,
        amount: 7045.5,
        currency: 'SEK',
        description: 'SWISH payment',
        raw_json: {}
      )

      expect(tx.matches_rent?(7045.0)).to be true
      expect(tx.matches_rent?(7046.0)).to be true
      expect(tx.matches_rent?(7044.5)).to be true  # 1.0 SEK difference
      expect(tx.matches_rent?(7044.0)).to be false # 1.5 SEK difference (exceeds tolerance)
    end

    it 'returns false when amount differs by more than tolerance' do
      tx = BankTransaction.new(
        external_id: 'lf_tx_abc123',
        account_id: '4065',
        booked_at: DateTime.now,
        amount: 7045.0,
        currency: 'SEK',
        description: 'SWISH payment',
        raw_json: {}
      )

      expect(tx.matches_rent?(7100.0)).to be false
      expect(tx.matches_rent?(6900.0)).to be false
    end

    it 'handles negative amounts (debits)' do
      tx = BankTransaction.new(
        external_id: 'lf_tx_abc123',
        account_id: '4065',
        booked_at: DateTime.now,
        amount: -7045.0,
        currency: 'SEK',
        description: 'SWISH payment',
        raw_json: {}
      )

      # Should match absolute value
      expect(tx.matches_rent?(7045.0)).to be true
    end
  end

  describe '#belongs_to_tenant?' do
    let(:tenant) do
      double(
        'Tenant',
        id: 'cmhqe9enc0000wopipuxgc3kw',
        name: 'Sanna Juni Benemar'
      )
    end

    it 'returns true when reference code contains tenant ID suffix' do
      tx = BankTransaction.new(
        external_id: 'lf_tx_abc123',
        account_id: '4065',
        booked_at: DateTime.now,
        amount: 7045.0,
        currency: 'SEK',
        description: 'SWISH SANNA BENEMAR KK-2025-11-Sanna-cmhqe9enc',
        raw_json: {}
      )

      expect(tx.belongs_to_tenant?(tenant)).to be true
    end

    it 'returns true when counterparty name fuzzy matches tenant name' do
      tx = BankTransaction.new(
        external_id: 'lf_tx_abc123',
        account_id: '4065',
        booked_at: DateTime.now,
        amount: 7045.0,
        currency: 'SEK',
        description: 'SWISH payment',
        counterparty: 'Sanna Benemar',
        raw_json: {}
      )

      expect(tx.belongs_to_tenant?(tenant)).to be true
    end

    it 'returns true for close name matches' do
      tx = BankTransaction.new(
        external_id: 'lf_tx_abc123',
        account_id: '4065',
        booked_at: DateTime.now,
        amount: 7045.0,
        currency: 'SEK',
        description: 'SWISH payment',
        counterparty: 'S. Benemar',
        raw_json: {}
      )

      expect(tx.belongs_to_tenant?(tenant)).to be true
    end

    it 'returns false when no match found' do
      tx = BankTransaction.new(
        external_id: 'lf_tx_abc123',
        account_id: '4065',
        booked_at: DateTime.now,
        amount: 7045.0,
        currency: 'SEK',
        description: 'SWISH payment from Adam',
        counterparty: 'Adam Smith',
        raw_json: {}
      )

      expect(tx.belongs_to_tenant?(tenant)).to be false
    end

    it 'returns false when counterparty nil and no reference code' do
      tx = BankTransaction.new(
        external_id: 'lf_tx_abc123',
        account_id: '4065',
        booked_at: DateTime.now,
        amount: 7045.0,
        currency: 'SEK',
        description: 'SWISH payment',
        raw_json: {}
      )

      expect(tx.belongs_to_tenant?(tenant)).to be false
    end
  end

  describe '#to_h' do
    it 'serializes all fields' do
      tx = BankTransaction.new(
        id: 'test123',
        external_id: 'lf_tx_abc123',
        account_id: '4065',
        booked_at: DateTime.new(2025, 11, 15, 10, 30),
        amount: 7045.0,
        currency: 'SEK',
        description: 'SWISH payment',
        counterparty: 'Sanna Benemar',
        raw_json: { merchant: 'Swish' },
        created_at: DateTime.new(2025, 11, 15, 10, 35)
      )

      hash = tx.to_h
      expect(hash[:id]).to eq('test123')
      expect(hash[:externalId]).to eq('lf_tx_abc123')
      expect(hash[:accountId]).to eq('4065')
      expect(hash[:amount]).to eq(7045.0)
      expect(hash[:currency]).to eq('SEK')
      expect(hash[:description]).to eq('SWISH payment')
      expect(hash[:counterparty]).to eq('Sanna Benemar')
      expect(hash[:rawJson]).to eq({ merchant: 'Swish' })
    end

    it 'handles nil values' do
      tx = BankTransaction.new(
        external_id: 'lf_tx_abc123',
        account_id: '4065',
        booked_at: DateTime.now,
        amount: 100.0,
        currency: 'SEK',
        raw_json: {}
      )

      hash = tx.to_h
      expect(hash[:description]).to eq('')  # Defaults to empty string (DB constraint NOT NULL)
      expect(hash[:counterparty]).to be_nil
    end
  end
end

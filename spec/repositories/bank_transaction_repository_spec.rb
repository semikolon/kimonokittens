require_relative '../spec_helper'
require_relative '../../lib/rent_db'
require_relative '../../lib/repositories/bank_transaction_repository'
require_relative '../../lib/models/bank_transaction'

RSpec.describe BankTransactionRepository, 'persistence layer' do
  let(:repo) { BankTransactionRepository.new }

  before(:each) do
    # Clean database before each test
    RentDb.db[:BankTransaction].delete
  end

  describe '#create' do
    it 'persists transaction to database' do
      tx = BankTransaction.new(
        external_id: 'lf_tx_test123',
        account_id: '4065',
        booked_at: DateTime.new(2025, 11, 15, 10, 30),
        amount: 7045.0,
        currency: 'SEK',
        description: 'SWISH SANNA BENEMAR',
        counterparty: 'Sanna Benemar',
        raw_json: { merchant: 'Swish' }
      )

      result = repo.create(tx)

      expect(result).to be_a(BankTransaction)
      expect(result.id).not_to be_nil
      expect(result.external_id).to eq('lf_tx_test123')
      expect(result.amount).to eq(7045.0)
    end

    it 'generates CUID for new transaction' do
      tx = BankTransaction.new(
        external_id: 'lf_tx_test456',
        account_id: '4065',
        booked_at: DateTime.now,
        amount: 100.0,
        currency: 'SEK',
        raw_json: {}
      )

      result = repo.create(tx)

      expect(result.id).to match(/^c[a-z0-9]{24}$/)
    end

    it 'stores created_at timestamp' do
      tx = BankTransaction.new(
        external_id: 'lf_tx_test789',
        account_id: '4065',
        booked_at: DateTime.now,
        amount: 100.0,
        currency: 'SEK',
        raw_json: {}
      )

      result = repo.create(tx)

      expect(result.created_at).not_to be_nil
      expect(result.created_at).to be_a(Time)
    end
  end

  describe '#find_by_id' do
    it 'finds transaction by ID' do
      tx = repo.create(BankTransaction.new(
        external_id: 'lf_tx_findme',
        account_id: '4065',
        booked_at: DateTime.now,
        amount: 500.0,
        currency: 'SEK',
        description: 'Test transaction',
        raw_json: {}
      ))

      found = repo.find_by_id(tx.id)

      expect(found).not_to be_nil
      expect(found.id).to eq(tx.id)
      expect(found.external_id).to eq('lf_tx_findme')
    end

    it 'returns nil when transaction not found' do
      found = repo.find_by_id('nonexistent_id')
      expect(found).to be_nil
    end
  end

  describe '#find_by_external_id' do
    it 'finds transaction by external_id' do
      repo.create(BankTransaction.new(
        external_id: 'lf_tx_unique123',
        account_id: '4065',
        booked_at: DateTime.now,
        amount: 750.0,
        currency: 'SEK',
        raw_json: {}
      ))

      found = repo.find_by_external_id('lf_tx_unique123')

      expect(found).not_to be_nil
      expect(found.external_id).to eq('lf_tx_unique123')
      expect(found.amount).to eq(750.0)
    end

    it 'returns nil when external_id not found' do
      found = repo.find_by_external_id('nonexistent_external_id')
      expect(found).to be_nil
    end
  end

  describe '#find_unreconciled' do
    before(:each) do
      # Create 3 reconciled transactions
      3.times do |i|
        RentDb.db[:BankTransaction].insert(
          id: "reconciled_#{i}",
          externalId: "lf_reconciled_#{i}",
          accountId: '4065',
          bookedAt: DateTime.now,
          amount: 100.0,
          currency: 'SEK',
          description: 'Test',
          rawJson: {}.to_json,
          createdAt: Time.now.utc,
          reconciledAt: Time.now.utc,  # RECONCILED
          rentReceiptId: "receipt_#{i}"
        )
      end

      # Create 5 unreconciled transactions
      5.times do |i|
        RentDb.db[:BankTransaction].insert(
          id: "unreconciled_#{i}",
          externalId: "lf_unreconciled_#{i}",
          accountId: '4065',
          bookedAt: DateTime.now - i,
          amount: 200.0,
          currency: 'SEK',
          description: 'Test',
          rawJson: {}.to_json,
          createdAt: Time.now.utc
          # reconciledAt and rentReceiptId are NULL (unreconciled)
        )
      end
    end

    it 'returns only unreconciled transactions' do
      results = repo.find_unreconciled

      expect(results.length).to eq(5)
      expect(results.all? { |tx| tx.is_a?(BankTransaction) }).to be true
      expect(results.map(&:external_id)).to all(start_with('lf_unreconciled_'))
    end

    it 'respects limit parameter' do
      results = repo.find_unreconciled(limit: 2)

      expect(results.length).to eq(2)
    end

    it 'orders by booked_at descending (most recent first)' do
      results = repo.find_unreconciled

      # Verify descending order by booked_at
      booked_times = results.map(&:booked_at)
      expect(booked_times).to eq(booked_times.sort.reverse)
    end

    it 'returns empty array when no unreconciled transactions' do
      # Mark all as reconciled
      RentDb.db[:BankTransaction].update(
        reconciledAt: Time.now.utc,
        rentReceiptId: 'test_receipt'
      )

      results = repo.find_unreconciled

      expect(results).to eq([])
    end
  end

  describe '#mark_reconciled' do
    let(:tx) do
      repo.create(BankTransaction.new(
        external_id: 'lf_tx_to_reconcile',
        account_id: '4065',
        booked_at: DateTime.now,
        amount: 7045.0,
        currency: 'SEK',
        raw_json: {}
      ))
    end

    it 'sets reconciled_at and rent_receipt_id' do
      receipt_id = 'receipt_abc123'
      repo.mark_reconciled(tx.id, receipt_id)

      row = RentDb.db[:BankTransaction].where(id: tx.id).first
      expect(row[:reconciledAt]).not_to be_nil
      expect(row[:rentReceiptId]).to eq(receipt_id)
    end

    it 'returns true when transaction found and updated' do
      result = repo.mark_reconciled(tx.id, 'receipt_xyz')
      expect(result).to be true
    end

    it 'returns false when transaction not found' do
      result = repo.mark_reconciled('nonexistent_id', 'receipt_xyz')
      expect(result).to be false
    end

    it 'excludes reconciled transactions from find_unreconciled' do
      repo.mark_reconciled(tx.id, 'receipt_test')

      results = repo.find_unreconciled
      expect(results.map(&:id)).not_to include(tx.id)
    end
  end

  describe '#upsert' do
    it 'inserts new transaction when external_id not exists' do
      count_before = RentDb.db[:BankTransaction].count

      repo.upsert(
        external_id: 'lf_tx_new',
        account_id: '4065',
        booked_at: DateTime.now,
        amount: 500.0,
        currency: 'SEK',
        description: 'New transaction',
        raw_json: {}
      )

      expect(RentDb.db[:BankTransaction].count).to eq(count_before + 1)
      found = repo.find_by_external_id('lf_tx_new')
      expect(found).not_to be_nil
      expect(found.amount).to eq(500.0)
    end

    it 'updates existing transaction when external_id exists' do
      repo.create(BankTransaction.new(
        external_id: 'lf_tx_existing',
        account_id: '4065',
        booked_at: DateTime.now,
        amount: 100.0,
        currency: 'SEK',
        description: 'Original',
        raw_json: {}
      ))

      count_before = RentDb.db[:BankTransaction].count

      repo.upsert(
        external_id: 'lf_tx_existing',
        account_id: '4065',
        booked_at: DateTime.now,
        amount: 200.0,
        currency: 'SEK',
        description: 'Updated',
        raw_json: { updated: true }
      )

      expect(RentDb.db[:BankTransaction].count).to eq(count_before)  # No new record
      found = repo.find_by_external_id('lf_tx_existing')
      expect(found.amount).to eq(200.0)
      expect(found.description).to eq('Updated')
    end

    it 'accepts counterparty parameter' do
      repo.upsert(
        external_id: 'lf_tx_with_counterparty',
        account_id: '4065',
        booked_at: DateTime.now,
        amount: 7045.0,
        currency: 'SEK',
        description: 'SWISH payment',
        counterparty: 'Sanna Benemar',
        raw_json: {}
      )

      found = repo.find_by_external_id('lf_tx_with_counterparty')
      expect(found.counterparty).to eq('Sanna Benemar')
    end
  end
end

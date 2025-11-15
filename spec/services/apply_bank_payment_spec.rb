require 'spec_helper'
require_relative '../rent_calculator/support/test_helpers'
require_relative '../../lib/services/apply_bank_payment'
require_relative '../../lib/models/bank_transaction'
require_relative '../../lib/models/rent_receipt'
require_relative '../../lib/models/rent_ledger'
require_relative '../../lib/models/tenant'
require_relative '../../lib/persistence'
require 'time'

RSpec.describe ApplyBankPayment do
  include RentCalculatorSpec::TestHelpers

  let(:current_month) { '2025-11' }
  let(:current_period) { Time.utc(2025, 11, 1) }

  # Test tenant data
  let(:sanna) do
    Tenant.new(
      id: 'cmhqe9enc0000wopipuxgc3kw',
      name: 'Sanna Juni Benemar',
      email: 'sanna@example.com',
      start_date: Date.new(2023, 6, 1),
      phone: '+46701234567'
    )
  end

  let(:adam) do
    Tenant.new(
      id: 'cmhqf1abc0001xyzabc123def',
      name: 'Adam Andersson',
      email: 'adam@example.com',
      start_date: Date.new(2023, 7, 1),
      phone: '+46709876543'
    )
  end

  # Mock ledger entries
  let(:sanna_ledger) do
    RentLedger.new(
      id: 'ledger_sanna_2025_11',
      tenant_id: sanna.id,
      period: current_period,
      amount_due: 7045.0,
      amount_paid: 0,
      days_stayed: 30,
      created_at: current_period
    )
  end

  let(:adam_ledger) do
    RentLedger.new(
      id: 'ledger_adam_2025_11',
      tenant_id: adam.id,
      period: current_period,
      amount_due: 7200.0,
      amount_paid: 0,
      days_stayed: 30,
      created_at: current_period
    )
  end

  before do
    clean_database

    # Create test tenants
    Persistence.tenants.create(sanna)
    Persistence.tenants.create(adam)

    # Create ledger entries
    Persistence.rent_ledger.create(sanna_ledger)
    Persistence.rent_ledger.create(adam_ledger)
  end

  describe 'Tier 1: Reference Code Matching' do
    it 'matches payment by reference code (UUID suffix)' do
      # Create Swish transaction with reference code
      tx = BankTransaction.new(
        external_id: 'lf_tx_ref_match_001',
        account_id: '4065',
        booked_at: DateTime.parse('2025-11-15T10:30:00Z'),
        amount: 7045.0,
        currency: 'SEK',
        description: 'SWISH SANNA BENEMAR KK-2025-11-Sanna-cmhqe9enc',
        counterparty: 'Sanna Benemar',
        raw_json: { id: 'lf_tx_ref_match_001' }
      )

      created_tx = Persistence.bank_transactions.create(tx)

      # Mock SMS gateway
      allow_any_instance_of(ApplyBankPayment).to receive(:send_admin_confirmation)

      # Execute service
      result = ApplyBankPayment.call(transaction_id: created_tx.id)

      # Verify receipt created
      receipts = Persistence.rent_receipts.find_by_tenant(sanna.id, year: 2025, month: 11)
      expect(receipts.length).to eq(1)

      receipt = receipts.first
      expect(receipt.tenant_id).to eq(sanna.id)
      expect(receipt.amount).to eq(7045.0)
      expect(receipt.matched_via).to eq('reference')
      expect(receipt.matched_tx_id).to eq(created_tx.id)
      expect(receipt.partial).to eq(false)

      # Verify ledger updated
      updated_ledger = Persistence.rent_ledger.find_by_id(sanna_ledger.id)
      expect(updated_ledger.amount_paid).to eq(7045.0)
      expect(updated_ledger.payment_date).not_to be_nil
    end

    it 'handles reference code with different UUID prefix lengths' do
      # Test with 8-char prefix
      tx = BankTransaction.new(
        external_id: 'lf_tx_ref_short',
        account_id: '4065',
        booked_at: DateTime.now,
        amount: 7045.0,
        currency: 'SEK',
        description: 'SWISH Payment KK-2025-11-Sanna-cmhqe9en',  # 8 chars
        counterparty: 'Sanna B.',
        raw_json: { id: 'lf_tx_ref_short' }
      )

      created_tx = Persistence.bank_transactions.create(tx)
      allow_any_instance_of(ApplyBankPayment).to receive(:send_admin_confirmation)

      ApplyBankPayment.call(transaction_id: created_tx.id)

      receipts = Persistence.rent_receipts.find_by_tenant(sanna.id, year: 2025, month: 11)
      expect(receipts.first.matched_via).to eq('reference')
    end
  end

  describe 'Tier 2: Fuzzy Name + Amount Matching' do
    it 'matches payment by amount and exact name match' do
      # Transaction WITHOUT reference code
      tx = BankTransaction.new(
        external_id: 'lf_tx_fuzzy_001',
        account_id: '4065',
        booked_at: DateTime.now,
        amount: 7045.0,
        currency: 'SEK',
        description: 'SWISH Betalning från Sanna Juni Benemar',
        counterparty: 'Sanna Juni Benemar',
        raw_json: { id: 'lf_tx_fuzzy_001' }
      )

      created_tx = Persistence.bank_transactions.create(tx)
      allow_any_instance_of(ApplyBankPayment).to receive(:send_admin_confirmation)

      ApplyBankPayment.call(transaction_id: created_tx.id)

      receipts = Persistence.rent_receipts.find_by_tenant(sanna.id, year: 2025, month: 11)
      expect(receipts.first.matched_via).to eq('amount+name')
    end

    it 'matches payment with fuzzy name similarity (middle name difference)' do
      tx = BankTransaction.new(
        external_id: 'lf_tx_fuzzy_002',
        account_id: '4065',
        booked_at: DateTime.now,
        amount: 7045.0,
        currency: 'SEK',
        description: 'SWISH från Sanna Benemar',  # Missing middle name
        counterparty: 'Sanna Benemar',
        raw_json: { id: 'lf_tx_fuzzy_002' }
      )

      created_tx = Persistence.bank_transactions.create(tx)
      allow_any_instance_of(ApplyBankPayment).to receive(:send_admin_confirmation)

      ApplyBankPayment.call(transaction_id: created_tx.id)

      receipts = Persistence.rent_receipts.find_by_tenant(sanna.id, year: 2025, month: 11)
      expect(receipts.first.matched_via).to eq('amount+name')
    end

    it 'matches with initial in name (S. Benemar → Sanna Benemar)' do
      tx = BankTransaction.new(
        external_id: 'lf_tx_initial',
        account_id: '4065',
        booked_at: DateTime.now,
        amount: 7045.0,
        currency: 'SEK',
        description: 'SWISH S. Benemar',
        counterparty: 'S. Benemar',
        raw_json: { id: 'lf_tx_initial' }
      )

      created_tx = Persistence.bank_transactions.create(tx)
      allow_any_instance_of(ApplyBankPayment).to receive(:send_admin_confirmation)

      ApplyBankPayment.call(transaction_id: created_tx.id)

      receipts = Persistence.rent_receipts.find_by_tenant(sanna.id, year: 2025, month: 11)
      expect(receipts.first.matched_via).to eq('amount+name')
    end

    it 'does NOT match when amount differs by more than tolerance' do
      tx = BankTransaction.new(
        external_id: 'lf_tx_wrong_amount',
        account_id: '4065',
        booked_at: DateTime.now,
        amount: 7100.0,  # More than ±1 SEK off
        currency: 'SEK',
        description: 'SWISH Sanna Benemar',
        counterparty: 'Sanna Benemar',
        raw_json: { id: 'lf_tx_wrong_amount' }
      )

      created_tx = Persistence.bank_transactions.create(tx)

      ApplyBankPayment.call(transaction_id: created_tx.id)

      receipts = Persistence.rent_receipts.find_by_tenant(sanna.id, year: 2025, month: 11)
      expect(receipts).to be_empty
    end

    it 'does NOT match when name similarity is too low' do
      tx = BankTransaction.new(
        external_id: 'lf_tx_wrong_name',
        account_id: '4065',
        booked_at: DateTime.now,
        amount: 7045.0,
        currency: 'SEK',
        description: 'SWISH Erik Johansson',
        counterparty: 'Erik Johansson',
        raw_json: { id: 'lf_tx_wrong_name' }
      )

      created_tx = Persistence.bank_transactions.create(tx)

      ApplyBankPayment.call(transaction_id: created_tx.id)

      receipts = Persistence.rent_receipts.find_by_tenant(sanna.id, year: 2025, month: 11)
      expect(receipts).to be_empty
    end
  end

  describe 'Partial Payments' do
    it 'marks first partial payment correctly' do
      tx = BankTransaction.new(
        external_id: 'lf_tx_partial_001',
        account_id: '4065',
        booked_at: DateTime.now,
        amount: 3000.0,  # Less than 7045
        currency: 'SEK',
        description: 'SWISH SANNA BENEMAR KK-2025-11-Sanna-cmhqe9enc',
        counterparty: 'Sanna Benemar',
        raw_json: { id: 'lf_tx_partial_001' }
      )

      created_tx = Persistence.bank_transactions.create(tx)
      allow_any_instance_of(ApplyBankPayment).to receive(:check_deadline_and_alert)

      ApplyBankPayment.call(transaction_id: created_tx.id)

      receipts = Persistence.rent_receipts.find_by_tenant(sanna.id, year: 2025, month: 11)
      receipt = receipts.first

      expect(receipt.partial).to eq(true)
      expect(receipt.amount).to eq(3000.0)

      # Ledger should NOT be updated yet (not fully paid)
      updated_ledger = Persistence.rent_ledger.find_by_id(sanna_ledger.id)
      expect(updated_ledger.amount_paid).to eq(0)
    end

    it 'accumulates multiple partial payments' do
      # First partial
      tx1 = BankTransaction.new(
        external_id: 'lf_tx_partial_1',
        account_id: '4065',
        booked_at: DateTime.parse('2025-11-15T10:00:00Z'),
        amount: 3000.0,
        currency: 'SEK',
        description: 'SWISH SANNA BENEMAR KK-2025-11-Sanna-cmhqe9enc',
        counterparty: 'Sanna Benemar',
        raw_json: { id: 'lf_tx_partial_1' }
      )

      created_tx1 = Persistence.bank_transactions.create(tx1)
      allow_any_instance_of(ApplyBankPayment).to receive(:check_deadline_and_alert)

      ApplyBankPayment.call(transaction_id: created_tx1.id)

      # Second partial (completes payment)
      tx2 = BankTransaction.new(
        external_id: 'lf_tx_partial_2',
        account_id: '4065',
        booked_at: DateTime.parse('2025-11-15T14:00:00Z'),
        amount: 4045.0,
        currency: 'SEK',
        description: 'SWISH SANNA BENEMAR KK-2025-11-Sanna-cmhqe9enc',
        counterparty: 'Sanna Benemar',
        raw_json: { id: 'lf_tx_partial_2' }
      )

      created_tx2 = Persistence.bank_transactions.create(tx2)
      allow_any_instance_of(ApplyBankPayment).to receive(:send_admin_confirmation)

      ApplyBankPayment.call(transaction_id: created_tx2.id)

      receipts = Persistence.rent_receipts.find_by_tenant(sanna.id, year: 2025, month: 11)
      expect(receipts.length).to eq(2)

      # Verify total
      total = receipts.sum(&:amount)
      expect(total).to eq(7045.0)

      # Second payment should not be marked partial (completes payment)
      second_receipt = receipts.find { |r| r.matched_tx_id == created_tx2.id }
      expect(second_receipt.partial).to eq(false)

      # Ledger should now be updated
      updated_ledger = Persistence.rent_ledger.find_by_id(sanna_ledger.id)
      expect(updated_ledger.amount_paid).to eq(7045.0)
    end
  end

  describe 'Overpayment Edge Case' do
    it 'handles overpayment gracefully' do
      tx = BankTransaction.new(
        external_id: 'lf_tx_overpay',
        account_id: '4065',
        booked_at: DateTime.now,
        amount: 8000.0,  # More than due
        currency: 'SEK',
        description: 'SWISH SANNA BENEMAR KK-2025-11-Sanna-cmhqe9enc',
        counterparty: 'Sanna Benemar',
        raw_json: { id: 'lf_tx_overpay' }
      )

      created_tx = Persistence.bank_transactions.create(tx)
      allow_any_instance_of(ApplyBankPayment).to receive(:send_admin_confirmation)

      ApplyBankPayment.call(transaction_id: created_tx.id)

      receipt = Persistence.rent_receipts.find_by_tenant(sanna.id, year: 2025, month: 11).first
      expect(receipt.partial).to eq(false)
      expect(receipt.amount).to eq(8000.0)

      # Ledger records actual payment (overpayment tracked)
      updated_ledger = Persistence.rent_ledger.find_by_id(sanna_ledger.id)
      expect(updated_ledger.amount_paid).to eq(8000.0)
    end
  end

  describe 'Admin SMS Notifications' do
    it 'sends admin SMS when payment fully completes' do
      tx = BankTransaction.new(
        external_id: 'lf_tx_complete',
        account_id: '4065',
        booked_at: DateTime.now,
        amount: 7045.0,
        currency: 'SEK',
        description: 'SWISH SANNA BENEMAR KK-2025-11-Sanna-cmhqe9enc',
        counterparty: 'Sanna Benemar',
        raw_json: { id: 'lf_tx_complete' }
      )

      created_tx = Persistence.bank_transactions.create(tx)

      # Expect SMS to be sent (match tenant by ID, not object equality)
      expect_any_instance_of(ApplyBankPayment).to receive(:send_admin_confirmation)
        .with(having_attributes(id: sanna.id), 7045.0, 7045.0, 'reference')

      ApplyBankPayment.call(transaction_id: created_tx.id)
    end

    it 'checks deadline proximity for partial payments' do
      tx = BankTransaction.new(
        external_id: 'lf_tx_partial_late',
        account_id: '4065',
        booked_at: DateTime.now,
        amount: 3000.0,
        currency: 'SEK',
        description: 'SWISH SANNA BENEMAR KK-2025-11-Sanna-cmhqe9enc',
        counterparty: 'Sanna Benemar',
        raw_json: { id: 'lf_tx_partial_late' }
      )

      created_tx = Persistence.bank_transactions.create(tx)

      # Expect deadline check (match tenant by ID, not object equality)
      expect_any_instance_of(ApplyBankPayment).to receive(:check_deadline_and_alert)
        .with(having_attributes(id: sanna.id), 3000.0, 7045.0)

      ApplyBankPayment.call(transaction_id: created_tx.id)
    end
  end

  describe 'WebSocket Broadcast' do
    it 'broadcasts update after successful payment' do
      tx = BankTransaction.new(
        external_id: 'lf_tx_ws_test',
        account_id: '4065',
        booked_at: DateTime.now,
        amount: 7045.0,
        currency: 'SEK',
        description: 'SWISH SANNA BENEMAR KK-2025-11-Sanna-cmhqe9enc',
        counterparty: 'Sanna Benemar',
        raw_json: { id: 'lf_tx_ws_test' }
      )

      created_tx = Persistence.bank_transactions.create(tx)
      allow_any_instance_of(ApplyBankPayment).to receive(:send_admin_confirmation)

      # Mock $pubsub global variable
      pubsub_mock = double('PubSub')
      allow(pubsub_mock).to receive(:publish).with('rent_data_updated')

      # Set the global variable
      original_pubsub = $pubsub
      $pubsub = pubsub_mock

      ApplyBankPayment.call(transaction_id: created_tx.id)

      # Verify publish was called
      expect(pubsub_mock).to have_received(:publish).with('rent_data_updated')

      # Restore original value
      $pubsub = original_pubsub
    end
  end

  describe 'Edge Cases' do
    it 'handles non-Swish transactions gracefully' do
      tx = BankTransaction.new(
        external_id: 'lf_tx_not_swish',
        account_id: '4065',
        booked_at: DateTime.now,
        amount: 7045.0,
        currency: 'SEK',
        description: 'Bank transfer from Sanna',
        counterparty: 'Sanna Benemar',
        raw_json: { id: 'lf_tx_not_swish' }
      )

      created_tx = Persistence.bank_transactions.create(tx)

      # Should not create receipt (not Swish)
      ApplyBankPayment.call(transaction_id: created_tx.id)

      receipts = Persistence.rent_receipts.find_by_tenant(sanna.id, year: 2025, month: 11)
      expect(receipts).to be_empty
    end

    it 'handles transaction without matching tenant' do
      tx = BankTransaction.new(
        external_id: 'lf_tx_unknown',
        account_id: '4065',
        booked_at: DateTime.now,
        amount: 5000.0,
        currency: 'SEK',
        description: 'SWISH Unknown Person',
        counterparty: 'Unknown Person',
        raw_json: { id: 'lf_tx_unknown' }
      )

      created_tx = Persistence.bank_transactions.create(tx)

      # Should not create receipt (no matching tenant)
      ApplyBankPayment.call(transaction_id: created_tx.id)

      # No receipts created
      all_receipts = Persistence.rent_receipts.all
      expect(all_receipts).to be_empty
    end

    it 'handles transaction without ledger entry for period' do
      # Remove ledger entry
      Persistence.rent_ledger.delete(sanna_ledger.id)

      tx = BankTransaction.new(
        external_id: 'lf_tx_no_ledger',
        account_id: '4065',
        booked_at: DateTime.now,
        amount: 7045.0,
        currency: 'SEK',
        description: 'SWISH SANNA BENEMAR KK-2025-11-Sanna-cmhqe9enc',
        counterparty: 'Sanna Benemar',
        raw_json: { id: 'lf_tx_no_ledger' }
      )

      created_tx = Persistence.bank_transactions.create(tx)

      # Should not create receipt (no ledger for period)
      ApplyBankPayment.call(transaction_id: created_tx.id)

      receipts = Persistence.rent_receipts.find_by_tenant(sanna.id, year: 2025, month: 11)
      expect(receipts).to be_empty
    end
  end
end

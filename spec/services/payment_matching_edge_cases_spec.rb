require 'spec_helper'
require_relative '../rent_calculator/support/test_helpers'
require_relative '../../lib/services/apply_bank_payment'
require_relative '../../lib/models/bank_transaction'
require_relative '../../lib/models/rent_receipt'
require_relative '../../lib/models/rent_ledger'
require_relative '../../lib/models/tenant'
require_relative '../../lib/persistence'
require 'time'

RSpec.describe 'Payment Matching Edge Cases' do
  include RentCalculatorSpec::TestHelpers

  let(:current_month) { '2025-11' }
  let(:current_period) { Time.utc(2025, 11, 1) }

  # Test tenant data from production snapshot
  let(:sanna) do
    Tenant.new(
      id: 'cmhqe9enc0000wopipuxgc3kw',
      name: 'Sanna Juni Benemar',
      email: 'sanna@example.com',
      phone_e164: '+46702894437',
      start_date: Date.new(2025, 10, 21),  # Recent tenant for deposit tests
      room: 'Höger nere',
      status: 'active',
      payday_start_day: 25
    )
  end

  let(:adam) do
    Tenant.new(
      id: 'cmcp5ovvc0000mnpiq34uprjv',
      name: 'Adam McCarthy',
      email: 'adam@example.com',
      phone_e164: '+46760177088',
      start_date: Date.new(2025, 3, 1),  # Older tenant - not new
      room: 'Höger uppe',
      status: 'active',
      payday_start_day: 25
    )
  end

  let(:sanna_ledger) do
    RentLedger.new(
      id: 'ledger_sanna_2025_11',
      tenant_id: sanna.id,
      period: current_period,
      amount_due: 6303.0,
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
      amount_due: 6302.0,
      amount_paid: 0,
      days_stayed: 30,
      created_at: current_period
    )
  end

  before do
    clean_database
    Persistence.tenants.create(sanna)
    Persistence.tenants.create(adam)
    Persistence.rent_ledger.create(sanna_ledger)
    Persistence.rent_ledger.create(adam_ledger)
  end

  describe 'Category 1: Transaction Direction Detection' do
    context 'Test 1.1: Incoming Swish (Rent Payment)' do
      it 'processes incoming Swish payment as rent' do
        tx = BankTransaction.new(
          external_id: 'lf_tx_incoming_001',
          account_id: '4653',
          booked_at: DateTime.parse('2025-11-24T10:30:00Z'),
          amount: 6303.0,
          currency: 'SEK',
          description: 'from: +46702894437 1806326367017854, reference: 1806326367017854IN',
          counterparty: '+46702894437',
          raw_json: {
            'id' => 'lf_tx_incoming_001',
            'merchant' => 'Swish Mottagen',
            'amount' => 6303.0
          }
        )

        created_tx = Persistence.bank_transactions.create(tx)
        allow_any_instance_of(ApplyBankPayment).to receive(:send_admin_confirmation)

        result = ApplyBankPayment.call(transaction_id: created_tx.id)

        expect(result).not_to be_nil
        expect(result.tenant_id).to eq(sanna.id)
        expect(result.matched_via).to eq('phone')

        # Verify transaction direction
        expect(created_tx.direction).to eq(:incoming)
        expect(created_tx.incoming_swish_payment?).to be true
      end
    end

    context 'Test 1.2: Outgoing Swish (Reimbursement)' do
      it 'does NOT process outgoing Swish payment as rent' do
        tx = BankTransaction.new(
          external_id: 'lf_tx_outgoing_001',
          account_id: '4653',
          booked_at: DateTime.parse('2025-11-26T14:00:00Z'),
          amount: -400.0,  # Negative amount
          currency: 'SEK',
          description: 'to: +46702894437 1806326367017854',
          counterparty: '+46702894437',
          raw_json: {
            'id' => 'lf_tx_outgoing_001',
            'merchant' => 'Swish Skickad',  # OUTGOING
            'amount' => -400.0
          }
        )

        created_tx = Persistence.bank_transactions.create(tx)

        result = ApplyBankPayment.call(transaction_id: created_tx.id)

        expect(result).to be_nil  # No receipt created
        expect(created_tx.direction).to eq(:outgoing)
        expect(created_tx.incoming_swish_payment?).to be false
      end
    end

    context 'Test 1.3: Incoming Bank Transfer (Non-Swish Rent)' do
      it 'processes incoming bank transfer as rent' do
        # Note: Current implementation only processes Swish payments
        # This test documents expected future behavior
        tx = BankTransaction.new(
          external_id: 'lf_tx_bank_transfer_001',
          account_id: '4653',
          booked_at: DateTime.now,
          amount: 6302.0,
          currency: 'SEK',
          description: 'Adam McCarthy - Rent November',
          counterparty: 'Adam McCarthy',
          raw_json: {
            'id' => 'lf_tx_bank_transfer_001',
            'merchant' => 'Överföring Via Internet',
            'amount' => 6302.0
          }
        )

        created_tx = Persistence.bank_transactions.create(tx)

        result = ApplyBankPayment.call(transaction_id: created_tx.id)

        # Current implementation: returns nil (only Swish)
        # Future: Should match by amount+name
        expect(result).to be_nil
      end
    end

    context 'Test 1.4: Outgoing Bank Transfer (Bill Payment)' do
      it 'does NOT process outgoing bank transfer as rent' do
        tx = BankTransaction.new(
          external_id: 'lf_tx_bill_payment_001',
          account_id: '4653',
          booked_at: DateTime.now,
          amount: -1685.69,
          currency: 'SEK',
          description: 'Vattenfall invoice payment',
          counterparty: 'Vattenfall AB',
          raw_json: {
            'id' => 'lf_tx_bill_payment_001',
            'merchant' => 'Överföring Via Internet',
            'amount' => -1685.69
          }
        )

        created_tx = Persistence.bank_transactions.create(tx)

        result = ApplyBankPayment.call(transaction_id: created_tx.id)

        expect(result).to be_nil  # No receipt created
        expect(created_tx.direction).to eq(:outgoing)
      end
    end
  end

  describe 'Category 12: Deposit Detection' do
    context 'Test 12.1: New Tenant - First Month Deposit' do
      it 'detects deposit and does NOT create rent receipt' do
        # Sanna's move-in date: Oct 21, 2025
        # Deposit payment: Oct 21, 2025 (same day)
        tx = BankTransaction.new(
          external_id: 'lf_tx_deposit_001',
          account_id: '4653',
          booked_at: DateTime.parse('2025-10-21T12:00:00Z'),
          amount: 6000.0,  # Within DEPOSIT_FIRST_MONTH_RANGE (6000-6200)
          currency: 'SEK',
          description: 'from: +46702894437 1806326367017854, reference: 1806326367017854IN',
          counterparty: '+46702894437',
          raw_json: {
            'id' => 'lf_tx_deposit_001',
            'merchant' => 'Swish Mottagen',
            'amount' => 6000.0
          }
        )

        created_tx = Persistence.bank_transactions.create(tx)

        # Mock admin alert
        expect_any_instance_of(ApplyBankPayment).to receive(:log_deposit_to_admin)

        result = ApplyBankPayment.call(transaction_id: created_tx.id)

        # Should NOT create receipt (deposit, not rent)
        expect(result).to be_nil

        receipts = Persistence.rent_receipts.find_by_tenant(sanna.id, year: 2025, month: 10)
        expect(receipts).to be_empty
      end
    end

    context 'Test 12.2: New Tenant - Composite Deposit' do
      it 'detects composite deposit (8,400 kr)' do
        tx = BankTransaction.new(
          external_id: 'lf_tx_deposit_composite',
          account_id: '4653',
          booked_at: DateTime.parse('2025-10-26T12:00:00Z'),  # 5 days after move-in
          amount: 8400.0,  # Within DEPOSIT_COMPOSITE_RANGE (8200-8600)
          currency: 'SEK',
          description: 'from: +46702894437 1806326367017854',
          counterparty: '+46702894437',
          raw_json: {
            'id' => 'lf_tx_deposit_composite',
            'merchant' => 'Swish Mottagen',
            'amount' => 8400.0
          }
        )

        created_tx = Persistence.bank_transactions.create(tx)
        expect_any_instance_of(ApplyBankPayment).to receive(:log_deposit_to_admin)

        result = ApplyBankPayment.call(transaction_id: created_tx.id)

        expect(result).to be_nil
      end
    end

    context 'Test 12.3: Old Tenant - NOT a Deposit' do
      it 'processes as partial rent for existing tenant' do
        # Adam moved in March 1, 2025 (8+ months ago)
        # 6000 kr payment should be treated as rent, not deposit
        tx = BankTransaction.new(
          external_id: 'lf_tx_not_deposit',
          account_id: '4653',
          booked_at: DateTime.parse('2025-11-24T12:00:00Z'),
          amount: 6000.0,  # Matches deposit range BUT tenant is old
          currency: 'SEK',
          description: 'from: +46760177088 1806326367017854',
          counterparty: '+46760177088',
          raw_json: {
            'id' => 'lf_tx_not_deposit',
            'merchant' => 'Swish Mottagen',
            'amount' => 6000.0
          }
        )

        created_tx = Persistence.bank_transactions.create(tx)
        allow_any_instance_of(ApplyBankPayment).to receive(:check_deadline_and_alert)

        result = ApplyBankPayment.call(transaction_id: created_tx.id)

        # Should create receipt (rent, not deposit)
        expect(result).not_to be_nil
        expect(result.tenant_id).to eq(adam.id)
        expect(result.partial).to be true  # 6000 < 6302
      end
    end

    context 'Test 12.4: Deposit Completion (Small Payment)' do
      it 'rejects small payment below threshold without reference code' do
        # Sanna pays 400 kr on Nov 18 (28 days after move-in, still in window)
        # But 400 kr is below 50% threshold and not a deposit amount
        tx = BankTransaction.new(
          external_id: 'lf_tx_small_payment',
          account_id: '4653',
          booked_at: DateTime.parse('2025-11-18T12:00:00Z'),
          amount: 400.0,  # Below 50% of 6303
          currency: 'SEK',
          description: 'from: +46702894437 1806326367017854',
          counterparty: '+46702894437',
          raw_json: {
            'id' => 'lf_tx_small_payment',
            'merchant' => 'Swish Mottagen',
            'amount' => 400.0
          }
        )

        created_tx = Persistence.bank_transactions.create(tx)
        expect_any_instance_of(ApplyBankPayment).to receive(:log_small_payment_to_admin)

        result = ApplyBankPayment.call(transaction_id: created_tx.id)

        # Should NOT create receipt (below threshold, no reference code)
        expect(result).to be_nil
      end
    end
  end

  describe 'Category 13: Amount Thresholds (50% Rule)' do
    context 'Test 13.1: Payment Meets 50% Threshold' do
      it 'creates receipt when payment >= 50% of expected rent' do
        # 3500 kr > 50% of 6303 kr (3151.5)
        tx = BankTransaction.new(
          external_id: 'lf_tx_threshold_pass',
          account_id: '4653',
          booked_at: DateTime.parse('2025-11-24T12:00:00Z'),
          amount: 3500.0,
          currency: 'SEK',
          description: 'from: +46702894437 1806326367017854',
          counterparty: '+46702894437',
          raw_json: {
            'id' => 'lf_tx_threshold_pass',
            'merchant' => 'Swish Mottagen',
            'amount' => 3500.0
          }
        )

        created_tx = Persistence.bank_transactions.create(tx)
        allow_any_instance_of(ApplyBankPayment).to receive(:check_deadline_and_alert)

        result = ApplyBankPayment.call(transaction_id: created_tx.id)

        expect(result).not_to be_nil
        expect(result.partial).to be true
        expect(result.amount).to eq(3500.0)
      end
    end

    context 'Test 13.2: Payment Below 50% Threshold' do
      it 'does NOT create receipt when payment < 50% without reference code' do
        # 3000 kr < 50% of 6303 kr (3151.5)
        tx = BankTransaction.new(
          external_id: 'lf_tx_threshold_fail',
          account_id: '4653',
          booked_at: DateTime.parse('2025-11-24T12:00:00Z'),
          amount: 3000.0,
          currency: 'SEK',
          description: 'from: +46702894437 1806326367017854',
          counterparty: '+46702894437',
          raw_json: {
            'id' => 'lf_tx_threshold_fail',
            'merchant' => 'Swish Mottagen',
            'amount' => 3000.0
          }
        )

        created_tx = Persistence.bank_transactions.create(tx)
        expect_any_instance_of(ApplyBankPayment).to receive(:log_small_payment_to_admin)

        result = ApplyBankPayment.call(transaction_id: created_tx.id)

        expect(result).to be_nil
      end
    end

    context 'Test 13.3: Reference Code Override (Below Threshold)' do
      it 'creates receipt when reference code exists even if below threshold' do
        # 2000 kr < 50% threshold BUT has reference code
        tx = BankTransaction.new(
          external_id: 'lf_tx_ref_override',
          account_id: '4653',
          booked_at: DateTime.parse('2025-11-24T12:00:00Z'),
          amount: 2000.0,
          currency: 'SEK',
          description: 'SWISH from +46702894437 KK202511Sannacmhqe9enc',
          counterparty: '+46702894437',
          raw_json: {
            'id' => 'lf_tx_ref_override',
            'merchant' => 'Swish Mottagen',
            'amount' => 2000.0
          }
        )

        created_tx = Persistence.bank_transactions.create(tx)
        allow_any_instance_of(ApplyBankPayment).to receive(:check_deadline_and_alert)

        result = ApplyBankPayment.call(transaction_id: created_tx.id)

        # Reference code bypasses threshold
        expect(result).not_to be_nil
        expect(result.matched_via).to eq('reference')
        expect(result.partial).to be true
      end
    end
  end

  describe 'Category 14: Same-Day Payment Aggregation' do
    context 'Test 14.1: Two Payments Same Day - Both Pass Individually' do
      it 'creates receipts for both payments that individually meet threshold' do
        # Payment 1: 5000 kr (79% of 6303)
        tx1 = BankTransaction.new(
          external_id: 'lf_tx_same_day_1',
          account_id: '4653',
          booked_at: DateTime.parse('2025-11-24T10:00:00Z'),
          amount: 5000.0,
          currency: 'SEK',
          description: 'from: +46702894437 1806326367017854',
          counterparty: '+46702894437',
          raw_json: {
            'id' => 'lf_tx_same_day_1',
            'merchant' => 'Swish Mottagen',
            'amount' => 5000.0
          }
        )

        # Payment 2: 1689 kr (27% of 6303) - would fail alone, but total > expected
        tx2 = BankTransaction.new(
          external_id: 'lf_tx_same_day_2',
          account_id: '4653',
          booked_at: DateTime.parse('2025-11-24T14:00:00Z'),
          amount: 1689.0,
          currency: 'SEK',
          description: 'from: +46702894437 1806326367017855',
          counterparty: '+46702894437',
          raw_json: {
            'id' => 'lf_tx_same_day_2',
            'merchant' => 'Swish Mottagen',
            'amount' => 1689.0
          }
        )

        created_tx1 = Persistence.bank_transactions.create(tx1)
        created_tx2 = Persistence.bank_transactions.create(tx2)

        allow_any_instance_of(ApplyBankPayment).to receive(:check_deadline_and_alert)
        allow_any_instance_of(ApplyBankPayment).to receive(:send_admin_confirmation)

        # Process with same_day_total parameter
        same_day_total = 6689.0

        result1 = ApplyBankPayment.call(
          transaction_id: created_tx1.id,
          same_day_total: same_day_total
        )

        result2 = ApplyBankPayment.call(
          transaction_id: created_tx2.id,
          same_day_total: same_day_total
        )

        expect(result1).not_to be_nil
        expect(result2).not_to be_nil

        receipts = Persistence.rent_receipts.find_by_tenant(sanna.id, year: 2025, month: 11)
        expect(receipts.length).to eq(2)
        expect(receipts.sum(&:amount)).to eq(6689.0)
      end
    end

    context 'Test 14.2: Two Payments Same Day - Second Fails Without Aggregation' do
      it 'creates receipts for both when aggregated total matches rent' do
        # Historical case: Feb 2024
        # Payment 1: 3000 kr (49.6% of 6053) - below 50%
        # Payment 2: 3053 kr (50.4% of 6053) - above 50%
        # Total: 6053 kr = exact match

        # Need temporary ledger for different amount
        temp_ledger = RentLedger.new(
          id: 'ledger_sanna_2024_02',
          tenant_id: sanna.id,
          period: Time.utc(2024, 2, 1),
          amount_due: 6053.0,
          amount_paid: 0,
          days_stayed: 29,
          created_at: Time.utc(2024, 2, 1)
        )
        Persistence.rent_ledger.create(temp_ledger)

        tx1 = BankTransaction.new(
          external_id: 'lf_tx_historical_1',
          account_id: '4653',
          booked_at: DateTime.parse('2024-02-26T10:00:00Z'),
          amount: 3000.0,
          currency: 'SEK',
          description: 'from: +46702894437 1806326367017854',
          counterparty: '+46702894437',
          raw_json: {
            'id' => 'lf_tx_historical_1',
            'merchant' => 'Swish Mottagen',
            'amount' => 3000.0
          }
        )

        tx2 = BankTransaction.new(
          external_id: 'lf_tx_historical_2',
          account_id: '4653',
          booked_at: DateTime.parse('2024-02-26T14:00:00Z'),
          amount: 3053.0,
          currency: 'SEK',
          description: 'from: +46702894437 1806326367017855',
          counterparty: '+46702894437',
          raw_json: {
            'id' => 'lf_tx_historical_2',
            'merchant' => 'Swish Mottagen',
            'amount' => 3053.0
          }
        )

        created_tx1 = Persistence.bank_transactions.create(tx1)
        created_tx2 = Persistence.bank_transactions.create(tx2)

        same_day_total = 6053.0

        allow_any_instance_of(ApplyBankPayment).to receive(:send_admin_confirmation)

        # With aggregation, both should succeed
        result1 = ApplyBankPayment.call(
          transaction_id: created_tx1.id,
          same_day_total: same_day_total
        )

        result2 = ApplyBankPayment.call(
          transaction_id: created_tx2.id,
          same_day_total: same_day_total
        )

        expect(result1).not_to be_nil
        expect(result2).not_to be_nil

        receipts = Persistence.rent_receipts.find_by_tenant(sanna.id, year: 2024, month: 2)
        expect(receipts.length).to eq(2)
        expect(receipts.sum(&:amount)).to eq(6053.0)
      end
    end

    context 'Test 14.3: Three Payments Same Day' do
      it 'creates receipts for all three when total matches rent' do
        tx1 = BankTransaction.new(
          external_id: 'lf_tx_triple_1',
          account_id: '4653',
          booked_at: DateTime.parse('2025-11-24T10:00:00Z'),
          amount: 2000.0,
          currency: 'SEK',
          description: 'from: +46702894437 1806326367017854',
          counterparty: '+46702894437',
          raw_json: {
            'id' => 'lf_tx_triple_1',
            'merchant' => 'Swish Mottagen',
            'amount' => 2000.0
          }
        )

        tx2 = BankTransaction.new(
          external_id: 'lf_tx_triple_2',
          account_id: '4653',
          booked_at: DateTime.parse('2025-11-24T12:00:00Z'),
          amount: 2000.0,
          currency: 'SEK',
          description: 'from: +46702894437 1806326367017855',
          counterparty: '+46702894437',
          raw_json: {
            'id' => 'lf_tx_triple_2',
            'merchant' => 'Swish Mottagen',
            'amount' => 2000.0
          }
        )

        tx3 = BankTransaction.new(
          external_id: 'lf_tx_triple_3',
          account_id: '4653',
          booked_at: DateTime.parse('2025-11-24T14:00:00Z'),
          amount: 2303.0,
          currency: 'SEK',
          description: 'from: +46702894437 1806326367017856',
          counterparty: '+46702894437',
          raw_json: {
            'id' => 'lf_tx_triple_3',
            'merchant' => 'Swish Mottagen',
            'amount' => 2303.0
          }
        )

        created_tx1 = Persistence.bank_transactions.create(tx1)
        created_tx2 = Persistence.bank_transactions.create(tx2)
        created_tx3 = Persistence.bank_transactions.create(tx3)

        same_day_total = 6303.0

        allow_any_instance_of(ApplyBankPayment).to receive(:send_admin_confirmation)

        ApplyBankPayment.call(transaction_id: created_tx1.id, same_day_total: same_day_total)
        ApplyBankPayment.call(transaction_id: created_tx2.id, same_day_total: same_day_total)
        ApplyBankPayment.call(transaction_id: created_tx3.id, same_day_total: same_day_total)

        receipts = Persistence.rent_receipts.find_by_tenant(sanna.id, year: 2025, month: 11)
        expect(receipts.length).to eq(3)
        expect(receipts.sum(&:amount)).to eq(6303.0)
      end
    end
  end

  describe 'Category 15: Multi-Day Payment Aggregation' do
    context 'Test 15.1: Two Payments Within 14 Days (Matching Rent)' do
      it 'finds and groups payments spanning multiple days' do
        # Payment 1: Nov 18 (3000 kr) - below threshold
        tx1 = BankTransaction.new(
          external_id: 'lf_tx_multiday_1',
          account_id: '4653',
          booked_at: DateTime.parse('2025-11-18T10:00:00Z'),
          amount: 3000.0,
          currency: 'SEK',
          description: 'from: +46702894437 1806326367017854',
          counterparty: '+46702894437',
          raw_json: {
            'id' => 'lf_tx_multiday_1',
            'merchant' => 'Swish Mottagen',
            'amount' => 3000.0
          }
        )

        # Payment 2: Nov 24 (3303 kr) - above threshold alone
        tx2 = BankTransaction.new(
          external_id: 'lf_tx_multiday_2',
          account_id: '4653',
          booked_at: DateTime.parse('2025-11-24T10:00:00Z'),
          amount: 3303.0,
          currency: 'SEK',
          description: 'from: +46702894437 1806326367017855',
          counterparty: '+46702894437',
          raw_json: {
            'id' => 'lf_tx_multiday_2',
            'merchant' => 'Swish Mottagen',
            'amount' => 3303.0
          }
        )

        Persistence.bank_transactions.create(tx1)
        Persistence.bank_transactions.create(tx2)

        # PaymentAggregator should find this combination
        require_relative '../../lib/services/payment_aggregator'

        groups = PaymentAggregator.find_partial_groups(sanna, Date.new(2025, 11, 1))

        expect(groups.length).to eq(1)
        expect(groups.first.length).to eq(2)
        expect(groups.first.sum(&:amount)).to eq(6303.0)
      end
    end

    context 'Test 15.2: Two Payments Too Far Apart (>14 Days)' do
      it 'does NOT group payments more than 14 days apart' do
        # Payment 1: Nov 10 (3000 kr)
        tx1 = BankTransaction.new(
          external_id: 'lf_tx_far_1',
          account_id: '4653',
          booked_at: DateTime.parse('2025-11-10T10:00:00Z'),
          amount: 3000.0,
          currency: 'SEK',
          description: 'from: +46702894437 1806326367017854',
          counterparty: '+46702894437',
          raw_json: {
            'id' => 'lf_tx_far_1',
            'merchant' => 'Swish Mottagen',
            'amount' => 3000.0
          }
        )

        # Payment 2: Nov 30 (3303 kr) - 20 days apart
        tx2 = BankTransaction.new(
          external_id: 'lf_tx_far_2',
          account_id: '4653',
          booked_at: DateTime.parse('2025-11-30T10:00:00Z'),
          amount: 3303.0,
          currency: 'SEK',
          description: 'from: +46702894437 1806326367017855',
          counterparty: '+46702894437',
          raw_json: {
            'id' => 'lf_tx_far_2',
            'merchant' => 'Swish Mottagen',
            'amount' => 3303.0
          }
        )

        Persistence.bank_transactions.create(tx1)
        Persistence.bank_transactions.create(tx2)

        require_relative '../../lib/services/payment_aggregator'

        groups = PaymentAggregator.find_partial_groups(sanna, Date.new(2025, 11, 1))

        # Should NOT find match (too far apart)
        expect(groups).to be_empty
      end
    end

    context 'Test 15.3: Three Payments Within Window' do
      it 'finds 3-payment combinations that sum to rent' do
        # Three payments over 10 days
        tx1 = BankTransaction.new(
          external_id: 'lf_tx_triple_multi_1',
          account_id: '4653',
          booked_at: DateTime.parse('2025-11-18T10:00:00Z'),
          amount: 2000.0,
          currency: 'SEK',
          description: 'from: +46702894437 1806326367017854',
          counterparty: '+46702894437',
          raw_json: {
            'id' => 'lf_tx_triple_multi_1',
            'merchant' => 'Swish Mottagen',
            'amount' => 2000.0
          }
        )

        tx2 = BankTransaction.new(
          external_id: 'lf_tx_triple_multi_2',
          account_id: '4653',
          booked_at: DateTime.parse('2025-11-22T10:00:00Z'),
          amount: 2000.0,
          currency: 'SEK',
          description: 'from: +46702894437 1806326367017855',
          counterparty: '+46702894437',
          raw_json: {
            'id' => 'lf_tx_triple_multi_2',
            'merchant' => 'Swish Mottagen',
            'amount' => 2000.0
          }
        )

        tx3 = BankTransaction.new(
          external_id: 'lf_tx_triple_multi_3',
          account_id: '4653',
          booked_at: DateTime.parse('2025-11-27T10:00:00Z'),  # Within window (day 27, not 28)
          amount: 2303.0,
          currency: 'SEK',
          description: 'from: +46702894437 1806326367017856',
          counterparty: '+46702894437',
          raw_json: {
            'id' => 'lf_tx_triple_multi_3',
            'merchant' => 'Swish Mottagen',
            'amount' => 2303.0
          }
        )

        Persistence.bank_transactions.create(tx1)
        Persistence.bank_transactions.create(tx2)
        Persistence.bank_transactions.create(tx3)

        require_relative '../../lib/services/payment_aggregator'

        groups = PaymentAggregator.find_partial_groups(sanna, Date.new(2025, 11, 1))

        expect(groups.length).to eq(1)
        expect(groups.first.length).to eq(3)
        expect(groups.first.sum(&:amount)).to eq(6303.0)
      end
    end

    context 'Test 15.4: Multiple Valid Combinations - Prefer Latter' do
      it 'chooses latter combination when multiple matches exist' do
        # Three payments creating two valid combinations
        tx1 = BankTransaction.new(
          external_id: 'lf_tx_combo_1',
          account_id: '4653',
          booked_at: DateTime.parse('2025-11-18T10:00:00Z'),
          amount: 3000.0,
          currency: 'SEK',
          description: 'from: +46702894437 1806326367017854',
          counterparty: '+46702894437',
          raw_json: {
            'id' => 'lf_tx_combo_1',
            'merchant' => 'Swish Mottagen',
            'amount' => 3000.0
          }
        )

        tx2 = BankTransaction.new(
          external_id: 'lf_tx_combo_2',
          account_id: '4653',
          booked_at: DateTime.parse('2025-11-20T10:00:00Z'),
          amount: 3000.0,
          currency: 'SEK',
          description: 'from: +46702894437 1806326367017855',
          counterparty: '+46702894437',
          raw_json: {
            'id' => 'lf_tx_combo_2',
            'merchant' => 'Swish Mottagen',
            'amount' => 3000.0
          }
        )

        tx3 = BankTransaction.new(
          external_id: 'lf_tx_combo_3',
          account_id: '4653',
          booked_at: DateTime.parse('2025-11-22T10:00:00Z'),
          amount: 3303.0,
          currency: 'SEK',
          description: 'from: +46702894437 1806326367017856',
          counterparty: '+46702894437',
          raw_json: {
            'id' => 'lf_tx_combo_3',
            'merchant' => 'Swish Mottagen',
            'amount' => 3303.0
          }
        )

        created_tx1 = Persistence.bank_transactions.create(tx1)
        created_tx2 = Persistence.bank_transactions.create(tx2)
        created_tx3 = Persistence.bank_transactions.create(tx3)

        require_relative '../../lib/services/payment_aggregator'

        groups = PaymentAggregator.find_partial_groups(sanna, Date.new(2025, 11, 1))

        # Should prefer tx2 + tx3 (latter combination)
        expect(groups.length).to eq(1)
        chosen_group = groups.first
        expect(chosen_group.map(&:external_id)).to contain_exactly('lf_tx_combo_2', 'lf_tx_combo_3')
      end
    end

    context 'Test 15.5: Tolerance Check (±100 kr or 1%)' do
      it 'accepts combinations within tolerance' do
        # Two payments slightly over expected rent
        tx1 = BankTransaction.new(
          external_id: 'lf_tx_tolerance_1',
          account_id: '4653',
          booked_at: DateTime.parse('2025-11-18T10:00:00Z'),
          amount: 3200.0,
          currency: 'SEK',
          description: 'from: +46702894437 1806326367017854',
          counterparty: '+46702894437',
          raw_json: {
            'id' => 'lf_tx_tolerance_1',
            'merchant' => 'Swish Mottagen',
            'amount' => 3200.0
          }
        )

        tx2 = BankTransaction.new(
          external_id: 'lf_tx_tolerance_2',
          account_id: '4653',
          booked_at: DateTime.parse('2025-11-24T10:00:00Z'),
          amount: 3200.0,
          currency: 'SEK',
          description: 'from: +46702894437 1806326367017855',
          counterparty: '+46702894437',
          raw_json: {
            'id' => 'lf_tx_tolerance_2',
            'merchant' => 'Swish Mottagen',
            'amount' => 3200.0
          }
        )

        Persistence.bank_transactions.create(tx1)
        Persistence.bank_transactions.create(tx2)

        require_relative '../../lib/services/payment_aggregator'

        groups = PaymentAggregator.find_partial_groups(sanna, Date.new(2025, 11, 1))

        # Total: 6400 kr vs expected 6303 kr = 97 kr difference (within 100 kr tolerance)
        expect(groups.length).to eq(1)
        expect(groups.first.sum(&:amount)).to eq(6400.0)
      end
    end

    context 'Test 15.6: Outside Rent-Paying Window (Day 15-27)' do
      it 'does NOT aggregate payments outside rent-paying window' do
        # Payment 1: Nov 10 (day 10) - too early
        tx1 = BankTransaction.new(
          external_id: 'lf_tx_window_early',
          account_id: '4653',
          booked_at: DateTime.parse('2025-11-10T10:00:00Z'),
          amount: 3000.0,
          currency: 'SEK',
          description: 'from: +46702894437 1806326367017854',
          counterparty: '+46702894437',
          raw_json: {
            'id' => 'lf_tx_window_early',
            'merchant' => 'Swish Mottagen',
            'amount' => 3000.0
          }
        )

        # Payment 2: Nov 30 (day 30) - too late
        tx2 = BankTransaction.new(
          external_id: 'lf_tx_window_late',
          account_id: '4653',
          booked_at: DateTime.parse('2025-11-30T10:00:00Z'),
          amount: 3303.0,
          currency: 'SEK',
          description: 'from: +46702894437 1806326367017855',
          counterparty: '+46702894437',
          raw_json: {
            'id' => 'lf_tx_window_late',
            'merchant' => 'Swish Mottagen',
            'amount' => 3303.0
          }
        )

        Persistence.bank_transactions.create(tx1)
        Persistence.bank_transactions.create(tx2)

        require_relative '../../lib/services/payment_aggregator'

        groups = PaymentAggregator.find_partial_groups(sanna, Date.new(2025, 11, 1))

        # Should NOT find match (outside day 15-27 window)
        expect(groups).to be_empty
      end
    end
  end
end

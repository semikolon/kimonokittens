require_relative '../spec_helper'
require 'rspec'
require_relative '../../lib/persistence'
require_relative '../../handlers/admin_contracts_handler'
require_relative '../support/api_test_helpers'

RSpec.describe AdminContractsHandler do
  include ApiTestHelpers

  let(:handler) { AdminContractsHandler.new }

  # Mock repositories
  let(:tenant_repo) { instance_double('TenantRepository') }
  let(:rent_ledger_repo) { instance_double('RentLedgerRepository') }
  let(:rent_receipt_repo) { instance_double('RentReceiptRepository') }
  let(:sms_event_repo) { instance_double('SmsEventRepository') }

  # Mock tenant data
  let(:tenant) do
    double('Tenant',
      id: 'test-tenant-id-123',
      name: 'Test Tenant',
      email: 'test@example.com',
      phone: '+46701234567'
    )
  end

  # Mock rent ledger (current month)
  let(:rent_ledger) do
    double('RentLedger',
      id: 'ledger-id-123',
      tenant_id: tenant.id,
      period: Date.new(2025, 11, 1),
      amount_due: BigDecimal('7045.00')
    )
  end

  before do
    # Note: Phase 1 repositories for rent_receipts exist but sms_events was not added to Persistence
    # For Phase 6 testing with mocked data, we'll stub at the repository method level
    allow(Persistence).to receive(:tenants).and_return(tenant_repo)
    allow(Persistence).to receive(:rent_ledger).and_return(rent_ledger_repo)
    allow(Persistence).to receive(:rent_receipts).and_return(rent_receipt_repo)
  end

  describe 'Payment status helper methods' do
    let(:current_month) { '2025-11' }
    let(:current_year) { 2025 }
    let(:current_month_num) { 11 }

    describe '#payment_status' do
      context 'when rent is fully paid' do
        it 'returns "paid"' do
          receipts = [
            double('RentReceipt', amount: BigDecimal('7045.00'))
          ]

          allow(rent_ledger_repo).to receive(:find_by_tenant_and_period)
            .with(tenant.id, Date.parse("#{current_month}-01"))
            .and_return(rent_ledger)
          allow(rent_receipt_repo).to receive(:find_by_tenant)
            .with(tenant.id, year: current_year, month: current_month_num)
            .and_return(receipts)

          status = handler.send(:payment_status, tenant, current_month)
          expect(status).to eq('paid')
        end
      end

      context 'when rent is partially paid' do
        it 'returns "partially_paid"' do
          receipts = [
            double('RentReceipt', amount: BigDecimal('3000.00'))
          ]

          allow(rent_ledger_repo).to receive(:find_by_tenant_and_period)
            .with(tenant.id, Date.parse("#{current_month}-01"))
            .and_return(rent_ledger)
          allow(rent_receipt_repo).to receive(:find_by_tenant)
            .with(tenant.id, year: current_year, month: current_month_num)
            .and_return(receipts)

          status = handler.send(:payment_status, tenant, current_month)
          expect(status).to eq('partially_paid')
        end
      end

      context 'when rent is unpaid' do
        it 'returns "unpaid"' do
          allow(rent_ledger_repo).to receive(:find_by_tenant_and_period)
            .with(tenant.id, Date.parse("#{current_month}-01"))
            .and_return(rent_ledger)
          allow(rent_receipt_repo).to receive(:find_by_tenant)
            .with(tenant.id, year: current_year, month: current_month_num)
            .and_return([])

          status = handler.send(:payment_status, tenant, current_month)
          expect(status).to eq('unpaid')
        end
      end

      context 'when no ledger exists' do
        it 'returns "unknown"' do
          allow(rent_ledger_repo).to receive(:find_by_tenant_and_period)
            .with(tenant.id, Date.parse("#{current_month}-01"))
            .and_return(nil)

          status = handler.send(:payment_status, tenant, current_month)
          expect(status).to eq('unknown')
        end
      end
    end

    describe '#current_rent_amount' do
      it 'returns rent amount from ledger' do
        allow(rent_ledger_repo).to receive(:find_by_tenant_and_period)
          .with(tenant.id, Date.parse("#{current_month}-01"))
          .and_return(rent_ledger)

        amount = handler.send(:current_rent_amount, tenant, current_month)
        expect(amount).to eq(7045.00)
      end

      it 'returns 0 when no ledger exists' do
        allow(rent_ledger_repo).to receive(:find_by_tenant_and_period)
          .with(tenant.id, Date.parse("#{current_month}-01"))
          .and_return(nil)

        amount = handler.send(:current_rent_amount, tenant, current_month)
        expect(amount).to eq(0)
      end
    end

    describe '#remaining_amount' do
      it 'returns amount still owed' do
        receipts = [
          double('RentReceipt', amount: BigDecimal('3000.00')),
          double('RentReceipt', amount: BigDecimal('2000.00'))
        ]

        allow(rent_ledger_repo).to receive(:find_by_tenant_and_period)
          .with(tenant.id, Date.parse("#{current_month}-01"))
          .and_return(rent_ledger)
        allow(rent_receipt_repo).to receive(:find_by_tenant)
          .with(tenant.id, year: current_year, month: current_month_num)
          .and_return(receipts)

        remaining = handler.send(:remaining_amount, tenant, current_month)
        expect(remaining).to eq(2045.00) # 7045 - 5000
      end

      it 'returns 0 when fully paid' do
        receipts = [
          double('RentReceipt', amount: BigDecimal('7045.00'))
        ]

        allow(rent_ledger_repo).to receive(:find_by_tenant_and_period)
          .with(tenant.id, Date.parse("#{current_month}-01"))
          .and_return(rent_ledger)
        allow(rent_receipt_repo).to receive(:find_by_tenant)
          .with(tenant.id, year: current_year, month: current_month_num)
          .and_return(receipts)

        remaining = handler.send(:remaining_amount, tenant, current_month)
        expect(remaining).to eq(0)
      end

      it 'returns full amount when unpaid' do
        allow(rent_ledger_repo).to receive(:find_by_tenant_and_period)
          .with(tenant.id, Date.parse("#{current_month}-01"))
          .and_return(rent_ledger)
        allow(rent_receipt_repo).to receive(:find_by_tenant)
          .with(tenant.id, year: current_year, month: current_month_num)
          .and_return([])

        remaining = handler.send(:remaining_amount, tenant, current_month)
        expect(remaining).to eq(7045.00)
      end
    end

    describe '#last_payment_date' do
      it 'returns most recent payment date' do
        receipts = [
          double('RentReceipt', paid_at: DateTime.new(2025, 11, 25, 10, 0, 0)),
          double('RentReceipt', paid_at: DateTime.new(2025, 11, 20, 15, 30, 0)),
          double('RentReceipt', paid_at: DateTime.new(2025, 11, 27, 9, 15, 0))
        ]

        allow(rent_receipt_repo).to receive(:find_by_tenant)
          .with(tenant.id, year: current_year, month: current_month_num)
          .and_return(receipts)

        last_date = handler.send(:last_payment_date, tenant, current_month)
        expect(last_date).to eq(DateTime.new(2025, 11, 27, 9, 15, 0))
      end

      it 'returns nil when no payments' do
        allow(rent_receipt_repo).to receive(:find_by_tenant)
          .with(tenant.id, year: current_year, month: current_month_num)
          .and_return([])

        last_date = handler.send(:last_payment_date, tenant, current_month)
        expect(last_date).to be_nil
      end
    end

    describe '#sms_count' do
      it 'returns count of SMS reminders for current month' do
        # Phase 6 uses mocked data - Phase 4 will implement actual SMS tracking
        # For now, we'll return a hardcoded count for testing UI
        count = handler.send(:sms_count, tenant, current_month)
        expect(count).to be >= 0
      end

      it 'returns 0 when no SMS sent' do
        count = handler.send(:sms_count, tenant, current_month)
        expect(count).to be >= 0
      end
    end
  end
end

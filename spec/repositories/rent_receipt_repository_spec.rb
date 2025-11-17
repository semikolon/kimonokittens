require_relative '../spec_helper'
require_relative '../../lib/repositories/rent_receipt_repository'
require_relative '../../lib/models/rent_receipt'
require_relative '../rent_calculator/support/test_helpers'

RSpec.describe RentReceiptRepository do
  include RentCalculatorSpec::TestHelpers
  let(:repo) { described_class.new }
  let(:db) { RentDb.instance }

  # Helper to create a test tenant
  def create_test_tenant(id:, name: 'Test Tenant')
    db.class.db[:Tenant].insert(
      id: id,
      name: name,
      email: "#{id}@test.com",
      createdAt: Time.now.utc,
      updatedAt: Time.now.utc
    )
  end

  before do
    clean_database
  end

  describe '#create' do
    it 'persists a new rent receipt' do
      create_test_tenant(id: 'tenant_123')

      receipt = RentReceipt.new(
        tenant_id: 'tenant_123',
        month: '2025-11',
        amount: 7045.0,
        paid_at: Time.utc(2025, 11, 25, 10, 30),
        matched_via: 'reference'
      )

      created_receipt = repo.create(receipt)

      expect(created_receipt.id).not_to be_nil
      expect(created_receipt.tenant_id).to eq('tenant_123')
      expect(created_receipt.month).to eq('2025-11')
      expect(created_receipt.amount).to eq(7045.0)
      expect(created_receipt.matched_via).to eq('reference')
    end

    it 'generates CUID for new receipts' do
      create_test_tenant(id: 'tenant_123')

      receipt = RentReceipt.new(
        tenant_id: 'tenant_123',
        month: '2025-11',
        amount: 7045.0,
        paid_at: Time.now,
        matched_via: 'reference'
      )

      created_receipt = repo.create(receipt)

      expect(created_receipt.id).to match(/^c[a-z0-9]{24}$/)
    end
  end

  describe '#find_by_id' do
    it 'retrieves a receipt by ID' do
      create_test_tenant(id: 'tenant_123')

      receipt = repo.create(RentReceipt.new(
        tenant_id: 'tenant_123',
        month: '2025-11',
        amount: 7045.0,
        paid_at: Time.now,
        matched_via: 'reference'
      ))

      found_receipt = repo.find_by_id(receipt.id)

      expect(found_receipt.id).to eq(receipt.id)
      expect(found_receipt.tenant_id).to eq('tenant_123')
    end

    it 'returns nil for non-existent ID' do
      result = repo.find_by_id('non_existent_id')

      expect(result).to be_nil
    end
  end

  describe '#find_by_tenant' do
    it 'retrieves receipts for a tenant in specific month' do
      tenant_id = 'tenant_123'
      create_test_tenant(id: tenant_id)
      create_test_tenant(id: 'tenant_789')

      # Receipts for Nov 2025
      receipt1 = repo.create(RentReceipt.new(
        tenant_id: tenant_id,
        month: '2025-11',
        amount: 3000.0,
        paid_at: Time.utc(2025, 11, 20),
        matched_via: 'reference',
        partial: true
      ))

      receipt2 = repo.create(RentReceipt.new(
        tenant_id: tenant_id,
        month: '2025-11',
        amount: 4045.0,
        paid_at: Time.utc(2025, 11, 25),
        matched_via: 'amount+name'
      ))

      # Different month (Oct 2025)
      repo.create(RentReceipt.new(
        tenant_id: tenant_id,
        month: '2025-10',
        amount: 7000.0,
        paid_at: Time.utc(2025, 10, 25),
        matched_via: 'reference'
      ))

      # Different tenant
      repo.create(RentReceipt.new(
        tenant_id: 'tenant_789',
        month: '2025-11',
        amount: 5000.0,
        paid_at: Time.utc(2025, 11, 25),
        matched_via: 'reference'
      ))

      receipts = repo.find_by_tenant(tenant_id, year: 2025, month: 11)

      expect(receipts.length).to eq(2)
      expect(receipts.map(&:id)).to contain_exactly(receipt1.id, receipt2.id)
    end

    it 'returns empty array when no receipts exist for tenant/month' do
      receipts = repo.find_by_tenant('tenant_123', year: 2025, month: 12)

      expect(receipts).to eq([])
    end
  end

  describe '#total_paid_for_tenant_month' do
    it 'calculates sum of all receipts for tenant/month' do
      tenant_id = 'tenant_123'
      create_test_tenant(id: tenant_id)

      repo.create(RentReceipt.new(
        tenant_id: tenant_id,
        month: '2025-11',
        amount: 3000.0,
        paid_at: Time.now,
        matched_via: 'reference',
        partial: true
      ))

      repo.create(RentReceipt.new(
        tenant_id: tenant_id,
        month: '2025-11',
        amount: 4045.0,
        paid_at: Time.now,
        matched_via: 'amount+name'
      ))

      total = repo.total_paid_for_tenant_month(tenant_id, year: 2025, month: 11)

      expect(total).to be_within(0.01).of(7045.0)
    end

    it 'returns 0 when no receipts exist for tenant/month' do
      total = repo.total_paid_for_tenant_month('tenant_123', year: 2025, month: 12)

      expect(total).to eq(0)
    end
  end

  describe '#all' do
    it 'retrieves all receipts ordered by paid_at descending' do
      create_test_tenant(id: 'tenant_123')
      create_test_tenant(id: 'tenant_789')

      old_receipt = repo.create(RentReceipt.new(
        tenant_id: 'tenant_123',
        month: '2025-11',
        amount: 7000.0,
        paid_at: Time.utc(2025, 11, 20),
        matched_via: 'reference'
      ))

      new_receipt = repo.create(RentReceipt.new(
        tenant_id: 'tenant_789',
        month: '2025-11',
        amount: 7045.0,
        paid_at: Time.utc(2025, 11, 25),
        matched_via: 'reference'
      ))

      receipts = repo.all

      expect(receipts.length).to eq(2)
      expect(receipts.first.id).to eq(new_receipt.id)  # Most recent first
      expect(receipts.last.id).to eq(old_receipt.id)
    end
  end

  describe '#delete' do
    it 'removes a receipt by ID' do
      create_test_tenant(id: 'tenant_123')

      receipt = repo.create(RentReceipt.new(
        tenant_id: 'tenant_123',
        month: '2025-11',
        amount: 7045.0,
        paid_at: Time.now,
        matched_via: 'reference'
      ))

      result = repo.delete(receipt.id)

      expect(result).to be true
      expect(repo.find_by_id(receipt.id)).to be_nil
    end

    it 'returns false for non-existent ID' do
      result = repo.delete('non_existent_id')

      expect(result).to be false
    end
  end
end

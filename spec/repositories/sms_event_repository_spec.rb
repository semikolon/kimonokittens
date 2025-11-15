require_relative '../spec_helper'
require_relative '../../lib/repositories/sms_event_repository'
require_relative '../../lib/models/sms_event'
require_relative '../../lib/rent_db'

RSpec.describe SmsEventRepository do
  let(:repo) { described_class.new }
  let(:db) { RentDb.instance }

  # Helper to create test tenants (required for foreign key constraints)
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
    # Clean up any existing SMS events and tenants
    repo.dataset.delete
    db.class.db[:Tenant].delete
  end

  describe '#find_by_id' do
    it 'returns nil when event not found' do
      expect(repo.find_by_id('nonexistent')).to be_nil
    end

    it 'returns event when found' do
      event = SmsEvent.new(
        phone_number: '+46701234567',
        message_body: 'Test message',
        sms_type: 'reminder',
        tone: 'neutral',
        delivery_status: 'sent',
        sent_at: Time.now
      )

      created = repo.save(event)
      found = repo.find_by_id(created.id)

      expect(found).not_to be_nil
      expect(found.phone_number).to eq('+46701234567')
      expect(found.message_body).to eq('Test message')
    end
  end

  describe '#find_by_tenant' do
    it 'returns events for specific tenant' do
      tenant_id = 'tenant_123'

      # Create test tenants
      create_test_tenant(id: tenant_id)
      create_test_tenant(id: 'other_tenant', name: 'Other Tenant')

      # Create events for tenant
      event1 = repo.save(SmsEvent.new(
        tenant_id: tenant_id,
        phone_number: '+46701234567',
        message_body: 'First message',
        sms_type: 'reminder',
        tone: 'neutral',
        delivery_status: 'sent',
        sent_at: Time.now - 3600
      ))

      event2 = repo.save(SmsEvent.new(
        tenant_id: tenant_id,
        phone_number: '+46701234567',
        message_body: 'Second message',
        sms_type: 'reminder',
        tone: 'friendly',
        delivery_status: 'delivered',
        sent_at: Time.now
      ))

      # Create event for different tenant
      repo.save(SmsEvent.new(
        tenant_id: 'other_tenant',
        phone_number: '+46709999999',
        message_body: 'Other message',
        sms_type: 'reminder',
        tone: 'neutral',
        delivery_status: 'sent',
        sent_at: Time.now
      ))

      results = repo.find_by_tenant(tenant_id)

      expect(results.length).to eq(2)
      expect(results.map(&:id)).to contain_exactly(event1.id, event2.id)
    end

    it 'limits results when limit parameter provided' do
      tenant_id = 'tenant_123'
      create_test_tenant(id: tenant_id)

      # Create 3 events
      3.times do |i|
        repo.save(SmsEvent.new(
          tenant_id: tenant_id,
          phone_number: '+46701234567',
          message_body: "Message #{i}",
          sms_type: 'reminder',
          tone: 'neutral',
          delivery_status: 'sent',
          sent_at: Time.now - (i * 60)
        ))
      end

      results = repo.find_by_tenant(tenant_id, limit: 2)

      expect(results.length).to eq(2)
    end

    it 'orders by sent_at descending (most recent first)' do
      tenant_id = 'tenant_123'
      create_test_tenant(id: tenant_id)

      first = repo.save(SmsEvent.new(
        tenant_id: tenant_id,
        phone_number: '+46701234567',
        message_body: 'First',
        sms_type: 'reminder',
        tone: 'neutral',
        delivery_status: 'sent',
        sent_at: Time.now - 7200
      ))

      second = repo.save(SmsEvent.new(
        tenant_id: tenant_id,
        phone_number: '+46701234567',
        message_body: 'Second',
        sms_type: 'reminder',
        tone: 'neutral',
        delivery_status: 'sent',
        sent_at: Time.now
      ))

      results = repo.find_by_tenant(tenant_id)

      expect(results.first.id).to eq(second.id)
      expect(results.last.id).to eq(first.id)
    end
  end

  describe '#find_failed' do
    it 'returns only failed SMS events' do
      failed = repo.save(SmsEvent.new(
        phone_number: '+46701234567',
        message_body: 'Failed message',
        sms_type: 'reminder',
        tone: 'neutral',
        delivery_status: 'failed',
        sent_at: Time.now,
        failure_reason: 'Invalid number'
      ))

      repo.save(SmsEvent.new(
        phone_number: '+46701234567',
        message_body: 'Delivered message',
        sms_type: 'reminder',
        tone: 'neutral',
        delivery_status: 'delivered',
        sent_at: Time.now
      ))

      results = repo.find_failed

      expect(results.length).to eq(1)
      expect(results.first.id).to eq(failed.id)
      expect(results.first.failed?).to be true
    end

    it 'limits results when limit parameter provided' do
      3.times do |i|
        repo.save(SmsEvent.new(
          phone_number: '+46701234567',
          message_body: "Failed #{i}",
          sms_type: 'reminder',
          tone: 'neutral',
          delivery_status: 'failed',
          sent_at: Time.now - (i * 60),
          failure_reason: 'Error'
        ))
      end

      results = repo.find_failed(limit: 2)

      expect(results.length).to eq(2)
    end
  end

  describe '#find_by_elks_message_id' do
    it 'returns nil when message ID not found' do
      expect(repo.find_by_elks_message_id('s999abc')).to be_nil
    end

    it 'returns event when message ID found' do
      event = repo.save(SmsEvent.new(
        phone_number: '+46701234567',
        message_body: 'Test',
        sms_type: 'reminder',
        tone: 'neutral',
        delivery_status: 'sent',
        sent_at: Time.now,
        elks_message_id: 's123abc'
      ))

      found = repo.find_by_elks_message_id('s123abc')

      expect(found).not_to be_nil
      expect(found.id).to eq(event.id)
      expect(found.elks_message_id).to eq('s123abc')
    end
  end

  describe '#save' do
    it 'creates new event with generated ID' do
      event = SmsEvent.new(
        phone_number: '+46701234567',
        message_body: 'Test',
        sms_type: 'reminder',
        tone: 'neutral',
        delivery_status: 'queued',
        sent_at: Time.now
      )

      saved = repo.save(event)

      expect(saved.id).not_to be_nil
      expect(saved.phone_number).to eq('+46701234567')
      expect(saved.created_at).not_to be_nil
    end

    it 'preserves all fields' do
      create_test_tenant(id: 'tenant_123')
      sent_time = Time.now - 3600
      delivered_time = Time.now

      event = SmsEvent.new(
        tenant_id: 'tenant_123',
        phone_number: '+46701234567',
        message_body: 'Test message',
        sms_type: 'reminder',
        tone: 'friendly',
        delivery_status: 'delivered',
        elks_message_id: 's123abc',
        cost: 6500,
        sent_at: sent_time,
        delivered_at: delivered_time,
        failure_reason: nil
      )

      saved = repo.save(event)

      expect(saved.tenant_id).to eq('tenant_123')
      expect(saved.elks_message_id).to eq('s123abc')
      expect(saved.cost).to eq(6500)
      expect(saved.sent_at.to_i).to eq(sent_time.to_i)
      expect(saved.delivered_at.to_i).to eq(delivered_time.to_i)
    end
  end

  describe '#update_delivery_status' do
    it 'updates status and timestamps' do
      event = repo.save(SmsEvent.new(
        phone_number: '+46701234567',
        message_body: 'Test',
        sms_type: 'reminder',
        tone: 'neutral',
        delivery_status: 'sent',
        sent_at: Time.now
      ))

      delivered_time = Time.now + 60

      repo.update_delivery_status(
        event.id,
        status: 'delivered',
        delivered_at: delivered_time
      )

      updated = repo.find_by_id(event.id)

      expect(updated.delivery_status).to eq('delivered')
      expect(updated.delivered_at.to_i).to eq(delivered_time.to_i)
    end

    it 'updates failure status with reason' do
      event = repo.save(SmsEvent.new(
        phone_number: '+46701234567',
        message_body: 'Test',
        sms_type: 'reminder',
        tone: 'neutral',
        delivery_status: 'sent',
        sent_at: Time.now
      ))

      repo.update_delivery_status(
        event.id,
        status: 'failed',
        failure_reason: 'Invalid phone number'
      )

      updated = repo.find_by_id(event.id)

      expect(updated.delivery_status).to eq('failed')
      expect(updated.failure_reason).to eq('Invalid phone number')
    end
  end

  describe '#total_cost_for_period' do
    it 'sums costs for events within date range' do
      base_time = Time.new(2025, 11, 15, 12, 0, 0)

      # Event within period (cost: 0.65 SEK)
      repo.save(SmsEvent.new(
        phone_number: '+46701234567',
        message_body: 'Test 1',
        sms_type: 'reminder',
        tone: 'neutral',
        delivery_status: 'delivered',
        sent_at: base_time,
        cost: 6500
      ))

      # Event within period (cost: 0.50 SEK)
      repo.save(SmsEvent.new(
        phone_number: '+46701234567',
        message_body: 'Test 2',
        sms_type: 'admin_alert',
        tone: 'neutral',
        delivery_status: 'delivered',
        sent_at: base_time + 3600,
        cost: 5000
      ))

      # Event outside period
      repo.save(SmsEvent.new(
        phone_number: '+46701234567',
        message_body: 'Test 3',
        sms_type: 'reminder',
        tone: 'neutral',
        delivery_status: 'delivered',
        sent_at: base_time - 86400,
        cost: 10000
      ))

      start_date = base_time - 60
      end_date = base_time + 7200

      total = repo.total_cost_for_period(start_date: start_date, end_date: end_date)

      # 6500 + 5000 = 11500 (1.15 SEK)
      expect(total).to eq(11500)
    end

    it 'handles nil costs by treating as zero' do
      base_time = Time.now

      repo.save(SmsEvent.new(
        phone_number: '+46701234567',
        message_body: 'Test',
        sms_type: 'reminder',
        tone: 'neutral',
        delivery_status: 'queued',
        sent_at: base_time,
        cost: nil
      ))

      total = repo.total_cost_for_period(
        start_date: base_time - 60,
        end_date: base_time + 60
      )

      expect(total).to eq(0)
    end

    it 'returns 0 when no events in period' do
      total = repo.total_cost_for_period(
        start_date: Time.now - 86400,
        end_date: Time.now
      )

      expect(total).to eq(0)
    end
  end
end

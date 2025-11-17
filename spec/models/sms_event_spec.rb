require_relative '../spec_helper'
require_relative '../../lib/models/sms_event'

RSpec.describe SmsEvent do
  describe '#initialize' do
    it 'creates a valid SMS event with required fields' do
      event = described_class.new(
        phone_number: '+46701234567',
        message_body: 'Test message',
        sms_type: 'reminder',
        tone: 'neutral',
        delivery_status: 'queued',
        sent_at: Time.now
      )

      expect(event.phone_number).to eq('+46701234567')
      expect(event.message_body).to eq('Test message')
      expect(event.sms_type).to eq('reminder')
      expect(event.tone).to eq('neutral')
      expect(event.delivery_status).to eq('queued')
    end

    it 'accepts optional tenant_id' do
      event = described_class.new(
        tenant_id: 'tenant_123',
        phone_number: '+46701234567',
        message_body: 'Test',
        sms_type: 'reminder',
        tone: 'neutral',
        delivery_status: 'queued',
        sent_at: Time.now
      )

      expect(event.tenant_id).to eq('tenant_123')
    end

    it 'accepts optional elks_message_id' do
      event = described_class.new(
        phone_number: '+46701234567',
        message_body: 'Test',
        sms_type: 'reminder',
        tone: 'neutral',
        delivery_status: 'sent',
        sent_at: Time.now,
        elks_message_id: 's123abc'
      )

      expect(event.elks_message_id).to eq('s123abc')
    end

    it 'accepts optional cost in 10,000ths' do
      event = described_class.new(
        phone_number: '+46701234567',
        message_body: 'Test',
        sms_type: 'reminder',
        tone: 'neutral',
        delivery_status: 'sent',
        sent_at: Time.now,
        cost: 6500 # 0.65 SEK
      )

      expect(event.cost).to eq(6500)
    end

    it 'accepts optional delivered_at timestamp' do
      delivered_time = Time.now
      event = described_class.new(
        phone_number: '+46701234567',
        message_body: 'Test',
        sms_type: 'reminder',
        tone: 'neutral',
        delivery_status: 'delivered',
        sent_at: Time.now - 60,
        delivered_at: delivered_time
      )

      expect(event.delivered_at).to eq(delivered_time)
    end

    it 'accepts optional failure_reason' do
      event = described_class.new(
        phone_number: '+46701234567',
        message_body: 'Test',
        sms_type: 'reminder',
        tone: 'neutral',
        delivery_status: 'failed',
        sent_at: Time.now,
        failure_reason: 'Invalid phone number'
      )

      expect(event.failure_reason).to eq('Invalid phone number')
    end
  end

  describe 'validations' do
    it 'rejects invalid phone number format' do
      expect {
        described_class.new(
          phone_number: '0701234567', # Missing +46
          message_body: 'Test',
          sms_type: 'reminder',
          tone: 'neutral',
          delivery_status: 'queued',
          sent_at: Time.now
        )
      }.to raise_error(ArgumentError, /phone number must be E\.164 format/)
    end

    it 'rejects invalid SMS type' do
      expect {
        described_class.new(
          phone_number: '+46701234567',
          message_body: 'Test',
          sms_type: 'invalid_type',
          tone: 'neutral',
          delivery_status: 'queued',
          sent_at: Time.now
        )
      }.to raise_error(ArgumentError, /sms_type must be one of/)
    end

    it 'rejects invalid tone' do
      expect {
        described_class.new(
          phone_number: '+46701234567',
          message_body: 'Test',
          sms_type: 'reminder',
          tone: 'invalid_tone',
          delivery_status: 'queued',
          sent_at: Time.now
        )
      }.to raise_error(ArgumentError, /tone must be one of/)
    end

    it 'rejects invalid delivery status' do
      expect {
        described_class.new(
          phone_number: '+46701234567',
          message_body: 'Test',
          sms_type: 'reminder',
          tone: 'neutral',
          delivery_status: 'invalid_status',
          sent_at: Time.now
        )
      }.to raise_error(ArgumentError, /delivery_status must be one of/)
    end

    it 'rejects empty message body' do
      expect {
        described_class.new(
          phone_number: '+46701234567',
          message_body: '',
          sms_type: 'reminder',
          tone: 'neutral',
          delivery_status: 'queued',
          sent_at: Time.now
        )
      }.to raise_error(ArgumentError, /message_body cannot be empty/)
    end

    it 'rejects missing sent_at' do
      expect {
        described_class.new(
          phone_number: '+46701234567',
          message_body: 'Test',
          sms_type: 'reminder',
          tone: 'neutral',
          delivery_status: 'queued',
          sent_at: nil
        )
      }.to raise_error(ArgumentError, /sent_at is required/)
    end
  end

  describe '#delivered?' do
    it 'returns true when delivery_status is delivered' do
      event = described_class.new(
        phone_number: '+46701234567',
        message_body: 'Test',
        sms_type: 'reminder',
        tone: 'neutral',
        delivery_status: 'delivered',
        sent_at: Time.now
      )

      expect(event.delivered?).to be true
    end

    it 'returns false when delivery_status is not delivered' do
      event = described_class.new(
        phone_number: '+46701234567',
        message_body: 'Test',
        sms_type: 'reminder',
        tone: 'neutral',
        delivery_status: 'sent',
        sent_at: Time.now
      )

      expect(event.delivered?).to be false
    end
  end

  describe '#failed?' do
    it 'returns true when delivery_status is failed' do
      event = described_class.new(
        phone_number: '+46701234567',
        message_body: 'Test',
        sms_type: 'reminder',
        tone: 'neutral',
        delivery_status: 'failed',
        sent_at: Time.now
      )

      expect(event.failed?).to be true
    end

    it 'returns false when delivery_status is not failed' do
      event = described_class.new(
        phone_number: '+46701234567',
        message_body: 'Test',
        sms_type: 'reminder',
        tone: 'neutral',
        delivery_status: 'delivered',
        sent_at: Time.now
      )

      expect(event.failed?).to be false
    end
  end

  describe '#reminder?' do
    it 'returns true when sms_type is reminder' do
      event = described_class.new(
        phone_number: '+46701234567',
        message_body: 'Test',
        sms_type: 'reminder',
        tone: 'neutral',
        delivery_status: 'queued',
        sent_at: Time.now
      )

      expect(event.reminder?).to be true
    end

    it 'returns false when sms_type is not reminder' do
      event = described_class.new(
        phone_number: '+46701234567',
        message_body: 'Test',
        sms_type: 'admin_alert',
        tone: 'neutral',
        delivery_status: 'queued',
        sent_at: Time.now
      )

      expect(event.reminder?).to be false
    end
  end

  describe '#admin_alert?' do
    it 'returns true when sms_type is admin_alert' do
      event = described_class.new(
        phone_number: '+46701234567',
        message_body: 'Test',
        sms_type: 'admin_alert',
        tone: 'neutral',
        delivery_status: 'queued',
        sent_at: Time.now
      )

      expect(event.admin_alert?).to be true
    end

    it 'returns false when sms_type is not admin_alert' do
      event = described_class.new(
        phone_number: '+46701234567',
        message_body: 'Test',
        sms_type: 'reminder',
        tone: 'neutral',
        delivery_status: 'queued',
        sent_at: Time.now
      )

      expect(event.admin_alert?).to be false
    end
  end

  describe '#cost_in_sek' do
    it 'converts cost from 10,000ths to SEK' do
      event = described_class.new(
        phone_number: '+46701234567',
        message_body: 'Test',
        sms_type: 'reminder',
        tone: 'neutral',
        delivery_status: 'sent',
        sent_at: Time.now,
        cost: 6500 # 0.65 SEK
      )

      expect(event.cost_in_sek).to eq(0.65)
    end

    it 'returns 0.0 when cost is nil' do
      event = described_class.new(
        phone_number: '+46701234567',
        message_body: 'Test',
        sms_type: 'reminder',
        tone: 'neutral',
        delivery_status: 'queued',
        sent_at: Time.now,
        cost: nil
      )

      expect(event.cost_in_sek).to eq(0.0)
    end

    it 'handles whole SEK amounts' do
      event = described_class.new(
        phone_number: '+46701234567',
        message_body: 'Test',
        sms_type: 'reminder',
        tone: 'neutral',
        delivery_status: 'sent',
        sent_at: Time.now,
        cost: 10000 # 1.00 SEK
      )

      expect(event.cost_in_sek).to eq(1.0)
    end
  end
end

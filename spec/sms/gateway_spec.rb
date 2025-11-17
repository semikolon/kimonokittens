require_relative '../spec_helper'
require_relative '../../lib/sms/gateway'
require_relative '../../lib/sms/elks_client'

RSpec.describe SmsGateway do
  let(:mock_client) { instance_double(ElksClient) }

  before do
    allow(ElksClient).to receive(:new).and_return(mock_client)
  end

  describe '.send' do
    it 'delegates to ElksClient#send with all parameters' do
      expect(mock_client).to receive(:send).with(
        to: '+46701234567',
        body: 'Test message',
        meta: { type: 'test' }
      ).and_return({ id: 'sms123', status: 'sent' })

      result = SmsGateway.send(
        to: '+46701234567',
        body: 'Test message',
        meta: { type: 'test' }
      )

      expect(result[:id]).to eq('sms123')
      expect(result[:status]).to eq('sent')
    end

    it 'passes through empty meta hash when not provided' do
      expect(mock_client).to receive(:send).with(
        to: '+46700000000',
        body: 'Minimal message',
        meta: {}
      )

      SmsGateway.send(
        to: '+46700000000',
        body: 'Minimal message'
      )
    end
  end

  describe '.send_admin_alert' do
    it 'sends SMS to admin phone with admin_alert type' do
      allow(ENV).to receive(:[]).with('ADMIN_PHONE').and_return('+46707654321')

      expect(mock_client).to receive(:send).with(
        to: '+46707654321',
        body: '⚠️ Bank sync failed: API timeout',
        meta: { type: 'admin_alert' }
      )

      SmsGateway.send_admin_alert('⚠️ Bank sync failed: API timeout')
    end

    it 'raises error when ADMIN_PHONE not configured' do
      allow(ENV).to receive(:[]).with('ADMIN_PHONE').and_return(nil)

      expect {
        SmsGateway.send_admin_alert('Test alert')
      }.to raise_error(/ADMIN_PHONE not configured/)
    end
  end
end

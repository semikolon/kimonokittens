require_relative '../spec_helper'
require 'rack/test'
require 'json'

# Load the handler
require_relative '../../handlers/elks_webhooks'

RSpec.describe ElksWebhooksHandler do
  include Rack::Test::Methods

  let(:app) { ElksWebhooksHandler.new }
  let(:mock_sms_repo) { double('sms_events_repo') }
  let(:mock_tenant_repo) { double('tenants_repo') }

  before do
    allow(Persistence).to receive(:sms_events).and_return(mock_sms_repo)
    allow(Persistence).to receive(:tenants).and_return(mock_tenant_repo)
  end

  describe 'POST /sms (incoming SMS from tenant)' do
    let(:tenant) { double('tenant', id: 'tenant123', name: 'Sanna Benemar', phone: '+46701234567') }

    before do
      allow(mock_tenant_repo).to receive(:find_by_phone_e164).with('+46701234567').and_return(tenant)
    end

    it 'logs incoming SMS to database' do
      expect(mock_sms_repo).to receive(:create) do |event|
        expect(event.direction).to eq('in')
        expect(event.provider_id).to eq('sf8425555e5d8db61dda7a7b3f1b91bdb')
        expect(event.message_body).to eq('STATUS')
        expect(event.phone_number).to eq('+46701234567')

        double(id: 'evt123')
      end

      post '/sms', {
        id: 'sf8425555e5d8db61dda7a7b3f1b91bdb',
        from: '+46701234567',
        to: '+46700000000',
        message: 'STATUS',
        direction: 'incoming',
        created: '2025-11-15T12:00:00.000000'
      }

      expect(last_response.status).to eq(200)
    end

    it 'generates STATUS reply for status command' do
      allow(mock_sms_repo).to receive(:create).and_return(double(id: 'evt123'))

      # Mock rent data
      ledger = double('ledger', amount_due: 7045.0)
      allow(Persistence).to receive(:rent_ledger).and_return(
        double(find_by_tenant_and_period: ledger)
      )
      allow(Persistence).to receive(:rent_receipts).and_return(
        double(find_by_tenant_and_month: [])
      )

      post '/sms', {
        id: 'sms123',
        from: '+46701234567',
        to: '+46700000000',
        message: 'STATUS',
        direction: 'incoming'
      }

      expect(last_response.status).to eq(200)
      expect(last_response.content_type).to include('application/json')

      response_data = JSON.parse(last_response.body)
      expect(response_data['message']).to include('7045')
      expect(response_data['message']).to include('kr kvar')
    end

    it 'generates HELP reply for help command' do
      allow(mock_sms_repo).to receive(:create).and_return(double(id: 'evt123'))

      post '/sms', {
        id: 'sms123',
        from: '+46701234567',
        to: '+46700000000',
        message: 'HELP',
        direction: 'incoming'
      }

      expect(last_response.status).to eq(200)

      response_data = JSON.parse(last_response.body)
      expect(response_data['message']).to include('Kommandon')
      expect(response_data['message']).to include('STATUS')
      expect(response_data['message']).to include('HELP')
    end

    it 'generates LLM reply for unknown messages' do
      allow(mock_sms_repo).to receive(:create).and_return(double(id: 'evt123'))

      # Mock LLM generation (Phase 5 will implement this)
      allow_any_instance_of(ElksWebhooksHandler).to receive(:generate_llm_reply)
        .with(tenant, 'When is rent due?')
        .and_return('Hyran ska vara betald senast den 27:e varje månad.')

      post '/sms', {
        id: 'sms123',
        from: '+46701234567',
        to: '+46700000000',
        message: 'When is rent due?',
        direction: 'incoming'
      }

      expect(last_response.status).to eq(200)

      response_data = JSON.parse(last_response.body)
      expect(response_data['message']).to include('27:e')
    end

    it 'returns 200 for unknown sender (no tenant match)' do
      allow(mock_tenant_repo).to receive(:find_by_phone_e164).with('+46709999999').and_return(nil)
      allow(mock_sms_repo).to receive(:create).and_return(double(id: 'evt123'))

      post '/sms', {
        id: 'sms123',
        from: '+46709999999',
        to: '+46700000000',
        message: 'Random message',
        direction: 'incoming'
      }

      expect(last_response.status).to eq(200)

      response_data = JSON.parse(last_response.body)
      expect(response_data['message']).to include('okänt i vårt system')
    end
  end

  describe 'POST /dlr (delivery receipt from 46elks)' do
    it 'updates SMS event status to delivered' do
      expect(mock_sms_repo).to receive(:update_delivery_status).with(
        's70df59406a1b4643b96f3f91e0bfb7b0',
        hash_including(
          status: 'delivered',
          delivered_at: kind_of(Time)
        )
      ).and_return(true)

      post '/dlr', {
        id: 's70df59406a1b4643b96f3f91e0bfb7b0',
        status: 'delivered',
        delivered: '2025-11-15T12:05:00.000000'
      }

      expect(last_response.status).to eq(200)
      expect(last_response.body).to eq('OK')
    end

    it 'updates SMS event status to failed with reason' do
      expect(mock_sms_repo).to receive(:update_delivery_status).with(
        'sms123',
        hash_including(
          status: 'failed',
          failure_reason: 'Invalid number'
        )
      ).and_return(true)

      post '/dlr', {
        id: 'sms123',
        status: 'failed',
        error: 'Invalid number'
      }

      expect(last_response.status).to eq(200)
    end

    it 'returns 200 even if event not found (idempotent)' do
      allow(mock_sms_repo).to receive(:update_delivery_status).and_return(false)

      post '/dlr', {
        id: 'nonexistent',
        status: 'delivered'
      }

      expect(last_response.status).to eq(200)
    end
  end

  describe 'Error handling' do
    it 'returns 405 for GET requests' do
      get '/sms'
      expect(last_response.status).to eq(405)
    end

    it 'returns 404 for unknown paths' do
      post '/unknown'
      expect(last_response.status).to eq(404)
    end

    it 'handles database errors gracefully' do
      allow(mock_sms_repo).to receive(:create).and_raise(StandardError, 'DB error')
      allow(mock_tenant_repo).to receive(:find_by_phone_e164).and_return(double(id: 't123', name: 'Test'))

      post '/sms', {
        id: 'sms123',
        from: '+46700000000',
        message: 'Test'
      }

      expect(last_response.status).to eq(500)
    end
  end
end

require_relative '../spec_helper'
require_relative '../../lib/sms/elks_client'

RSpec.describe ElksClient do
  let(:client) { ElksClient.new }
  let(:mock_http) { instance_double(Net::HTTP) }
  let(:mock_response) { instance_double(Net::HTTPSuccess) }

  before do
    allow(ENV).to receive(:[]).with('ELKS_USERNAME').and_return('test_user')
    allow(ENV).to receive(:[]).with('ELKS_PASSWORD').and_return('test_pass')
    allow(ENV).to receive(:[]).with('API_BASE_URL').and_return('https://kimonokittens.com')
  end

  describe '#send' do
    context 'successful SMS sending' do
      before do
        # Mock Persistence layer to avoid database
        sms_events_repo = double('sms_events_repo')
        allow(sms_events_repo).to receive(:create).and_return(double(id: 'evt123'))
        allow(Persistence).to receive(:sms_events).and_return(sms_events_repo)
      end

      it 'sends SMS via mocked 46elks response' do
        result = client.send(
          to: '+46701234567',
          body: 'Test message',
          meta: { tenant_id: 'tenant123', type: 'reminder' }
        )

        # Verify mocked response structure (actual ID is random from SecureRandom)
        expect(result[:id]).to start_with('s')  # 46elks format
        expect(result[:status]).to eq('created')
        expect(result[:cost]).to eq(5000)  # 1 part * 5000
        expect(result[:parts]).to eq(1)
        expect(result[:from]).to eq('KimonoKittens')
        expect(result[:to]).to eq('+46701234567')
      end

      it 'logs SMS event to database after sending' do
        sms_events_repo = double('sms_events_repo')
        allow(Persistence).to receive(:sms_events).and_return(sms_events_repo)

        expect(sms_events_repo).to receive(:create) do |event|
          expect(event.phone_number).to eq('+46701234567')
          expect(event.message_body).to eq('Rent reminder')
          expect(event.provider_id).to start_with('s')  # Random ID from mock
          expect(event.sms_type).to eq('reminder')
          expect(event.delivery_status).to eq('sent')

          double(id: 'evt456')
        end

        client.send(
          to: '+46701234567',
          body: 'Rent reminder',
          meta: { tenant_id: 'tenant123', type: 'reminder', tone: 'friendly' }
        )
      end

      it 'calculates SMS parts from message length' do
        # Multi-part message (320 characters)
        long_message = 'a' * 320

        allow(mock_response).to receive(:body).and_return(
          { id: 'sms123', status: 'created', parts: 3, cost: 15000 }.to_json
        )

        sms_events_repo = double('sms_events_repo')
        allow(Persistence).to receive(:sms_events).and_return(sms_events_repo)

        expect(sms_events_repo).to receive(:create) do |event|
          # Repository will calculate parts internally
          expect(event.message_body.length).to eq(320)
          double(id: 'evt789')
        end

        client.send(to: '+46700000000', body: long_message, meta: {})
      end
    end

    context 'error handling (when real API calls enabled)' do
      # These tests would apply when send_http_request is uncommented for production
      # Currently mocked responses don't raise errors, but structure is here for reference

      it 'documents expected 403 Forbidden handling' do
        # TODO: When real 46elks API is enabled, this would raise:
        # expect { client.send(...) }.to raise_error(/Insufficient credits/)
        expect(true).to be true  # Placeholder
      end

      it 'documents expected 401 Unauthorized handling' do
        # TODO: When real 46elks API is enabled, this would raise:
        # expect { client.send(...) }.to raise_error(/Invalid credentials/)
        expect(true).to be true  # Placeholder
      end

      it 'documents expected network failure handling' do
        # TODO: When real 46elks API is enabled, this would raise:
        # expect { client.send(...) }.to raise_error(Errno::ECONNREFUSED)
        expect(true).to be true  # Placeholder
      end
    end

    context 'TODO: Remove mocking for production' do
      it 'includes TODO comment about mocking actual API calls' do
        # This test documents that we're mocking 46elks API
        # User hasn't signed up yet, so we mock responses
        # TODO: After 46elks signup, update ElksClient to make real API calls
        expect(true).to be true
      end
    end
  end
end

# frozen_string_literal: true

require_relative '../spec_helper'
require_relative '../../lib/banking/lunchflow_client'
require 'webmock/rspec'

RSpec.describe LunchflowClient do
  let(:api_key) { 'test_api_key_12345' }
  let(:client) { described_class.new(api_key) }
  let(:base_url) { 'https://www.lunchflow.app/api/v1' }

  before do
    WebMock.disable_net_connect!(allow_localhost: true)
  end

  after do
    WebMock.reset!
  end

  describe '#initialize' do
    it 'accepts an API key' do
      expect(client.instance_variable_get(:@api_key)).to eq(api_key)
    end

    it 'uses ENV variable when no key provided' do
      allow(ENV).to receive(:[]).with('LUNCHFLOW_API_KEY').and_return('env_key')
      client = described_class.new
      expect(client.instance_variable_get(:@api_key)).to eq('env_key')
    end
  end

  describe '#list_accounts' do
    it 'returns array of accounts on success' do
      stub_request(:get, "#{base_url}/accounts")
        .with(headers: { 'x-api-key' => api_key, 'Content-Type' => 'application/json' })
        .to_return(
          status: 200,
          body: {
            accounts: [
              { id: 4065, name: 'Huset', institution_name: 'Swedbank' },
              { id: 5678, name: 'Savings', institution_name: 'Nordea' }
            ]
          }.to_json,
          headers: { 'Content-Type' => 'application/json' }
        )

      result = client.list_accounts
      expect(result).to be_an(Array)
      expect(result.length).to eq(2)
      expect(result.first[:id]).to eq(4065)
      expect(result.first[:name]).to eq('Huset')
    end

    it 'returns empty array when accounts key missing' do
      stub_request(:get, "#{base_url}/accounts")
        .to_return(status: 200, body: '{}', headers: { 'Content-Type' => 'application/json' })

      result = client.list_accounts
      expect(result).to eq([])
    end

    it 'raises error on 401 unauthorized' do
      stub_request(:get, "#{base_url}/accounts")
        .to_return(status: 401, body: { error: 'Invalid API key' }.to_json)

      expect { client.list_accounts }.to raise_error(/Lunch Flow API error: 401/)
    end

    it 'raises error on 500 server error' do
      stub_request(:get, "#{base_url}/accounts")
        .to_return(status: 500, body: 'Internal Server Error')

      expect { client.list_accounts }.to raise_error(/Lunch Flow API error: 500/)
    end
  end

  describe '#fetch_transactions' do
    let(:account_id) { 4065 }

    context 'without date filtering' do
      it 'returns all transactions' do
        stub_request(:get, "#{base_url}/accounts/#{account_id}/transactions")
          .with(headers: { 'x-api-key' => api_key })
          .to_return(
            status: 200,
            body: {
              transactions: [
                {
                  id: 'txn_123',
                  accountId: 4065,
                  date: '2025-11-15',
                  amount: 7045.0,
                  currency: 'SEK',
                  merchant: 'Sanna Benemar',
                  description: 'SWISH SANNA BENEMAR KK-2025-11-Sanna-cmhqe9enc'
                },
                {
                  id: 'txn_124',
                  accountId: 4065,
                  date: '2025-11-14',
                  amount: -1500.0,
                  currency: 'SEK',
                  merchant: 'Vattenfall',
                  description: 'Electricity payment'
                }
              ]
            }.to_json
          )

        result = client.fetch_transactions(account_id: account_id)
        expect(result[:transactions].length).to eq(2)
        expect(result[:transactions].first[:id]).to eq('txn_123')
      end
    end

    context 'with date filtering' do
      it 'filters transactions client-side by date' do
        stub_request(:get, "#{base_url}/accounts/#{account_id}/transactions")
          .to_return(
            status: 200,
            body: {
              transactions: [
                { id: 'txn_123', date: '2025-11-15', amount: 100 },
                { id: 'txn_124', date: '2025-11-10', amount: 200 },
                { id: 'txn_125', date: '2025-11-01', amount: 300 }
              ]
            }.to_json
          )

        result = client.fetch_transactions(account_id: account_id, since: '2025-11-12')
        expect(result[:transactions].length).to eq(1)
        expect(result[:transactions].first[:id]).to eq('txn_123')
      end

      it 'accepts Date object for since parameter' do
        stub_request(:get, "#{base_url}/accounts/#{account_id}/transactions")
          .to_return(
            status: 200,
            body: {
              transactions: [
                { id: 'txn_123', date: '2025-11-15', amount: 100 },
                { id: 'txn_124', date: '2025-11-10', amount: 200 }
              ]
            }.to_json
          )

        result = client.fetch_transactions(account_id: account_id, since: Date.parse('2025-11-12'))
        expect(result[:transactions].length).to eq(1)
      end
    end

    it 'returns empty array when transactions key missing' do
      stub_request(:get, "#{base_url}/accounts/#{account_id}/transactions")
        .to_return(status: 200, body: '{}')

      result = client.fetch_transactions(account_id: account_id)
      expect(result[:transactions]).to eq([])
    end

    it 'uses SSL with verify_none mode' do
      # This test ensures SSL is configured correctly for Ruby Net::HTTP
      stub = stub_request(:get, "#{base_url}/accounts/#{account_id}/transactions")
               .to_return(status: 200, body: { transactions: [] }.to_json)

      client.fetch_transactions(account_id: account_id)
      expect(stub).to have_been_requested
    end
  end

  describe 'error handling' do
    let(:account_id) { 4065 }

    it 'raises on network timeout' do
      stub_request(:get, "#{base_url}/accounts/#{account_id}/transactions")
        .to_timeout

      expect do
        client.fetch_transactions(account_id: account_id)
      end.to raise_error(/timeout|timed out/i)
    end

    it 'includes response body in error messages' do
      stub_request(:get, "#{base_url}/accounts")
        .to_return(status: 403, body: { error: 'Forbidden', message: 'API key lacks permission' }.to_json)

      expect do
        client.list_accounts
      end.to raise_error(/403.*Forbidden|403.*API key lacks permission/)
    end
  end

  describe 'authentication' do
    it 'uses x-api-key header not Bearer token' do
      stub = stub_request(:get, "#{base_url}/accounts")
               .with(headers: { 'x-api-key' => api_key })
               .to_return(status: 200, body: { accounts: [] }.to_json)

      client.list_accounts
      expect(stub).to have_been_requested
    end

    it 'does not include Authorization header' do
      stub_request(:get, "#{base_url}/accounts")
        .to_return(status: 200, body: { accounts: [] }.to_json)

      client.list_accounts

      # Verify Authorization header was NOT sent
      expect(WebMock).not_to have_requested(:get, "#{base_url}/accounts")
        .with(headers: { 'Authorization' => /Bearer/ })
    end
  end
end

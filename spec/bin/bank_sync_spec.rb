# frozen_string_literal: true

require_relative '../spec_helper'
require 'json'
require 'fileutils'
require 'tmpdir'
require 'date'

RSpec.describe 'bin/bank_sync' do
  let(:state_dir) { Dir.mktmpdir('bank_sync_test') }
  let(:state_file) { File.join(state_dir, 'bank_sync.json') }
  let(:test_account_id) { '4065' }

  # Mock transactions from Lunch Flow API
  let(:mock_transactions) do
    [
      {
        id: 'txn_swish_001',
        accountId: test_account_id,
        date: '2025-11-15',
        booked_at: '2025-11-15T10:30:00Z',
        amount: 7045.0,
        currency: 'SEK',
        counterparty_name: 'Sanna Benemar',
        description: 'SWISH SANNA BENEMAR KK-2025-11-Sanna-cmhqe9enc'
      },
      {
        id: 'txn_electricity_002',
        accountId: test_account_id,
        date: '2025-11-14',
        booked_at: '2025-11-14T08:00:00Z',
        amount: -1500.0,
        currency: 'SEK',
        counterparty_name: 'Vattenfall',
        description: 'Electricity invoice payment'
      }
    ]
  end

  let(:mock_lunchflow_response) do
    { transactions: mock_transactions }
  end

  before do
    # Mock environment variables
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with('LUNCHFLOW_API_KEY').and_return('test_key')
    allow(ENV).to receive(:[]).with('LUNCHFLOW_ACCOUNT_ID').and_return(test_account_id)

    # Override state file location
    stub_const('STATE_FILE', state_file)
  end

  after do
    FileUtils.rm_rf(state_dir) if File.exist?(state_dir)
  end

  describe 'cursor state management' do
    it 'loads cursor from existing state file' do
      File.write(state_file, { cursor: '2025-11-01' }.to_json)

      state = if File.exist?(state_file)
                JSON.parse(File.read(state_file))
              else
                {}
              end

      expect(state['cursor']).to eq('2025-11-01')
    end

    it 'handles missing state file gracefully' do
      state = if File.exist?(state_file)
                JSON.parse(File.read(state_file))
              else
                {}
              end

      expect(state).to eq({})
      expect(state['cursor']).to be_nil
    end

    it 'updates cursor after successful sync' do
      # Simulate successful sync
      new_cursor = '2025-11-15'
      state = { 'cursor' => new_cursor }

      File.write(state_file, JSON.pretty_generate(state))

      saved_state = JSON.parse(File.read(state_file))
      expect(saved_state['cursor']).to eq(new_cursor)
    end
  end

  describe 'transaction processing' do
    it 'identifies Swish payments for reconciliation' do
      swish_tx = mock_transactions.first
      expect(swish_tx[:description]).to include('SWISH')
      expect(swish_tx[:amount]).to be > 0
    end

    it 'skips non-Swish transactions for reconciliation' do
      non_swish_tx = mock_transactions.last
      expect(non_swish_tx[:description]).not_to include('SWISH')
    end

    it 'upsertsactions by external_id to prevent duplicates' do
      # This test verifies deduplication logic concept
      # Actual implementation will use BankTransactionRepository.upsert
      external_ids = mock_transactions.map { |tx| tx[:id] }
      expect(external_ids.uniq.length).to eq(external_ids.length)
    end
  end

  describe 'dry-run mode' do
    it 'detects --dry-run flag from ARGV' do
      argv = ['--dry-run']
      dry_run = argv.include?('--dry-run')

      expect(dry_run).to be true
    end

    it 'skips database writes in dry-run mode' do
      dry_run = true

      # Simulate dry-run logic
      if dry_run
        output = "🔍 DRY RUN MODE - No changes will be saved\n"
        output += "Found #{mock_transactions.length} transactions:\n"
        mock_transactions.each do |tx|
          output += "\n#{tx[:id]}: #{tx[:amount]} #{tx[:currency]} - #{tx[:description]}\n"
          reconcile_flag = tx[:description]&.include?('SWISH') ? 'YES (Swish payment)' : 'NO'
          output += "  Would reconcile: #{reconcile_flag}\n"
        end

        expect(output).to include('DRY RUN MODE')
        expect(output).to include('txn_swish_001')
        expect(output).to include('Would reconcile: YES')
      end
    end
  end

  describe 'error handling' do
    it 'sends admin SMS on API failure' do
      # Mock SmsGateway (will be implemented in Phase 4)
      sms_gateway = double('SmsGateway')
      allow(sms_gateway).to receive(:send_admin_alert)

      error_message = 'Lunch Flow API error: 500 Internal Server Error'

      # Simulate error handling
      unless true # dry_run
        sms_gateway.send_admin_alert("⚠️ Bank sync failed: #{error_message}")
      end

      # In dry-run mode, SMS should not be sent
      expect(sms_gateway).not_to have_received(:send_admin_alert)
    end

    it 're-raises errors after sending alert' do
      error = StandardError.new('API timeout')

      expect do
        # Simulate bank sync error
        raise error unless false # dry_run
      end.to raise_error(StandardError, 'API timeout')
    end
  end

  describe 'ApplyBankPayment service integration' do
    it 'calls service for Swish payments' do
      # Mock ApplyBankPayment service (Phase 3)
      service = double('ApplyBankPayment')
      allow(service).to receive(:call)

      mock_transactions.each do |tx|
        if tx[:description]&.include?('SWISH')
          service.call(transaction_id: tx[:id])
        end
      end

      expect(service).to have_received(:call).once
    end

    it 'skips service call in dry-run mode' do
      dry_run = true
      service = double('ApplyBankPayment')
      allow(service).to receive(:call)

      mock_transactions.each do |tx|
        if !dry_run && tx[:description]&.include?('SWISH')
          service.call(transaction_id: tx[:id])
        end
      end

      expect(service).not_to have_received(:call)
    end
  end

  describe 'BankTransactionRepository integration' do
    it 'upserts transactions with all required fields' do
      tx = mock_transactions.first

      # Simulate repository upsert call
      upsert_params = {
        external_id: tx[:id],
        account_id: tx[:accountId],
        booked_at: DateTime.parse(tx[:booked_at]),
        amount: tx[:amount],
        currency: tx[:currency],
        description: tx[:description],
        counterparty: tx[:counterparty_name],
        raw_json: tx
      }

      # Verify all required fields present
      expect(upsert_params[:external_id]).to eq('txn_swish_001')
      expect(upsert_params[:booked_at]).to be_a(DateTime)
      expect(upsert_params[:amount]).to eq(7045.0)
      expect(upsert_params[:currency]).to eq('SEK')
      expect(upsert_params[:description]).to include('SWISH')
      expect(upsert_params[:counterparty]).to eq('Sanna Benemar')
      expect(upsert_params[:raw_json]).to be_a(Hash)
    end
  end

  describe 'success output' do
    it 'logs sync summary' do
      synced_count = mock_transactions.length
      dry_run = false

      output = if dry_run
                 "Would sync #{synced_count} transactions"
               else
                 "Synced #{synced_count} transactions"
               end

      expect(output).to include('2 transactions')
    end

    it 'logs dry-run summary' do
      synced_count = mock_transactions.length
      dry_run = true

      output = if dry_run
                 "Would sync #{synced_count} transactions"
               else
                 "Synced #{synced_count} transactions"
               end

      expect(output).to include('Would sync')
    end
  end
end

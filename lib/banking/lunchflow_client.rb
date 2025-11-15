# frozen_string_literal: true

require 'net/http'
require 'json'
require 'date'

# Lunch Flow API client for bank transaction sync
# Authentication: x-api-key header (NOT Bearer token)
# Base URL: https://www.lunchflow.app/api/v1
class LunchflowClient
  BASE_URL = 'https://www.lunchflow.app/api/v1'
  TIMEOUT = 60 # seconds

  def initialize(api_key = ENV['LUNCHFLOW_API_KEY'])
    @api_key = api_key
    raise ArgumentError, 'LUNCHFLOW_API_KEY is required' if @api_key.nil? || @api_key.empty?
  end

  # Get all connected bank accounts
  # Returns: Array of account hashes with :id, :name, :institution_name
  def list_accounts
    response = request(:get, '/accounts')
    response[:accounts] || []
  end

  # Fetch transactions for a specific account
  # @param account_id [String, Integer] Account ID from list_accounts
  # @param since [String, Date, nil] Optional date filter (client-side)
  # @return [Hash] { transactions: [...] }
  def fetch_transactions(account_id:, since: nil)
    path = "/accounts/#{account_id}/transactions"
    response = request(:get, path)

    transactions = response[:transactions] || []

    # Client-side date filtering (API returns all transactions)
    if since
      since_date = since.is_a?(Date) ? since : Date.parse(since.to_s)
      transactions = transactions.select do |tx|
        Date.parse(tx[:date]) >= since_date
      end
    end

    { transactions: transactions }
  end

  private

  def request(method, path, params: {})
    uri = URI("#{BASE_URL}#{path}")
    uri.query = URI.encode_www_form(params) if params.any?

    # Build request
    req_class = case method
                when :get then Net::HTTP::Get
                when :post then Net::HTTP::Post
                else
                  raise ArgumentError, "Unsupported HTTP method: #{method}"
                end

    req = req_class.new(uri)
    req['x-api-key'] = @api_key # CRITICAL: Use x-api-key, NOT Bearer!
    req['Content-Type'] = 'application/json'

    # Configure SSL
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    # Ruby SSL workaround for CRL verification issues
    http.verify_mode = OpenSSL::SSL::VERIFY_NONE
    http.read_timeout = TIMEOUT
    http.open_timeout = TIMEOUT

    # Execute request
    response = http.request(req)

    # Handle errors
    unless response.is_a?(Net::HTTPSuccess)
      error_body = response.body || 'No response body'
      raise "Lunch Flow API error: #{response.code} #{error_body}"
    end

    # Parse JSON response
    JSON.parse(response.body, symbolize_names: true)
  rescue Net::ReadTimeout, Net::OpenTimeout => e
    raise "Lunch Flow API timeout: #{e.message}"
  rescue Errno::ETIMEDOUT => e
    raise "Lunch Flow API network timeout: #{e.message}"
  end
end

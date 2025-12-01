require 'net/http'
require 'json'
require_relative '../persistence'
require_relative '../models/sms_event'

# ElksClient - 46elks SMS API client
#
# Sends SMS via 46elks API and logs events to database.
#
# Authentication: Basic Auth with ELKS_USERNAME and ELKS_PASSWORD
# Webhook: Delivery receipts sent to API_BASE_URL/webhooks/elks/dlr
# Testing: Tests mock Net::HTTP layer to avoid real API calls
#
# @example Send SMS
#   client = ElksClient.new
#   result = client.send(
#     to: '+46701234567',
#     body: 'Rent due in 3 days',
#     meta: { tenant_id: 'cmhqe9enc', type: 'reminder', tone: 'friendly' }
#   )
#   # => { id: 'sms123', status: 'created', cost: 5000, parts: 1 }
class ElksClient
  API_URL = 'https://api.46elks.com/a1/sms'

  def initialize
    @username = ENV['ELKS_USERNAME']
    @password = ENV['ELKS_PASSWORD']
    @api_base_url = ENV['API_BASE_URL']
  end

  # Send SMS message
  #
  # @param to [String] Recipient phone number (E.164 format)
  # @param body [String] Message text
  # @param meta [Hash] Metadata (tenant_id, type, tone, month, etc.)
  # @return [Hash] 46elks API response
  # @raise [RuntimeError] On API errors (403, 401, etc.)
  def send(to:, body:, meta: {})
    # Prepare request parameters
    params = {
      from: 'Katten',  # Alphanumeric sender ID (max 11 chars, Swedish for "the cat")
      to: to,
      message: body
    }

    # Only add delivery receipt webhook in production (requires publicly accessible URL)
    unless ENV['RACK_ENV'] == 'development'
      # Use WEBHOOK_BASE_URL for external services (not API_BASE_URL which is for internal use)
      webhook_base = ENV['WEBHOOK_BASE_URL'] || @api_base_url
      webhook_url = "#{webhook_base}/webhooks/elks/dlr"
      params[:whendelivered] = webhook_url
    end

    # Send request to 46elks API (tests mock Net::HTTP layer)
    result = send_http_request(params)

    # Log SMS event to database
    log_sms_event(result, to, body, meta)

    result
  end

  private

  # Send HTTP request to 46elks API
  #
  # @param params [Hash] Form data parameters
  # @return [Hash] Parsed JSON response
  # @raise [RuntimeError] On HTTP errors
  def send_http_request(params)
    uri = URI(API_URL)
    req = Net::HTTP::Post.new(uri)
    req.basic_auth(@username, @password)
    req.set_form_data(params)

    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.verify_mode = OpenSSL::SSL::VERIFY_NONE  # TODO: Fix SSL certificates properly
    response = http.request(req)

    handle_response(response)
  end

  # Handle HTTP response from 46elks
  #
  # @param response [Net::HTTPResponse]
  # @return [Hash] Parsed JSON
  # @raise [RuntimeError] On error responses
  def handle_response(response)
    case response
    when Net::HTTPSuccess
      JSON.parse(response.body, symbolize_names: true)
    when Net::HTTPForbidden
      raise "Insufficient credits: #{response.body}"
    when Net::HTTPUnauthorized
      raise "Invalid credentials"
    else
      raise "HTTP #{response.code}: #{response.body}"
    end
  end

  # Mock 46elks API response for development/manual testing
  # Production code uses send_http_request; tests mock Net::HTTP layer
  #
  # @param to [String] Phone number
  # @param body [String] Message text
  # @param params [Hash] Request parameters
  # @return [Hash] Mocked response matching 46elks format
  def mock_46elks_response(to, body, params)
    # Calculate parts (160 chars per part for GSM, 70 for UTF-16)
    # Simplified: assume GSM encoding
    parts = (body.length / 160.0).ceil

    # Cost: ~0.50 SEK per part = 5000 in 10,000ths
    cost = parts * 5000

    {
      id: "s#{SecureRandom.hex(16)}",  # Mock 46elks message ID
      status: 'created',
      direction: 'outgoing',
      from: params[:from],
      to: to,
      message: body,
      created: Time.now.utc.iso8601(6),
      parts: parts,
      cost: cost
    }
  end

  # Log SMS event to database
  #
  # @param api_response [Hash] 46elks API response
  # @param to [String] Recipient phone number
  # @param body [String] Message text
  # @param meta [Hash] Metadata (tenant_id, type, tone, month, etc.)
  # @return [SmsEvent] Created event
  def log_sms_event(api_response, to, body, meta)
    event = SmsEvent.new(
      tenant_id: meta[:tenant_id],
      month: meta[:month],  # Rent month in "YYYY-MM" format (e.g., "2025-11")
      phone_number: to,
      message_body: body,
      sms_type: meta[:type] || 'reminder',
      tone: meta[:tone] || 'neutral',
      delivery_status: 'sent',  # Initial status after send
      elks_message_id: api_response[:id],
      cost: api_response[:cost],
      sent_at: Time.now
    )

    Persistence.sms_events.save(event)
  end
end

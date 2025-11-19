require 'rack'
require 'json'
require_relative '../lib/persistence'

# ElksWebhooksHandler - Handle 46elks SMS webhooks
#
# Receives:
# 1. Delivery receipts (POST /dlr) - Update SMS event status
# 2. Incoming SMS (POST /sms) - Log + generate reply
#
# 46elks sends webhooks as application/x-www-form-urlencoded POST requests
#
# Webhook routes:
# - POST /dlr - Delivery status updates (sent, delivered, failed)
# - POST /sms - Incoming SMS from tenants
#
# @example Delivery receipt webhook
#   POST /dlr
#   id=s70df59406a1b4643b96f3f91e0bfb7b0&status=delivered&delivered=2025-11-15T12:05:00
#
# @example Incoming SMS webhook
#   POST /sms
#   id=sf8425555&from=%2B46701234567&to=%2B46700000000&message=STATUS&direction=incoming
class ElksWebhooksHandler
  def call(env)
    req = Rack::Request.new(env)

    # Only accept POST requests
    return method_not_allowed unless req.post?

    # Route based on path
    case req.path_info
    when '/sms'
      handle_incoming_sms(req)
    when '/dlr'
      handle_delivery_receipt(req)
    else
      not_found
    end
  rescue => e
    # Log error but still return 200 to prevent 46elks retries
    puts "ElksWebhooksHandler error: #{e.message}"
    puts e.backtrace.first(5).join("\n")
    internal_error
  end

  private

  # Handle incoming SMS from tenant
  #
  # @param req [Rack::Request]
  # @return [Array] Rack response (200, headers, body)
  def handle_incoming_sms(req)
    params = req.params

    # Log incoming SMS to database
    # Note: sms_type must be 'confirmation' (valid type) for incoming SMS
    Persistence.sms_events.create(
      SmsEvent.new(
        direction: 'in',
        provider_id: params['id'],
        phone_number: params['from'],
        message_body: params['message'],
        sms_type: 'confirmation',  # Using 'confirmation' as closest match for incoming
        tone: 'neutral',
        delivery_status: 'sent',  # Valid status (received doesn't exist)
        sent_at: Time.now
      )
    )

    # Parse tenant from phone number (use phoneE164 field from schema)
    tenant = Persistence.tenants.find_by_phone_e164(params['from'])

    unless tenant
      # Unknown sender - polite response
      reply = "Tack för ditt meddelande. Detta nummer är okänt i vårt system."
      return json_response(200, { message: reply })
    end

    # Generate reply based on message content
    reply = case params['message'].to_s.downcase.strip
    when /status/
      generate_status_reply(tenant)
    when /help|hjälp/
      "Kommandon: STATUS (visa hyra), HELP (denna hjälp)"
    else
      # LLM-generated reply (Phase 5 will implement)
      generate_llm_reply(tenant, params['message'])
    end

    # Return JSON response (46elks auto-sends this as SMS)
    json_response(200, { message: reply })
  end

  # Handle delivery receipt from 46elks
  #
  # @param req [Rack::Request]
  # @return [Array] Rack response (200, headers, body)
  def handle_delivery_receipt(req)
    params = req.params

    # Update SMS event status
    Persistence.sms_events.update_delivery_status(
      params['id'],
      status: params['status'],
      delivered_at: params['delivered'] ? Time.parse(params['delivered']) : nil,
      failure_reason: params['error']
    )

    # Return 200 OK (required by 46elks)
    [200, { 'Content-Type' => 'text/plain' }, ['OK']]
  end

  # Generate status reply with rent info
  #
  # @param tenant [Tenant]
  # @return [String] Reply message
  def generate_status_reply(tenant)
    current_month = Time.now.strftime('%Y-%m')

    # Get rent ledger for current month
    ledger = Persistence.rent_ledger.find_by_tenant_and_period(
      tenant.id,
      Date.parse("#{current_month}-01")
    )

    return "Kunde inte hitta hyresinfo för #{current_month}" unless ledger

    # Get rent month for display (ledger.period is config month)
    rent_month_display = ledger.period_swedish  # e.g., "December 2025"

    # Get existing receipts
    receipts = Persistence.rent_receipts.find_by_tenant_and_month(
      tenant.id,
      current_month
    )
    total_paid = receipts.sum(&:amount)
    remaining = ledger.amount_due - total_paid

    if remaining <= 0
      "Hyra #{rent_month_display}: Betald (#{ledger.amount_due.round} kr)"
    else
      # Generate reference code and Swish link
      ref = generate_reference(tenant, current_month)
      swish_link = generate_swish_link(tenant.phone, remaining, ref)

      "Hyra #{rent_month_display}: #{remaining.round} kr kvar\nRef: #{ref}\nLänk: #{swish_link}"
    end
  end

  # Generate LLM reply (mocked for now, Phase 5 implements)
  #
  # @param tenant [Tenant]
  # @param message [String]
  # @return [String] Reply message
  def generate_llm_reply(tenant, message)
    # TODO: Phase 5 will implement GPT-5-mini LLM generation
    # For now, return helpful default response
    "Tack för ditt meddelande! Skriv STATUS för att se din hyra, eller HELP för kommandon."
  end

  # Generate reference code for payment
  #
  # @param tenant [Tenant]
  # @param month [String] "YYYY-MM"
  # @return [String] Reference code (e.g., "KK-2025-11-Sanna-cmhqe9enc")
  def generate_reference(tenant, month)
    short_uuid = tenant.id[-13..-1]  # Last 13 chars of CUID
    first_name = tenant.name.split(' ').first

    "KK-#{month}-#{first_name}-#{short_uuid}"
  end

  # Generate Swish deep link
  #
  # @param phone [String] Landlord's Swish number
  # @param amount [Float] Amount in SEK
  # @param reference [String] Reference code
  # @return [String] Swish URL
  def generate_swish_link(phone, amount, reference)
    swish_number = ENV['ADMIN_SWISH_NUMBER'] || '0701234567'
    params = {
      phone: swish_number.gsub(/\D/, ''),  # Remove +46 prefix
      amount: amount.round.to_i,
      message: reference
    }

    "swish://payment?" + URI.encode_www_form(params)
  end

  # Rack responses

  def json_response(status, data)
    [status, { 'Content-Type' => 'application/json' }, [JSON.generate(data)]]
  end

  def method_not_allowed
    [405, { 'Content-Type' => 'application/json' }, ['{"error":"Method not allowed"}']]
  end

  def not_found
    [404, { 'Content-Type' => 'application/json' }, ['{"error":"Not found"}']]
  end

  def internal_error
    [500, { 'Content-Type' => 'application/json' }, ['{"error":"Internal server error"}']]
  end
end

require 'time'
require 'json'

# SmsEvent domain model representing an SMS sent or received via 46elks
#
# Adapts to the actual database schema which uses:
# - direction: "out" (sent), "in" (received), "dlr" (delivery receipt)
# - providerId: 46elks message ID
# - body: message text
# - status: delivery status
# - meta: JSONB field containing type, tone, cost, timestamps, phone numbers
#
# Provides backward-compatible API for existing tests while using new schema.
#
# @example Create a rent reminder SMS
#   event = SmsEvent.new(
#     tenant_id: 'cmhqe9enc',
#     phone_number: '+46701234567',
#     message_body: 'Hyra för november: 7045 kr...',
#     sms_type: 'reminder',
#     tone: 'friendly',
#     delivery_status: 'queued',
#     sent_at: Time.now
#   )
#
# @example Create an admin alert
#   event = SmsEvent.new(
#     phone_number: '+46707654321',
#     message_body: 'Bank sync failed: API timeout',
#     sms_type: 'admin_alert',
#     tone: 'urgent',
#     delivery_status: 'queued',
#     sent_at: Time.now
#   )
class SmsEvent
  VALID_SMS_TYPES = %w[reminder admin_alert confirmation].freeze
  VALID_TONES = %w[neutral friendly urgent].freeze
  VALID_DELIVERY_STATUSES = %w[queued sent delivered failed].freeze
  E164_REGEX = /^\+[1-9]\d{1,14}$/.freeze

  # Internal attributes mapping to actual schema
  attr_reader :id, :tenant_id, :direction, :provider_id, :body, :status, :meta, :created_at

  def initialize(
    id: nil,
    tenant_id: nil,
    phone_number:,
    message_body:,
    sms_type:,
    tone:,
    delivery_status:,
    elks_message_id: nil,
    cost: nil,
    sent_at:,
    delivered_at: nil,
    failure_reason: nil,
    created_at: nil,
    updated_at: nil,
    # Internal schema fields (used by repository)
    direction: nil,
    provider_id: nil,
    body: nil,
    status: nil,
    meta: nil
  )
    @id = id
    @tenant_id = tenant_id

    # Use schema fields if provided, otherwise construct from legacy fields
    @direction = direction || 'out'
    @provider_id = provider_id || elks_message_id
    @body = body || message_body.to_s
    @status = status || delivery_status.to_s

    # Build meta hash from both explicit meta and legacy fields
    @meta = build_meta(
      meta: meta,
      phone_number: phone_number,
      sms_type: sms_type,
      tone: tone,
      cost: cost,
      delivered_at: delivered_at,
      failure_reason: failure_reason
    )

    @created_at = created_at || parse_time(sent_at)

    validate!
  end

  # Legacy API compatibility methods

  def phone_number
    @meta['to'] || @meta['from']
  end

  def message_body
    @body
  end

  def sms_type
    @meta['type']
  end

  def tone
    @meta['tone']
  end

  def delivery_status
    @status
  end

  def elks_message_id
    @provider_id
  end

  def cost
    @meta['cost']
  end

  def sent_at
    @created_at
  end

  def delivered_at
    parse_time(@meta['delivered_at'])
  end

  def failure_reason
    @meta['failure_reason']
  end

  def updated_at
    # Not stored in new schema, return created_at for compatibility
    @created_at
  end

  # Check if SMS was successfully delivered
  # @return [Boolean]
  def delivered?
    status == 'delivered'
  end

  # Check if SMS delivery failed
  # @return [Boolean]
  def failed?
    status == 'failed'
  end

  # Check if SMS is a rent reminder
  # @return [Boolean]
  def reminder?
    sms_type == 'reminder'
  end

  # Check if SMS is an admin alert
  # @return [Boolean]
  def admin_alert?
    sms_type == 'admin_alert'
  end

  # Convert cost from 10,000ths to SEK
  # @return [Float] Cost in SEK (e.g., 6500 -> 0.65)
  def cost_in_sek
    return 0.0 if cost.nil?
    cost / 10000.0
  end

  def to_s
    "#{sms_type} SMS to #{phone_number} (#{delivery_status})"
  end

  private

  def build_meta(meta:, phone_number:, sms_type:, tone:, cost:, delivered_at:, failure_reason:)
    result = meta.is_a?(Hash) ? meta.dup : {}

    # Add/override with explicit parameters
    result['to'] = phone_number.to_s if phone_number
    result['type'] = sms_type.to_s if sms_type
    result['tone'] = tone.to_s if tone
    result['cost'] = cost.to_i if cost
    result['delivered_at'] = delivered_at.iso8601(6) if delivered_at.is_a?(Time)  # Keep microseconds
    result['failure_reason'] = failure_reason if failure_reason

    result
  end

  def validate!
    phone = phone_number
    raise ArgumentError, "phone number must be E.164 format (e.g., +46701234567)" unless phone =~ E164_REGEX
    raise ArgumentError, "message_body cannot be empty" if message_body.empty?
    raise ArgumentError, "sms_type must be one of: #{VALID_SMS_TYPES.join(', ')}" unless VALID_SMS_TYPES.include?(sms_type)
    raise ArgumentError, "tone must be one of: #{VALID_TONES.join(', ')}" unless VALID_TONES.include?(tone)
    raise ArgumentError, "delivery_status must be one of: #{VALID_DELIVERY_STATUSES.join(', ')}" unless VALID_DELIVERY_STATUSES.include?(delivery_status)
    raise ArgumentError, "sent_at is required" unless sent_at.is_a?(Time)
  end

  def parse_time(value)
    case value
    when Time
      value
    when String
      Time.parse(value)
    when nil
      nil
    else
      value
    end
  end
end

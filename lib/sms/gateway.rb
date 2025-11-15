require_relative 'elks_client'

# SmsGateway - Abstract interface for SMS sending
#
# Provides a simple API for sending SMS messages via 46elks.
# Delegates to ElksClient for actual API interaction.
#
# @example Send a rent reminder
#   SmsGateway.send(
#     to: '+46701234567',
#     body: 'Hyra för november: 7045 kr...',
#     meta: { tenant_id: 'cmhqe9enc', month: '2025-11', type: 'reminder', tone: 'friendly' }
#   )
#
# @example Send admin alert
#   SmsGateway.send_admin_alert('⚠️ Bank sync failed: API timeout')
class SmsGateway
  # Send SMS message
  #
  # @param to [String] Recipient phone number (E.164 format)
  # @param body [String] Message text
  # @param meta [Hash] Optional metadata (type, tenant_id, month, tone, etc.)
  # @return [Hash] 46elks API response with id, status, cost, etc.
  def self.send(to:, body:, meta: {})
    ElksClient.new.send(to: to, body: body, meta: meta)
  end

  # Send admin alert SMS
  #
  # @param body [String] Alert message text
  # @return [Hash] 46elks API response
  # @raise [RuntimeError] If ADMIN_PHONE not configured
  def self.send_admin_alert(body)
    admin_phone = ENV['ADMIN_PHONE']
    raise 'ADMIN_PHONE not configured in environment' unless admin_phone

    send(to: admin_phone, body: body, meta: { type: 'admin_alert' })
  end
end

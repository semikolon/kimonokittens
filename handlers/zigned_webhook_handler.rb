require 'json'
require 'openssl'
require_relative '../lib/contract_signer'
require_relative '../lib/data_broadcaster'

# ZignedWebhookHandler processes signing events from Zigned API
#
# Zigned sends webhooks for these events:
# - case.created - New signing case created
# - case.signed - A signer completed their signature
# - case.completed - All signers have signed
# - case.expired - Case expired without completion
# - case.cancelled - Case was cancelled
#
# Security:
# - Validates webhook signature using HMAC-SHA256
# - Rejects requests with invalid signatures
#
# Integration Points:
# - Updates contract metadata files
# - Broadcasts signing events via WebSocket
# - Auto-downloads signed PDF when completed
# - Notifies stakeholders (future: email/SMS)
#
# Usage in puma_server.rb:
#   post '/api/webhooks/zigned' do
#     handler = ZignedWebhookHandler.new
#     result = handler.handle(request)
#
#     status result[:status]
#     json result
#   end
class ZignedWebhookHandler
  METADATA_DIR = File.join(File.dirname(__FILE__), '../contracts/metadata')

  # @param webhook_secret [String] Secret key from Zigned dashboard for signature verification
  def initialize(webhook_secret: ENV['ZIGNED_WEBHOOK_SECRET'])
    @webhook_secret = webhook_secret
    @broadcaster = DataBroadcaster.instance
  end

  # Process incoming webhook from Zigned
  #
  # @param request [Sinatra::Request] The HTTP request object
  #
  # @return [Hash] { status: Integer, message: String, event: String }
  def handle(request)
    # Read raw body for signature verification
    body = request.body.read
    request.body.rewind

    # Verify signature if secret is configured
    if @webhook_secret
      signature = request.env['HTTP_X_ZIGNED_SIGNATURE']
      unless valid_signature?(body, signature)
        return { status: 401, message: 'Invalid webhook signature', error: true }
      end
    end

    # Parse webhook payload
    begin
      payload = JSON.parse(body)
    rescue JSON::ParserError => e
      return { status: 400, message: "Invalid JSON: #{e.message}", error: true }
    end

    event_type = payload['event']
    case_data = payload['data']

    # Process event
    case event_type
    when 'case.created'
      handle_case_created(case_data)
    when 'case.signed'
      handle_case_signed(case_data)
    when 'case.completed'
      handle_case_completed(case_data)
    when 'case.expired'
      handle_case_expired(case_data)
    when 'case.cancelled'
      handle_case_cancelled(case_data)
    else
      return { status: 400, message: "Unknown event type: #{event_type}", error: true }
    end

    { status: 200, message: 'Webhook processed successfully', event: event_type }

  rescue => e
    puts "❌ Webhook error: #{e.message}"
    puts e.backtrace.join("\n")
    { status: 500, message: "Internal error: #{e.message}", error: true }
  end

  private

  # Verify webhook signature using HMAC-SHA256
  def valid_signature?(body, signature)
    return false unless signature

    expected_signature = OpenSSL::HMAC.hexdigest(
      OpenSSL::Digest.new('sha256'),
      @webhook_secret,
      body
    )

    # Constant-time comparison to prevent timing attacks
    Rack::Utils.secure_compare(signature, expected_signature)
  end

  # Handle case.created event
  def handle_case_created(data)
    case_id = data['id']
    title = data['title']

    puts "📝 New signing case created: #{case_id} - #{title}"

    update_metadata(case_id) do |metadata|
      metadata['status'] = 'created'
      metadata['zigned_webhook_received_at'] = Time.now.strftime('%Y-%m-%d %H:%M:%S')
    end

    # Broadcast event
    @broadcaster.broadcast_data('contract_status', {
      case_id: case_id,
      event: 'created',
      title: title,
      timestamp: Time.now.to_i
    })
  end

  # Handle case.signed event (one signer completed)
  def handle_case_signed(data)
    case_id = data['id']
    signer = data['signer']

    puts "✍️  Signature received: #{signer['name']} signed case #{case_id}"

    update_metadata(case_id) do |metadata|
      metadata['signers'] ||= []
      metadata['signers'] << {
        name: signer['name'],
        personnummer: signer['personal_number'],
        signed_at: signer['signed_at']
      }
    end

    # Broadcast event
    @broadcaster.broadcast_data('contract_status', {
      case_id: case_id,
      event: 'signed',
      signer_name: signer['name'],
      timestamp: Time.now.to_i
    })
  end

  # Handle case.completed event (all signers done)
  def handle_case_completed(data)
    case_id = data['id']
    title = data['title']

    puts "🎉 Contract fully signed: #{case_id} - #{title}"

    # Auto-download signed PDF
    begin
      metadata = find_metadata_by_case_id(case_id)
      if metadata
        tenant_name = metadata['tenant_name']
        signer = ContractSigner.new(test_mode: metadata['test_mode'] || false)

        signed_path = signer.download_signed_contract(case_id, tenant_name)

        puts "✅ Signed PDF downloaded: #{signed_path}"
      end
    rescue => e
      puts "⚠️  Failed to auto-download signed PDF: #{e.message}"
    end

    update_metadata(case_id) do |metadata|
      metadata['status'] = 'completed'
      metadata['completed_at'] = Time.now.strftime('%Y-%m-%d %H:%M:%S')
    end

    # Broadcast event
    @broadcaster.broadcast_data('contract_status', {
      case_id: case_id,
      event: 'completed',
      title: title,
      timestamp: Time.now.to_i
    })

    # Future: Send notification emails/SMS
    # send_completion_notification(metadata)
  end

  # Handle case.expired event
  def handle_case_expired(data)
    case_id = data['id']
    title = data['title']

    puts "⏰ Contract expired: #{case_id} - #{title}"

    update_metadata(case_id) do |metadata|
      metadata['status'] = 'expired'
      metadata['expired_at'] = Time.now.strftime('%Y-%m-%d %H:%M:%S')
    end

    # Broadcast event
    @broadcaster.broadcast_data('contract_status', {
      case_id: case_id,
      event: 'expired',
      title: title,
      timestamp: Time.now.to_i
    })

    # Future: Send expiration notification
    # send_expiration_notification(metadata)
  end

  # Handle case.cancelled event
  def handle_case_cancelled(data)
    case_id = data['id']
    title = data['title']

    puts "🚫 Contract cancelled: #{case_id} - #{title}"

    update_metadata(case_id) do |metadata|
      metadata['status'] = 'cancelled'
      metadata['cancelled_at'] = Time.now.strftime('%Y-%m-%d %H:%M:%S')
    end

    # Broadcast event
    @broadcaster.broadcast_data('contract_status', {
      case_id: case_id,
      event: 'cancelled',
      title: title,
      timestamp: Time.now.to_i
    })
  end

  # Find metadata file by case_id
  def find_metadata_by_case_id(case_id)
    metadata_files = Dir.glob(File.join(METADATA_DIR, '*_contract_metadata.json'))

    metadata_files.each do |file|
      data = JSON.parse(File.read(file))
      return data if data['case_id'] == case_id
    end

    nil
  end

  # Update metadata file for a case
  def update_metadata(case_id)
    metadata_files = Dir.glob(File.join(METADATA_DIR, '*_contract_metadata.json'))

    metadata_files.each do |file|
      data = JSON.parse(File.read(file))
      if data['case_id'] == case_id
        yield data
        File.write(file, JSON.pretty_generate(data))
        return true
      end
    end

    false
  end
end

require 'json'
require 'openssl'
require_relative '../lib/contract_signer'
require_relative '../lib/data_broadcaster'
require_relative '../lib/repositories/signed_contract_repository'
require_relative '../lib/persistence'

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
# - Updates SignedContract database records
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
  # @param webhook_secret [String] Secret key from Zigned dashboard for signature verification
  # @param broadcaster [DataBroadcaster, nil] Optional broadcaster for WebSocket notifications
  def initialize(webhook_secret: ENV['ZIGNED_WEBHOOK_SECRET'], broadcaster: nil)
    @webhook_secret = webhook_secret
    @broadcaster = broadcaster
    @repository = Persistence.signed_contracts
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

    # Update database record
    contract = @repository.find_by_case_id(case_id)
    if contract
      contract.status = 'awaiting_signatures'
      @repository.update(contract)
    else
      puts "⚠️  Warning: SignedContract record not found for case_id #{case_id}"
    end

    # Broadcast event
    @broadcaster&.broadcast_data('contract_status', {
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

    # Update database record with signature info
    contract = @repository.find_by_case_id(case_id)
    if contract
      # Determine if landlord or tenant signed (simplified - assumes Fredrik is landlord)
      is_landlord = signer['personal_number']&.gsub(/\D/, '') == '8604230717'

      if is_landlord
        contract.landlord_signed = true
        contract.landlord_signed_at = Time.parse(signer['signed_at'])
      else
        contract.tenant_signed = true
        contract.tenant_signed_at = Time.parse(signer['signed_at'])
      end

      @repository.update(contract)
    else
      puts "⚠️  Warning: SignedContract record not found for case_id #{case_id}"
    end

    # Broadcast event
    @broadcaster&.broadcast_data('contract_status', {
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

    contract = @repository.find_by_case_id(case_id)
    unless contract
      puts "⚠️  Warning: SignedContract record not found for case_id #{case_id}"
      return
    end

    # Auto-download signed PDF
    begin
      tenant = Persistence.tenants.find_by_id(contract.tenant_id)
      if tenant
        # TODO: Determine test mode from contract metadata
        signer = ContractSigner.new(test_mode: false)

        signed_path = signer.download_signed_contract(case_id, tenant.name)

        # Update contract with signed PDF URL (for now, local path)
        contract.pdf_url = signed_path
        puts "✅ Signed PDF downloaded: #{signed_path}"
      end
    rescue => e
      puts "⚠️  Failed to auto-download signed PDF: #{e.message}"
    end

    # Update contract status
    contract.status = 'completed'
    contract.completed_at = Time.now
    @repository.update(contract)

    # Broadcast event
    @broadcaster&.broadcast_data('contract_status', {
      case_id: case_id,
      event: 'completed',
      title: title,
      timestamp: Time.now.to_i
    })

    # Future: Send notification emails/SMS
    # send_completion_notification(contract)
  end

  # Handle case.expired event
  def handle_case_expired(data)
    case_id = data['id']
    title = data['title']

    puts "⏰ Contract expired: #{case_id} - #{title}"

    contract = @repository.find_by_case_id(case_id)
    if contract
      contract.status = 'expired'
      @repository.update(contract)
    else
      puts "⚠️  Warning: SignedContract record not found for case_id #{case_id}"
    end

    # Broadcast event
    @broadcaster&.broadcast_data('contract_status', {
      case_id: case_id,
      event: 'expired',
      title: title,
      timestamp: Time.now.to_i
    })

    # Future: Send expiration notification
    # send_expiration_notification(contract)
  end

  # Handle case.cancelled event
  def handle_case_cancelled(data)
    case_id = data['id']
    title = data['title']

    puts "🚫 Contract cancelled: #{case_id} - #{title}"

    contract = @repository.find_by_case_id(case_id)
    if contract
      contract.status = 'cancelled'
      @repository.update(contract)
    else
      puts "⚠️  Warning: SignedContract record not found for case_id #{case_id}"
    end

    # Broadcast event
    @broadcaster&.broadcast_data('contract_status', {
      case_id: case_id,
      event: 'cancelled',
      title: title,
      timestamp: Time.now.to_i
    })
  end
end

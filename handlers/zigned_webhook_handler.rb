require 'json'
require 'openssl'
require_relative '../lib/contract_signer'
require_relative '../lib/data_broadcaster'
require_relative '../lib/repositories/signed_contract_repository'
require_relative '../lib/persistence'

# ZignedWebhookHandler processes signing events from Zigned API v3
#
# Zigned v3 sends webhooks for these events:
# - agreement.lifecycle.pending - Agreement activated (ready for signing)
# - participant.lifecycle.fulfilled - Individual signer completed
# - agreement.lifecycle.fulfilled - All signers have signed
# - agreement.lifecycle.finalized - Signed PDF ready for download
# - agreement.lifecycle.expired - Agreement expired without completion
# - agreement.lifecycle.cancelled - Agreement was cancelled
#
# Security:
# - Validates webhook signature using HMAC-SHA256 (x-zigned-request-signature header)
# - FAIL-CLOSED: Rejects requests if webhook secret not configured
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

    # Fail-closed security: Reject if webhook secret not configured
    unless @webhook_secret
      return { status: 500, message: 'Webhook secret not configured - refusing request', error: true }
    end

    # Verify signature (v3 uses x-zigned-request-signature header)
    signature = request.env['HTTP_X_ZIGNED_REQUEST_SIGNATURE']
    unless valid_signature?(body, signature)
      return { status: 401, message: 'Invalid webhook signature', error: true }
    end

    # Parse webhook payload
    begin
      payload = JSON.parse(body)
    rescue JSON::ParserError => e
      return { status: 400, message: "Invalid JSON: #{e.message}", error: true }
    end

    # V3 payload structure: { version, event_type, resource_type, data }
    event_type = payload['event_type']  # v3 uses 'event_type' not 'event'
    agreement_data = payload['data']

    # Process event (v3 terminology)
    case event_type
    when 'agreement.lifecycle.pending'
      handle_agreement_pending(agreement_data)
    when 'participant.lifecycle.fulfilled'
      handle_participant_fulfilled(agreement_data)
    when 'agreement.lifecycle.fulfilled'
      handle_agreement_fulfilled(agreement_data)
    when 'agreement.lifecycle.finalized'
      handle_agreement_finalized(agreement_data)
    when 'agreement.lifecycle.expired'
      handle_agreement_expired(agreement_data)
    when 'agreement.lifecycle.cancelled'
      handle_agreement_cancelled(agreement_data)
    else
      puts "⚠️  Unhandled webhook event: #{event_type}"
      return { status: 200, message: "Event type not implemented: #{event_type}", event: event_type }
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

    # Debug logging for signature verification
    puts "🔐 Signature Debug:"
    puts "   Received signature: #{signature}"
    puts "   Expected signature: #{expected_signature}"
    puts "   Body length: #{body.length} bytes"
    puts "   Secret length: #{@webhook_secret.length} chars"
    puts "   Match: #{signature == expected_signature}"

    # Constant-time comparison to prevent timing attacks
    Rack::Utils.secure_compare(signature, expected_signature)
  end

  # Handle agreement.lifecycle.pending event
  def handle_agreement_pending(data)
    agreement_id = data['id']
    title = data['title']
    test_mode = data['test_mode']
    expires_at = data['expires_at']
    participants = data['participants'] || []

    puts "📝 Agreement activated: #{agreement_id} - #{title}"
    puts "   Test mode: #{test_mode}"
    puts "   Expires: #{expires_at}"
    puts "   Participants: #{participants.length}"

    # Update database record
    contract = @repository.find_by_case_id(agreement_id)
    if contract
      # Update contract status
      contract.status = 'awaiting_signatures'

      # Update lifecycle tracking - PDF generated, validated, emails being sent
      contract.generation_status = 'completed'
      contract.generation_completed_at = Time.now
      contract.validation_status = 'completed'
      contract.validation_completed_at = Time.now
      contract.email_delivery_status = 'delivering'

      @repository.update(contract)

      # Create participant records for multi-party tracking
      participants.each do |participant_data|
        begin
          create_or_update_participant(contract.id, participant_data)
          puts "   ✅ Participant created: #{participant_data['name']}"
        rescue => e
          puts "   ⚠️  Failed to create participant #{participant_data['name']}: #{e.message}"
        end
      end
    else
      puts "⚠️  Warning: SignedContract record not found for agreement_id #{agreement_id}"
    end

    # Broadcast event
    @broadcaster&.broadcast_data('contract_status', {
      case_id: agreement_id,
      event: 'pending',
      title: title,
      test_mode: test_mode,
      expires_at: expires_at,
      participant_count: participants.length,
      timestamp: Time.now.to_i
    })
  end

  # Handle participant.lifecycle.fulfilled event (one signer completed)
  def handle_participant_fulfilled(data)
    participant_data = data['participant']
    agreement_id = data['agreement_id']

    participant_id = participant_data['id']
    name = participant_data['name']
    personal_number = participant_data['personal_number']
    signed_at = participant_data['signed_at']

    puts "✍️  Signature received: #{name} (#{personal_number})"
    puts "   Participant ID: #{participant_id}"
    puts "   Signed at: #{signed_at}"

    # Update database record with signature info
    contract = @repository.find_by_case_id(agreement_id)
    if contract
      # Update participant record (new tracking system)
      update_participant_fulfillment(participant_data)

      # Update legacy landlord/tenant fields (for backward compatibility)
      if is_landlord?(personal_number)
        contract.landlord_signed = true
        contract.landlord_signed_at = Time.parse(signed_at) if signed_at
      else
        contract.tenant_signed = true
        contract.tenant_signed_at = Time.parse(signed_at) if signed_at
      end

      @repository.update(contract)
    else
      puts "⚠️  Warning: SignedContract record not found for agreement_id #{agreement_id}"
    end

    # Broadcast event
    @broadcaster&.broadcast_data('contract_status', {
      case_id: agreement_id,
      event: 'participant_signed',
      participant_name: name,
      participant_id: participant_id,
      timestamp: Time.now.to_i
    })
  end

  # Handle agreement.lifecycle.fulfilled event (all signers done)
  def handle_agreement_fulfilled(data)
    agreement_id = data['id']
    title = data['title']
    fulfilled_at = data['fulfilled_at']

    puts "🎉 Contract fully signed: #{agreement_id} - #{title}"
    puts "   Fulfilled at: #{fulfilled_at}"

    contract = @repository.find_by_case_id(agreement_id)
    unless contract
      puts "⚠️  Warning: SignedContract record not found for agreement_id #{agreement_id}"
      return
    end

    # Update contract status - NOT 'completed' yet (waiting for finalized event)
    contract.status = 'fulfilled'
    contract.landlord_signed = true
    contract.tenant_signed = true

    # Mark email delivery as successful (all signers received and responded)
    contract.email_delivery_status = 'delivered'
    contract.landlord_email_delivered = true
    contract.tenant_email_delivered = true

    @repository.update(contract)

    # Broadcast event
    @broadcaster&.broadcast_data('contract_status', {
      case_id: agreement_id,
      event: 'fulfilled',
      title: title,
      fulfilled_at: fulfilled_at,
      timestamp: Time.now.to_i
    })
  end

  # Handle agreement.lifecycle.finalized event (signed PDF ready)
  def handle_agreement_finalized(data)
    agreement_id = data['id']
    title = data['title']
    signed_document_url = data['signed_document_url']
    finalized_at = data['finalized_at']

    puts "📥 Contract finalized: #{agreement_id}"
    puts "   Signed PDF URL: #{signed_document_url}"
    puts "   Finalized at: #{finalized_at}"

    contract = @repository.find_by_case_id(agreement_id)
    unless contract
      puts "⚠️  Warning: SignedContract record not found for agreement_id #{agreement_id}"
      return
    end

    # Auto-download signed PDF
    begin
      tenant = Persistence.tenants.find_by_id(contract.tenant_id)
      if tenant
        signer = ContractSigner.new(test_mode: contract.test_mode)
        signed_path = signer.download_signed_contract(agreement_id, tenant.name)

        # Update contract with signed PDF path and mark as completed
        contract.pdf_url = signed_path
        contract.status = 'completed'
        contract.completed_at = Time.parse(finalized_at) if finalized_at
        puts "✅ Signed PDF downloaded: #{signed_path}"
      end
    rescue => e
      puts "⚠️  Failed to auto-download signed PDF: #{e.message}"
      puts e.backtrace.join("\n")
    end

    @repository.update(contract)

    # Broadcast completion event
    @broadcaster&.broadcast_data('contract_status', {
      case_id: agreement_id,
      event: 'completed',
      title: title,
      signed_pdf_path: contract.pdf_url,
      finalized_at: finalized_at,
      timestamp: Time.now.to_i
    })

    # Future: Send notification emails/SMS
    # send_completion_notification(contract)
  end

  # Handle agreement.lifecycle.expired event
  def handle_agreement_expired(data)
    agreement_id = data['id']
    title = data['title']
    expired_at = data['expired_at']

    puts "⏰ Agreement expired: #{agreement_id} - #{title}"
    puts "   Expired at: #{expired_at}"

    contract = @repository.find_by_case_id(agreement_id)
    if contract
      contract.status = 'expired'
      @repository.update(contract)
    else
      puts "⚠️  Warning: SignedContract record not found for agreement_id #{agreement_id}"
    end

    # Broadcast event
    @broadcaster&.broadcast_data('contract_status', {
      case_id: agreement_id,
      event: 'expired',
      title: title,
      expired_at: expired_at,
      timestamp: Time.now.to_i
    })

    # Future: Send expiration notification
    # send_expiration_notification(contract)
  end

  # Handle agreement.lifecycle.cancelled event
  def handle_agreement_cancelled(data)
    agreement_id = data['id']
    title = data['title']
    cancellation_reason = data['cancellation_reason']
    cancelled_at = data['cancelled_at']

    puts "🚫 Agreement cancelled: #{agreement_id} - #{title}"
    puts "   Reason: #{cancellation_reason}" if cancellation_reason
    puts "   Cancelled at: #{cancelled_at}"

    contract = @repository.find_by_case_id(agreement_id)
    if contract
      contract.status = 'cancelled'
      @repository.update(contract)
    else
      puts "⚠️  Warning: SignedContract record not found for agreement_id #{agreement_id}"
    end

    # Broadcast event
    @broadcaster&.broadcast_data('contract_status', {
      case_id: agreement_id,
      event: 'cancelled',
      title: title,
      cancellation_reason: cancellation_reason,
      cancelled_at: cancelled_at,
      timestamp: Time.now.to_i
    })
  end

  private

  # Create or update participant record from Zigned webhook data
  def create_or_update_participant(contract_id, participant_data)
    participant_repo = Persistence.contract_participants

    participant_id = participant_data['id']
    existing = participant_repo.find_by_participant_id(participant_id)

    participant_attrs = {
      contract_id: contract_id,
      participant_id: participant_id,
      name: participant_data['name'],
      email: participant_data['email'],
      personal_number: participant_data['personal_number'],
      role: participant_data['role'] || 'signer',
      status: participant_data['status'] || 'pending',
      signing_url: participant_data['signing_url']
    }

    if existing
      # Update existing participant
      participant_attrs.each { |k, v| existing.send("#{k}=", v) if existing.respond_to?("#{k}=") && v }
      participant_repo.update(existing)
    else
      # Create new participant
      participant = ContractParticipant.new(**participant_attrs)
      participant_repo.save(participant)
    end
  end

  # Update participant fulfillment status from webhook event
  def update_participant_fulfillment(participant_data)
    participant_repo = Persistence.contract_participants

    participant_id = participant_data['id']
    participant = participant_repo.find_by_participant_id(participant_id)

    if participant
      participant.status = 'fulfilled'
      participant.signed_at = Time.parse(participant_data['signed_at']) if participant_data['signed_at']
      participant_repo.update(participant)
    else
      puts "⚠️  Warning: Participant not found: #{participant_id}"
    end
  end

  # Determine if participant is landlord (for legacy field updates)
  def is_landlord?(personal_number)
    personal_number&.gsub(/\D/, '') == '8604230717'
  end
end

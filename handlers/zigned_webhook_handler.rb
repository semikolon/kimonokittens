require 'json'
require 'openssl'
require 'logger'
require_relative '../lib/contract_signer'
require_relative '../lib/data_broadcaster'
require_relative '../lib/repositories/signed_contract_repository'
require_relative '../lib/persistence'

# Dedicated logger for Zigned webhook events
# Production: /var/log/kimonokittens/zigned-webhooks.log
# Development: log/zigned-webhooks.log (local project directory)
# Daily rotation, 14 days retention (aligned with planned logrotate config)
ZIGNED_LOG_PATH = if File.directory?('/var/log/kimonokittens')
  '/var/log/kimonokittens/zigned-webhooks.log'
else
  File.join(__dir__, '..', 'log', 'zigned-webhooks.log')
end

ZIGNED_LOGGER = Logger.new(
  ZIGNED_LOG_PATH,
  'daily',
  14
)
ZIGNED_LOGGER.level = Logger::INFO
ZIGNED_LOGGER.formatter = proc do |severity, datetime, progname, msg|
  "[#{datetime.strftime('%Y-%m-%d %H:%M:%S')}] #{severity}: #{msg}\n"
end

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

    # Zigned API quirk: v3 event names sent with v1 field structure
    # Field name: 'event' (v1), Event names: 'participant.lifecycle.fulfilled' (v3)
    event_type = payload['event_type'] || payload['event']
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

    # Participant tracking events
    when 'participant.identity_enforcement.passed'
      handle_identity_enforcement_passed(agreement_data)
    when 'participant.identity_enforcement.failed'
      handle_identity_enforcement_failed(agreement_data)

    # PDF validation events
    when 'agreement.pdf_verification.completed'
      handle_pdf_verification_completed(agreement_data)
    when 'agreement.pdf_verification.failed'
      handle_pdf_verification_failed(agreement_data)

    # Email delivery events
    when 'email_event.agreement_invitation.delivered'
      handle_email_invitation_delivered(agreement_data)
    when 'email_event.agreement_invitation.all_delivered'
      handle_all_emails_delivered(agreement_data)
    when 'email_event.agreement_invitation.delivery_failed'
      handle_email_delivery_failed(agreement_data)
    when 'email_event.agreement_finalized.delivered'
      handle_finalized_email_delivered(agreement_data)

    # Sign event tracking (participant engagement)
    when 'sign_event.signing_room.entered'
      handle_sign_event_viewing(agreement_data)
    when 'sign_event.document.loaded'
      handle_sign_event_document_loaded(agreement_data)
    when 'sign_event.document.began_scroll'
      handle_sign_event_reading(agreement_data)
    when 'sign_event.document.scrolled_to_bottom'
      handle_sign_event_reviewed(agreement_data)
    when 'sign_event.sign.initiated_sign'
      handle_sign_event_signing(agreement_data)
    when 'sign_event.sign.completed_sign'
      handle_sign_event_signed(agreement_data)

    else
      ZIGNED_LOGGER.warn "⚠️  Unhandled webhook event: #{event_type}"
      return { status: 200, message: "Event type not implemented: #{event_type}", event: event_type }
    end

    { status: 200, message: 'Webhook processed successfully', event: event_type }

  rescue => e
    ZIGNED_LOGGER.error "❌ Webhook error: #{e.message}"
    ZIGNED_LOGGER.error e.backtrace.join("\n")
    { status: 500, message: "Internal error: #{e.message}", error: true }
  end

  private

  # Verify webhook signature using HMAC-SHA256 with timestamp
  # Zigned uses format: "t=<timestamp>,v1=<signature>"
  def valid_signature?(body, signature_header)
    return false unless signature_header

    # Parse timestamped signature format
    parts = signature_header.split(',').map { |p| p.split('=', 2) }.to_h
    timestamp = parts['t']
    received_signature = parts['v1']

    return false unless timestamp && received_signature

    # Construct signed payload: timestamp + . + body
    signed_payload = "#{timestamp}.#{body}"

    expected_signature = OpenSSL::HMAC.hexdigest(
      OpenSSL::Digest.new('sha256'),
      @webhook_secret,
      signed_payload
    )

    # Debug logging for signature verification
    ZIGNED_LOGGER.info "🔐 Signature Debug:"
    ZIGNED_LOGGER.info "   Webhook secret: #{@webhook_secret[0..2]}...#{@webhook_secret[-3..-1]} (#{@webhook_secret.length} chars)"
    ZIGNED_LOGGER.info "   Received signature header: #{signature_header}"
    ZIGNED_LOGGER.info "   Parsed timestamp: #{timestamp}"
    ZIGNED_LOGGER.info "   Parsed signature (v1): #{received_signature}"
    ZIGNED_LOGGER.info "   Signed payload: timestamp.body (#{signed_payload.length} bytes)"
    ZIGNED_LOGGER.info "   Signed payload first 50 chars: #{signed_payload[0..49]}"
    ZIGNED_LOGGER.info "   Expected signature: #{expected_signature}"
    ZIGNED_LOGGER.info "   Match: #{received_signature == expected_signature}"

    # Constant-time comparison to prevent timing attacks
    Rack::Utils.secure_compare(received_signature, expected_signature)
  end

  # Handle agreement.lifecycle.pending event
  def handle_agreement_pending(data)
    agreement_id = data['id']
    title = data['title']
    test_mode = data['test_mode']
    expires_at = data['expires_at']
    participants = data['participants'] || []

    ZIGNED_LOGGER.info "📝 Agreement activated: #{agreement_id} - #{title}"
    ZIGNED_LOGGER.info "   Test mode: #{test_mode}"
    ZIGNED_LOGGER.info "   Expires: #{expires_at}"
    ZIGNED_LOGGER.info "   Participants: #{participants.length}"

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

      # Note: Participants array contains only IDs, not full objects
      # Participant records will be created when participant.lifecycle.fulfilled events arrive
      ZIGNED_LOGGER.info "   📋 Participants (IDs only): #{participants.join(', ')}"
    else
      ZIGNED_LOGGER.warn "⚠️  Warning: SignedContract record not found for agreement_id #{agreement_id}"
    end

    # Broadcast event
    @broadcaster&.broadcast_contract_update(agreement_id, 'pending', {
      title: title,
      test_mode: test_mode,
      expires_at: expires_at,
      participant_count: participants.length
    })
  end

  # Handle participant.lifecycle.fulfilled event (one signer completed)
  def handle_participant_fulfilled(data)
    # In actual v3 webhooks, data IS the participant (not data.participant)
    participant_id = data['id']
    name = data['name']
    email = data['email']
    agreement_id = data['agreement']  # Field is 'agreement', not 'agreement_id'
    signed_at = data['signed_at']
    status = data['status']
    role = data['role']

    # Look up personal_number from existing participant record
    participant_repo = Persistence.contract_participants
    participant = participant_repo.find_by_participant_id(participant_id)
    personal_number = participant&.personal_number

    ZIGNED_LOGGER.info "✍️  Signature received: #{name} (#{email})"
    ZIGNED_LOGGER.info "   Participant ID: #{participant_id}"
    ZIGNED_LOGGER.info "   Agreement ID: #{agreement_id}"
    ZIGNED_LOGGER.info "   Signed at: #{signed_at}"
    ZIGNED_LOGGER.info "   Role: #{role}, Status: #{status}"

    # Update database record with signature info
    contract = @repository.find_by_case_id(agreement_id)
    if contract
      # Update participant record (new tracking system)
      if participant
        participant.status = 'fulfilled'
        participant.signed_at = Time.parse(signed_at) if signed_at
        participant_repo.update(participant)
        ZIGNED_LOGGER.info "   ✅ Participant record updated"
      else
        ZIGNED_LOGGER.warn "   ⚠️  Participant record not found - creating new one"
        # Create participant record if it doesn't exist (fallback)
        create_or_update_participant(contract.id, data)
      end

      # Update legacy landlord/tenant fields (for backward compatibility)
      if personal_number && is_landlord?(personal_number)
        contract.landlord_signed = true
        contract.landlord_signed_at = Time.parse(signed_at) if signed_at
        ZIGNED_LOGGER.info "   ✅ Landlord signature recorded"
      elsif personal_number
        contract.tenant_signed = true
        contract.tenant_signed_at = Time.parse(signed_at) if signed_at
        ZIGNED_LOGGER.info "   ✅ Tenant signature recorded"
      end

      @repository.update(contract)
    else
      ZIGNED_LOGGER.warn "⚠️  Warning: SignedContract record not found for agreement_id #{agreement_id}"
    end

    # Broadcast event
    @broadcaster&.broadcast_contract_update(agreement_id, 'participant_signed', {
      participant_name: name,
      participant_id: participant_id
    })
  end

  # Handle agreement.lifecycle.fulfilled event (all signers done)
  def handle_agreement_fulfilled(data)
    agreement_id = data['id']
    title = data['title']
    fulfilled_at = data['fulfilled_at']

    ZIGNED_LOGGER.info "🎉 Contract fully signed: #{agreement_id} - #{title}"
    ZIGNED_LOGGER.info "   Fulfilled at: #{fulfilled_at}"

    contract = @repository.find_by_case_id(agreement_id)
    unless contract
      ZIGNED_LOGGER.warn "⚠️  Warning: SignedContract record not found for agreement_id #{agreement_id}"
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
    @broadcaster&.broadcast_contract_update(agreement_id, 'fulfilled', {
      title: title,
      fulfilled_at: fulfilled_at
    })
  end

  # Handle agreement.lifecycle.finalized event (signed PDF ready)
  def handle_agreement_finalized(data)
    agreement_id = data['id']
    title = data['title']
    finalized_at = data['updated_at']  # Use updated_at as finalized timestamp

    # Extract signed document URL from nested structure
    signed_document = data.dig('documents', 'signed_document', 'data')
    signed_document_url = signed_document&.dig('url')
    signed_document_filename = signed_document&.dig('filename')

    ZIGNED_LOGGER.info "📥 Contract finalized: #{agreement_id}"
    ZIGNED_LOGGER.info "   Title: #{title}"
    ZIGNED_LOGGER.info "   Signed PDF filename: #{signed_document_filename}"
    ZIGNED_LOGGER.info "   Signed PDF URL: #{signed_document_url}"
    ZIGNED_LOGGER.info "   Finalized at: #{finalized_at}"

    contract = @repository.find_by_case_id(agreement_id)
    unless contract
      ZIGNED_LOGGER.warn "⚠️  Warning: SignedContract record not found for agreement_id #{agreement_id}"
      return
    end

    # Auto-download signed PDF
    begin
      tenant = Persistence.tenants.find_by_id(contract.tenant_id)
      if tenant && signed_document_url
        signer = ContractSigner.new(test_mode: contract.test_mode)
        signed_path = signer.download_signed_pdf_from_url(signed_document_url, tenant.name)

        # Update contract with signed PDF path and mark as completed
        contract.pdf_url = signed_path
        contract.status = 'completed'
        contract.completed_at = Time.parse(finalized_at) if finalized_at
        ZIGNED_LOGGER.info "✅ Signed PDF downloaded: #{signed_path}"
      end
    rescue => e
      ZIGNED_LOGGER.warn "⚠️  Failed to auto-download signed PDF: #{e.message}"
      ZIGNED_LOGGER.warn e.backtrace.join("\n")
    end

    @repository.update(contract)

    # Broadcast completion event
    @broadcaster&.broadcast_contract_update(agreement_id, 'completed', {
      title: title,
      signed_pdf_path: contract.pdf_url,
      finalized_at: finalized_at
    })

    # Future: Send notification emails/SMS
    # send_completion_notification(contract)
  end

  # Handle agreement.lifecycle.expired event
  def handle_agreement_expired(data)
    agreement_id = data['id']
    title = data['title']
    expired_at = data['expired_at']

    ZIGNED_LOGGER.info "⏰ Agreement expired: #{agreement_id} - #{title}"
    ZIGNED_LOGGER.info "   Expired at: #{expired_at}"

    contract = @repository.find_by_case_id(agreement_id)
    if contract
      contract.status = 'expired'
      @repository.update(contract)
    else
      ZIGNED_LOGGER.warn "⚠️  Warning: SignedContract record not found for agreement_id #{agreement_id}"
    end

    # Broadcast event
    @broadcaster&.broadcast_contract_update(agreement_id, 'expired', {
      title: title,
      expired_at: expired_at
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

    ZIGNED_LOGGER.info "🚫 Agreement cancelled: #{agreement_id} - #{title}"
    ZIGNED_LOGGER.info "   Reason: #{cancellation_reason}" if cancellation_reason
    ZIGNED_LOGGER.info "   Cancelled at: #{cancelled_at}"

    contract = @repository.find_by_case_id(agreement_id)
    if contract
      contract.status = 'cancelled'
      @repository.update(contract)
    else
      ZIGNED_LOGGER.warn "⚠️  Warning: SignedContract record not found for agreement_id #{agreement_id}"
    end

    # Broadcast event
    @broadcaster&.broadcast_contract_update(agreement_id, 'cancelled', {
      title: title,
      cancellation_reason: cancellation_reason,
      cancelled_at: cancelled_at
    })
  end

  # Handle participant.identity_enforcement.passed event
  def handle_identity_enforcement_passed(data)
    participant_id = data['id']
    name = data['name']
    agreement_id = data['agreement']
    identity_status = data.dig('identity_enforcement', 'status')
    enforcement_method = data.dig('identity_enforcement', 'enforcement_method')

    ZIGNED_LOGGER.info "🔐 Identity enforcement passed: #{name}"
    ZIGNED_LOGGER.info "   Participant ID: #{participant_id}"
    ZIGNED_LOGGER.info "   Method: #{enforcement_method}"
    ZIGNED_LOGGER.info "   Status: #{identity_status}"

    # Update participant record
    participant_repo = Persistence.contract_participants
    participant = participant_repo.find_by_participant_id(participant_id)

    if participant
      participant.identity_enforcement_passed = true
      participant_repo.update(participant)
      ZIGNED_LOGGER.info "   ✅ Participant identity verified"
    else
      ZIGNED_LOGGER.warn "   ⚠️  Participant record not found - will be created on fulfillment"
    end
  end

  # Handle agreement.pdf_verification.completed event
  def handle_pdf_verification_completed(data)
    agreement_id = data['id']
    status = data['status']
    updated_at = data['updated_at']

    ZIGNED_LOGGER.info "📋 PDF verification completed: #{agreement_id}"
    ZIGNED_LOGGER.info "   Status: #{status}"
    ZIGNED_LOGGER.info "   Verified at: #{updated_at}"

    contract = @repository.find_by_case_id(agreement_id)
    if contract
      contract.validation_status = 'completed'
      contract.validation_completed_at = Time.parse(updated_at) if updated_at
      @repository.update(contract)
      ZIGNED_LOGGER.info "   ✅ Contract validation status updated"
    else
      ZIGNED_LOGGER.warn "   ⚠️  Contract record not found for agreement_id #{agreement_id}"
    end
  end

  # Handle email_event.agreement_invitation.delivered event
  def handle_email_invitation_delivered(data)
    agreement_id = data['agreement']
    description = data['description']  # "Invitation to sign successfully delivered to branstrom@gmail.com"
    created_at = data['created_at']

    # Extract email from description
    email = description[/delivered to ([^\s]+)/, 1]

    ZIGNED_LOGGER.info "📧 Email invitation delivered: #{agreement_id}"
    ZIGNED_LOGGER.info "   To: #{email}"
    ZIGNED_LOGGER.info "   At: #{created_at}"

    # Mark email as delivered for specific participant (by email lookup)
    if email
      participant_repo = Persistence.contract_participants
      contract = @repository.find_by_case_id(agreement_id)

      if contract
        # Find participant by email
        participants = participant_repo.find_by_contract_id(contract.id)
        participant = participants.find { |p| p.email == email }

        if participant
          participant.email_delivered = true
          participant.email_delivered_at = Time.parse(created_at) if created_at
          participant_repo.update(participant)
          ZIGNED_LOGGER.info "   ✅ Participant email delivery recorded"
        else
          ZIGNED_LOGGER.warn "   ⚠️  Participant not found for email #{email}"
        end
      end
    end
  end

  # Handle email_event.agreement_invitation.all_delivered event
  def handle_all_emails_delivered(data)
    agreement_id = data['agreement']
    created_at = data['created_at']

    ZIGNED_LOGGER.info "📬 All invitation emails delivered: #{agreement_id}"
    ZIGNED_LOGGER.info "   At: #{created_at}"

    contract = @repository.find_by_case_id(agreement_id)
    if contract
      contract.email_delivery_status = 'delivered'
      @repository.update(contract)
      ZIGNED_LOGGER.info "   ✅ Contract email delivery status updated"
    end
  end

  # Handle email_event.agreement_finalized.delivered event
  def handle_finalized_email_delivered(data)
    agreement_id = data['agreement']
    description = data['description']  # "Signed document successfully delivered to branstrom@gmail.com"

    email = description[/delivered to ([^\s]+)/, 1]

    ZIGNED_LOGGER.info "📨 Signed document email delivered: #{agreement_id}"
    ZIGNED_LOGGER.info "   To: #{email}"
    ZIGNED_LOGGER.info "   ✅ Final document delivered"
  end

  # Handle participant.identity_enforcement.failed event
  def handle_identity_enforcement_failed(data)
    participant_id = data['id']
    name = data['name']
    agreement_id = data['agreement']
    identity_status = data.dig('identity_enforcement', 'status')
    enforcement_method = data.dig('identity_enforcement', 'enforcement_method')
    failure_reason = data.dig('identity_enforcement', 'failure_reason')

    ZIGNED_LOGGER.error "❌ Identity enforcement failed: #{name}"
    ZIGNED_LOGGER.info "   Participant ID: #{participant_id}"
    ZIGNED_LOGGER.info "   Method: #{enforcement_method}"
    ZIGNED_LOGGER.info "   Status: #{identity_status}"
    ZIGNED_LOGGER.info "   Reason: #{failure_reason}" if failure_reason

    # Update participant record
    participant_repo = Persistence.contract_participants
    participant = participant_repo.find_by_participant_id(participant_id)

    if participant
      participant.identity_enforcement_passed = false
      participant.identity_enforcement_failed_at = Time.now
      participant_repo.update(participant)
      ZIGNED_LOGGER.warn "   ⚠️  Participant identity verification failed - recorded"
    else
      ZIGNED_LOGGER.warn "   ⚠️  Participant record not found"
    end
  end

  # Handle agreement.pdf_verification.failed event
  def handle_pdf_verification_failed(data)
    agreement_id = data['id']
    status = data['status']
    updated_at = data['updated_at']
    error_message = data['error'] || data['validation_error']

    ZIGNED_LOGGER.error "❌ PDF verification failed: #{agreement_id}"
    ZIGNED_LOGGER.info "   Status: #{status}"
    ZIGNED_LOGGER.info "   Error: #{error_message}" if error_message
    ZIGNED_LOGGER.info "   Failed at: #{updated_at}"

    contract = @repository.find_by_case_id(agreement_id)
    if contract
      contract.validation_status = 'failed'
      contract.validation_failed_at = Time.parse(updated_at) if updated_at
      contract.validation_errors = error_message if error_message
      @repository.update(contract)
      ZIGNED_LOGGER.warn "   ⚠️  Contract validation failure recorded"
    else
      ZIGNED_LOGGER.warn "   ⚠️  Contract record not found for agreement_id #{agreement_id}"
    end
  end

  # Handle email_event.agreement_invitation.delivery_failed event
  def handle_email_delivery_failed(data)
    agreement_id = data['agreement']
    description = data['description']
    error_message = data['error'] || data['bounce_reason']
    created_at = data['created_at']

    # Extract email from description
    email = description[/delivered to ([^\s]+)/, 1] if description

    ZIGNED_LOGGER.error "❌ Email delivery failed: #{agreement_id}"
    ZIGNED_LOGGER.info "   To: #{email}" if email
    ZIGNED_LOGGER.info "   Error: #{error_message}" if error_message
    ZIGNED_LOGGER.info "   Failed at: #{created_at}"

    # Update participant email delivery failure
    if email
      participant_repo = Persistence.contract_participants
      contract = @repository.find_by_case_id(agreement_id)

      if contract
        # Find participant by email
        participants = participant_repo.find_by_contract_id(contract.id)
        participant = participants.find { |p| p.email == email }

        if participant
          participant.email_delivered = false
          participant.email_delivery_failed = true
          participant.email_delivery_error = error_message if error_message
          participant_repo.update(participant)
          ZIGNED_LOGGER.warn "   ⚠️  Participant email failure recorded"
        else
          ZIGNED_LOGGER.warn "   ⚠️  Participant not found for email #{email}"
        end

        # Also update contract-level email status
        contract.email_delivery_status = 'failed'
        contract.email_delivery_failed_at = Time.parse(created_at) if created_at
        contract.email_delivery_error = error_message if error_message
        @repository.update(contract)
      end
    end
  end

  private

  # Create or update participant record from Zigned webhook data
  def create_or_update_participant(contract_id, participant_data)
    participant_repo = Persistence.contract_participants

    participant_id = participant_data['id']
    existing = participant_repo.find_by_participant_id(participant_id)

    # Webhooks don't send personal_number - look it up from contract + tenant
    personal_number = participant_data['personal_number'] || lookup_personal_number(contract_id, participant_data)

    # Handle field name inconsistency: signing_url vs signing_room_url
    signing_url = participant_data['signing_url'] || participant_data['signing_room_url']

    participant_attrs = {
      contract_id: contract_id,
      participant_id: participant_id,
      name: participant_data['name'],
      email: participant_data['email'],
      personal_number: personal_number,
      role: participant_data['role'] || 'signer',
      status: participant_data['status'] || 'pending',
      signing_url: signing_url,
      signed_at: participant_data['signed_at'] ? Time.parse(participant_data['signed_at']) : nil
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
      ZIGNED_LOGGER.warn "⚠️  Warning: Participant not found: #{participant_id}"
    end
  end

  # Look up personal_number from contract + tenant data
  # Webhooks don't send personal_number, so we match by email
  def lookup_personal_number(contract_id, participant_data)
    email = participant_data['email']

    # Landlord email (hardcoded in ContractSigner)
    landlord_email = 'branstrom@gmail.com'
    landlord_personnummer = '8604230717'

    # Check if this is the landlord
    return landlord_personnummer if email&.downcase == landlord_email

    # Otherwise look up tenant personnummer from contract
    contract = @repository.find_by_id(contract_id)
    if contract
      tenant = Persistence.tenants.find_by_id(contract.tenant_id)
      return tenant.personnummer if tenant
    end

    # Fallback: nil (will cause validation error, but with better logging)
    ZIGNED_LOGGER.warn "⚠️  Warning: Could not lookup personal_number for #{email} (contract #{contract_id})"
    nil
  end

  # Determine if participant is landlord (for legacy field updates)
  def is_landlord?(personal_number)
    personal_number&.gsub(/\D/, '') == '8604230717'
  end

  # ========== SIGN EVENT HANDLERS (Participant Engagement Tracking) ==========

  # Generic helper to update participant status from sign events
  def update_participant_status_from_sign_event(data, new_status, log_emoji, log_message)
    agreement_id = data['agreement_id']
    participant_email = data['participant_email']
    occurred_at = data['occurred_at']

    contract = @repository.find_by_case_id(agreement_id)
    unless contract
      ZIGNED_LOGGER.warn "⚠️  Warning: Contract not found for sign_event (#{agreement_id})"
      return
    end

    # Find participant by email
    participant_repo = Persistence.contract_participants
    participant = participant_repo.find_by_contract_and_email(contract.id, participant_email)

    unless participant
      ZIGNED_LOGGER.warn "⚠️  Warning: Participant not found for email #{participant_email} (contract #{contract.id})"
      return
    end

    # Update status
    participant.status = new_status
    participant_repo.update(participant)

    ZIGNED_LOGGER.info "#{log_emoji} #{log_message}: #{participant.name} (#{participant_email})"
    ZIGNED_LOGGER.info "   Agreement: #{agreement_id}"
    ZIGNED_LOGGER.info "   Status: #{participant.status}"
    ZIGNED_LOGGER.info "   Time: #{occurred_at}"

    # Broadcast real-time update
    @broadcaster&.broadcast_contract_update(agreement_id, 'participant_status_updated', {
      participant_id: participant.id,
      participant_name: participant.name,
      status: new_status,
      occurred_at: occurred_at
    })
  end

  # Handle signing room entered (participant opened link)
  def handle_sign_event_viewing(data)
    update_participant_status_from_sign_event(
      data,
      'viewing',
      '👀',
      'Participant opened signing room'
    )
  end

  # Handle document loaded (PDF rendered in viewer)
  def handle_sign_event_document_loaded(data)
    # Don't change status - this is just a technical event
    ZIGNED_LOGGER.info "📄 Document loaded by #{data['participant_email']}"
  end

  # Handle document scroll started (participant is reading)
  def handle_sign_event_reading(data)
    update_participant_status_from_sign_event(
      data,
      'reading',
      '📖',
      'Participant started reading'
    )
  end

  # Handle scrolled to bottom (participant reviewed entire contract)
  def handle_sign_event_reviewed(data)
    update_participant_status_from_sign_event(
      data,
      'reviewed',
      '✅',
      'Participant reviewed entire contract'
    )
  end

  # Handle BankID authentication initiated
  def handle_sign_event_signing(data)
    update_participant_status_from_sign_event(
      data,
      'signing',
      '🔐',
      'Participant initiated BankID signing'
    )
  end

  # Handle BankID signature completed
  def handle_sign_event_signed(data)
    agreement_id = data['agreement_id']
    participant_email = data['participant_email']
    occurred_at = data['occurred_at']

    contract = @repository.find_by_case_id(agreement_id)
    unless contract
      ZIGNED_LOGGER.warn "⚠️  Warning: Contract not found for sign_event (#{agreement_id})"
      return
    end

    # Find participant by email
    participant_repo = Persistence.contract_participants
    participant = participant_repo.find_by_contract_and_email(contract.id, participant_email)

    unless participant
      ZIGNED_LOGGER.warn "⚠️  Warning: Participant not found for email #{participant_email} (contract #{contract.id})"
      return
    end

    # Update status AND set signed_at timestamp
    participant.status = 'signed'
    participant.signed_at = Time.parse(occurred_at) if occurred_at
    participant_repo.update(participant)

    ZIGNED_LOGGER.info "🎉 Participant completed BankID signature: #{participant.name}"
    ZIGNED_LOGGER.info "   Agreement: #{agreement_id}"
    ZIGNED_LOGGER.info "   Signed at: #{participant.signed_at}"

    # Broadcast real-time update
    @broadcaster&.broadcast_contract_update(agreement_id, 'participant_signed', {
      participant_id: participant.id,
      participant_name: participant.name,
      signed_at: participant.signed_at&.iso8601
    })
  end
end

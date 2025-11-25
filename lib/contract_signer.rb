require_relative 'contract_generator_html'
require_relative 'zigned_client_v3'
require_relative 'repositories/tenant_repository'
require_relative 'repositories/signed_contract_repository'
require_relative 'models/signed_contract'
require_relative 'persistence'
require 'json'
require 'fileutils'
require 'securerandom'

require_relative 'landlord_profile'

# ContractSigner orchestrates the entire contract signing workflow
#
# Responsibilities:
# - Generate PDF from tenant data
# - Upload to Zigned for e-signing
# - Track signing status
# - Save metadata for future database integration
#
# Usage:
#   signer = ContractSigner.new(test_mode: true)
#
#   result = signer.sign_contract(
#     tenant: {
#       name: 'Sanna Juni Benemar',
#       personnummer: '8706220020',
#       email: 'sanna_benemar@hotmail.com',
#       phone: '070 289 44 37',
#       move_in_date: Date.new(2025, 11, 1)
#     }
#   )
#
#   # Result contains:
#   # - pdf_path: Generated PDF location
#   # - case_id: Zigned case ID
#   # - signing_links: Hash of personnummer => URL
#   # - metadata_path: JSON metadata file
class ContractSigner
  CONTRACTS_DIR = File.join(File.dirname(__FILE__), '../contracts')
  GENERATED_DIR = File.join(CONTRACTS_DIR, 'generated')
  SIGNED_DIR = File.join(CONTRACTS_DIR, 'signed')
  METADATA_DIR = File.join(CONTRACTS_DIR, 'metadata')

  # Database-driven contract signing (PRODUCTION CODE PATH)
  #
  # Generates contract from database tenant record and sends for e-signing
  #
  # @param tenant_id [String] Tenant ID from database
  # @param test_mode [Boolean] Use Zigned test environment (default: false)
  # @param send_emails [Boolean] Whether Zigned should send email invitations (default: true)
  #
  # @return [Hash] {
  #   pdf_path: String,
  #   case_id: String,
  #   signing_links: Hash,
  #   landlord_link: String,
  #   tenant_link: String
  # }
  #
  # @example
  #   # Test mode with no emails (safe for testing)
  #   result = ContractSigner.create_and_send(
  #     tenant_id: 'cmhqe9enc0000wopipuxgc3kw',
  #     test_mode: true,
  #     send_emails: false
  #   )
  #
  #   # Production mode (real BankID signatures, sends emails)
  #   result = ContractSigner.create_and_send(
  #     tenant_id: 'cmhqe9enc0000wopipuxgc3kw'
  #   )
  def self.create_and_send(tenant_id:, test_mode: false, send_emails: true)
    # Load tenant from database
    repo = TenantRepository.new
    tenant = repo.find_by_id(tenant_id)
    raise ArgumentError, "Tenant not found: #{tenant_id}" unless tenant

    puts "👤 Loading tenant: #{tenant.name}"
    puts "   Email: #{tenant.email}"
    puts "   Phone: #{tenant.phone}"
    puts "   Start_date: #{tenant.start_date}"
    puts "   Test mode: #{test_mode ? 'YES (free, invalid signatures)' : 'NO (production, real BankID)'}"
    puts "   Send emails: #{send_emails ? 'YES' : 'NO (manual link sharing)'}"
    puts ""

    # Check if tenant IS the landlord (self-contract)
    landlord = LandlordProfile.info
    tenant_pnr = tenant.personnummer&.gsub(/\D/, '')
    landlord_pnr = landlord[:personnummer]&.gsub(/\D/, '')
    is_self_contract = tenant_pnr && landlord_pnr && tenant_pnr == landlord_pnr

    if is_self_contract
      puts "🏠 Self-contract detected (tenant = landlord)"
      puts "   Skipping Zigned - landlord signature implicit"
      return create_self_contract(tenant_id: tenant_id, tenant: tenant, test_mode: test_mode)
    end

    # Step 1: Generate PDF from database
    # Sanitize Swedish characters for filesystem-safe filename
    name_parts = tenant.name.split(' ')
    first_name = name_parts.first
    surname = name_parts.last
    sanitized_first = first_name.tr('åäöÅÄÖ', 'aaoAAO')
    sanitized_surname = surname.tr('åäöÅÄÖ', 'aaoAAO')
    pdf_filename = "#{sanitized_first}_#{sanitized_surname}_Hyresavtal_#{tenant.start_date&.strftime('%Y-%m-%d') || 'DRAFT'}.pdf"
    pdf_path = File.join(GENERATED_DIR, pdf_filename)

    puts "📄 Generating contract PDF from database..."
    ContractGeneratorHtml.generate_from_tenant_id(tenant_id, output_path: pdf_path)
    puts "✅ PDF generated: #{pdf_path} (#{File.size(pdf_path)} bytes)"

    # Step 2: Create Zigned signing case
    puts "\n🔐 Creating Zigned signing case..."

    zigned = ZignedClientV3.new(
      client_id: ENV['ZIGNED_CLIENT_ID'] || raise('ZIGNED_CLIENT_ID not set in environment'),
      client_secret: ENV['ZIGNED_API_KEY'] || raise('ZIGNED_API_KEY not set in environment'),
      test_mode: test_mode
    )

    landlord = LandlordProfile.info

    case_title = "Hyresavtal - #{tenant.name}"
    webhook_url = ENV['WEBHOOK_BASE_URL'] ? "#{ENV['WEBHOOK_BASE_URL']}/api/webhooks/zigned" : nil

    signers = [
      landlord,
      {
        name: tenant.name,
        personnummer: tenant.personnummer,
        email: tenant.email
      }
    ]

    # send_emails parameter controls whether Zigned sends email invitations
    zigned_result = zigned.create_and_activate(
      pdf_path: pdf_path,
      signers: signers,
      title: case_title,
      webhook_url: webhook_url,
      message: "Välkommen till Kimono Kittens! Vänligen signera hyresavtalet med ditt BankID.",
      send_emails: send_emails
    )

    puts "✅ Signing case created: #{zigned_result[:case_id]}"
    puts "📅 Expires at: #{zigned_result[:expires_at]}"

    # Step 3: Save to database (replaces file-based metadata)
    # NOTE: Lookup by email (not personal number) - Zigned API uses email as unique identifier
    landlord_link = zigned_result[:signing_links][landlord[:email]]
    tenant_link = zigned_result[:signing_links][tenant.email]

    signed_contract = SignedContract.new(
      id: SecureRandom.uuid,
      tenant_id: tenant_id,
      case_id: zigned_result[:case_id],
      pdf_url: pdf_path,  # Will be updated to signed PDF path when completed
      status: 'pending',
      landlord_signed: false,
      tenant_signed: false,
      landlord_signing_url: landlord_link,
      tenant_signing_url: tenant_link,
      test_mode: test_mode,
      expires_at: zigned_result[:expires_at] ? Time.parse(zigned_result[:expires_at]) : Time.now + (30 * 24 * 60 * 60),  # Default 30 days for test mode
      created_at: Time.now,
      updated_at: Time.now
    )

    Persistence.signed_contracts.save(signed_contract)
    puts "✅ Contract record saved to database"

    # Step 3.5: Create participant records (will be enriched by Zigned webhooks)
    require_relative 'models/contract_participant'
    participant_repo = Persistence.contract_participants

    landlord_participant = ContractParticipant.new(
      id: SecureRandom.uuid,
      contract_id: signed_contract.id,
      participant_id: nil, # Will be set by webhook
      name: landlord[:name],
      email: landlord[:email],
      personal_number: landlord[:personnummer],
      role: 'landlord',
      signing_url: landlord_link,
      signed_at: nil, # Will be set by webhook when signed
      sms_delivered: false, # Will be set to true after SMS sends
      email_delivered: false, # Will be set to true by webhook
      created_at: Time.now,
      updated_at: Time.now
    )

    tenant_participant = ContractParticipant.new(
      id: SecureRandom.uuid,
      contract_id: signed_contract.id,
      participant_id: nil, # Will be set by webhook
      name: tenant.name,
      email: tenant.email,
      personal_number: tenant.personnummer,
      role: 'tenant',
      signing_url: tenant_link,
      signed_at: nil, # Will be set by webhook when signed
      sms_delivered: false, # Will be set to true after SMS sends
      email_delivered: false, # Will be set to true by webhook
      created_at: Time.now,
      updated_at: Time.now
    )

    participant_repo.save(landlord_participant)
    participant_repo.save(tenant_participant)
    puts "✅ Participant records created"

    # Step 4: Send SMS notifications with signing links
    sms_sent = send_contract_invitation_sms(tenant, tenant_link, landlord, landlord_link)

    # Step 4.5: Mark SMS as delivered if sent successfully
    if sms_sent[:tenant_success]
      tenant_participant.sms_delivered = true
      tenant_participant.sms_delivered_at = Time.now
      participant_repo.update(tenant_participant)
    end

    if sms_sent[:landlord_success]
      landlord_participant.sms_delivered = true
      landlord_participant.sms_delivered_at = Time.now
      participant_repo.update(landlord_participant)
    end

    if sms_sent[:tenant_success] || sms_sent[:landlord_success]
      puts "✅ SMS delivery tracked in database"
    end

    # Step 5: Print signing links
    puts "\n🔗 Signing Links:"
    puts "\nLandlord (#{landlord[:name]}):"
    puts landlord_link
    puts "\nTenant (#{tenant.name}):"
    puts tenant_link

    if send_emails
      puts "\n📧 Zigned will send email invitations to both parties."
    else
      puts "\n⚠️  Email invitations disabled - share links manually."
    end

    # Return result
    {
      pdf_path: pdf_path,
      case_id: zigned_result[:case_id],
      signing_links: zigned_result[:signing_links],
      landlord_link: landlord_link,
      tenant_link: tenant_link,
      expires_at: zigned_result[:expires_at],
      status: zigned_result[:status],
      contract_id: signed_contract.id
    }
  end

  # @param test_mode [Boolean] Use Zigned test environment (free, no real signatures)
  def initialize(test_mode: false)
    @test_mode = test_mode
    @generator = nil  # Lazy-loaded when needed (only for PDF generation, not downloads)
    @zigned = ZignedClientV3.new(
      client_id: ENV['ZIGNED_CLIENT_ID'] || raise('ZIGNED_CLIENT_ID not set in environment'),
      client_secret: ENV['ZIGNED_API_KEY'] || raise('ZIGNED_API_KEY not set in environment'),
      test_mode: test_mode
    )

    ensure_directories_exist
  end

  # Generate contract PDF and send for e-signing
  #
  # @param tenant [Hash] Tenant information (name, personnummer, email, phone, move_in_date)
  # @param send_emails [Boolean] Whether Zigned should send email invitations (default: true)
  #
  # @return [Hash] {
  #   pdf_path: String,
  #   case_id: String,
  #   signing_links: Hash,
  #   metadata_path: String,
  #   landlord_link: String,
  #   tenant_link: String
  # }
  def sign_contract(tenant:, send_emails: true)
    validate_tenant_data!(tenant)

    # Step 1: Generate PDF
    pdf_filename = generate_filename(tenant)
    pdf_path = File.join(GENERATED_DIR, pdf_filename)

    puts "📄 Generating contract PDF..."
    @generator ||= ContractGenerator.new  # Lazy-load generator only when needed
    @generator.generate(tenant: tenant, output_path: pdf_path)
    puts "✅ PDF generated: #{pdf_path}"

    # Step 2: Create Zigned signing case
    puts "\n🔐 Creating Zigned signing case..."
    case_title = "Hyresavtal - #{tenant[:name]}"
    webhook_url = ENV['WEBHOOK_BASE_URL'] ? "#{ENV['WEBHOOK_BASE_URL']}/api/webhooks/zigned" : nil

    landlord = LandlordProfile.info
    signers = [
      landlord,
      { name: tenant[:name], personnummer: tenant[:personnummer], email: tenant[:email] }
    ]

    zigned_result = @zigned.create_and_activate(
      pdf_path: pdf_path,
      signers: signers,
      title: case_title,
      webhook_url: webhook_url,
      message: "Välkommen till BRF Kimonokittens! Vänligen signera hyresavtalet med ditt BankID.",
      send_emails: send_emails
    )

    puts "✅ Signing case created: #{zigned_result[:case_id]}"
    puts "📅 Expires at: #{zigned_result[:expires_at]}"

    # Step 3: Save metadata
    metadata = {
      tenant_name: tenant[:name],
      tenant_personnummer: tenant[:personnummer],
      tenant_email: tenant[:email],
      tenant_phone: tenant[:phone],
      move_in_date: tenant[:move_in_date].strftime('%Y-%m-%d'),
      pdf_path: pdf_path,
      case_id: zigned_result[:case_id],
      status: zigned_result[:status],
      created_at: Time.now.strftime('%Y-%m-%d %H:%M:%S'),
      expires_at: zigned_result[:expires_at],
      test_mode: @test_mode,
      signing_links: zigned_result[:signing_links]
    }

    metadata_path = save_metadata(tenant, metadata)
    puts "✅ Metadata saved: #{metadata_path}"

    # Step 4: Print signing links
    landlord_link = zigned_result[:signing_links][landlord[:personnummer].gsub(/\D/, '')]
    tenant_link = zigned_result[:signing_links][tenant[:personnummer].gsub(/\D/, '')]

    puts "\n🔗 Signing Links:"
    puts "\nLandlord (#{landlord[:name]}):"
    puts landlord_link
    puts "\nTenant (#{tenant[:name]}):"
    puts tenant_link

    if send_emails
      puts "\n📧 Zigned will send email invitations to both parties."
    else
      puts "\n⚠️  Email invitations disabled - share links manually."
    end

    # Return comprehensive result
    {
      pdf_path: pdf_path,
      case_id: zigned_result[:case_id],
      signing_links: zigned_result[:signing_links],
      metadata_path: metadata_path,
      landlord_link: landlord_link,
      tenant_link: tenant_link,
      expires_at: zigned_result[:expires_at],
      status: zigned_result[:status]
    }
  end

  # Check signing status for a contract
  #
  # @param case_id [String] The Zigned case ID (agreement_id in v3)
  #
  # @return [Hash] Status information including signer progress
  def check_status(case_id)
    @zigned.get_agreement_status(case_id)
  end

  # Download signed PDF when signing is complete
  #
  # @param case_id [String] The Zigned case ID (agreement_id in v3)
  # @param tenant_name [String] Tenant name for filename
  #
  # @return [String] Path to downloaded signed PDF
  #
  # @raise [RuntimeError] If signing is not complete yet
  def download_signed_contract(case_id, tenant_name)
    status = @zigned.get_agreement_status(case_id)

    raise "Contract not fully signed yet (status: #{status[:status]})" unless status[:status] == 'fulfilled'

    # Generate filename for signed PDF
    safe_name = tenant_name.gsub(/[^\w\s-]/, '').gsub(/\s+/, '_')
    signed_filename = "#{safe_name}_Hyresavtal_Signed_#{Time.now.strftime('%Y-%m-%d')}.pdf"
    signed_path = File.join(SIGNED_DIR, signed_filename)

    puts "📥 Downloading signed PDF..."
    @zigned.download_signed_pdf(case_id, signed_path)
    puts "✅ Signed PDF saved: #{signed_path}"

    # Update metadata with signed PDF path
    update_metadata_with_signed_path(case_id, signed_path)

    signed_path
  end

  # Download signed PDF from direct URL (from webhook payload)
  #
  # This method is used by webhooks when the signed PDF URL is already available
  # in the webhook payload, avoiding an unnecessary API call.
  #
  # @param pdf_url [String] Direct URL to signed PDF (from webhook)
  # @param tenant_name [String] Tenant name for filename generation
  #
  # @return [String] Path to downloaded signed PDF
  #
  # @raise [RuntimeError] If download fails
  def download_signed_pdf_from_url(pdf_url, tenant_name)
    # Generate filename for signed PDF
    safe_name = tenant_name.gsub(/[^\w\s-]/, '').gsub(/\s+/, '_')
    signed_filename = "#{safe_name}_Hyresavtal_Signed_#{Time.now.strftime('%Y-%m-%d')}.pdf"
    signed_path = File.join(SIGNED_DIR, signed_filename)

    puts "📥 Downloading signed PDF from webhook URL..."

    # Download PDF with authentication
    pdf_response = HTTParty.get(
      pdf_url,
      headers: { 'Authorization' => "Bearer #{@zigned.instance_variable_get(:@access_token)}" }
    )

    raise "Failed to download PDF: #{pdf_response.code}" unless pdf_response.success?

    # Save to file
    File.write(signed_path, pdf_response.body, mode: 'wb')
    puts "✅ Signed PDF saved: #{signed_path}"

    signed_path
  end

  # Cancel a pending signing case
  #
  # @param case_id [String] The Zigned case ID (agreement_id in v3)
  #
  # @return [Boolean] True if cancelled successfully
  def cancel_contract(case_id)
    @zigned.cancel_agreement(case_id)
  end

  private

  def validate_tenant_data!(tenant)
    required_fields = [:name, :personnummer, :email, :phone, :move_in_date]
    missing_fields = required_fields - tenant.keys

    raise ArgumentError, "Missing required tenant fields: #{missing_fields.join(', ')}" unless missing_fields.empty?
    raise ArgumentError, "move_in_date must be a Date object" unless tenant[:move_in_date].is_a?(Date)
  end

  def generate_filename(tenant)
    safe_name = tenant[:name].gsub(/[^\w\s-]/, '').gsub(/\s+/, '_')
    move_in = tenant[:move_in_date].strftime('%Y-%m-%d')
    "#{safe_name}_Hyresavtal_#{move_in}.pdf"
  end

  def save_metadata(tenant, metadata)
    safe_name = tenant[:name].gsub(/[^\w\s-]/, '').gsub(/\s+/, '_')
    metadata_filename = "#{safe_name}_contract_metadata.json"
    metadata_path = File.join(METADATA_DIR, metadata_filename)

    File.write(metadata_path, JSON.pretty_generate(metadata))

    metadata_path
  end

  def update_metadata_with_signed_path(case_id, signed_path)
    # Find metadata file by case_id
    metadata_files = Dir.glob(File.join(METADATA_DIR, '*_contract_metadata.json'))

    metadata_files.each do |file|
      data = JSON.parse(File.read(file))
      if data['case_id'] == case_id
        data['signed_pdf_path'] = signed_path
        data['signed_at'] = Time.now.strftime('%Y-%m-%d %H:%M:%S')
        data['status'] = 'completed'
        File.write(file, JSON.pretty_generate(data))
        puts "✅ Metadata updated: #{file}"
        break
      end
    end
  end

  def ensure_directories_exist
    [GENERATED_DIR, SIGNED_DIR, METADATA_DIR].each do |dir|
      FileUtils.mkdir_p(dir) unless Dir.exist?(dir)
    end
  end

  # Send SMS invitations to both signers with signing links
  #
  # @param tenant [Tenant] Tenant object with name, phone
  # @param tenant_link [String] Tenant's signing URL
  # @param landlord [Hash] Landlord info with :name, :phone
  # @param landlord_link [String] Landlord's signing URL
  def self.send_contract_invitation_sms(tenant, tenant_link, landlord, landlord_link)
    require_relative 'sms/gateway'

    # CRITICAL: Validate signing URLs are present before sending SMS
    # (Research: docs/ZIGNED_SIGNING_URL_RESEARCH.md - URLs only available after activation)
    if tenant_link.nil? || tenant_link.empty?
      raise ArgumentError, "Tenant signing URL is missing - cannot send SMS invitation"
    end

    if landlord_link.nil? || landlord_link.empty?
      raise ArgumentError, "Landlord signing URL is missing - cannot send SMS invitation"
    end

    # Clean phone numbers (remove spaces, dashes)
    tenant_phone = tenant.phone&.gsub(/[\s\-]/, '')
    landlord_phone = landlord[:phone]&.gsub(/[\s\-]/, '')

    # Ensure E.164 format (add +46 if missing)
    tenant_phone = "+46#{tenant_phone.sub(/^0/, '')}" unless tenant_phone&.start_with?('+')
    landlord_phone = "+46#{landlord_phone.sub(/^0/, '')}" unless landlord_phone&.start_with?('+')

    message = "Du har blivit inbjuden att skriva på ett hyresavtal med Kimono Kittens! Signera med BankID här: "

    # Send to tenant
    tenant_success = false
    begin
      SmsGateway.send(
        to: tenant_phone,
        body: "#{message}#{tenant_link}",
        meta: { type: 'contract_invitation', tenant_id: tenant.id }
      )
      puts "📱 SMS invitation sent to tenant: #{tenant.name}"
      tenant_success = true
    rescue => e
      puts "⚠️  Failed to send SMS to tenant: #{e.message}"
    end

    # Send to landlord
    landlord_success = false
    begin
      SmsGateway.send(
        to: landlord_phone,
        body: "#{message}#{landlord_link}",
        meta: { type: 'contract_invitation', role: 'landlord' }
      )
      puts "📱 SMS invitation sent to landlord: #{landlord[:name]}"
      landlord_success = true
    rescue => e
      puts "⚠️  Failed to send SMS to landlord: #{e.message}"
    end

    { tenant_success: tenant_success, landlord_success: landlord_success }
  end

  # Creates a self-contract for when tenant IS the landlord
  # Skips Zigned entirely - landlord signature is implicit
  def self.create_self_contract(tenant_id:, tenant:, test_mode:)
    # Generate PDF (same as normal flow)
    name_parts = tenant.name.split(' ')
    first_name = name_parts.first
    surname = name_parts.last
    sanitized_first = first_name.tr('åäöÅÄÖ', 'aaoAAO')
    sanitized_surname = surname.tr('åäöÅÄÖ', 'aaoAAO')
    pdf_filename = "#{sanitized_first}_#{sanitized_surname}_Hyresavtal_#{tenant.start_date&.strftime('%Y-%m-%d') || 'DRAFT'}.pdf"
    pdf_path = File.join(GENERATED_DIR, pdf_filename)

    puts "📄 Generating contract PDF from database..."
    ContractGeneratorHtml.generate_from_tenant_id(tenant_id, output_path: pdf_path)
    puts "✅ PDF generated: #{pdf_path} (#{File.size(pdf_path)} bytes)"

    # Create contract record with landlord already signed
    contract_id = SecureRandom.uuid
    landlord = LandlordProfile.info

    signed_contract = SignedContract.new(
      id: contract_id,
      tenant_id: tenant_id,
      case_id: "SELF-#{contract_id[0..7]}", # No real Zigned case ID
      pdf_url: pdf_path,
      status: 'completed', # Both signatures automatic (you signed with yourself!)
      landlord_signed: true,  # Implicit signature
      landlord_signed_at: Time.now,
      tenant_signed: true,    # Also implicit (same person!)
      tenant_signed_at: Time.now,
      landlord_signing_url: '', # No Zigned URLs needed
      tenant_signing_url: '',
      test_mode: test_mode,
      expires_at: Time.now + (30 * 24 * 60 * 60), # 30 days from now
      created_at: Time.now,
      updated_at: Time.now,
      generation_status: 'completed', # PDF already generated
      generation_completed_at: Time.now,
      validation_status: 'completed',
      validation_completed_at: Time.now,
      email_delivery_status: 'delivered' # Pretend emails sent (maintains UI consistency)
    )

    repo = SignedContractRepository.new
    repo.save(signed_contract)

    # Create participant records (pretend ceremony happened)
    require_relative 'models/contract_participant'
    participant_repo = Persistence.contract_participants

    landlord_participant = ContractParticipant.new(
      id: SecureRandom.uuid,
      contract_id: signed_contract.id,
      participant_id: nil, # No Zigned participant ID
      role: 'landlord',
      name: landlord[:name],
      email: landlord[:email],
      personal_number: landlord[:personnummer],
      status: 'fulfilled', # Already signed (implicit)
      signed_at: Time.now,
      sms_delivered: true, # Pretend SMS sent
      sms_delivered_at: Time.now,
      created_at: Time.now,
      updated_at: Time.now
    )

    tenant_participant = ContractParticipant.new(
      id: SecureRandom.uuid,
      contract_id: signed_contract.id,
      participant_id: nil, # No Zigned participant ID
      role: 'tenant',
      name: tenant.name,
      email: tenant.email,
      personal_number: tenant.personnummer,
      status: 'fulfilled', # Already signed (implicit)
      signed_at: Time.now,
      sms_delivered: true, # Pretend SMS sent
      sms_delivered_at: Time.now,
      created_at: Time.now,
      updated_at: Time.now
    )

    participant_repo.save(landlord_participant)
    participant_repo.save(tenant_participant)

    puts "✅ Self-contract created (auto-completed)"
    puts "   Contract ID: #{contract_id}"
    puts "   Status: completed (both signatures automatic)"
    puts "   Participants: 2 (landlord + tenant, SMS marked delivered)"
    puts ""
    puts "💡 Note: No Zigned case created - you signed with yourself!"

    {
      pdf_path: pdf_path,
      case_id: signed_contract.case_id,
      landlord_link: nil,
      tenant_link: nil,
      contract_id: contract_id
    }
  end
end

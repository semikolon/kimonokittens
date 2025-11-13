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
    puts "   Start date: #{tenant.start_date}"
    puts "   Test mode: #{test_mode ? 'YES (free, invalid signatures)' : 'NO (production, real BankID)'}"
    puts "   Send emails: #{send_emails ? 'YES' : 'NO (manual link sharing)'}"
    puts ""

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
    landlord_link = zigned_result[:signing_links][landlord[:personnummer].gsub(/\D/, '')]
    tenant_link = zigned_result[:signing_links][tenant.personnummer.gsub(/\D/, '')]

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

    # Step 4: Print signing links
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
end

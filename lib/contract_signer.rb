require_relative 'contract_generator'
require_relative 'zigned_client'
require 'json'
require 'fileutils'

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

  LANDLORD = {
    name: 'Fredrik Bränström',
    personnummer: '8604230717',
    email: 'branstrom@gmail.com'
  }.freeze

  # @param test_mode [Boolean] Use Zigned test environment (free, no real signatures)
  def initialize(test_mode: false)
    @test_mode = test_mode
    @generator = ContractGenerator.new
    @zigned = ZignedClient.new(
      api_key: ENV['ZIGNED_API_KEY'] || raise('ZIGNED_API_KEY not set in environment'),
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
    @generator.generate(tenant: tenant, output_path: pdf_path)
    puts "✅ PDF generated: #{pdf_path}"

    # Step 2: Create Zigned signing case
    puts "\n🔐 Creating Zigned signing case..."
    case_title = "Hyresavtal - #{tenant[:name]}"
    webhook_url = ENV['WEBHOOK_BASE_URL'] ? "#{ENV['WEBHOOK_BASE_URL']}/api/webhooks/zigned" : nil

    signers = [
      LANDLORD,
      { name: tenant[:name], personnummer: tenant[:personnummer], email: tenant[:email] }
    ]

    zigned_result = @zigned.create_signing_case(
      pdf_path: pdf_path,
      signers: signers,
      title: case_title,
      webhook_url: webhook_url,
      message: "Välkommen till BRF Kimonokittens! Vänligen signera hyresavtalet med ditt BankID."
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
    landlord_link = zigned_result[:signing_links][LANDLORD[:personnummer].gsub(/\D/, '')]
    tenant_link = zigned_result[:signing_links][tenant[:personnummer].gsub(/\D/, '')]

    puts "\n🔗 Signing Links:"
    puts "\nLandlord (#{LANDLORD[:name]}):"
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
  # @param case_id [String] The Zigned case ID
  #
  # @return [Hash] Status information including signer progress
  def check_status(case_id)
    @zigned.get_case_status(case_id)
  end

  # Download signed PDF when signing is complete
  #
  # @param case_id [String] The Zigned case ID
  # @param tenant_name [String] Tenant name for filename
  #
  # @return [String] Path to downloaded signed PDF
  #
  # @raise [RuntimeError] If signing is not complete yet
  def download_signed_contract(case_id, tenant_name)
    status = @zigned.get_case_status(case_id)

    raise "Contract not fully signed yet (status: #{status[:status]})" unless status[:status] == 'completed'

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

  # Cancel a pending signing case
  #
  # @param case_id [String] The Zigned case ID
  #
  # @return [Boolean] True if cancelled successfully
  def cancel_contract(case_id)
    @zigned.cancel_case(case_id)
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

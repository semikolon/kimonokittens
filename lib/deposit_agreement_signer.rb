require 'erb'
require 'ferrum'
require 'fileutils'
require 'securerandom'
require_relative 'zigned_client_v3'
require_relative 'landlord_profile'
require_relative 'persistence'
require_relative 'models/signed_contract'
require_relative 'models/contract_participant'

# DepositAgreementSigner handles the creation and signing of deposit repayment agreements
#
# This is a specialized signer for one-off agreements between landlord and tenant
# regarding deposit repayment, separate from rental contracts.
#
# Usage:
#   result = DepositAgreementSigner.create_and_send(
#     tenant_name: 'Adam McCarthy',
#     tenant_personnummer: '19890714-0357',
#     tenant_email: 'adam@example.com',
#     deposit_amount: 8_200,
#     repayment_deadline: '1 mars 2026',
#     test_mode: false
#   )
class DepositAgreementSigner
  GENERATED_DIR = File.expand_path('../contracts/generated', __dir__)
  FONTS_DIR = File.expand_path('../fonts', __dir__)
  LOGO_PATH = File.expand_path('assets/logo-80pct-saturated-2000w.png', __dir__)
  TEMPLATE_PATH = File.expand_path('deposit_agreement_template.html.erb', __dir__)

  # Create and send a deposit agreement for signing
  #
  # @param tenant_name [String] Full name of the tenant
  # @param tenant_personnummer [String] Tenant's personnummer (format: YYYYMMDD-XXXX or YYMMDD-XXXX)
  # @param tenant_email [String] Tenant's email for Zigned
  # @param deposit_amount [Integer] Amount to be repaid (e.g., 8200)
  # @param repayment_deadline [String] Human-readable deadline (e.g., "1 mars 2026")
  # @param test_mode [Boolean] Use Zigned test environment (default: false)
  # @param send_emails [Boolean] Whether Zigned should send email invitations (default: true)
  #
  # @return [Hash] Result with case_id, signing_links, etc.
  def self.create_and_send(
    tenant_name:,
    tenant_personnummer:,
    tenant_email:,
    deposit_amount:,
    repayment_deadline:,
    test_mode: false,
    send_emails: true
  )
    new.create_and_send(
      tenant_name: tenant_name,
      tenant_personnummer: tenant_personnummer,
      tenant_email: tenant_email,
      deposit_amount: deposit_amount,
      repayment_deadline: repayment_deadline,
      test_mode: test_mode,
      send_emails: send_emails
    )
  end

  def create_and_send(
    tenant_name:,
    tenant_personnummer:,
    tenant_email:,
    deposit_amount:,
    repayment_deadline:,
    test_mode: false,
    send_emails: true
  )
    landlord = LandlordProfile.info

    puts "📜 Creating deposit agreement..."
    puts "   Tenant: #{tenant_name}"
    puts "   Amount: #{format_currency(deposit_amount)} kr"
    puts "   Deadline: #{repayment_deadline}"
    puts "   Test mode: #{test_mode ? 'YES (free)' : 'NO (production)'}"
    puts ""

    # Step 1: Generate PDF
    pdf_path = generate_pdf(
      landlord: landlord,
      tenant_name: tenant_name,
      tenant_personnummer: tenant_personnummer,
      deposit_amount: deposit_amount,
      repayment_deadline: repayment_deadline
    )
    puts "✅ PDF generated: #{pdf_path}"

    # Step 2: Create Zigned signing case
    puts "\n🔐 Creating Zigned signing case..."

    zigned = ZignedClientV3.new(
      client_id: ENV['ZIGNED_CLIENT_ID'] || raise('ZIGNED_CLIENT_ID not set'),
      client_secret: ENV['ZIGNED_API_KEY'] || raise('ZIGNED_API_KEY not set'),
      test_mode: test_mode
    )

    case_title = "Depositionsavtal - #{tenant_name}"
    webhook_url = ENV['WEBHOOK_BASE_URL'] ? "#{ENV['WEBHOOK_BASE_URL']}/api/webhooks/zigned" : nil

    signers = [
      landlord,
      {
        name: tenant_name,
        personnummer: tenant_personnummer,
        email: tenant_email
      }
    ]

    zigned_result = zigned.create_and_activate(
      pdf_path: pdf_path,
      signers: signers,
      title: case_title,
      webhook_url: webhook_url,
      message: "Vänligen signera depositionsavtalet med ditt BankID.",
      send_emails: send_emails
    )

    puts "✅ Signing case created: #{zigned_result[:case_id]}"

    # Step 3: Save to database
    landlord_link = zigned_result[:signing_links][landlord[:email]]
    tenant_link = zigned_result[:signing_links][tenant_email]

    # We need a tenant_id for the contract - use a special identifier
    # Since this is a one-off agreement, we'll look up the tenant or use a placeholder
    tenant_id = find_or_create_tenant_id(tenant_name, tenant_personnummer, tenant_email)

    signed_contract = SignedContract.new(
      id: SecureRandom.uuid,
      tenant_id: tenant_id,
      case_id: zigned_result[:case_id],
      pdf_url: pdf_path,
      status: 'pending',
      landlord_signed: false,
      tenant_signed: false,
      landlord_signing_url: landlord_link,
      tenant_signing_url: tenant_link,
      test_mode: test_mode,
      expires_at: zigned_result[:expires_at] ? Time.parse(zigned_result[:expires_at]) : Time.now + (30 * 24 * 60 * 60),
      created_at: Time.now,
      updated_at: Time.now
    )

    Persistence.signed_contracts.save(signed_contract)
    puts "✅ Agreement saved to database"

    # Step 4: Create participant records
    participant_repo = Persistence.contract_participants

    landlord_participant = ContractParticipant.new(
      id: SecureRandom.uuid,
      contract_id: signed_contract.id,
      participant_id: nil,
      name: landlord[:name],
      email: landlord[:email],
      personal_number: landlord[:personnummer],
      role: 'landlord',
      signing_url: landlord_link,
      created_at: Time.now,
      updated_at: Time.now
    )

    tenant_participant = ContractParticipant.new(
      id: SecureRandom.uuid,
      contract_id: signed_contract.id,
      participant_id: nil,
      name: tenant_name,
      email: tenant_email,
      personal_number: tenant_personnummer,
      role: 'tenant',
      signing_url: tenant_link,
      created_at: Time.now,
      updated_at: Time.now
    )

    participant_repo.save(landlord_participant)
    participant_repo.save(tenant_participant)
    puts "✅ Participant records created"

    # Step 5: Send SMS notifications
    sms_sent = send_sms_invitations(
      tenant_name: tenant_name,
      tenant_link: tenant_link,
      landlord: landlord,
      landlord_link: landlord_link
    )

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

    # Step 6: Print signing links
    puts "\n🔗 Signing Links:"
    puts "\nLandlord (#{landlord[:name]}):"
    puts landlord_link
    puts "\nTenant (#{tenant_name}):"
    puts tenant_link

    {
      pdf_path: pdf_path,
      case_id: zigned_result[:case_id],
      signing_links: zigned_result[:signing_links],
      landlord_link: landlord_link,
      tenant_link: tenant_link,
      expires_at: zigned_result[:expires_at],
      contract_id: signed_contract.id
    }
  end

  private

  def generate_pdf(landlord:, tenant_name:, tenant_personnummer:, deposit_amount:, repayment_deadline:)
    FileUtils.mkdir_p(GENERATED_DIR)

    # Prepare template data
    data = {
      fonts_dir: FONTS_DIR,
      logo_path: LOGO_PATH,
      landlord: {
        name: landlord[:name],
        personnummer: landlord[:personnummer],
        first_name: landlord[:name].split(' ').first
      },
      tenant: {
        name: tenant_name,
        personnummer: tenant_personnummer,
        first_name: tenant_name.split(' ').first
      },
      deposit: {
        amount: format_currency(deposit_amount),
        repayment_deadline: repayment_deadline
      }
    }

    # Render HTML
    template = ERB.new(File.read(TEMPLATE_PATH))
    html = template.result_with_hash(data)

    # Generate filenames
    safe_name = tenant_name.gsub(/[^\w\s-]/, '').gsub(/\s+/, '_')
    timestamp = Time.now.strftime('%Y-%m-%d')
    html_path = File.join(GENERATED_DIR, "#{safe_name}_Depositionsavtal_#{timestamp}_temp.html")
    pdf_path = File.join(GENERATED_DIR, "#{safe_name}_Depositionsavtal_#{timestamp}.pdf")

    # Save HTML
    File.write(html_path, html)

    # Generate PDF with Ferrum
    browser = Ferrum::Browser.new(
      headless: true,
      window_size: [1200, 1600],
      browser_options: {
        'args' => ['--no-pdf-header-footer', '--disable-gpu']
      }
    )

    begin
      browser.goto("file://#{File.absolute_path(html_path)}")
      sleep 1  # Wait for fonts

      browser.pdf(
        path: pdf_path,
        format: :A4,
        margin_top: 0,
        margin_right: 0,
        margin_bottom: 0,
        margin_left: 0,
        printBackground: true,
        preferCSSPageSize: false
      )
    ensure
      browser.quit
    end

    # Clean up temp HTML
    File.delete(html_path) if File.exist?(html_path)

    pdf_path
  end

  def format_currency(amount)
    return amount if amount.is_a?(String)
    amount.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1 ').reverse
  end

  def find_or_create_tenant_id(name, personnummer, email)
    # Try to find existing tenant by personnummer or email
    require_relative 'repositories/tenant_repository'
    repo = TenantRepository.new

    # Search by email first (most reliable)
    tenant = repo.find_by_email(email)
    return tenant.id if tenant

    # If not found, we'll use a special placeholder ID
    # This is a one-off agreement, so we generate a deterministic ID
    "deposit-agreement-#{personnummer.gsub(/\D/, '')}"
  end

  def send_sms_invitations(tenant_name:, tenant_link:, landlord:, landlord_link:)
    require_relative 'sms/gateway'

    tenant_success = false
    landlord_success = false

    # Get landlord phone
    landlord_phone = landlord[:phone]&.gsub(/[\s\-]/, '')
    landlord_phone = "+46#{landlord_phone.sub(/^0/, '')}" unless landlord_phone&.start_with?('+')

    message = "Vänligen signera depositionsavtalet med BankID: "

    # Send to landlord
    begin
      SmsGateway.send(
        to: landlord_phone,
        body: "#{message}#{landlord_link}",
        meta: { type: 'deposit_agreement', role: 'landlord' }
      )
      puts "📱 SMS sent to landlord: #{landlord[:name]}"
      landlord_success = true
    rescue => e
      puts "⚠️  Failed to send SMS to landlord: #{e.message}"
    end

    # Note: We don't have tenant phone in this context - they'll get email from Zigned
    puts "ℹ️  Tenant will receive email invitation from Zigned"

    { tenant_success: tenant_success, landlord_success: landlord_success }
  end
end

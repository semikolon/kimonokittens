require 'httparty'
require 'json'

# ZignedClient handles all interactions with Zigned e-signing API
#
# Zigned provides Swedish BankID e-signing with REST API
# Pricing: 19 SEK base + 5 SEK per signer (average 29 SEK for landlord+tenant)
#
# Usage:
#   client = ZignedClient.new(api_key: ENV['ZIGNED_API_KEY'], test_mode: true)
#
#   # Create signing case
#   result = client.create_signing_case(
#     pdf_path: 'contracts/generated/Sanna_Contract.pdf',
#     signers: [
#       { name: 'Fredrik Bränström', personnummer: '8604230717', email: 'branstrom@gmail.com' },
#       { name: 'Sanna Juni Benemar', personnummer: '8706220020', email: 'sanna_benemar@hotmail.com' }
#     ],
#     title: 'Hyresavtal - Sanna Juni Benemar',
#     webhook_url: 'https://kimonokittens.com/api/webhooks/zigned'
#   )
#
#   # Check status
#   status = client.get_case_status(result[:case_id])
#
#   # Download signed PDF when complete
#   client.download_signed_pdf(result[:case_id], 'contracts/signed/Sanna_Signed.pdf')
class ZignedClient
  include HTTParty

  # Zigned API endpoints
  # NOTE: Zigned uses the same API endpoint for both test and production.
  # Test mode is determined by which API key you use (test vs production key),
  # not by a separate domain. Test keys create invalid signatures for free.
  BASE_URL = 'https://api.zigned.se/v1'

  # @param api_key [String] Your Zigned API key from dashboard (test or production)
  # @param test_mode [Boolean] Documentation flag (doesn't change endpoint - determined by API key)
  def initialize(api_key:, test_mode: false)
    raise ArgumentError, 'API key is required' if api_key.nil? || api_key.empty?

    @api_key = api_key
    @test_mode = test_mode
    @base_url = BASE_URL  # Always use same endpoint - test/prod determined by API key

    self.class.base_uri(@base_url)
    self.class.headers(
      'Authorization' => "Bearer #{@api_key}",
      'Content-Type' => 'application/json',
      'Accept' => 'application/json'
    )
  end

  # Create a new signing case with PDF upload
  #
  # @param pdf_path [String] Absolute path to PDF file
  # @param signers [Array<Hash>] Array of signer hashes with :name, :personnummer, :email
  # @param title [String] Case title shown to signers
  # @param webhook_url [String] URL to receive status updates (optional)
  # @param message [String] Message shown to signers (optional)
  # @param send_emails [Boolean] Send email invitations to signers (default: true)
  #
  # @return [Hash] { case_id:, signing_links: { personnummer: url } }
  #
  # @example
  #   result = client.create_signing_case(
  #     pdf_path: 'contract.pdf',
  #     signers: [
  #       { name: 'Fredrik Bränström', personnummer: '8604230717', email: 'branstrom@gmail.com' },
  #       { name: 'Sanna Benemar', personnummer: '8706220020', email: 'sanna_benemar@hotmail.com' }
  #     ],
  #     title: 'Hyresavtal - Sanna Juni Benemar',
  #     webhook_url: 'https://kimonokittens.com/api/webhooks/zigned',
  #     send_emails: false  # Disable emails for testing
  #   )
  def create_signing_case(pdf_path:, signers:, title:, webhook_url: nil, message: nil, send_emails: true)
    raise ArgumentError, "PDF file not found: #{pdf_path}" unless File.exist?(pdf_path)
    raise ArgumentError, 'At least 2 signers required (landlord + tenant)' if signers.length < 2

    # Read PDF file as base64
    pdf_content = File.read(pdf_path, mode: 'rb')
    pdf_base64 = Base64.strict_encode64(pdf_content)

    # Build request payload
    payload = {
      title: title,
      document: {
        name: File.basename(pdf_path),
        content: pdf_base64,
        content_type: 'application/pdf'
      },
      signers: signers.map do |signer|
        {
          name: signer[:name],
          personal_number: signer[:personnummer].gsub(/\D/, ''), # Remove hyphens
          email: signer[:email],
          authentication_method: 'se_bankid' # Swedish BankID
        }
      end
    }

    payload[:webhook_url] = webhook_url if webhook_url
    payload[:message] = message if message
    payload[:send_emails] = send_emails

    # Make API request
    response = self.class.post('/cases', body: payload.to_json)

    handle_response(response) do |data|
      {
        case_id: data['id'],
        signing_links: data['signers'].each_with_object({}) do |signer, hash|
          hash[signer['personal_number']] = signer['signing_url']
        end,
        expires_at: data['expires_at'],
        status: data['status']
      }
    end
  end

  # Get current status of a signing case
  #
  # @param case_id [String] The case ID from create_signing_case
  #
  # @return [Hash] { status:, signers:, signed_at:, signed_pdf_url: }
  #
  # @example
  #   status = client.get_case_status('zcs_abc123')
  #   puts status[:status] # => 'pending', 'completed', 'cancelled', 'expired'
  def get_case_status(case_id)
    response = self.class.get("/cases/#{case_id}")

    handle_response(response) do |data|
      {
        case_id: data['id'],
        status: data['status'],
        title: data['title'],
        created_at: data['created_at'],
        expires_at: data['expires_at'],
        signed_at: data['signed_at'],
        signed_pdf_url: data['signed_document_url'],
        signers: data['signers'].map do |signer|
          {
            name: signer['name'],
            personnummer: signer['personal_number'],
            email: signer['email'],
            signed: signer['signed'],
            signed_at: signer['signed_at']
          }
        end
      }
    end
  end

  # Download signed PDF to local file
  #
  # @param case_id [String] The case ID
  # @param output_path [String] Where to save the signed PDF
  #
  # @return [String] Path to downloaded file
  #
  # @raise [RuntimeError] If case is not completed yet
  def download_signed_pdf(case_id, output_path)
    status = get_case_status(case_id)

    raise "Case not completed yet (status: #{status[:status]})" unless status[:status] == 'completed'
    raise "No signed PDF URL available" unless status[:signed_pdf_url]

    # Download signed PDF
    pdf_response = HTTParty.get(
      status[:signed_pdf_url],
      headers: { 'Authorization' => "Bearer #{@api_key}" }
    )

    raise "Failed to download PDF: #{pdf_response.code}" unless pdf_response.success?

    # Save to file
    File.write(output_path, pdf_response.body, mode: 'wb')

    output_path
  end

  # Cancel a pending signing case
  #
  # @param case_id [String] The case ID to cancel
  #
  # @return [Boolean] True if cancelled successfully
  def cancel_case(case_id)
    response = self.class.post("/cases/#{case_id}/cancel")

    handle_response(response) do |data|
      data['status'] == 'cancelled'
    end
  end

  # List all cases (paginated)
  #
  # @param page [Integer] Page number (default: 1)
  # @param per_page [Integer] Items per page (default: 20)
  #
  # @return [Hash] { cases:, total:, page:, per_page: }
  def list_cases(page: 1, per_page: 20)
    response = self.class.get('/cases', query: { page: page, per_page: per_page })

    handle_response(response) do |data|
      {
        cases: data['cases'].map { |c| { case_id: c['id'], title: c['title'], status: c['status'], created_at: c['created_at'] } },
        total: data['total'],
        page: data['page'],
        per_page: data['per_page']
      }
    end
  end

  private

  # Handle API response with error checking
  def handle_response(response)
    case response.code
    when 200..299
      yield response.parsed_response
    when 401
      raise "Zigned API authentication failed - check your API key"
    when 404
      raise "Resource not found - case may not exist"
    when 422
      errors = response.parsed_response['errors']&.join(', ') || 'Validation failed'
      raise "Zigned API validation error: #{errors}"
    when 500..599
      raise "Zigned API server error (#{response.code})"
    else
      raise "Zigned API error (#{response.code}): #{response.body}"
    end
  end
end

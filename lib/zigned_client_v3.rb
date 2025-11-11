require 'httparty'
require 'json'

# ZignedClientV3 handles all interactions with Zigned e-signing API v3
#
# **CRITICAL CHANGES FROM V1:**
# - Base URL: https://api.zigned.se/rest/v3 (not /v1)
# - File upload: Multipart form-data to /files endpoint (not inline base64)
# - Workflow: Multi-step (upload → create → attach → participants → activate)
# - Primary resource: /agreements (not /cases)
# - File limit: 15 MB documented
#
# **Migration from v1:**
# Old: client.create_signing_case(pdf_path: ..., signers: ...)
# New: client.create_and_activate(pdf_path: ..., signers: ...)
# Return format preserved for backward compatibility
#
# Usage:
#   client = ZignedClientV3.new(api_key: ENV['ZIGNED_API_KEY'], test_mode: true)
#
#   result = client.create_and_activate(
#     pdf_path: 'contracts/generated/Contract.pdf',
#     signers: [
#       { name: 'Fredrik Bränström', personnummer: '8604230717', email: 'branstrom@gmail.com' },
#       { name: 'Tenant Name', personnummer: '9001011234', email: 'tenant@example.com' }
#     ],
#     title: 'Hyresavtal - Tenant Name',
#     webhook_url: 'https://kimonokittens.com/api/webhooks/zigned',
#     send_emails: false
#   )
#
#   # Returns (compatible with v1):
#   # {
#   #   case_id: 'agreement_id',  # Note: called case_id for compatibility
#   #   signing_links: { '8604230717' => 'https://...', '9001011234' => 'https://...' },
#   #   expires_at: '2025-12-01T...',
#   #   status: 'pending'
#   # }
class ZignedClientV3
  include HTTParty

  # Zigned API v3 endpoint
  BASE_URL = 'https://api.zigned.se/rest/v3'
  OAUTH_URL = 'https://api.zigned.se/oauth/token'
  MAX_FILE_SIZE = 15_728_640  # 15 MB in bytes

  # OAuth token caching (class variables shared across instances)
  @@cached_token = nil
  @@token_expires_at = nil
  @@token_mutex = Mutex.new  # Thread safety for token refresh

  # @param client_id [String] Your Zigned OAuth client ID
  # @param client_secret [String] Your Zigned OAuth client secret
  # @param test_mode [Boolean] Documentation flag (actual mode determined by credentials)
  def initialize(client_id:, client_secret:, test_mode: false)
    raise ArgumentError, 'Client ID is required' if client_id.nil? || client_id.empty?
    raise ArgumentError, 'Client secret is required' if client_secret.nil? || client_secret.empty?

    @client_id = client_id
    @client_secret = client_secret
    @test_mode = test_mode
    @base_url = BASE_URL
    @access_token = nil

    self.class.base_uri(@base_url)
    self.class.default_options.update(verify: true)

    # Get OAuth access token
    obtain_access_token
  end

  # High-level method: Upload PDF and create activated agreement
  #
  # This replaces v1's create_signing_case() with the same interface
  # for minimal changes to ContractSigner.
  #
  # @param pdf_path [String] Absolute path to PDF file
  # @param signers [Array<Hash>] Array with :name, :personnummer, :email
  # @param title [String] Agreement title
  # @param webhook_url [String] Webhook URL for status updates (optional)
  # @param message [String] Custom message to signers (optional)
  # @param send_emails [Boolean] Send email invitations (default: true)
  #
  # @return [Hash] { case_id:, signing_links:, expires_at:, status: }
  def create_and_activate(pdf_path:, signers:, title:, webhook_url: nil, message: nil, send_emails: true)
    raise ArgumentError, "PDF file not found: #{pdf_path}" unless File.exist?(pdf_path)
    raise ArgumentError, 'At least 2 signers required (landlord + tenant)' if signers.length < 2

    # Validate file size
    pdf_size = File.size(pdf_path)
    if pdf_size > MAX_FILE_SIZE
      raise ArgumentError, "PDF too large (#{pdf_size} bytes). Maximum: #{MAX_FILE_SIZE} bytes (15 MB)"
    end

    # Validate file type
    unless File.extname(pdf_path).downcase == '.pdf'
      raise ArgumentError, "Only PDF files supported, got: #{File.extname(pdf_path)}"
    end

    # Step 1: Upload PDF to files repository
    file = upload_file(pdf_path, lookup_key: "contract_#{Time.now.to_i}")

    # Step 2: Create agreement
    agreement = create_agreement(
      title: title,
      webhook_url: webhook_url,
      send_emails: send_emails
    )
    puts "DEBUG: Agreement created with ID: #{agreement[:agreement_id]}"

    # Step 3: Attach main document
    attach_main_document(agreement[:agreement_id], file[:file_id])
    puts "DEBUG: Document attached to agreement #{agreement[:agreement_id]}"

    # Step 4: Add participants
    participants = add_participants(
      agreement[:agreement_id],
      signers: signers,
      message: message
    )
    puts "DEBUG: #{participants.length} participants added to agreement #{agreement[:agreement_id]}"

    # Step 5: Activate agreement
    puts "DEBUG: Attempting to activate agreement #{agreement[:agreement_id]}"
    activated = activate_agreement(agreement[:agreement_id])

    # Return format compatible with v1
    {
      case_id: agreement[:agreement_id],  # Keep 'case_id' for compatibility
      signing_links: extract_signing_links(participants, signers),
      expires_at: activated[:expires_at],
      status: activated[:status]
    }
  end

  # Upload PDF file to Zigned file repository
  #
  # @param pdf_path [String] Path to PDF file
  # @param lookup_key [String] Optional lookup key for organization
  #
  # @return [Hash] { file_id:, filename:, mime_type:, size:, lookup_key: }
  def upload_file(pdf_path, lookup_key: nil)
    payload = { file: File.open(pdf_path, 'rb') }
    payload[:lookup_key] = lookup_key if lookup_key

    response = self.class.post(
      '/files',
      body: payload,
      headers: {
        'Authorization' => "Bearer #{@access_token}",
        'Accept' => 'application/json'
        # Note: Content-Type omitted - HTTParty sets multipart boundary automatically
      }
    )

    handle_response(response) do |data|
      file_data = data['data']  # v3 wraps response in { version:, result_type:, resource_type:, data: }
      {
        file_id: file_data['id'],
        filename: file_data['filename'],
        mime_type: file_data['mime_type'],
        size: file_data['size'],
        lookup_key: file_data['lookup_key']
      }
    end
  end

  # Create agreement in draft status
  #
  # @param title [String] Agreement title
  # @param webhook_url [String] Webhook URL for events (optional)
  # @param send_emails [Boolean] Enable email notifications
  #
  # @return [Hash] { agreement_id:, status:, test_mode: }
  def create_agreement(title:, webhook_url: nil, send_emails: true)
    payload = {
      title: title,
      trust_level: 'AES',  # Advanced Electronic Signatures (BankID)
      locale: 'sv-SE',
      enable_emails: send_emails
    }

    payload[:webhook_url] = webhook_url if webhook_url

    response = self.class.post(
      '/agreements',
      body: payload.to_json,
      headers: default_headers
    )

    handle_response(response) do |data|
      agreement_data = data['data']
      {
        agreement_id: agreement_data['id'],
        status: agreement_data['status'],
        test_mode: agreement_data['test_mode']
      }
    end
  end

  # Attach main document to agreement
  #
  # @param agreement_id [String] The agreement ID
  # @param file_id [String] The file ID from upload_file
  #
  # @return [Boolean] True if successful
  def attach_main_document(agreement_id, file_id)
    payload = { file_id: file_id }

    response = self.class.post(
      "/agreements/#{agreement_id}/documents/main",
      body: payload.to_json,
      headers: default_headers
    )

    handle_response(response) { |_data| true }
  end

  # Add participants (signers) to agreement
  #
  # @param agreement_id [String] The agreement ID
  # @param signers [Array<Hash>] Signer details
  # @param message [String] Optional custom message
  #
  # @return [Array<Hash>] Participant records with signing URLs
  def add_participants(agreement_id, signers:, message: nil)
    participants_payload = signers.map do |signer|
      {
        name: signer[:name],
        email: signer[:email],
        role: 'signer',
        personal_number: signer[:personnummer].gsub(/\D/, '')  # Remove hyphens
        # Note: No order field = parallel signing (landlord and tenant can sign in any order)
      }
    end

    payload = { participants: participants_payload }

    response = self.class.post(
      "/agreements/#{agreement_id}/participants/batch",
      body: payload.to_json,
      headers: default_headers
    )

    handle_response(response) do |data|
      data['data'].map do |participant|
        {
          participant_id: participant['id'],
          name: participant['name'],
          email: participant['email'],
          personal_number: participant['personal_number'],
          signing_url: participant['signing_url'],
          role: participant['role']
        }
      end
    end
  end

  # Activate agreement (moves from draft to pending)
  #
  # @param agreement_id [String] The agreement ID
  #
  # @return [Hash] { status:, expires_at: }
  def activate_agreement(agreement_id)
    payload = {
      lifecycle_state: {
        status: 'pending'
      }
    }

    response = self.class.post(
      "/agreements/#{agreement_id}/lifecycle",
      body: payload.to_json,
      headers: default_headers
    )

    handle_response(response) do |data|
      agreement_data = data['data']

      # Lifecycle endpoint doesn't return expires_at, fetch full agreement details
      status_response = get_agreement_status(agreement_id)

      {
        status: agreement_data['status'],
        expires_at: status_response[:expires_at]
      }
    end
  end

  # Get agreement status
  #
  # @param agreement_id [String] The agreement ID
  #
  # @return [Hash] { status:, signers:, signed_at:, signed_pdf_url: }
  def get_agreement_status(agreement_id)
    response = self.class.get(
      "/agreements/#{agreement_id}",
      headers: default_headers
    )

    handle_response(response) do |data|
      agreement_data = data['data']
      {
        agreement_id: agreement_data['id'],
        status: agreement_data['status'],
        title: agreement_data['title'],
        created_at: agreement_data['created_at'],
        expires_at: agreement_data['expires_at'],
        fulfilled_at: agreement_data['fulfilled_at'],
        signed_pdf_url: agreement_data['signed_document_url'],  # Available when fulfilled
        participants: agreement_data['participants']  # Array of participant IDs
      }
    end
  end

  # Download signed PDF (when agreement fulfilled)
  #
  # @param agreement_id [String] The agreement ID
  # @param output_path [String] Where to save PDF
  #
  # @return [String] Path to downloaded file
  def download_signed_pdf(agreement_id, output_path)
    status = get_agreement_status(agreement_id)

    unless status[:status] == 'fulfilled'
      raise "Agreement not fulfilled yet (status: #{status[:status]})"
    end

    unless status[:signed_pdf_url]
      raise "No signed PDF URL available"
    end

    # Download signed PDF
    pdf_response = HTTParty.get(
      status[:signed_pdf_url],
      headers: { 'Authorization' => "Bearer #{@access_token}" }
    )

    raise "Failed to download PDF: #{pdf_response.code}" unless pdf_response.success?

    # Save to file
    File.write(output_path, pdf_response.body, mode: 'wb')

    output_path
  end

  # Cancel a pending agreement
  #
  # @param agreement_id [String] The agreement ID
  #
  # @return [Boolean] True if cancelled successfully
  def cancel_agreement(agreement_id)
    response = self.class.post(
      "/agreements/#{agreement_id}/lifecycle/cancel",
      headers: default_headers
    )

    handle_response(response) do |data|
      agreement_data = data['data']
      agreement_data['status'] == 'cancelled'
    end
  end

  private

  # Obtain OAuth access token using client credentials (with caching)
  def obtain_access_token
    @@token_mutex.synchronize do
      # Reuse cached token if still valid (5 min buffer before expiry)
      if @@cached_token && @@token_expires_at && Time.now < (@@token_expires_at - 300)
        @access_token = @@cached_token
        return
      end

      # Fetch fresh token
      response = HTTParty.post(
        OAUTH_URL,
        body: {
          grant_type: 'client_credentials',
          client_id: @client_id,
          client_secret: @client_secret
        },
        headers: { 'Content-Type' => 'application/x-www-form-urlencoded' }
      )

      if response.success?
        parsed = response.parsed_response
        @access_token = parsed['access_token']

        # Cache token with expiration (default 74 years, but respect API response)
        @@cached_token = @access_token
        expires_in = parsed['expires_in'] || 2_335_680_000  # 74 years in seconds
        @@token_expires_at = Time.now + expires_in
      else
        raise "OAuth token exchange failed (#{response.code}): #{response.body}"
      end
    end
  end

  def default_headers
    {
      'Authorization' => "Bearer #{@access_token}",
      'Content-Type' => 'application/json',
      'Accept' => 'application/json'
    }
  end

  # Extract signing links in v1-compatible format
  # Returns hash: { 'personnummer' => 'signing_url' }
  def extract_signing_links(participants, signers)
    participants.each_with_object({}) do |participant, hash|
      hash[participant[:personal_number]] = participant[:signing_url]
    end
  end

  # Handle API response with comprehensive error checking
  def handle_response(response)
    case response.code
    when 200..299
      yield response.parsed_response
    when 401
      raise "Zigned API authentication failed - check API key validity"
    when 404
      raise "Resource not found - agreement or file may not exist"
    when 413
      raise "File too large - maximum 15MB for PDF uploads"
    when 422
      errors = extract_validation_errors(response)
      raise "Zigned API validation error: #{errors}"
    when 500..599
      raise "Zigned API server error (#{response.code}) - try again later"
    else
      error_msg = extract_error_message(response)
      raise "Zigned API error (#{response.code}): #{error_msg}"
    end
  end

  # Extract validation errors from 422 responses
  def extract_validation_errors(response)
    parsed = response.parsed_response
    if parsed.is_a?(Hash) && parsed['errors']
      # v3 returns errors as array
      errors = parsed['errors']
      errors.is_a?(Array) ? errors.join(', ') : errors.to_s
    else
      'Unknown validation error'
    end
  end

  # Extract error message from response
  def extract_error_message(response)
    return nil unless response.body

    # Try to parse as JSON
    parsed = response.parsed_response
    if parsed.is_a?(Hash)
      # Common error message fields
      parsed['error'] || parsed['message'] || parsed['detail'] || parsed['errors']&.join(', ')
    else
      # HTML error page - extract text from <pre> tag if present
      if response.body =~ /<pre>([^<]+)<\/pre>/
        $1.strip
      else
        # Fallback to truncated body
        response.body.length > 100 ? "#{response.body[0..100]}..." : response.body
      end
    end
  rescue JSON::ParserError
    # If JSON parsing fails, return truncated body
    response.body.length > 100 ? "#{response.body[0..100]}..." : response.body
  end
end

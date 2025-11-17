# Handler for public tenant signup form
# POST /api/signup - Creates TenantLead and sends admin notification
class SignupHandler
  RATE_LIMIT_WINDOW = 24 * 60 * 60 # 24 hours in seconds
  RATE_LIMIT_MAX = 2 # Max submissions per IP per window

  def initialize
    require 'json'
    require 'net/http'
    require 'uri'
    require_relative '../lib/rent_db'
  end

  def call(env)
    req = Rack::Request.new(env)

    return method_not_allowed unless req.post?

    begin
      # Parse request body
      data = JSON.parse(req.body.read)

      # Validate required fields
      errors = validate_input(data)
      return bad_request(errors) unless errors.empty?

      # Rate limiting check
      ip_address = req.ip
      if rate_limit_exceeded?(ip_address)
        return too_many_requests
      end

      # Verify Cloudflare Turnstile token (skip in development)
      captcha_token = data['captcha']
      unless ENV['RACK_ENV'] == 'development' || verify_turnstile(captcha_token, ip_address)
        return bad_request(['CAPTCHA verification failed'])
      end

      # Create TenantLead record
      lead = create_lead(data, ip_address, req.user_agent)

      # Send SMS notification to admin (placeholder for now)
      send_admin_sms(lead)

      # Broadcast to admin dashboard via WebSocket
      broadcast_leads_updated

      # Return success
      success_response

    rescue JSON::ParserError
      bad_request(['Invalid JSON'])
    rescue StandardError => e
      puts "Signup error: #{e.message}"
      puts e.backtrace.join("\n")
      internal_error
    end
  end

  private

  def validate_input(data)
    errors = []

    # Required: name
    errors << 'Name is required' if data['name'].nil? || data['name'].strip.empty?

    # Required: contact_method
    contact_method = data['contact_method']
    unless %w[email facebook].include?(contact_method)
      errors << 'Contact method must be "email" or "facebook"'
    end

    # Required: contact value (email or facebook_id)
    if contact_method == 'email'
      email = data['email']
      if email.nil? || email.strip.empty?
        errors << 'Email is required when contact method is email'
      elsif !valid_email?(email)
        errors << 'Invalid email format'
      end
    elsif contact_method == 'facebook'
      facebook_id = data['facebook_id']
      if facebook_id.nil? || facebook_id.strip.empty?
        errors << 'Facebook ID is required when contact method is facebook'
      end
    end

    # Required: move_in_flexibility
    move_in = data['move_in_flexibility']
    unless %w[immediate 1month 2months 3months specific other].include?(move_in)
      errors << 'Invalid move-in flexibility option'
    end

    # If move_in is "specific" or "other", move_in_extra is required
    if %w[specific other].include?(move_in)
      if data['move_in_extra'].nil? || data['move_in_extra'].strip.empty?
        errors << 'Move-in details required for selected option'
      end
    end

    # Optional: phone validation
    if data['phone'] && !data['phone'].strip.empty?
      phone = data['phone'].gsub(/[^0-9+]/, '') # Strip formatting
      if phone.length < 9 || phone.length > 15
        errors << 'Invalid phone number'
      end
    end

    errors
  end

  def valid_email?(email)
    email =~ /\A[^@\s]+@[^@\s]+\.[^@\s]+\z/
  end

  def rate_limit_exceeded?(ip_address)
    db = RentDb.instance.class.db

    # Count submissions from this IP in the last 24 hours
    cutoff_time = Time.now - RATE_LIMIT_WINDOW

    count = db[:TenantLead]
      .where(ipAddress: ip_address)
      .where { createdAt > cutoff_time }
      .count

    count >= RATE_LIMIT_MAX
  end

  def verify_turnstile(token, ip_address)
    return false if token.nil? || token.strip.empty?

    secret_key = ENV['TURNSTILE_SECRET_KEY']
    return false if secret_key.nil? || secret_key == 'placeholder'

    uri = URI('https://challenges.cloudflare.com/turnstile/v0/siteverify')

    response = Net::HTTP.post_form(uri, {
      'secret' => secret_key,
      'response' => token,
      'remoteip' => ip_address
    })

    result = JSON.parse(response.body)
    result['success'] == true

  rescue StandardError => e
    puts "Turnstile verification error: #{e.message}"
    false
  end

  def create_lead(data, ip_address, user_agent)
    db = RentDb.instance.class.db

    lead_id = SecureRandom.uuid
    now = Time.now

    db[:TenantLead].insert(
      id: lead_id,
      name: data['name'].strip,
      email: data['email']&.strip,
      facebookId: data['facebook_id']&.strip,
      phone: data['phone']&.strip,
      contactMethod: data['contact_method'],
      moveInFlexibility: data['move_in_flexibility'],
      moveInExtra: data['move_in_extra']&.strip,
      motivation: data['motivation']&.strip,
      status: 'pending_review',
      source: 'web_form',
      ipAddress: ip_address,
      userAgent: user_agent,
      createdAt: now,
      updatedAt: now
    )

    db[:TenantLead].where(id: lead_id).first
  end

  def send_admin_sms(lead)
    # TODO: Integrate SMS service when available
    # For now, just log the notification
    contact_info = lead[:contactMethod] == 'email' ? lead[:email] : "facebook.com/#{lead[:facebookId]}"

    puts "📱 SMS NOTIFICATION (stub):"
    puts "  New tenant application from #{lead[:name]}"
    puts "  Contact: #{contact_info}"
    puts "  Move-in: #{lead[:moveInFlexibility]}"
    puts "  View in admin dashboard"
  end

  def broadcast_leads_updated
    # Trigger WebSocket broadcast to admin dashboard
    # DataBroadcaster will pick up the change on next fetch cycle
    # TODO: Add immediate broadcast method if needed
    puts "🔔 Lead created - admin dashboard will update on next fetch"
  end

  def success_response
    [200, { 'Content-Type' => 'application/json' }, [{ success: true }.to_json]]
  end

  def bad_request(errors)
    [400, { 'Content-Type' => 'application/json' },
     [{ error: errors.join(', '), errors: errors }.to_json]]
  end

  def too_many_requests
    [429, { 'Content-Type' => 'application/json' },
     [{ error: 'Too many submissions. Please try again tomorrow.' }.to_json]]
  end

  def method_not_allowed
    [405, { 'Content-Type' => 'application/json' },
     [{ error: 'Method not allowed' }.to_json]]
  end

  def internal_error
    [500, { 'Content-Type' => 'application/json' },
     [{ error: 'Internal server error' }.to_json]]
  end
end

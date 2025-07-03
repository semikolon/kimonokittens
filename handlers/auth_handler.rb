require 'httparty'
require 'jwt'
require 'json'

class AuthHandler < WEBrick::HTTPServlet::AbstractServlet
  def initialize(server)
    super
    @facebook_app_id = ENV['FACEBOOK_APP_ID']
    @facebook_app_secret = ENV['FACEBOOK_APP_SECRET']
    @jwt_secret = ENV['JWT_SECRET']
  end

  def do_POST(req, res)
    res['Content-Type'] = 'application/json'
    res['Access-Control-Allow-Origin'] = '*'
    res['Access-Control-Allow-Methods'] = 'POST, OPTIONS'
    res['Access-Control-Allow-Headers'] = 'Content-Type'

    case req.path
    when '/api/auth/facebook'
      handle_facebook_login(req, res)
    else
      res.status = 404
      res.body = { error: 'Not Found' }.to_json
    end
  rescue => e
    puts "Auth error: #{e.message}"
    puts e.backtrace
    res.status = 500
    res.body = { error: 'Internal server error' }.to_json
  end

  def do_OPTIONS(req, res)
    res['Access-Control-Allow-Origin'] = '*'
    res['Access-Control-Allow-Methods'] = 'POST, OPTIONS'
    res['Access-Control-Allow-Headers'] = 'Content-Type'
    res.status = 200
    res.body = ''
  end

  private

  def handle_facebook_login(req, res)
    # Parse request body
    request_body = JSON.parse(req.body)
    access_token = request_body['accessToken']

    unless access_token
      res.status = 400
      res.body = { error: 'Missing accessToken' }.to_json
      return
    end

    # Verify token with Facebook
    facebook_user = verify_facebook_token(access_token)
    unless facebook_user
      res.status = 401
      res.body = { error: 'Invalid Facebook token' }.to_json
      return
    end

    # Find or create tenant
    tenant = find_or_create_tenant(facebook_user)
    unless tenant
      res.status = 500
      res.body = { error: 'Failed to create user account' }.to_json
      return
    end

    # Generate JWT
    jwt_token = generate_jwt(tenant[:id])

    # Set secure cookie
    set_auth_cookie(res, jwt_token)

    # Return user data
    res.status = 200
    res.body = {
      user: {
        id: tenant[:id],
        name: tenant[:name],
        avatarUrl: tenant[:avatarUrl]
      }
    }.to_json
  end

  def verify_facebook_token(access_token)
    # Debug token with Facebook's API
    debug_url = "https://graph.facebook.com/debug_token"
    debug_response = HTTParty.get(debug_url, query: {
      input_token: access_token,
      access_token: "#{@facebook_app_id}|#{@facebook_app_secret}"
    })

    unless debug_response.success? && debug_response['data']['is_valid']
      puts "Facebook token verification failed: #{debug_response.body}"
      return nil
    end

    # Get user profile
    profile_url = "https://graph.facebook.com/me"
    profile_response = HTTParty.get(profile_url, query: {
      access_token: access_token,
      fields: 'id,first_name,picture.type(large)'
    })

    unless profile_response.success?
      puts "Facebook profile fetch failed: #{profile_response.body}"
      return nil
    end

    {
      id: profile_response['id'],
      name: profile_response['first_name'],
      avatarUrl: profile_response.dig('picture', 'data', 'url')
    }
  end

  def find_or_create_tenant(facebook_user)
    # This is a mock implementation since we don't have Prisma set up yet
    # In a real implementation, this would use Prisma to query/create the tenant
    
    # For now, return a mock tenant object
    {
      id: "tenant_#{facebook_user[:id]}",
      name: facebook_user[:name],
      avatarUrl: facebook_user[:avatarUrl],
      facebookId: facebook_user[:id]
    }
  end

  def generate_jwt(tenant_id)
    payload = {
      tenant_id: tenant_id,
      exp: Time.now.to_i + (7 * 24 * 60 * 60) # 7 days
    }
    JWT.encode(payload, @jwt_secret, 'HS256')
  end

  def set_auth_cookie(res, jwt_token)
    # Set secure HTTP-only cookie
    cookie_attributes = [
      "auth_token=#{jwt_token}",
      "HttpOnly",
      "Path=/",
      "Max-Age=#{7 * 24 * 60 * 60}", # 7 days
      "SameSite=Strict"
    ]
    
    # Add Secure flag in production
    if ENV['RACK_ENV'] == 'production'
      cookie_attributes << "Secure"
    end

    res['Set-Cookie'] = cookie_attributes.join('; ')
  end
end 
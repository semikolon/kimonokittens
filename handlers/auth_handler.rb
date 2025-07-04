require 'agoo'
require 'httparty'
require 'jwt'
require 'json'
require 'faraday'
require_relative '../lib/rent_db' # Use our new DB module

# AuthHandler now follows the Agoo pattern: a plain Ruby class with a `call` method.
# It handles Facebook OAuth callbacks, verifies the token, finds or creates a user
# in our database, and returns a JWT for session management.
class AuthHandler
  def initialize
    @facebook_app_id = ENV['FACEBOOK_APP_ID']
    @facebook_app_secret = ENV['FACEBOOK_APP_SECRET']
    @jwt_secret = ENV['JWT_SECRET']
  end

  def call(req)
    # Handle CORS preflight requests
    if req['REQUEST_METHOD'] == 'OPTIONS'
      return [204, cors_headers, []]
    end

    case req['PATH_INFO']
    when '/api/auth/facebook'
      handle_facebook_login(req)
    else
      [404, { 'Content-Type' => 'application/json' }, [{ error: 'Not Found' }.to_json]]
    end
  rescue => e
    puts "Auth error: #{e.message}"
    puts e.backtrace
    [500, { 'Content-Type' => 'application/json' }, [{ error: 'Internal server error' }.to_json]]
  end

  private

  def handle_facebook_login(req)
    # Parse request body from Agoo request
    request_body = JSON.parse(req['rack.input'].read)
    access_token = request_body['accessToken']

    unless access_token
      return [400, cors_headers, [{ error: 'Missing accessToken' }.to_json]]
    end

    # Verify token with Facebook
    facebook_user = verify_facebook_token(access_token)
    unless facebook_user
      return [401, cors_headers, [{ error: 'Invalid Facebook token' }.to_json]]
    end

    # Find or create tenant in our actual database
    tenant = find_or_create_tenant(facebook_user)
    unless tenant
      return [500, cors_headers, [{ error: 'Failed to find or create user account' }.to_json]]
    end

    # Generate JWT
    jwt_token = generate_jwt(tenant['id'])

    # Prepare response headers, including the auth cookie
    headers = cors_headers.merge('Set-Cookie' => auth_cookie_string(jwt_token))

    # Return user data in the response body
    response_body = {
      user: {
        id: tenant['id'],
        name: tenant['name'],
        avatarUrl: tenant['avatarUrl']
      }
    }.to_json

    [200, headers, [response_body]]
  end
  
  def cors_headers
    {
      'Content-Type' => 'application/json',
      'Access-Control-Allow-Origin' => 'http://localhost:5173', # Be specific for security
      'Access-Control-Allow-Methods' => 'POST, GET, OPTIONS',
      'Access-Control-Allow-Headers' => 'Content-Type, Authorization',
      'Access-Control-Allow-Credentials' => 'true'
    }
  end

  def verify_facebook_token(access_token)
    # This method remains largely the same, using HTTParty to call Facebook's API.
    debug_url = "https://graph.facebook.com/debug_token"
    debug_response = HTTParty.get(debug_url, query: {
      input_token: access_token,
      access_token: "#{@facebook_app_id}|#{@facebook_app_secret}"
    })

    unless debug_response.success? && debug_response.dig('data', 'is_valid')
      puts "Facebook token verification failed: #{debug_response.body}"
      return nil
    end

    user_id = debug_response.dig('data', 'user_id')
    return nil unless user_id

    # Get user profile
    profile_url = "https://graph.facebook.com/#{user_id}"
    profile_response = HTTParty.get(profile_url, query: {
      access_token: access_token,
      fields: 'id,first_name,picture.type(large)'
    })

    unless profile_response.success?
      puts "Facebook profile fetch failed: #{profile_response.body}"
      return nil
    end

    {
      facebookId: profile_response['id'],
      name: profile_response['first_name'],
      avatarUrl: profile_response.dig('picture', 'data', 'url')
    }
  end

  def find_or_create_tenant(facebook_user)
    # Replace mock implementation with a call to our RentDb module.
    db = RentDb.instance
    
    # Check if a tenant with this Facebook ID already exists.
    existing_tenant = db.find_tenant_by_facebook_id(facebook_user[:facebookId])
    return existing_tenant if existing_tenant

    # If not, create a new tenant.
    # Note: The `add_tenant` method in RentDb will need to handle this structure.
    # We might need to adjust it if it doesn't match.
    new_tenant_data = {
      name: facebook_user[:name],
      facebookId: facebook_user[:facebookId],
      avatarUrl: facebook_user[:avatarUrl],
      # Email is required by the schema, but not provided by FB basic login.
      # We'll use a placeholder.
      email: "#{facebook_user[:facebookId]}@facebook.placeholder.com"
    }
    db.add_tenant(**new_tenant_data.transform_keys(&:to_sym))
    
    # Fetch the newly created tenant to ensure we have the CUID etc.
    db.find_tenant_by_facebook_id(facebook_user[:facebookId])
  end

  def generate_jwt(tenant_id)
    payload = {
      tenant_id: tenant_id,
      exp: Time.now.to_i + (7 * 24 * 60 * 60) # 7 days
    }
    JWT.encode(payload, @jwt_secret, 'HS256')
  end

  def auth_cookie_string(jwt_token)
    # Consolidate cookie attributes into a single string.
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

    cookie_attributes.join('; ')
  end
end 
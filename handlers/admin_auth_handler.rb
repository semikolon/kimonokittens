require 'json'
require_relative '../lib/admin_auth'

class AdminAuthHandler
  def call(env)
    req = Rack::Request.new(env)

    case req.request_method
    when 'POST'
      authenticate(req)
    else
      response(405, { error: 'Method not allowed' })
    end
  end

  private

  def authenticate(req)
    body = req.body.read
    data = body.empty? ? {} : JSON.parse(body)
    pin = data['pin']&.to_s

    return response(400, { error: 'PIN krävs' }) if pin.nil? || pin.empty?

    begin
      result = AdminAuth.authenticate(pin)
    rescue => e
      return response(500, { error: e.message })
    end

    return response(401, { error: 'Fel PIN' }) unless result

    response(200, {
      token: result[:token],
      expires_at: result[:expires_at].iso8601,
      ttl_seconds: AdminAuth::SESSION_TTL_SECONDS
    })
  rescue JSON::ParserError
    response(400, { error: 'Ogiltig JSON' })
  end

  def response(status, payload)
    [status, { 'Content-Type' => 'application/json' }, [JSON.generate(payload)]]
  end
end

require 'securerandom'
require 'rack/utils'
require 'time'

# Minimal in-memory admin authentication for kiosk actions
module AdminAuth
  SESSION_TTL_SECONDS = (ENV.fetch('ADMIN_PANEL_SESSION_MINUTES', '30').to_i.clamp(1, 720)) * 60

  class << self
    def authenticate(pin)
      configured_pin = ENV.fetch('ADMIN_PANEL_PIN', '').strip
      raise 'ADMIN_PANEL_PIN is not configured' if configured_pin.empty?
      return nil unless secure_compare(pin, configured_pin)

      token = SecureRandom.hex(32)
      expiry = Time.now + SESSION_TTL_SECONDS

      mutex.synchronize do
        cleanup_expired_sessions
        sessions[token] = expiry
      end

      { token: token, expires_at: expiry }
    end

    def authorized?(token)
      return false if token.nil? || token.empty?

      now = Time.now
      mutex.synchronize do
        cleanup_expired_sessions(now)
        expiry = sessions[token]
        return false unless expiry && expiry > now
        true
      end
    end

    def expiry_for(token)
      mutex.synchronize { sessions[token] }
    end

    private

    def sessions
      @sessions ||= {}
    end

    def mutex
      @mutex ||= Mutex.new
    end

    def cleanup_expired_sessions(now = Time.now)
      sessions.delete_if { |_token, expiry| expiry <= now }
    end

    def secure_compare(pin, configured_pin)
      pin = pin.to_s
      configured_pin = configured_pin.to_s
      return false unless pin.bytesize == configured_pin.bytesize
      Rack::Utils.secure_compare(pin, configured_pin)
    rescue
      false
    end
  end
end

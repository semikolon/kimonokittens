require 'faraday'
require 'faraday/excon'

class ProxyHandler
  def call(req)
    # Try kimonokittens.com first, fallback to local IP
    endpoints = [
      "https://kimonokittens.com",
      "http://192.168.4.66:1880"
    ]

    last_error = nil
    endpoints.each do |base_url|
      begin
        conn = Faraday.new(base_url) do |faraday|
          faraday.adapter :excon
          faraday.options.open_timeout = 2  # TCP connection timeout
          faraday.options.timeout = 5       # Overall request timeout
          # Skip SSL verification for kimonokittens.com
          if base_url.include?('kimonokittens.com')
            faraday.ssl.verify = false
          end
        end
        response = conn.get("/data/#{req['PATH_INFO'].split('/data/').last}")
        puts "SUCCESS: Retrieved data from #{base_url}"
        return [response.status, response.headers, [response.body]]
      rescue Faraday::Error => e
        puts "ERROR: Failed to connect to #{base_url}: #{e.message}"
        last_error = e
        next  # Try next endpoint
      end
    end

    # All endpoints failed
    puts "ERROR: All Node-RED endpoints failed, last error: #{last_error.message}"

    error_msg = case last_error.message
    when /No route to host|Couldn't connect to server/
      "Node-RED inte nåbar från alla endpoints"
    when /timeout/i
      "Node-RED svarar för långsamt"
    else
      "Node-RED-tjänst inte tillgänglig: #{last_error.message}"
    end

    [504, { 'Content-Type' => 'application/json' }, ["{\"error\": \"#{error_msg}\"}"]]
  end
end
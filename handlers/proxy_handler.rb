require 'httparty'

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
        url = "#{base_url}/data/#{req['PATH_INFO'].split('/data/').last}"
        options = {
          timeout: 5,
          open_timeout: 2
        }

        # Skip SSL verification for kimonokittens.com
        if base_url.include?('kimonokittens.com')
          options[:verify] = false
        end

        response = HTTParty.get(url, options)
        puts "SUCCESS: Retrieved data from #{base_url}"

        # Simple, safe response processing
        status_code = response.code.to_i
        headers = { 'Content-Type' => 'application/json' }
        body = response.body.to_s

        return [status_code, headers, [body]]
      rescue => e
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

    [504, { 'Content-Type' => 'application/json' }, ["{\"error\": \"#{error_msg}\"}".to_s]]
  end
end
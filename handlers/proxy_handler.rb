require 'faraday'
require 'faraday/excon'

class ProxyHandler
  def call(req)
    # Forward the request to Node-RED with proper timeouts
    conn = Faraday.new("http://192.168.4.66:1880") do |faraday|
      faraday.adapter :excon
      faraday.options.open_timeout = 2  # TCP connection timeout
      faraday.options.timeout = 3       # Overall request timeout
    end
    response = conn.get("/data/#{req['PATH_INFO'].split('/data/').last}")
    [response.status, response.headers, [response.body]]
  rescue Faraday::Error => e
    puts "ERROR: Node-RED proxy call failed: #{e.message}"
    # If Node-RED is down or slow, return a 504 Gateway Timeout
    [504, { 'Content-Type' => 'application/json' }, ['{"error": "Node-RED service is unavailable"}']]
  end
end
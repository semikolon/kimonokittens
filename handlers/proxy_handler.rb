require 'faraday'

class ProxyHandler
  def call(req)
    # Forward the request to Node-RED
    response = Faraday.get("http://192.168.4.66:1880/data/#{req['PATH_INFO'].split('/data/').last}")
    [response.status, response.headers, [response.body]]
  rescue Faraday::Error
    # If Node-RED is down, return a 504 Gateway Timeout
    [504, { 'Content-Type' => 'application/json' }, ['{"error": "Node-RED service is unavailable"}']]
  end
end
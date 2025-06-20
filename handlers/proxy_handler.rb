require 'faraday'

class ProxyHandler
  def call(req)
    response = Faraday.get("http://192.168.4.66:1880/data/#{req['PATH_INFO'].split('/data/').last}")
    [response.status, response.headers, [response.body]]
  end
end
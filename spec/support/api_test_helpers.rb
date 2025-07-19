require 'json'
require 'oj'
require 'stringio'

module ApiTestHelpers
  # Simulates a POST request with a JSON payload
  def post_json(handler, path, payload)
    json_payload = Oj.dump(payload, mode: :compat)
    env = {
      'PATH_INFO' => path,
      'REQUEST_METHOD' => 'POST',
      'rack.input' => StringIO.new(json_payload)
    }
    status, headers, body_array = handler.call(env)
    parsed_body = body_array.any? ? Oj.load(body_array.first, symbol_keys: true) : nil
    [status, headers, parsed_body]
  end

  # Simulates a GET request
  def get_json(handler, path)
    env = {
      'PATH_INFO' => path,
      'REQUEST_METHOD' => 'GET',
      'rack.input' => StringIO.new('')
    }
    status, headers, body_array = handler.call(env)
    parsed_body = body_array.any? ? Oj.load(body_array.first, symbol_keys: true) : nil
    [status, headers, parsed_body]
  end
end 
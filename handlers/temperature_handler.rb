require 'httparty'

class TemperatureHandler
  def call(req)
    begin
      puts "TEMPERATURE_HANDLER: Starting temperature data fetch"

      # Use local Node-RED endpoint directly (domain migrated, public URL phased out)
      endpoints = [
        "http://192.168.4.66:1880/data/temperature"
      ]

      last_error = nil
      endpoints.each do |url|
        begin
          puts "TEMPERATURE_HANDLER: Trying endpoint #{url}"

          options = {
            timeout: 5,
            open_timeout: 2
          }

          response = HTTParty.get(url, options)
          puts "TEMPERATURE_HANDLER: Got response code #{response.code}"

          if response.success?
            body = response.body.to_s
            puts "TEMPERATURE_HANDLER: Success, body length: #{body.length}"

            return [200, { 'Content-Type' => 'application/json' }, [body]]
          else
            puts "TEMPERATURE_HANDLER: Response not successful: #{response.code}"
            next
          end
        rescue => e
          puts "TEMPERATURE_HANDLER: Error with #{url}: #{e.message}"
          last_error = e
          next
        end
      end

      # All endpoints failed
      puts "TEMPERATURE_HANDLER: All endpoints failed, last error: #{last_error&.message}"
      error_msg = case last_error&.message
      when /No route to host|Couldn't connect to server/
        "Temperature sensor inte nåbar från alla endpoints"
      when /timeout/i
        "Temperature sensor svarar för långsamt"
      else
        "Temperature-tjänst inte tillgänglig: #{last_error&.message}"
      end

      [504, { 'Content-Type' => 'application/json' }, ["{\"error\": \"#{error_msg}\"}"]]

    rescue => e
      puts "TEMPERATURE_HANDLER: Unexpected error: #{e.class}: #{e.message}"
      puts e.backtrace.join("\n")
      [500, { 'Content-Type' => 'application/json' }, ["{\"error\": \"Temperature handler error: #{e.message}\"}"]]
    end
  end
end
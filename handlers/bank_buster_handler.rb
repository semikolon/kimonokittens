class BankBusterHandler
  def initialize
    @bank_buster = BankBuster.new
  end

  def call(req)
    return unless req.upgrade?

    req.websocket do |ws|
      ws.on_message do |msg|
        handle_message(ws, msg)
      end
    end
  end

def handle_message(ws, msg)
  puts "Received: #{msg}"

  case msg
  when 'START'
    begin
      @bank_buster.parse do |result|
        if result[:type] == 'QR_UPDATE'
          # Send a message to the frontend to refresh the QR code image.
          ws.write("QR_UPDATE?timestamp=#{Time.now.to_i}")
        elsif result[:type] == 'FILES_RETRIEVED'
          processed_data = BankPaymentsReader.parse_files(result[:filenames])
          # Convert the processed data to JSON using Oj and send it to the frontend.
          ws.write("FILES_RETRIEVED=#{Oj.dump(processed_data)}")
        elsif result[:type] == 'PROGRESS_UPDATE'
          ws.write("PROGRESS_UPDATE=#{result[:progress]}")
        end
      end
        end
      end
    rescue => e
      # Send an error message to the frontend when an exception is raised.
      ws.write("ERROR: #{e.message}")
    end
  end
end

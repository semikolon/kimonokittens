require 'oj'

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
  yield({ type: 'LOG', data: "Received: #{msg}" }) if block_given?

  case msg
  when 'START'
    begin
      @bank_buster.parse do |result|
        # Convert the result to JSON using Oj and send it to the frontend.
        ws.write(Oj.dump(result))
      end
    rescue => e
      # Send an error message to the frontend when an exception is raised.
      ws.write("ERROR: #{e.message}")
    end
  end
end

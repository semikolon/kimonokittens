require 'oj'
require_relative '../bank_buster'
require 'oj'

class BankBusterHandler
  def initialize
    puts "Initializing..."
    # comment out the instance 
    #@bank_buster = BankBuster.new
  end

  def call(req)
    return unless req.upgrade?

    req.websocket do |ws|
      ws.on_open do
        puts "Socket connection opened successfully."
      end
      ws.on_message do |msg|
        handle_message(ws, msg)
      end
      ws.on_close do 
        puts "Closing socket connection."
      end
    end
  end

  def handle_message(ws, msg)
    puts "Received message: #{msg}"
    
    # If msg == 'START', just print out we got the start message, but don't do any parsing
    if msg == 'START'
      puts "Received start message"
    end
  # Comment the rescue part, let the exceptions propagate to get the default debugging behavior. 
  # rescue => e
  #   ws.write("ERROR: #{e.message}")
  end
end

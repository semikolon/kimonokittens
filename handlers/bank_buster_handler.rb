require_relative '../bank_buster'
require 'oj'
# require 'pry'  # Temporarily disabled due to gem conflict
require 'agoo'
require 'colorize'

class BankBusterHandler
  def initialize
    puts "Initializing BankBusterHandler..."
    # A BankBuster instance will be created on-demand for each job.
  end

  def call(env)
    if env['rack.upgrade?'] == :websocket
      env['rack.upgrade'] = self # Return this instance as the WebSocket handler so callbacks fire
      # DO NOT CHANGE THIS STATUS CODE! Agoo+Rack requires 101 for WebSocket upgrades.
      return [101, {}, []]
    end
    [404, { 'Content-Type' => 'text/plain' }, ['Not Found']]
  end

  def on_open(client)
    puts "BANKBUSTER WS: Connection opened."
  end

  def on_message(client, msg)
    puts "BANKBUSTER WS: Received message: #{msg}"

    if msg == 'START'
      puts "BANKBUSTER WS: Received start message, starting a new BankBuster job"
      # Send immediate acknowledgement so frontend knows handler is alive
      client.write(Oj.dump({ type: 'LOG', data: 'BankBuster job started on server...' }))
      
      # Run the scraper in a separate thread to avoid blocking the server and the websocket connection.
      Thread.new do
        begin
          # Use the modern Vessel API with run method
          BankBuster.run do |event|
            puts "BANKBUSTER EVENT: #{event.inspect}"
            client.write(Oj.dump(event))
          end
        rescue => e
          error_details = { type: 'FATAL_ERROR', error: e.class.name, message: e.message, backtrace: e.backtrace }
          puts "Error in BankBuster thread: #{error_details}".red
          client.write(Oj.dump(error_details))
        end
      end
    end
  end

  def on_close(client)
    puts "BANKBUSTER WS: Closing socket connection."
  end
end
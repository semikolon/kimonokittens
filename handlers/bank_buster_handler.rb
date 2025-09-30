# require_relative '../bank_buster'
require 'oj'
# require 'pry'  # Temporarily disabled due to gem conflict
# require 'agoo' # Removed - using Puma instead

=begin
class BankBusterHandler
  def initialize
    puts "Initializing BankBusterHandler..."
    # @bank_buster = BankBuster.new
  end

  def call(env)
    if env[\'rack.upgrade?\'] == :websocket
      env[\'rack.upgrade\'] = self
      # DO NOT CHANGE THIS STATUS CODE! Agoo+Rack requires 101 for WebSocket upgrades.
      return [101, {}, []]
    end
    [404, { \'Content-Type\' => \'text/plain\' }, [\'Not Found\']]
  end

  def on_open(client)
    puts "BANKBUSTER WS: Connection opened."
  end

  def on_message(client, msg)
    puts "BANKBUSTER WS: Received message: #{msg}"
    
    if msg == \'START\'
      puts "BANKBUSTER WS: Received start message"
      client.write(\'echo: START received\')
    end
  end

  def on_close(client)
    puts "BANKBUSTER WS: Closing socket connection."
  end
end
=end

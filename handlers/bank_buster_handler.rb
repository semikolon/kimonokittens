# require_relative '../bank_buster'
require 'oj'
# require 'pry'  # Temporarily disabled due to gem conflict
require 'agoo'

class BankBusterHandler
  def initialize
    puts "Initializing..."
    # @bank_buster = BankBuster.new
  end

  def call(env)
    return unless env['rack.upgrade?'] == :websocket

    io = env['rack.hijack'].call
    #binding.pry
    ws = Agoo::Upgraded.new(io, self)
    ws.each do |msg|
      handle_message(ws, msg)
    end
  end

  def on_open(upgraded)
    puts "Socket connection opened successfully."
  end

  def on_close(upgraded)
    puts "Closing socket connection."
  end

  def on_message(upgraded, msg)
    puts "Received message: #{msg}"
    
    if msg == 'START'
      puts "Received start message"
    end
  end
end
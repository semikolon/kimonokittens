# require_relative '../bank_buster'
require 'oj'
require 'pry'
require 'agoo'

class BankBusterHandler
  def initialize
    puts "Initializing..."
    # @bank_buster = BankBuster.new
  end

  def call(env)
    return unless env['rack.upgrade?'] == :websocket

    req = env['rack.hijack']
    ws = Agoo::Upgraded.new(req, self)
    ws.each do |msg|
      handle_message(ws, msg)
    end
  end

  def on_open(upgraded)
    puts "Socket connection opened successfully."
  end

  def on_message(upgraded, msg)
    handle_message(upgraded, msg)
  end

  def on_close(upgraded)
    puts "Closing socket connection."
  end

  def handle_message(ws, msg)
    puts "Received message: #{msg}"
    
    if msg == 'START'
      puts "Received start message"
    end
  end
end
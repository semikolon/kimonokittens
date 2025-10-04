require_relative 'spec_helper'
require 'rack/test'
require_relative '../json_server'
require 'webmock/rspec'
require 'faye/websocket'
require 'eventmachine'

# Note: This is a more complex integration test that requires a running EventMachine reactor.
# It's necessary for testing stateful WebSocket connections.

RSpec.describe 'Handbook WebSocket Integration' do
  include Rack::Test::Methods

  def app
    # This points to the Agoo server setup in json_server.rb
    Agoo::Server
  end

  # This test requires a running server instance to connect to.
  # We'll need to manage the server lifecycle for this test.
  before(:all) do
    # Suppress server output during tests
    Agoo::Log.configure(dir: '', console: false, classic: false)
    
    # Fork a process for the server to run in the background
    @server_pid = fork do
      # Make sure to load the environment for the server
      require 'dotenv/load'
      # This loads all the handlers and starts the server
      load 'json_server.rb'
    end
    # Give the server a moment to boot
    sleep 2
  end

  after(:all) do
    # Shut down the server process after tests are done
    Process.kill('KILL', @server_pid)
    Process.wait(@server_pid)
  end

  it 'accepts a WebSocket connection and receives a broadcasted message' do
    received_message = nil
    error_message = nil

    EM.run do
      # Connect to the running server's WebSocket endpoint
      ws = Faye::WebSocket::Client.new('ws://localhost:3001/handbook/ws')

      ws.on :open do |event|
        # Publish a message from the server side via the global $pubsub
        $pubsub.publish('hello_from_spec')
      end

      ws.on :message do |event|
        received_message = event.data
        ws.close
      end

      ws.on :error do |event|
        error_message = event.message
        EM.stop
      end

      ws.on :close do |event|
        EM.stop
      end
      
      # Timeout to prevent test from hanging
      EM.add_timer(5) do
        EM.stop
        fail "Test timed out" unless received_message
      end
    end

    expect(error_message).to be_nil
    expect(received_message).to eq('hello_from_spec')
  end
end 
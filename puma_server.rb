require 'dotenv/load'
require 'puma'
require 'faraday'
require 'oj'
require 'awesome_print'
require 'active_support/all'
require 'fileutils'
require 'digest/sha1'
require 'base64'

puts "Puma version: #{Puma::Const::VERSION}"

# Set timezone to avoid segfaults in rufus-scheduler/et-orbi
Time.zone = 'Europe/Stockholm'
ENV['TZ'] = Time.zone.name

# Load the DataBroadcaster
require_relative 'lib/data_broadcaster'

# Configure logging
if ENV['RACK_ENV'] == 'production'
  log_dir = '/var/log/kimonokittens'
else
  log_dir = File.expand_path('log', __dir__)
  FileUtils.mkdir_p(log_dir)
  puts "Development mode - logging to #{log_dir}"
end

# Load handlers
require_relative 'handlers/proxy_handler'
require_relative 'handlers/home_page_handler'
require_relative 'handlers/static_handler'
require_relative 'handlers/train_departure_handler'
require_relative 'handlers/strava_workouts_handler'
require_relative 'handlers/rent_and_finances_handler'
require_relative 'handlers/rent_calculator_handler'
require_relative 'handlers/handbook_handler'
require_relative 'handlers/weather_handler'
require_relative 'handlers/temperature_handler'

# Initialize handlers
home_page_handler = HomePageHandler.new
proxy_handler = ProxyHandler.new
static_handler = StaticHandler.new
train_departure_handler = TrainDepartureHandler.new
strava_workouts_handler = StravaWorkoutsHandler.new
rent_and_finances_handler = RentAndFinancesHandler.new
rent_calculator_handler = RentCalculatorHandler.new
handbook_handler = HandbookHandler.new
weather_handler = WeatherHandler.new
temperature_handler = TemperatureHandler.new

# --- WebSocket Pub/Sub Manager ---
class PubSub
  def initialize
    @clients = {}
    @mutex = Mutex.new
  end

  def subscribe(con_id, stream)
    @mutex.synchronize do
      @clients[con_id] = stream
    end
    puts "Client subscribed with con_id: #{con_id}"
  end

  def unsubscribe(con_id)
    @mutex.synchronize do
      @clients.delete(con_id)
    end
    puts "Client unsubscribed with con_id: #{con_id}"
  end

  def publish(message)
    clients_to_remove = []
    @mutex.synchronize do
      @clients.each do |con_id, stream|
        begin
          # Write WebSocket frame
          frame = create_websocket_frame(message)
          stream.write(frame)
        rescue => e
          puts "Error writing to client #{con_id}: #{e.message}"
          clients_to_remove << con_id
        end
      end
      # Remove dead clients
      clients_to_remove.each { |con_id| @clients.delete(con_id) }
    end
    puts "Published message to #{@clients.size} clients: #{message}"
  end

  private

  def create_websocket_frame(data)
    # Ensure data is UTF-8 encoded
    data = data.force_encoding('UTF-8')

    # Create a simple WebSocket text frame
    frame = "\x81".force_encoding('BINARY') # FIN=1, opcode=1 (text)

    if data.bytesize < 126
      frame += [data.bytesize].pack('C')
    elsif data.bytesize < 65536
      frame += [126, data.bytesize].pack('Cn')
    else
      frame += [127, data.bytesize].pack('CQ>')
    end

    frame + data.force_encoding('BINARY')
  end
end

# Simple WebSocket handler using Rack hijacking
class WebSocketHandler
  WS_MAGIC_STRING = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"

  def call(env)
    if websocket_request?(env)
      upgrade_connection(env)
    else
      [404, { 'Content-Type' => 'text/plain' }, ['Not Found']]
    end
  end

  private

  def websocket_request?(env)
    env['HTTP_UPGRADE']&.downcase == 'websocket' &&
      env['HTTP_CONNECTION']&.downcase&.include?('upgrade') &&
      env['HTTP_SEC_WEBSOCKET_KEY']
  end

  def upgrade_connection(env)
    # Calculate WebSocket accept key
    key = env['HTTP_SEC_WEBSOCKET_KEY']
    accept = Base64.strict_encode64(Digest::SHA1.digest(key + WS_MAGIC_STRING))

    # Return upgrade response
    headers = {
      'Upgrade' => 'websocket',
      'Connection' => 'Upgrade',
      'Sec-WebSocket-Accept' => accept
    }

    # Use rack.hijack to take over the connection
    [101, headers, []]
  end
end

# Main WebSocket handler
class WsHandler < WebSocketHandler
  def upgrade_connection(env)
    key = env['HTTP_SEC_WEBSOCKET_KEY']
    accept = Base64.strict_encode64(Digest::SHA1.digest(key + WS_MAGIC_STRING))

    headers = {
      'Upgrade' => 'websocket',
      'Connection' => 'Upgrade',
      'Sec-WebSocket-Accept' => accept,
      'rack.hijack' => lambda do |io|
        handle_websocket_connection(io)
      end
    }

    [101, headers, []]
  end

  private

  def handle_websocket_connection(io)
    con_id = io.object_id
    puts "WS: Connection opened #{con_id}"

    # Subscribe to pubsub
    $pubsub.subscribe(con_id, io)

    # Send immediate data
    $data_broadcaster.send_immediate_data_to_new_client

    # Handle incoming messages in a separate thread to avoid blocking Puma
    Thread.new do
      begin
        while !io.closed?
          # Simple WebSocket frame reading (basic implementation)
          if io.wait_readable(30) # 30 second timeout
            data = io.read_nonblock(1024)
            if data && data.length > 0
              puts "PUMA WS: #{con_id} -> received data"
              # Echo back (simple implementation)
              frame = $pubsub.send(:create_websocket_frame, "echo: message received")
              io.write(frame)
            end
          end
        end
      rescue EOFError, Errno::ECONNRESET, IO::WaitReadable
        puts "PUMA WS: Connection closed #{con_id}"
      rescue => e
        puts "PUMA WS: Error handling connection #{con_id}: #{e.message}"
      ensure
        $pubsub.unsubscribe(con_id)
        io.close unless io.closed?
      end
    end
  end
end

# Debug WebSocket handler
class DebugWsHandler < WebSocketHandler
  def upgrade_connection(env)
    result = super(env)

    env['rack.hijack_io'] = lambda do |io|
      puts "*** DEBUG WS: Connection established ***"
      frame = $pubsub.send(:create_websocket_frame, "DEBUG: Connection established at #{Time.now}")
      io.write(frame)

      Thread.new do
        begin
          while !io.closed?
            if io.wait_readable(30)
              data = io.read_nonblock(1024)
              if data && data.length > 0
                frame = $pubsub.send(:create_websocket_frame, "DEBUG: Echo at #{Time.now.strftime('%H:%M:%S')}")
                io.write(frame)
              end
            end
          end
        rescue => e
          puts "DEBUG WS: Connection error: #{e.message}"
        ensure
          puts "*** DEBUG WS: Connection closed ***"
          io.close unless io.closed?
        end
      end
    end

    result
  end
end

# Initialize global PubSub instance and DataBroadcaster
$pubsub = PubSub.new
$data_broadcaster = DataBroadcaster.new($pubsub)

# Create Rack application
app = Rack::Builder.new do
  # WebSocket routes
  map "/dashboard/ws" do
    run WsHandler.new
  end

  map "/debug/ws" do
    run DebugWsHandler.new
  end

  # API routes
  map "/api/handbook" do
    run handbook_handler
  end

  map "/api/rent" do
    run rent_calculator_handler
  end

  # Data routes
  map "/data/train_departures" do
    run train_departure_handler
  end

  map "/data/strava_stats" do
    run strava_workouts_handler
  end

  map "/data/weather" do
    run weather_handler
  end

  map "/data/temperature" do
    run temperature_handler
  end

  map "/data" do
    run proxy_handler
  end

  # Home and static routes
  map "/" do
    run home_page_handler
  end

  # Catch-all for static files
  run static_handler
end

# Configure Puma
port = ENV.fetch('PORT', 3001).to_i

# Start the data broadcaster after short delay
if ENV.fetch('ENABLE_BROADCASTER', '0') == '1'
  Thread.new do
    sleep(3) # Give server time to start
    begin
      $data_broadcaster.start
      puts "DataBroadcaster started successfully"
    rescue => e
      puts "Failed to start DataBroadcaster: #{e.message}"
    end
  end
else
  puts "DataBroadcaster disabled (set ENABLE_BROADCASTER=1 to enable)"
end

# If this file is run directly, start the server manually for testing
if __FILE__ == $0
  port = ENV.fetch('PORT', 3001).to_i
  puts "Starting development server on http://0.0.0.0:#{port}"
  require 'puma'
  Puma::Server.new(app).tap do |server|
    server.add_tcp_listener('0.0.0.0', port)
    server.run.join
  end
end
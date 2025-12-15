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

# Enable immediate stdout/stderr flushing for non-TTY logging
$stdout.sync = true
$stderr.sync = true

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
require_relative 'handlers/todos_handler'
require_relative 'handlers/reload_handler'
require_relative 'handlers/display_control_handler'
require_relative 'handlers/sleep_schedule_handler'
require_relative 'handlers/heating_cost_handler'
require_relative 'handlers/electricity_price_handler'
require_relative 'handlers/electricity_stats_handler'
require_relative 'handlers/heatpump_price_handler'
require_relative 'handlers/heatpump_schedule_handler'
require_relative 'handlers/heatpump_config_handler'
require_relative 'handlers/heatpump_analysis_handler'
require_relative 'handlers/screenshot_handler'
require_relative 'handlers/zigned_webhook_handler'
require_relative 'handlers/contract_pdf_handler'
require_relative 'handlers/admin_contracts_handler'
require_relative 'handlers/tenant_handler'
require_relative 'handlers/admin_auth_handler'
require_relative 'handlers/signup_handler'
require_relative 'handlers/admin_leads_handler'
require_relative 'handlers/admin_todos_handler'
require_relative 'handlers/elks_webhooks'
require_relative 'handlers/sun_handler'

# Initialize handlers
home_page_handler = HomePageHandler.new
heating_cost_handler = HeatingCostHandler.new
electricity_price_handler = ElectricityPriceHandler.new
electricity_stats_handler = ElectricityStatsHandler.new(electricity_price_handler)
heatpump_price_handler = HeatpumpPriceHandler.new(electricity_price_handler)
heatpump_schedule_handler = HeatpumpScheduleHandler.new(heatpump_price_handler)
heatpump_config_handler = HeatpumpConfigHandler.new
heatpump_analysis_handler = HeatpumpAnalysisHandler.new
screenshot_handler = ScreenshotHandler.new
proxy_handler = ProxyHandler.new
static_handler = StaticHandler.new
train_departure_handler = TrainDepartureHandler.new
strava_workouts_handler = StravaWorkoutsHandler.new
rent_and_finances_handler = RentAndFinancesHandler.new
rent_calculator_handler = RentCalculatorHandler.new
handbook_handler = HandbookHandler.new
weather_handler = WeatherHandler.new
temperature_handler = TemperatureHandler.new
todos_handler = TodosHandler.new
contract_pdf_handler = ContractPdfHandler.new
admin_contracts_handler = AdminContractsHandler.new
tenant_handler = TenantHandler.new
admin_auth_handler = AdminAuthHandler.new
signup_handler = SignupHandler.new
admin_leads_handler = AdminLeadsHandler.new
admin_todos_handler = AdminTodosHandler.new
sun_handler = SunHandler.new

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
$reload_handler = ReloadHandler.new($pubsub)

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

  map "/api/todos" do
    run todos_handler
  end

  map "/api/reload" do
    run $reload_handler
  end

  map "/api/heating/cost_per_degree" do
    run heating_cost_handler
  end

  map "/api/screenshot" do
    run screenshot_handler
  end

  # Admin contracts API
  map "/api/admin/contracts" do
    run admin_contracts_handler
  end

  map "/api/admin/auth" do
    run admin_auth_handler
  end

  # Admin leads API
  map "/api/admin/leads" do
    run admin_leads_handler
  end

  # Admin todos API (Git-backed, PIN-gated)
  map "/api/admin/todos" do
    run admin_todos_handler
  end

  # Public signup form
  map "/api/signup" do
    run signup_handler
  end

  # Contract PDF serving endpoint
  map "/api/contracts" do
    run contract_pdf_handler
  end

  # Tenant management API
  map "/api/tenants" do
    run tenant_handler
  end

  # Zigned webhook endpoint for contract signing events
  map "/api/webhooks/zigned" do
    run lambda { |env|
      req = Rack::Request.new(env)

      if req.post?
        handler = ZignedWebhookHandler.new(broadcaster: $data_broadcaster)
        result = handler.handle(req)

        status = result[:status]
        body = Oj.dump(result)

        [status, {'Content-Type' => 'application/json'}, [body]]
      else
        [405, {'Content-Type' => 'application/json'}, [Oj.dump({ error: 'Method not allowed' })]]
      end
    }
  end

  # 46elks SMS webhooks (delivery receipts + incoming SMS)
  map "/webhooks/elks" do
    run ElksWebhooksHandler.new
  end

  # Display control routes
  map "/api/display" do
    run lambda { |env|
      req = Rack::Request.new(env)
      path = req.path_info

      # Route based on full path
      case path
      when '/power'
        if req.post?
          params = Oj.load(req.body.read) rescue {}
          result = DisplayControlHandler.handle_display_power(params)
          [200, {'Content-Type' => 'application/json'}, [Oj.dump(result)]]
        else
          [405, {'Content-Type' => 'application/json'}, [Oj.dump({ error: 'Method not allowed' })]]
        end
      when '/brightness'
        if req.post?
          params = Oj.load(req.body.read) rescue {}
          result = DisplayControlHandler.handle_brightness(params)
          [200, {'Content-Type' => 'application/json'}, [Oj.dump(result)]]
        else
          [405, {'Content-Type' => 'application/json'}, [Oj.dump({ error: 'Method not allowed' })]]
        end
      else
        [404, {'Content-Type' => 'application/json'}, [Oj.dump({ error: 'Not found' })]]
      end
    }
  end

  # Sleep schedule config
  map "/api/sleep/config" do
    run lambda { |env|
      req = Rack::Request.new(env)

      if req.get?
        result = SleepScheduleHandler.get_config
        [200, {'Content-Type' => 'application/json'}, [Oj.dump(result)]]
      else
        [405, {'Content-Type' => 'application/json'}, [Oj.dump({ error: 'Method not allowed' })]]
      end
    }
  end

  # Frontend logging endpoint (for debugging)
  map "/api/log" do
    run lambda { |env|
      req = Rack::Request.new(env)
      if req.post?
        begin
          data = Oj.load(req.body.read)
          log_file = ENV['RACK_ENV'] == 'production' ? '/var/log/kimonokittens/frontend.log' : File.expand_path('log/frontend.log', __dir__)
          File.open(log_file, 'a') { |f| f.puts "[#{Time.now.strftime('%H:%M:%S')}] #{data['message']}" }
          [200, {'Content-Type' => 'application/json'}, ['{}']]
        rescue
          [500, {'Content-Type' => 'application/json'}, ['{"error":"failed"}']]
        end
      else
        [405, {'Content-Type' => 'text/plain'}, ['Method Not Allowed']]
      end
    }
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

  map "/data/electricity_prices" do
    run electricity_price_handler
  end

  map "/data/sun_windows" do
    run sun_handler
  end

  map "/api/electricity/daily_costs" do
    run electricity_stats_handler
  end

  map "/api/heatpump/prices" do
    run heatpump_price_handler
  end

  map "/api/heatpump/schedule" do
    run heatpump_schedule_handler
  end

  map "/api/heatpump/config" do
    run heatpump_config_handler
  end

  map "/api/heatpump/analysis" do
    run heatpump_analysis_handler
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

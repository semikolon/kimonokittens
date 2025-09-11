require 'dotenv/load'
require 'agoo'
require 'faraday'
require 'oj'
require 'awesome_print'
require 'active_support/all'
require 'fileutils'
# require 'pry'  # Temporarily disabled due to gem conflict

puts "Agoo version: #{Agoo::VERSION}"

# Set timezone to avoid segfaults in rufus-scheduler/et-orbi
Time.zone = 'Europe/Stockholm'
ENV['TZ'] = Time.zone.name

# Load the DataBroadcaster
require_relative 'lib/data_broadcaster'

# Configure Agoo logging
if ENV['RACK_ENV'] == 'production'
  # In production, write to system log directory and disable console logging
  log_dir = '/var/log/kimonokittens'
  # Do not attempt to create the system directory here; ensure it exists in deployment
  Agoo::Log.configure(
    dir: log_dir,
    console: false,
    classic: true,
    colorize: false,
    states: {
      INFO: true,
      DEBUG: true,
      connect: true,
      request: true,
      response: true,
      eval: true,
      push: true
    }
  )
else
  # In development, write to repo-local log/ and keep console logging
  log_dir = File.expand_path('log', __dir__)
  FileUtils.mkdir_p(log_dir)
  Agoo::Log.configure(
    dir: log_dir,
    console: true,
    classic: true,
    colorize: true,
    states: {
      INFO: true,
      DEBUG: true,
      connect: true,
      request: true,
      response: true,
      eval: true,
      push: true
    }
  )
end

# Initialize the Agoo server with SSL configuration
# Initialize the Agoo server - SSL only in production
if ENV['RACK_ENV'] == 'production'
  Agoo::Server.init(6464, 'root', thread_count: 0,
    ssl_cert: "/etc/letsencrypt/live/kimonokittens.com/fullchain.pem",
    ssl_key: ENV['SSL_KEY_PATH'] || "/etc/letsencrypt/live/kimonokittens.com/privkey.pem",
    bind: ['http://0.0.0.0:6464',
            'https://0.0.0.0:6465',
          ],
  )
else
  # Development mode - no SSL
  Agoo::Server.init(3001, 'root', thread_count: 0,
    bind: ['http://0.0.0.0:3001'],
  )
  puts "Starting development server on http://localhost:3001"
end

# require_relative 'handlers/electricity_stats_handler'
require_relative 'handlers/proxy_handler'
require_relative 'handlers/home_page_handler'
require_relative 'handlers/static_handler'
require_relative 'handlers/train_departure_handler'
require_relative 'handlers/strava_workouts_handler'
# # require_relative 'handlers/bank_buster_handler'
require_relative 'handlers/rent_and_finances_handler'
require_relative 'handlers/rent_calculator_handler'
require_relative 'handlers/handbook_handler'
# require_relative 'handlers/auth_handler'
require_relative 'handlers/weather_handler'

home_page_handler = HomePageHandler.new
# electricity_stats_handler = ElectricityStatsHandler.new
proxy_handler = ProxyHandler.new
static_handler = StaticHandler.new
train_departure_handler = TrainDepartureHandler.new
strava_workouts_handler = StravaWorkoutsHandler.new
# # bank_buster_handler = BankBusterHandler.new
rent_and_finances_handler = RentAndFinancesHandler.new
rent_calculator_handler = RentCalculatorHandler.new
handbook_handler = HandbookHandler.new
# auth_handler = AuthHandler.new
weather_handler = WeatherHandler.new

# --- WebSocket Pub/Sub Manager ---
# A simple in-memory manager for WebSocket connections.
class PubSub
  def initialize
    @clients = {}
    @mutex = Mutex.new
  end

  def subscribe(con_id, client)
    @mutex.synchronize do
      @clients[con_id] = client
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
    @mutex.synchronize do
      @clients.values.each do |client|
        # Agoo's #write is thread-safe
        client.write(message)
      end
    end
    puts "Published message to #{@clients.size} clients: #{message}"
  end
end

class WsHandler
  def call(env)
    puts "WsHandler#call - rack.upgrade? = #{env['rack.upgrade?']}"
    if env['rack.upgrade?'] == :websocket
      env['rack.upgrade'] = self.class   # hand the CLASS, not an instance
      puts "WsHandler#call - Setting env['rack.upgrade'] to #{env['rack.upgrade']} (class: #{env['rack.upgrade'].class}, object_id: #{env['rack.upgrade'].object_id})"
      # DO NOT CHANGE THIS STATUS CODE! Agoo+Rack requires 101 (Switching Protocols) for WebSocket upgrades.
      # See: https://github.com/ohler55/agoo/issues/216
      return [101, {}, []]               # 101 Switching Protocols is the correct status
    end
    [404, { 'Content-Type' => 'text/plain' }, ['Not Found']]
  end

  def on_open(client)
    con_id = client.con_id
    client.vars[:con_id] = con_id        # store per-connection state
    $pubsub.subscribe(con_id, client)
    puts "HANDBOOK WS: open #{con_id}"
  end

  def on_message(client, msg)
    con_id = client.vars[:con_id]
    puts "HANDBOOK WS: #{con_id} -> #{msg}"
    client.write("echo: #{msg}")
  end

  def on_close(client)
    con_id = client.vars[:con_id]
    $pubsub.unsubscribe(con_id) if con_id
    puts "HANDBOOK WS: close #{con_id}"
  end
end

# Minimal debug WebSocket handler for testing on_open callbacks
class DebugWsHandler
  def call(env)
    puts "DebugWsHandler#call - rack.upgrade? = #{env['rack.upgrade?']}"
    if env['rack.upgrade?'] == :websocket
      env['rack.upgrade'] = self.class
      puts "DebugWsHandler#call - Setting env['rack.upgrade'] to #{env['rack.upgrade']} (class: #{env['rack.upgrade'].class}, object_id: #{env['rack.upgrade'].object_id})"
      return [101, {}, []]
    end
    [404, { 'Content-Type' => 'text/plain' }, ['Not Found']]
  end

  def on_open(client)
    puts "*** DEBUG WS: on_open fired! Client con_id: #{client.con_id} ***"
    client.write("DEBUG: Connection established at #{Time.now}")
  end

  def on_message(client, msg)
    puts "DEBUG WS: Received message: #{msg}"
    client.write("DEBUG: Echo at #{Time.now.strftime('%H:%M:%S')} - #{msg}")
  end

  def on_close(client)
    puts "*** DEBUG WS: on_close fired! Client con_id: #{client.con_id} ***"
  end
end

# Initialize global PubSub instance and DataBroadcaster
$pubsub = PubSub.new
$data_broadcaster = DataBroadcaster.new($pubsub)

Agoo::Server.handle(:GET, "/", home_page_handler)

# Add WebSocket handler for the Dashboard
Agoo::Server.handle(:GET, "/dashboard/ws", WsHandler.new)

# Add debug WebSocket handler for testing on_open callbacks
Agoo::Server.handle(:GET, "/debug/ws", DebugWsHandler.new)

# Add WebSocket handler for BankBuster
# Agoo::Server.handle(:GET, "/ws", bank_buster_handler)

# Add Handbook API handlers
Agoo::Server.handle(:GET, "/api/handbook/*", handbook_handler)
Agoo::Server.handle(:POST, "/api/handbook/*", handbook_handler)

# Add Authentication API handlers
# Agoo::Server.handle(:POST, "/api/auth/*", auth_handler)
# Agoo::Server.handle(:OPTIONS, "/api/auth/*", auth_handler)

Agoo::Server.handle(:GET, "/*", static_handler)

# Agoo::Server.handle(:GET, "/data/rent_and_finances", rent_and_finances_handler)
# Agoo::Server.handle(:GET, "/data/electricity", electricity_stats_handler)
Agoo::Server.handle(:GET, "/data/train_departures", train_departure_handler)
Agoo::Server.handle(:GET, "/data/strava_stats", strava_workouts_handler)
Agoo::Server.handle(:GET, "/data/weather", weather_handler)

# Add rent calculator endpoints
Agoo::Server.handle(:GET, "/api/rent", rent_calculator_handler)
Agoo::Server.handle(:GET, "/api/rent/forecast", rent_calculator_handler)
Agoo::Server.handle(:GET, "/api/rent/history", rent_calculator_handler)
Agoo::Server.handle(:GET, "/api/rent/roommates", rent_calculator_handler)
Agoo::Server.handle(:POST, "/api/rent", rent_calculator_handler)
Agoo::Server.handle(:POST, "/api/rent/roommates", rent_calculator_handler)
Agoo::Server.handle(:PUT, "/api/rent/config", rent_calculator_handler)

Agoo::Server.handle(:GET, "/data/*", proxy_handler)

# Start the data broadcaster

if ENV.fetch('ENABLE_BROADCASTER', '0') == '1'
  begin
    $data_broadcaster.start
  rescue => e
    puts "Failed to start DataBroadcaster: #{e.message}"
  end
else
  puts "DataBroadcaster disabled (set ENABLE_BROADCASTER=1 to enable)"
end

Agoo::Server.start()

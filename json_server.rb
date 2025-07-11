require 'dotenv/load'
require 'agoo'
require 'faraday'
require 'oj'
require 'awesome_print'
# require 'pry'  # Temporarily disabled due to gem conflict

# Configure Agoo logging
Agoo::Log.configure(dir: '',
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
    push: false
  })

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

require_relative 'handlers/electricity_stats_handler'
require_relative 'handlers/proxy_handler'
require_relative 'handlers/home_page_handler'
require_relative 'handlers/static_handler'
require_relative 'handlers/train_departure_handler'
require_relative 'handlers/strava_workouts_handler'
require_relative 'handlers/bank_buster_handler'
require_relative 'handlers/rent_and_finances_handler'
require_relative 'handlers/rent_calculator_handler'
require_relative 'handlers/handbook_handler'
require_relative 'handlers/auth_handler'
require_relative 'handlers/weather_handler'

home_page_handler = HomePageHandler.new
electricity_stats_handler = ElectricityStatsHandler.new
proxy_handler = ProxyHandler.new
static_handler = StaticHandler.new
train_departure_handler = TrainDepartureHandler.new
strava_workouts_handler = StravaWorkoutsHandler.new
bank_buster_handler = BankBusterHandler.new
rent_and_finances_handler = RentAndFinancesHandler.new
rent_calculator_handler = RentCalculatorHandler.new
handbook_handler = HandbookHandler.new
auth_handler = AuthHandler.new
weather_handler = WeatherHandler.new

def run_one_time_data_correction
  puts "Running one-time data corrections..."
  db = RentDb.instance

  # This is a critical data correction block that runs on server start.
  # It ensures that tenant data in the database is consistent with our
  # historical records.
  tenant_data = {
    'Fredrik' => { startDate: '2023-02-01', departureDate: nil },
    'Rasmus' => { startDate: '2023-06-01', departureDate: nil },
    'Elvira' => { startDate: '2024-11-22', departureDate: nil },
    'Adam' => { startDate: '2025-03-01', departureDate: nil },
    'Frans-Lukas' => { startDate: '2023-12-01', departureDate: '2025-03-01' },
    'Malin' => { startDate: '2023-02-01', departureDate: '2024-11-21' },
    'Astrid' => { startDate: '2024-02-01', departureDate: '2024-11-30' },
    'Camila' => { startDate: '2023-02-01', departureDate: '2023-05-31' }
  }

  tenant_data.each do |name, dates|
    # Ensure the tenant exists
    email = "#{name.downcase.gsub(/\\s+/, '.')}@kimonokittens.com"
    db.add_tenant(name: name) unless db.find_tenant_by_email(email)

    # Set start and departure dates
    db.set_start_date(name: name, date: dates[:startDate]) if dates[:startDate]
    db.set_departure_date(name: name, date: dates[:departureDate]) if dates[:departureDate]
  end

  puts "Data corrections complete."
end

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
    if env['rack.upgrade?'] == :websocket
      env['rack.upgrade'] = self.class   # hand the CLASS, not an instance
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

run_one_time_data_correction()

# Initialize global PubSub instance
$pubsub = PubSub.new

Agoo::Server.handle(:GET, "/", home_page_handler)

# Add WebSocket handler for the Handbook
Agoo::Server.handle(:GET, "/handbook/ws", WsHandler.new)

# Add WebSocket handler for the Dashboard
Agoo::Server.handle(:GET, "/dashboard/ws", WsHandler.new)

# Add WebSocket handler for BankBuster
Agoo::Server.handle(:GET, "/ws", bank_buster_handler)

# Add Handbook API handlers
Agoo::Server.handle(:GET, "/api/handbook/*", handbook_handler)
Agoo::Server.handle(:POST, "/api/handbook/*", handbook_handler)

# Add Authentication API handlers
Agoo::Server.handle(:POST, "/api/auth/*", auth_handler)
Agoo::Server.handle(:OPTIONS, "/api/auth/*", auth_handler)

Agoo::Server.handle(:GET, "/*", static_handler)

Agoo::Server.handle(:GET, "/api/v1/rent_and_finances", rent_and_finances_handler)
Agoo::Server.handle(:GET, "/api/v1/electricity", electricity_stats_handler)
Agoo::Server.handle(:GET, "/api/v1/train_departures", train_departure_handler)
Agoo::Server.handle(:GET, "/api/v1/strava_stats", strava_workouts_handler)
Agoo::Server.handle(:GET, "/api/v1/weather", weather_handler)

# Add rent calculator endpoints
Agoo::Server.handle(:GET, "/api/rent", rent_calculator_handler)
Agoo::Server.handle(:GET, "/api/rent/forecast", rent_calculator_handler)
Agoo::Server.handle(:GET, "/api/rent/history", rent_calculator_handler)
Agoo::Server.handle(:GET, "/api/rent/roommates", rent_calculator_handler)
Agoo::Server.handle(:POST, "/api/rent", rent_calculator_handler)
Agoo::Server.handle(:POST, "/api/rent/roommates", rent_calculator_handler)
Agoo::Server.handle(:PUT, "/api/rent/config", rent_calculator_handler)

Agoo::Server.handle(:GET, "/data/*", proxy_handler)

Agoo::Server.start()

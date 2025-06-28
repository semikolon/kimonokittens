require 'dotenv/load'
require 'agoo'
require 'faraday'
require 'oj'
require 'awesome_print'
require 'pry'
require 'pry-nav'

# Configure Agoo logging
Agoo::Log.configure(dir: '',
  console: true,
  classic: true,
  colorize: true,
  states: {
    INFO: true,
    DEBUG: false,
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
    ssl_key: "***REMOVED***",
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
require_relative 'handlers/handbook_handler'
require_relative 'handlers/auth_handler'

home_page_handler = HomePageHandler.new
electricity_stats_handler = ElectricityStatsHandler.new
proxy_handler = ProxyHandler.new
static_handler = StaticHandler.new
train_departure_handler = TrainDepartureHandler.new
strava_workouts_handler = StravaWorkoutsHandler.new
bank_buster_handler = BankBusterHandler.new
rent_and_finances_handler = RentAndFinancesHandler.new
handbook_handler = HandbookHandler.new
auth_handler = AuthHandler.new

Agoo::Server.handle(:GET, "/", home_page_handler)

# Add WebSocket handler for BankBuster
Agoo::Server.handle(:GET, "/ws", bank_buster_handler)

# Add Handbook API handlers
Agoo::Server.handle(:GET, "/api/handbook/*", handbook_handler)
Agoo::Server.handle(:POST, "/api/handbook/*", handbook_handler)

# Add Authentication API handlers
Agoo::Server.handle(:POST, "/api/auth/*", auth_handler)
Agoo::Server.handle(:OPTIONS, "/api/auth/*", auth_handler)

Agoo::Server.handle(:GET, "/*", static_handler)

Agoo::Server.handle(:GET, "/data/rent_and_finances", rent_and_finances_handler)
Agoo::Server.handle(:GET, "/data/electricity", electricity_stats_handler)
Agoo::Server.handle(:GET, "/data/train_departures", train_departure_handler)
Agoo::Server.handle(:GET, "/data/strava_stats", strava_workouts_handler)

Agoo::Server.handle(:GET, "/data/*", proxy_handler)


Agoo::Server.start()

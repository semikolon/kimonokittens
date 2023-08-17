require 'dotenv/load'
require 'agoo'
require 'faraday'
require 'oj'
require 'awesome_print'
require 'pry'
require 'pry-nav'

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
                      push: false,
                    })

Agoo::Server.init(6464, 'root', thread_count: 0)

require_relative 'handlers/electricity_stats_handler'
require_relative 'handlers/proxy_handler'
require_relative 'handlers/home_page_handler'
require_relative 'handlers/static_handler'
require_relative 'handlers/train_departure_handler'
require_relative 'handlers/strava_workouts_handler'
require_relative 'handlers/bank_buster_handler'

home_page_handler = HomePageHandler.new
electricity_stats_handler = ElectricityStatsHandler.new
proxy_handler = ProxyHandler.new
static_handler = StaticHandler.new
train_departure_handler = TrainDepartureHandler.new
strava_workouts_handler = StravaWorkoutsHandler.new
bank_buster_handler = BankBusterHandler.new

Agoo::Server.handle(:GET, "/", home_page_handler)
Agoo::Server.handle(:GET, "/*", static_handler)
Agoo::Server.handle(:GET, "/data/electricity", electricity_stats_handler)
Agoo::Server.handle(:GET, "/data/train_departures", train_departure_handler)
Agoo::Server.handle(:GET, "/data/strava_stats", strava_workouts_handler)
Agoo::Server.handle(:GET, "/data/*", proxy_handler)

# Add WebSocket handler for BankBuster
Agoo::Server.handle(:GET, "/ws", bank_buster_handler)

Agoo::Server.start()

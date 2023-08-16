require 'dotenv/load'
require 'agoo'
require 'faraday'
require 'oj'
require 'awesome_print'
require 'pry'
require 'pry-nav'

# Setting the thread count to 0 causes the server to use the current
# thread. Greater than zero runs the server in a separate thread and the
# current thread can be used for other tasks as long as it does not exit.
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

home_page_handler = HomePageHandler.new
electricity_stats_handler = ElectricityStatsHandler.new
proxy_handler = ProxyHandler.new
static_handler = StaticHandler.new
train_departure_handler = TrainDepartureHandler.new
strava_workouts_handler = StravaWorkoutsHandler.new

Agoo::Server.handle(:GET, "/", home_page_handler)
Agoo::Server.handle(:GET, "/*", static_handler)
Agoo::Server.handle(:GET, "/data/electricity", electricity_stats_handler)
Agoo::Server.handle(:GET, "/data/train_departures", train_departure_handler)
Agoo::Server.handle(:GET, "/data/strava_stats", strava_workouts_handler)
Agoo::Server.handle(:GET, "/data/*", proxy_handler)
Agoo::Server.start()
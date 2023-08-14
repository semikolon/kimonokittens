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

# I maj 2023 använde vi 900 kWh och betalade 616 kr till elhandelsbolaget.
# Samt till elnätsbolaget 1299 kr - varav 467 kr är en statisk månadsavgift.

# Den variabla delen av elnätskostnaden får vi genom att subtrahera den fasta
# abonnemangsavgiften från den totala elnätskostnaden:
# 1299 kr - 467 kr = 832 kr
# Detta är alltså kostnaden för elnätet baserat på förbrukningen.

# Nu kan vi räkna ut den totala kostnaden för elen, vilket är summan av kostnaden
# för elhandeln och den variabla delen av elnätskostnaden:
# 616 kr (elhandel) + 832 kr (variabel elnätskostnad) = 1448 kr

# Slutligen, för att räkna ut elpriset per kWh, delar vi den totala kostnaden med antalet kWh:
# 1448 kr / 900 kWh = 1.61 kr/kWh

KWH_PRICE = 1.61
# KWH_TRANSFER_PRICE = (0.244 + 0.392) * 1.25 # Elöverföring + energiskatt + moms (Vattenfall)
KWH_TRANSFER_PRICE = (0.09 + 0.392) * 1.25 # Elöverföring + energiskatt + moms (Vattenfall)
# https://www.vattenfalleldistribution.se/kund-i-elnatet/elnatspriser/elnatspriser-och-avtalsvillkor/
# https://www.vattenfalleldistribution.se/kund-i-elnatet/elnatspriser/energiskatt/
MONTHLY_FEE = 467 + 39 # Månadsavgift för elnät + elhandel

WDAY = {
  'Mon': 'Mån',
  'Tue': 'Tis',
  'Wed': 'Ons',
  'Thu': 'Tor',
  'Fri': 'Fre',
  'Sat': 'Lör',
  'Sun': 'Sön'
}

class ElectricityStatsHandler
  def call(req)
    electricity_stats = Oj.load_file('electricity_usage.json')
    tibber_prices = Oj.load_file('tibber_price_data.json')
    
    avg_price_per_kwh = tibber_prices.values.sum / tibber_prices.count

    all_hours = electricity_stats.map do |hour|
      consumption = hour['consumption']

      date = DateTime.parse(hour['date'])
      short_date = date.strftime("%b %-d")
      weekday = WDAY[date.strftime("%a").to_sym]

      price_per_kwh = tibber_prices[hour['date']]
      price_per_kwh ||= avg_price_per_kwh
      price_per_kwh = price_per_kwh + KWH_TRANSFER_PRICE
      price = consumption * price_per_kwh

      {
        date: short_date,
        short_date: short_date,
        weekday: weekday,
        full_date: "#{weekday} #{short_date} #{date.strftime("%H.%M")}",
        hour_of_day: date.strftime("%H").to_i,
        price_per_kwh: price_per_kwh,
        consumption: consumption,
        price: price
      }
    end
    
    #ap all_hours

    price_so_far = all_hours.sum { |hour| hour[:price] }
    average_hour = price_so_far / all_hours.count
    projected_total = ((average_hour * 31 * 24).to_f)
    
    peak_hours = all_hours.sort_by { |hour| hour[:price] }.last(24).reverse!
    # Select the peak hours where the price_per_kwh was above the average price_per_kwh
    avg_price_per_kwh = peak_hours.sum { |hour| hour[:price_per_kwh] } / peak_hours.count
    peak_pricey_hours = peak_hours.select { |hour| hour[:price_per_kwh] > avg_price_per_kwh }

    last_days = all_hours.last(24 * 7).group_by { |hour| hour[:date] }
    
    # last_days.each do |date, date_hours|
    #   if date_hours.count.between?(18, 24)
    #     # Make an educated guess as to what the price will be for the remaining hours
    #     # by taking the average price of the same hours for the last month
    #     last_month_same_hours = all_hours.select { |hour| hour[:hour_of_day] == date_hours.first[:hour_of_day] }
    #     avg_price_per_kwh = last_month_same_hours.sum { |hour| hour[:price_per_kwh] } / last_month_same_hours.count
    #     remaining_hours = 24 - date_hours.count
    #     remaining_price = avg_price_per_kwh * remaining_hours
    #     date_hours << {
    #       date: date,
    #       short_date: date,
    #       weekday: date_hours.first[:weekday],
    #       full_date: "#{date_hours.first[:weekday]} #{date}",
    #       hour_of_day: date_hours.first[:hour_of_day],
    #       price_per_kwh: avg_price_per_kwh,
    #       consumption: 0,
    #       price: remaining_price
    #     }
    #   end
    # end
    last_days.reject! { |date, date_hours| date_hours.count < 24 } # Remove days that are not complete
    
    last_days_summed = last_days.map do |date, date_hours|
      price_sum = date_hours.sum { |hour| hour[:price] }.ceil
      consumption_sum = date_hours.sum { |hour| hour[:consumption] }
      first_hour = date_hours.first
      {
        date: date,
        weekday: first_hour[:weekday],
        full_date: "#{first_hour[:weekday]} #{first_hour[:short_date]}",
        price: price_sum,
        title: "= #{price_sum} kr (#{first_hour[:weekday]})",
        long_title: "#{consumption_sum} kWh = #{price_sum} kr (#{first_hour[:weekday]})",
        consumption: consumption_sum
      }
    end.reverse

    # Exclude the current day (the first one) from last_days_summary
    last_days_summary = last_days_summed[1..-1].map do |date|
      "#{date[:weekday]}: #{date[:price]} kr\n"
    end.join
    
    last_days_summed.prepend({
      price_so_far: price_so_far.ceil + MONTHLY_FEE,
      projected_total: projected_total.ceil + MONTHLY_FEE,
      average_hour: average_hour.round(3),
      peak_pricey_hours: peak_pricey_hours,
      last_days_summary: last_days_summary
    })
    
    stats = {
      electricity_stats: last_days_summed
    }
    [200, { 'Content-Type' => 'application/json' }, [ Oj.dump(stats) ]]
  end
end

class ProxyHandler
  def call(req)
    response = Faraday.get("http://192.168.0.210:1880/data/#{req['PATH_INFO'].split('/data/').last}")
    [response.status, response.headers, [response.body]]
  end
end

class HomePageHandler
  def initialize
    @content = File.read('www/index.html')
  end

  def call(req)
    [200, { 'Content-Type' => 'text/html' }, [ @content ]]
  end
end

class StaticHandler
  WWW_DIR = File.expand_path("../www", __FILE__)

  def call(req)
    path = File.join(WWW_DIR, req['PATH_INFO'])
    if File.exist?(path) && !File.directory?(path)
      Agoo::Log.info("Serving file: #{path}")
      serve_file(path)
    else
      Agoo::Log.warn("File not found: #{path}")
      [404, { 'Content-Type' => 'text/plain' }, [ "File not found." ]]
    end
  end

  private

  def serve_file(path)
    ext = File.extname(path)
    content_type = case ext
                   when '.html'
                     'text/html'
                   when '.css'
                     'text/css'
                   when '.js'
                     'application/javascript'
                   when '.png'
                     'image/png'
                   when '.jpg', '.jpeg'
                     'image/jpeg'
                   when '.gif'
                     'image/gif'
                   else
                     'application/octet-stream'
                   end
    [200, { 'Content-Type' => content_type }, [ File.read(path) ]]
  end
end

def to_sentence(array)
  if array.size > 1
    last = array.pop
    "#{array.join(', ')} och #{last}"
  else
    array.first
  end
end

class TrainDepartureHandler
  SL_API_KEY = ENV['SL_API_KEY']
  SITE_ID = 9527 # From https://api.sl.se/api2/typeahead.json?key=#{SL_API_KEY}&searchstring=Huddinge%20station&stationsonly=true&maxresults=2
  TIME_WINDOW = 60 # time in minutes to fetch departures for, max 60
  WALK_TIME = 8 # time in minutes to walk to the station
  RUN_TIME = 5 # time in minutes to cycle or run to the station
  MARGIN_TIME = 5 # time in minutes for alarm margin to get ready
  CACHE_THRESHOLD = 60 * 5 # time in seconds to keep data in cache

  def initialize
    @data = nil
    @fetched_at = nil
  end

  def call(req)
    # For testing:
    #@data = Oj.load_file('train_examples.json')
    #@data = Oj.load_file('train_examples_deviations.json')
    #@fetched_at = Time.now

    if @data.nil? || Time.now - @fetched_at > CACHE_THRESHOLD
      response = Faraday.get("https://api.sl.se/api2/realtimedeparturesV4.json?key=#{SL_API_KEY}&siteid=#{SITE_ID}&timewindow=#{TIME_WINDOW}")

      if response.success?
        @data = Oj.load(response.body)
        @fetched_at = Time.now
      else
        return [500, { 'Content-Type' => 'application/json' }, [ Oj.dump({ 'error': 'Failed to fetch train departures' }) ]]
      end
    end

    ap @data
    # Example:
    # [7] {
    #   "SecondaryDestinationName" => nil,
    #                "GroupOfLine" => "Pendeltåg",
    #              "TransportMode" => "TRAIN",
    #                 "LineNumber" => "41",
    #                "Destination" => "Södertälje centrum",
    #           "JourneyDirection" => 1,
    #               "StopAreaName" => "Huddinge",
    #             "StopAreaNumber" => 5161,
    #            "StopPointNumber" => 5161,
    #       "StopPointDesignation" => "3",
    #         "TimeTabledDateTime" => "2023-07-02T15:55:00",
    #           "ExpectedDateTime" => "2023-07-02T15:55:00",
    #                "DisplayTime" => "15:55",
    #              "JourneyNumber" => 2947,
    #                 "Deviations" => [
    #       [0] {
    #                      "Text" => "Inställd på grund av personalbrist.",
    #               "Consequence" => "INFORMATION",
    #           "ImportanceLevel" => 7
    #       }

    
    # Filter for northbound trains that aren't cancelled
    northbound_trains = @data['ResponseData']['Trains'].select do |train| 
      train['JourneyDirection'] == 2
      # && (train['Deviations'].nil? || train['Deviations'].none? { |deviation| deviation['Text'].include?('Inställd') })
    end

    #now = DateTime.parse('2023-07-01T10:21:00+02:00')
    now = DateTime.now.new_offset('+02:00')
    departures = northbound_trains.map do |train|
      expected_time = train['ExpectedDateTime'] || train['TimeTabledDateTime']
      departure_time = DateTime.parse(expected_time + '+02:00')
      minutes_until_departure = ((departure_time - now) * 24 * 60).to_i
      #display_time = "#{minutes_until_departure / 60}h #{minutes_until_departure % 60}m"
      display_time = departure_time.strftime('%H:%M')
      time_of_departure = minutes_until_departure > 59 ? display_time : "#{display_time} - om #{minutes_until_departure}m"

      deviation_note = ''
      summary_deviation_note = ''
      if train['Deviations']
        deviation_note = train['Deviations'].map { |deviation| deviation['Text'].strip }.join(', ')
        summary_deviation_note = ' (försenad)' if deviation_note.include?('Försenad')
        summary_deviation_note = ' (inställd)' if deviation_note.include?('Inställd')
      end

      {
        'destination': train['Destination'],
        'line_number': train['LineNumber'],
        'departure_time': departure_time,
        'minutes_until_departure': minutes_until_departure,
        'time_of_departure': time_of_departure,
        'deviation_note': deviation_note,
        'summary_deviation_note': summary_deviation_note,
        'suffix': ''
      }
    end
    
    # Construct deviation summary string
    deviation_summary = departures.map do |d|
      unless d[:deviation_note].empty?
        "#{d[:departure_time].strftime('%H:%M')} till #{d[:destination]}: #{d[:deviation_note].downcase}"
      end
    end.compact.join(" ")

    # Filter for northbound trains that aren't cancelled and aren't past rushing to the station
    departures = departures.select do |d|
      d[:summary_deviation_note] != ' (inställd)' &&
      d[:minutes_until_departure] > RUN_TIME
    end

    if departures.any?
      first_train_you_can_catch = departures.first
      late = first_train_you_can_catch[:minutes_until_departure] < WALK_TIME
      first_train_you_can_catch[:suffix] = if late
        " - spring eller cykla!"
      elsif first_train_you_can_catch[:minutes_until_departure] > (WALK_TIME + MARGIN_TIME + 5) # E.g. 8 + 5 + 5 = 18 mins
        alarm_time = first_train_you_can_catch[:departure_time] - (WALK_TIME + MARGIN_TIME) / (24 * 60.0)
        " - var redo #{alarm_time.strftime("%H:%M")}"
      else
        " - du hinner gå"
      end
    end
    
    departures.each { |d| d[:departure_time] = d[:departure_time].strftime('%H:%M') }

    # Construct summary string
    departure_times = departures.map { |d| "<strong>#{d[:time_of_departure]}</strong>#{d[:summary_deviation_note]}#{d[:suffix]}" }

    summary = "#{departure_times.join("<br/>")}"
    summary = "Inga pendeltåg inom en timme" if departure_times.empty? || departure_times.all? { |t| t.include?('inställt') }

    response = {
      'summary': summary,
      'deviation_summary': deviation_summary
    }

    [200, { 'Content-Type' => 'application/json' }, [ Oj.dump(response) ]]
  end
end

require 'faraday'
require 'oj'

class StravaWorkoutsHandler
  STRAVA_API_URL = 'https://www.strava.com/api/v3'
  CLIENT_ID = ENV['STRAVA_CLIENT_ID']
  CLIENT_SECRET = ENV['STRAVA_CLIENT_SECRET']
  
  def initialize
    @access_token = ENV['STRAVA_ACCESS_TOKEN']
    @refresh_token = ENV['STRAVA_REFRESH_TOKEN']
    if File.exist?('.refresh_token')
      @refresh_token = File.read('.refresh_token').strip
    end  
  end

  def call(req)
    response = Faraday.get("#{STRAVA_API_URL}/athletes/6878181/stats", {}, { 'Authorization' => "Bearer #{@access_token}" })

    if response.status == 401 # Unauthorized, possibly due to expired token
      refresh_access_token
      response = Faraday.get("#{STRAVA_API_URL}/athletes/6878181/stats", {}, { 'Authorization' => "Bearer #{@access_token}" })
    end

    if response.success?
      stats = Oj.load(response.body)
      stats = transform_stats(stats)
    else
      return [500, { 'Content-Type' => 'application/json' }, [ Oj.dump({ 'error': 'Failed to fetch stats from Strava' }) ]]
    end

    [200, { 'Content-Type' => 'application/json' }, [ Oj.dump(stats) ]]
  end

  def transform_stats(stats)
    # Example JSON:
    # {
    #   "biggest_ride_distance": null,
    #   "biggest_climb_elevation_gain": null,
    #   "recent_ride_totals": {
    #   "count": 0,
    #   "distance": 0,
    #   "moving_time": 0,
    #   "elapsed_time": 0,
    #   "elevation_gain": 0,
    #   "achievement_count": 0
    #   },
    #   "all_ride_totals": {
    #   "count": 0,
    #   "distance": 0,
    #   "moving_time": 0,
    #   "elapsed_time": 0,
    #   "elevation_gain": 0
    #   },
    #   "recent_run_totals": {
    #   "count": 3,
    #   "distance": 11313.1997070312,
    #   "moving_time": 4217,
    #   "elapsed_time": 4365,
    #   "elevation_gain": 205.50465393066406,
    #   "achievement_count": 8
    #   },
    #   "all_run_totals": {
    #   "count": 22,
    #   "distance": 81314,
    #   "moving_time": 30749,
    #   "elapsed_time": 41898,
    #   "elevation_gain": 1120
    #   },
    #   "recent_swim_totals": {
    #   "count": 0,
    #   "distance": 0,
    #   "moving_time": 0,
    #   "elapsed_time": 0,
    #   "elevation_gain": 0,
    #   "achievement_count": 0
    #   },
    #   "all_swim_totals": {
    #   "count": 0,
    #   "distance": 0,
    #   "moving_time": 0,
    #   "elapsed_time": 0,
    #   "elevation_gain": 0
    #   },
    #   "ytd_ride_totals": {
    #   "count": 0,
    #   "distance": 0,
    #   "moving_time": 0,
    #   "elapsed_time": 0,
    #   "elevation_gain": 0
    #   },
    #   "ytd_run_totals": {
    #   "count": 12,
    #   "distance": 42319,
    #   "moving_time": 16236,
    #   "elapsed_time": 20971,
    #   "elevation_gain": 706
    #   },
    #   "ytd_swim_totals": {
    #   "count": 0,
    #   "distance": 0,
    #   "moving_time": 0,
    #   "elapsed_time": 0,
    #   "elevation_gain": 0
    #   }
    #   }
    
    # Transform to:
    # "11.3 km sedan 3 jun - 3.77 km per tur"
    # "42.3 km sedan 1 jan - 3.53 km per tur"
    
    recent_run_totals = stats['recent_run_totals']
    ytd_run_totals = stats['ytd_run_totals']

    recent_distance = (recent_run_totals['distance'].to_f / 1000).round(1)
    recent_count = recent_run_totals['count'].to_f
    recent_distance_per_run = (recent_distance / recent_count).round(2)

    ytd_distance = (ytd_run_totals['distance'].to_f / 1000).round(1)
    ytd_count = ytd_run_totals['count'].to_f
    ytd_distance_per_run = (ytd_distance / ytd_count).round(2)

    recent_pace = (recent_run_totals['moving_time'].to_f / recent_run_totals['distance'].to_f * 1000).round(0)
    ytd_pace = (ytd_run_totals['moving_time'].to_f / ytd_run_totals['distance'].to_f * 1000).round(0)

    recent_pace = "#{(recent_pace / 60).floor}:#{(recent_pace % 60).to_s.rjust(2, '0')}"
    ytd_pace = "#{(ytd_pace / 60).floor}:#{(ytd_pace % 60).to_s.rjust(2, '0')}"

    since_date = (Time.now - 4 * 7 * 24 * 60 * 60).strftime("%-d %b").downcase
    {
      runs: "<strong>#{recent_distance} km</strong> sedan #{since_date} - #{recent_distance_per_run} km per tur - #{recent_pace} min/km<br/>
        <strong>#{ytd_distance} km</strong> sedan 1 jan - #{ytd_distance_per_run} km per tur - #{ytd_pace} min/km"
    }

  end

  private

  def refresh_access_token
    response = Faraday.post('https://www.strava.com/oauth/token') do |req|
      req.params['client_id'] = CLIENT_ID
      req.params['client_secret'] = CLIENT_SECRET
      req.params['refresh_token'] = @refresh_token
      req.params['grant_type'] = 'refresh_token'
    end

    if response.success?
      data = Oj.load(response.body)
      @access_token = data['access_token']
      File.write('.refresh_token', data['refresh_token'])
    else
      raise "Failed to refresh Strava access token"
    end
  end
end

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
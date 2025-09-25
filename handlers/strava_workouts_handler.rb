require 'net/http'
require 'uri'
require 'oj'
# require 'pry'  # Temporarily disabled due to gem conflict
# require 'pry-nav'  # Temporarily disabled due to gem conflict

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
    puts "DEBUG: Strava handler called with access_token: #{@access_token[0..10]}..."
    puts "DEBUG: Making request to /athletes/6878181/stats"

    response = make_api_request("/athletes/6878181/stats")

    puts "DEBUG: First API response status: #{response.code}"
    puts "DEBUG: First API response body: #{response.body[0..200]}..."

    if response.code.to_i == 401 # Unauthorized, possibly due to expired token
      puts "DEBUG: Token expired, refreshing..."
      refresh_access_token
      puts "DEBUG: Token refreshed, new token: #{@access_token[0..10]}..."
      response = make_api_request("/athletes/6878181/stats")
      puts "DEBUG: Second API response status: #{response.code}"
      puts "DEBUG: Second API response body: #{response.body[0..200]}..."
    end

    if response.code.to_i == 200
      puts "DEBUG: API call successful, parsing response"
      data = Oj.load(response.body)
      puts "DEBUG: Parsed data keys: #{data.keys.join(', ')}"
      stats = transform_stats(data)
      puts "DEBUG: Transformed stats: #{stats}"
    else
      puts "ERROR: API call failed with status #{response.code}: #{response.body}"
      return [500, { 'Content-Type' => 'application/json' }, [ Oj.dump({ 'error' => "Failed to fetch stats from Strava (#{response.code}): #{response.body}" }, mode: :compat) ]]
    end

    [200, { 'Content-Type' => 'application/json' }, [ Oj.dump(stats, mode: :compat) ]]
  rescue => e
    puts "ERROR: Strava API call failed: #{e.message}"
    [504, { 'Content-Type' => 'application/json' }, [ Oj.dump({ 'error' => "Strava API error: #{e.message}" }, mode: :compat) ]]
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
    recent_distance_per_run = recent_count != 0 ? (recent_distance / recent_count).round(2) : 0

    ytd_distance = (ytd_run_totals['distance'].to_f / 1000).round(1)
    ytd_count = ytd_run_totals['count'].to_f
    ytd_distance_per_run = (ytd_distance / ytd_count).round(2)
    
    recent_moving_time = recent_run_totals['moving_time'].to_f
    
    recent_pace = recent_distance != 0 ? (recent_moving_time / recent_distance).round(0) : 0
    ytd_pace = (ytd_run_totals['moving_time'].to_f / ytd_run_totals['distance'].to_f * 1000).round(0)

    recent_pace = "#{(recent_pace / 60).floor}:#{(recent_pace % 60).to_s.rjust(2, '0')}"
    ytd_pace = "#{(ytd_pace / 60).floor}:#{(ytd_pace % 60).to_s.rjust(2, '0')}"

    since_date_obj = Time.now - 4 * 7 * 24 * 60 * 60
    since_date = since_date_obj.strftime("%-d %b").downcase
    year_start = Time.new(Time.now.year, 1, 1)

    {
      runs: "<strong>#{recent_distance} km</strong> sedan #{since_date} - #{recent_distance_per_run} km per tur - #{recent_pace} min/km<br/><strong>#{ytd_distance} km</strong> sedan 1 jan - #{ytd_distance_per_run} km per tur - #{ytd_pace} min/km",
      recent_period: {
        start_date: since_date_obj.utc.iso8601,
        start_timestamp: since_date_obj.to_i,
        distance_km: recent_distance,
        count: recent_count.to_i,
        pace: recent_pace
      },
      ytd_period: {
        start_date: year_start.utc.iso8601,
        start_timestamp: year_start.to_i,
        distance_km: ytd_distance,
        count: ytd_count.to_i,
        pace: ytd_pace
      },
      generated_at: Time.now.utc.iso8601,
      generated_timestamp: Time.now.to_i
    }

  end

  private

  def make_api_request(path)
    uri = URI("#{STRAVA_API_URL}#{path}")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.open_timeout = 2
    http.read_timeout = 3

    request = Net::HTTP::Get.new(uri)
    request['Authorization'] = "Bearer #{@access_token}"
    request['User-Agent'] = 'KimonoKittens/1.0'

    http.request(request)
  end

  def refresh_access_token
    uri = URI('https://www.strava.com/oauth/token')
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.open_timeout = 2
    http.read_timeout = 5

    request = Net::HTTP::Post.new(uri)
    request.set_form_data(
      'client_id' => CLIENT_ID,
      'client_secret' => CLIENT_SECRET,
      'refresh_token' => @refresh_token,
      'grant_type' => 'refresh_token'
    )

    response = http.request(request)

    if response.code.to_i == 200
      data = Oj.load(response.body)
      @access_token = data['access_token']
      File.write('.refresh_token', data['refresh_token'])
    else
      raise "Failed to refresh Strava access token"
    end
  end
end

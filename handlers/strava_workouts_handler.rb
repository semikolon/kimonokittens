require 'faraday'
require 'oj'
require 'pry'
require 'pry-nav'

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
    recent_distance_per_run = recent_count != 0 ? (recent_distance / recent_count).round(2) : 0

    ytd_distance = (ytd_run_totals['distance'].to_f / 1000).round(1)
    ytd_count = ytd_run_totals['count'].to_f
    ytd_distance_per_run = (ytd_distance / ytd_count).round(2)
    
    recent_moving_time = recent_run_totals['moving_time'].to_f
    
    recent_pace = recent_distance != 0 ? (recent_moving_time / recent_distance).round(0) : 0
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

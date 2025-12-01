# Sun Window Handler - Returns brightness predictions from Open-Meteo API
#
# Uses Open-Meteo (FREE, no API key) for sun/brightness predictions.
# Replaced Meteoblue due to credit exhaustion ($31/year unsustainable).
#
# Endpoint: GET /data/sun_windows
#
# Response includes:
#   - current_brightness_percent: How much sunlight is getting through clouds (0-100%)
#   - is_daylight: Whether it's daytime
#   - next_sun_window_start: ISO8601 timestamp of next perceivable sun
#   - next_sun_window_duration_minutes: How long the sun window lasts
#   - todays_brightness_curve: Hourly brightness data for today
#
# Brightness calculation:
#   brightness_percent = (GHI / clearsky_GHI) * 100
#   This captures diffuse light on overcast days (like Meteoblue did).
#
# Swedish Winter Context:
#   At 59°N, max clear-sky GHI is only ~100 W/m² in winter (not 200+ like summer).
#   brightness_percent thresholds:
#     80-100%: Direct sun perceivable
#     50-79%:  Partly sunny, occasional glimpses
#     <50%:    Overcast, no direct sun
#
require 'oj'
require_relative '../lib/open_meteo_sun_predictor'

class SunHandler
  CACHE_THRESHOLD = 60 * 60  # 1 hour cache (Open-Meteo is free, no rush)
  CACHE_FILE = '/tmp/kimonokittens_sun_cache.json'

  # Backoff configuration for API errors (lighter since Open-Meteo is free)
  INITIAL_BACKOFF = 60 * 5       # 5 minutes initial backoff
  MAX_BACKOFF = 60 * 60          # 1 hour maximum backoff
  BACKOFF_MULTIPLIER = 2         # Double backoff each time

  def initialize
    @data = nil
    @fetched_at = nil
    @error_count = 0
    @backoff_until = nil          # Time when we can retry after errors
    @current_backoff = INITIAL_BACKOFF

    # Try to load cached data from file on startup
    load_file_cache
  end

  def call(req)
    # Check if we're in backoff period (API errors)
    if in_backoff_period?
      remaining = (@backoff_until - Time.now).to_i
      puts "SunHandler: In backoff period, #{remaining}s remaining. Returning cached data."
      return serve_cached_or_placeholder("API error - retry in #{remaining / 60} minutes")
    end

    # Check cache freshness
    if @data.nil? || @fetched_at.nil? || Time.now - @fetched_at > CACHE_THRESHOLD
      begin
        predictions = OpenMeteoSunPredictor.predict_sun_windows
        @data = transform_sun_data(predictions)
        @fetched_at = Time.now
        @error_count = 0

        # Reset backoff on successful request
        @current_backoff = INITIAL_BACKOFF
        @backoff_until = nil

        # Save to file cache for persistence across restarts
        save_file_cache

        puts "SunHandler: Fresh data fetched from Open-Meteo"
      rescue => e
        @error_count += 1
        start_backoff
        puts "SunHandler error (#{@error_count}): #{e.message}. Backoff for #{@current_backoff / 60} minutes."

        # Return cached data if available
        return serve_cached_or_placeholder(e.message)
      end
    end

    [200, { 'Content-Type' => 'application/json' }, [Oj.dump(@data, mode: :compat)]]
  end

  private

  def transform_sun_data(predictions)
    now = Time.now

    # Use first location (Solgård) as primary for dashboard
    primary = predictions.first || {}

    {
      'locations' => predictions.map do |p|
        {
          'name' => p[:location],
          'lat' => p[:lat],
          'lng' => p[:lng],
          'current_brightness_percent' => p[:current_brightness_percent],
          'current_ghi' => p[:current_ghi],
          'current_clearsky_ghi' => p[:current_clearsky_ghi],
          'is_daylight' => p[:is_daylight],
          'next_sun_window' => p[:next_sun_window_start] ? {
            'start' => p[:next_sun_window_start],
            'duration_minutes' => p[:next_sun_window_duration_minutes],
            'peak_brightness' => p[:next_sun_window_peak_brightness]
          } : nil,
          'todays_brightness_curve' => p[:todays_brightness_curve],
          'daily_sun_hours' => p[:daily_sun_hours]
        }
      end,
      # Primary location data for simple dashboard access
      'current_brightness_percent' => primary[:current_brightness_percent] || 0,
      'is_daylight' => primary[:is_daylight] || false,
      'next_sun_window' => primary[:next_sun_window_start] ? {
        'start' => primary[:next_sun_window_start],
        'duration_minutes' => primary[:next_sun_window_duration_minutes],
        'peak_brightness' => primary[:next_sun_window_peak_brightness]
      } : nil,
      'sun_status' => calculate_sun_status(primary),
      # Daily sun hours for weather forecast integration (next 7 days)
      'daily_sun_hours' => primary[:daily_sun_hours] || [],
      'generated_at' => now.utc.iso8601,
      'generated_timestamp' => now.to_i
    }
  end

  # Human-readable sun status for UI
  def calculate_sun_status(data)
    return 'night' unless data[:is_daylight]

    brightness = data[:current_brightness_percent] || 0

    if brightness >= 90
      'clear'       # Direct sun visible
    elsif brightness >= 80
      'bright'      # Sun perceivable through thin clouds
    elsif brightness >= 60
      'partly'      # Occasional glimpses
    else
      'overcast'    # No direct sun
    end
  end

  def placeholder_response(message)
    data = {
      'locations' => [],
      'current_brightness_percent' => 0,
      'is_daylight' => false,
      'next_sun_window' => nil,
      'sun_status' => 'unknown',
      'error' => message,
      'generated_at' => Time.now.utc.iso8601,
      'generated_timestamp' => Time.now.to_i
    }
    [200, { 'Content-Type' => 'application/json' }, [Oj.dump(data, mode: :compat)]]
  end

  def error_response(message)
    [500, { 'Content-Type' => 'application/json' }, [Oj.dump({ 'error' => message }, mode: :compat)]]
  end

  # Check if we're currently in a backoff period
  def in_backoff_period?
    @backoff_until && Time.now < @backoff_until
  end

  # Start or extend backoff period (exponential)
  def start_backoff
    @backoff_until = Time.now + @current_backoff
    @current_backoff = [@current_backoff * BACKOFF_MULTIPLIER, MAX_BACKOFF].min
  end

  # Return cached data if available, otherwise placeholder
  def serve_cached_or_placeholder(error_message)
    if @data
      # Add staleness indicator to cached data
      stale_data = @data.dup
      stale_data['stale'] = true
      stale_data['stale_reason'] = error_message
      stale_data['cached_at'] = @fetched_at&.iso8601
      [200, { 'Content-Type' => 'application/json' }, [Oj.dump(stale_data, mode: :compat)]]
    else
      placeholder_response(error_message)
    end
  end

  # Load cached data from file (survives service restarts)
  def load_file_cache
    return unless File.exist?(CACHE_FILE)

    begin
      cached = Oj.load(File.read(CACHE_FILE), mode: :compat)
      if cached && cached['generated_timestamp']
        cache_age = Time.now.to_i - cached['generated_timestamp']
        # Accept file cache if less than 6 hours old
        if cache_age < 6 * 3600
          @data = cached
          @fetched_at = Time.at(cached['generated_timestamp'])
          puts "SunHandler: Loaded file cache (#{cache_age / 60} minutes old)"
        else
          puts "SunHandler: File cache too old (#{cache_age / 3600} hours), ignoring"
        end
      end
    rescue => e
      puts "SunHandler: Failed to load file cache: #{e.message}"
    end
  end

  # Save current data to file cache
  def save_file_cache
    return unless @data

    begin
      File.write(CACHE_FILE, Oj.dump(@data, mode: :compat))
      puts "SunHandler: Saved to file cache"
    rescue => e
      puts "SunHandler: Failed to save file cache: #{e.message}"
    end
  end
end

# Sun Window Handler - Returns brightness predictions from Meteoblue API
#
# Uses CMV (Cloud Motion Vector) nowcasting for accurate 1-2 hour predictions.
# Returns current brightness % and next sun window for both Huddinge locations.
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
# Swedish Winter Context:
#   At 59°N, max clear-sky GHI is only ~100 W/m² in winter (not 200+ like summer).
#   So we use brightness % (GHI/ClearSky × 100) instead of absolute W/m²:
#     90-100%: Clear sky, direct sun visible
#     80-89%:  Thin clouds, sun perceivable
#     60-79%:  Partly cloudy, occasional glimpses
#     <60%:    Overcast, no direct sun
#
require 'oj'
require_relative '../lib/meteoblue_sun_predictor'

class SunHandler
  CACHE_THRESHOLD = 60 * 15 # 15 minutes cache (API updates every 15 min)

  def initialize
    @data = nil
    @fetched_at = nil
    @error_count = 0
  end

  def call(req)
    # Check if we have API key
    unless ENV['METEOBLUE_API_KEY']
      return placeholder_response("METEOBLUE_API_KEY not configured")
    end

    # Check cache
    if @data.nil? || Time.now - @fetched_at > CACHE_THRESHOLD
      begin
        predictions = MeteoblueSunPredictor.predict_sun_windows
        @data = transform_sun_data(predictions)
        @fetched_at = Time.now
        @error_count = 0
      rescue => e
        @error_count += 1
        puts "SunHandler error (#{@error_count}): #{e.message}"

        # Return cached data if available, otherwise error response
        if @data
          puts "SunHandler: Returning stale cached data"
        else
          return error_response(e.message)
        end
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
          'todays_brightness_curve' => p[:todays_brightness_curve]
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
end

# Open-Meteo Sun Predictor - FREE replacement for Meteoblue
#
# Uses Open-Meteo API (completely free, no API key required) to predict
# sun windows and brightness. Returns data compatible with the existing
# SunHandler/frontend interface.
#
# Key differences from Meteoblue:
#   - Uses sunshine_duration (seconds of direct sun per hour) as brightness proxy
#   - brightness_percent = (sunshine_duration / 3600) * 100
#   - This correlates well with "is sun visible" which is what we care about
#   - GHI (shortwave_radiation) still available for actual irradiance values
#
# @example
#   prediction = OpenMeteoSunPredictor.predict_sun_window
#   # => { location: "Solgård", current_brightness_percent: 85, ... }
#
require 'httparty'
require 'json'
require 'time'

module OpenMeteoSunPredictor
  BASE_URL = 'https://api.open-meteo.com/v1/forecast'

  # Thresholds matching original Meteoblue implementation
  SUN_THRESHOLD = 80     # percent - direct sun perceivable
  BRIGHT_THRESHOLD = 50  # percent - relatively bright
  MIN_SUN_DURATION_MINUTES = 10

  # Single location (Solgård) - no need for two locations
  LOCATION = { name: 'Solgård', lat: 59.233055, lng: 17.978695 }.freeze

  class << self
    # Predicts sun window for Solgård location
    # Returns data structure compatible with MeteoblueSunPredictor
    #
    # @return [Array<Hash>] Array with single prediction (for compatibility)
    def predict_sun_windows
      [predict_sun_window]
    end

    # Single location prediction
    #
    # @return [Hash] Prediction result
    def predict_sun_window
      forecast = fetch_forecast
      sun_window = find_first_sun_window(forecast)
      current = find_current_conditions(forecast)

      {
        location: LOCATION[:name],
        lat: LOCATION[:lat],
        lng: LOCATION[:lng],
        # Current brightness conditions
        current_brightness_percent: current[:brightness_percent],
        current_ghi: current[:ghi],
        current_clearsky_ghi: current[:clearsky_ghi],
        is_daylight: current[:is_daylight],
        # Next sun window (brightness >= 80%)
        next_sun_window_start: sun_window&.dig(:start),
        next_sun_window_duration_minutes: sun_window&.dig(:duration_minutes),
        next_sun_window_peak_brightness: sun_window&.dig(:peak_brightness),
        # Today's brightness curve
        todays_brightness_curve: build_brightness_curve(forecast),
        # Daily sun hours for next 7 days
        daily_sun_hours: build_daily_sun_hours(forecast),
        forecast_fetched_at: Time.now.iso8601
      }
    end

    private

    # Fetches forecast from Open-Meteo API (FREE, no key required)
    #
    # @return [Array<Hash>] Forecast data points
    def fetch_forecast
      response = HTTParty.get(BASE_URL, {
        query: {
          latitude: LOCATION[:lat],
          longitude: LOCATION[:lng],
          hourly: 'shortwave_radiation,direct_radiation,diffuse_radiation,sunshine_duration,is_day',
          daily: 'sunshine_duration',
          timezone: 'Europe/Stockholm',
          forecast_days: 7
        },
        timeout: 15
      })

      unless response.success?
        raise "Open-Meteo API error: #{response.code} - #{response.message}"
      end

      data = JSON.parse(response.body)
      parse_hourly_data(data)
    end

    # Parse Open-Meteo response into forecast points
    #
    # @param data [Hash] Raw API response
    # @return [Array<Hash>] Parsed forecast points
    def parse_hourly_data(data)
      hourly = data['hourly']
      return [] unless hourly

      times = hourly['time'] || []
      ghi = hourly['shortwave_radiation'] || []
      direct = hourly['direct_radiation'] || []
      diffuse = hourly['diffuse_radiation'] || []
      sunshine = hourly['sunshine_duration'] || []  # seconds per hour
      is_day = hourly['is_day'] || []

      times.each_with_index.map do |time_str, i|
        time = Time.parse(time_str)
        sunshine_seconds = sunshine[i].to_f
        ghi_value = ghi[i].to_f

        # Convert sunshine_duration to brightness_percent
        # 3600 seconds = 100% sunshine that hour
        brightness = (sunshine_seconds / 3600.0 * 100).round

        # Estimate clear-sky GHI based on time of year and solar position
        # In Swedish winter at 59°N, max is ~100 W/m² at solar noon
        # Use a simple seasonal model
        clearsky_ghi = estimate_clearsky_ghi(time)

        {
          time: time,
          ghi: ghi_value,
          direct_radiation: direct[i].to_f,
          diffuse_radiation: diffuse[i].to_f,
          sunshine_seconds: sunshine_seconds,
          clearsky_ghi: clearsky_ghi,
          brightness_percent: brightness,
          is_daylight: is_day[i] == 1
        }
      end
    end

    # Estimate theoretical clear-sky GHI based on solar position
    # Simple model for Swedish latitudes (59°N)
    #
    # @param time [Time] The time to estimate for
    # @return [Float] Estimated clear-sky GHI in W/m²
    def estimate_clearsky_ghi(time)
      # Day of year (1-365)
      day_of_year = time.yday

      # Hour of day (0-23)
      hour = time.hour + time.min / 60.0

      # Solar declination (simplified)
      declination = 23.45 * Math.sin(2 * Math::PI * (284 + day_of_year) / 365.0)

      # Latitude of Solgård
      latitude = 59.233

      # Hour angle (15 degrees per hour from solar noon ~12:00)
      hour_angle = (hour - 12) * 15

      # Solar elevation angle (simplified)
      sin_elevation = Math.sin(latitude * Math::PI / 180) * Math.sin(declination * Math::PI / 180) +
                      Math.cos(latitude * Math::PI / 180) * Math.cos(declination * Math::PI / 180) *
                      Math.cos(hour_angle * Math::PI / 180)

      elevation = Math.asin(sin_elevation) * 180 / Math::PI

      # If sun is below horizon, return 0
      return 0.0 if elevation <= 0

      # Clear-sky GHI model (simplified)
      # At sea level, max direct normal irradiance is ~1000 W/m²
      # GHI = DNI * sin(elevation) + diffuse (~100 W/m² on clear day)
      # Apply atmospheric extinction
      air_mass = 1.0 / [Math.sin(elevation * Math::PI / 180), 0.1].max
      extinction = Math.exp(-0.1 * air_mass)

      dni = 1000 * extinction
      ghi = dni * Math.sin(elevation * Math::PI / 180) + 50 * (elevation / 90.0)

      [ghi, 0].max.round(1)
    end

    # Finds current conditions (nearest hour)
    #
    # @param forecast [Array<Hash>] Forecast data points
    # @return [Hash] Current conditions
    def find_current_conditions(forecast)
      now = Time.now
      current_hour = forecast.find { |p| p[:time].hour == now.hour && p[:time].to_date == now.to_date }

      current_hour || {
        brightness_percent: 0,
        ghi: 0,
        clearsky_ghi: 0,
        is_daylight: false
      }
    end

    # Builds brightness curve for today
    #
    # @param forecast [Array<Hash>] Forecast data points
    # @return [Array<Hash>] Hourly brightness data for today
    def build_brightness_curve(forecast)
      today = Date.today
      forecast.select { |p| p[:time].to_date == today && p[:is_daylight] }
              .map do |p|
                {
                  hour: p[:time].strftime('%H:%M'),
                  brightness_percent: p[:brightness_percent],
                  ghi: p[:ghi].round,
                  clearsky_ghi: p[:clearsky_ghi].round
                }
              end
    end

    # Calculates daily sun hours for next 7 days
    #
    # @param forecast [Array<Hash>] Forecast data points
    # @return [Array<Hash>] Daily sun hours with timing
    def build_daily_sun_hours(forecast)
      # Group by date
      by_date = forecast.group_by { |p| p[:time].to_date }

      by_date.map do |date, points|
        # Find all sunny hours (brightness >= 80% during daylight)
        sunny_points = points.select { |p| p[:is_daylight] && p[:brightness_percent] >= SUN_THRESHOLD }
                             .sort_by { |p| p[:time] }
        sunny_hours = sunny_points.count

        # Find first and last sunny hour
        first_sunny = sunny_points.first
        last_sunny = sunny_points.last

        first_sun_hour = first_sunny ? first_sunny[:time].strftime('%H') : nil
        last_sun_end = last_sunny ? (last_sunny[:time] + 3600).strftime('%H') : nil

        # Find brightness window (50%+ hours) for grey days
        bright_points = points.select { |p| p[:is_daylight] && p[:brightness_percent] >= BRIGHT_THRESHOLD }
                              .sort_by { |p| p[:time] }
        first_bright = bright_points.first
        last_bright = bright_points.last
        first_bright_hour = first_bright ? first_bright[:time].strftime('%H') : nil
        last_bright_end = last_bright ? (last_bright[:time] + 3600).strftime('%H') : nil

        {
          date: date.iso8601,
          sun_hours: sunny_hours,
          sun_hours_text: format_sun_hours(sunny_hours),
          first_sun_hour: first_sun_hour,
          last_sun_end: last_sun_end,
          first_bright_hour: first_bright_hour,
          last_bright_end: last_bright_end
        }
      end.sort_by { |d| d[:date] }
    end

    # Formats sun hours for display
    #
    # @param hours [Integer] Number of sunny hours
    # @return [String, nil] Formatted string like "2h" or nil if 0
    def format_sun_hours(hours)
      return nil if hours == 0
      "#{hours}h"
    end

    # Finds the first continuous sun window meeting minimum duration
    #
    # @param forecast [Array<Hash>] Forecast data points
    # @return [Hash, nil] Sun window with :start and :duration_minutes
    def find_first_sun_window(forecast)
      now = Time.now
      future = forecast.select { |p| p[:time] >= now && p[:is_daylight] }
      return nil if future.empty?

      sorted = future.sort_by { |p| p[:time] }

      current_window_start = nil
      current_duration = 0

      sorted.each do |point|
        if point[:brightness_percent] >= SUN_THRESHOLD
          current_window_start ||= point[:time]
          current_duration += 60

          if current_duration >= MIN_SUN_DURATION_MINUTES
            total_duration = calculate_total_duration(sorted, current_window_start)
            return {
              start: current_window_start.iso8601,
              duration_minutes: total_duration,
              peak_brightness: find_peak_brightness(sorted, current_window_start)
            }
          end
        else
          current_window_start = nil
          current_duration = 0
        end
      end

      nil
    end

    # Calculates total duration of continuous sun from start point
    #
    # @param sorted [Array<Hash>] Sorted forecast points
    # @param start_time [Time] Window start time
    # @return [Integer] Total duration in minutes
    def calculate_total_duration(sorted, start_time)
      duration = 0

      sorted.each do |point|
        next if point[:time] < start_time
        break if point[:brightness_percent] < SUN_THRESHOLD

        duration += 60
      end

      duration
    end

    # Finds peak brightness during a sun window
    #
    # @param sorted [Array<Hash>] Sorted forecast points
    # @param start_time [Time] Window start time
    # @return [Integer] Peak brightness percentage
    def find_peak_brightness(sorted, start_time)
      sorted.select { |p| p[:time] >= start_time && p[:brightness_percent] >= SUN_THRESHOLD }
            .map { |p| p[:brightness_percent] }
            .max || 0
    end
  end
end

# CLI interface for standalone testing
if __FILE__ == $PROGRAM_NAME
  begin
    prediction = OpenMeteoSunPredictor.predict_sun_window
    puts JSON.pretty_generate(prediction)
  rescue => e
    puts JSON.pretty_generate({ error: e.message })
    exit 1
  end
end

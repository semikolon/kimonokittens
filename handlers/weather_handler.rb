require 'httparty'
require 'oj'

class WeatherHandler
  WEATHER_API_KEY = ENV['WEATHER_API_KEY']
  LOCATION = 'Huddinge,Sweden'
  CACHE_THRESHOLD = 60 * 10 # 10 minutes cache

  def initialize
    @data = nil
    @fetched_at = nil
  end

  def call(req)
    # Check if we have a valid API key
    unless WEATHER_API_KEY
      return placeholder_response
    end

    # Check cache
    if @data.nil? || Time.now - @fetched_at > CACHE_THRESHOLD
      response = HTTParty.get("https://api.weatherapi.com/v1/forecast.json",
        query: {
          key: WEATHER_API_KEY,
          q: LOCATION,
          days: 5,
          aqi: 'yes',
          alerts: 'no',
          lang: 'sv'
        }
      )

      if response.success?
        raw_data = response.parsed_response
        @data = transform_weather_data(raw_data)
        @fetched_at = Time.now
      else
        return [500, { 'Content-Type' => 'application/json' }, [ Oj.dump({ 'error': 'Failed to fetch weather data' }) ]]
      end
    end

    [200, { 'Content-Type' => 'application/json' }, [ Oj.dump(@data, mode: :compat) ]]
  end

  private

  def placeholder_response
    placeholder_data = {
      'current' => {
        'temp_c' => nil,
        'condition' => {
          'text' => "Det regnar",
          'icon' => "//cdn.weatherapi.com/weather/64x64/day/296.png"
        },
        'humidity' => nil,
        'wind_kph' => nil,
        'wind_dir' => nil
      },
      'forecast' => {
        'forecastday' => []
      },
      'location' => {
        'name' => "Huddinge",
        'country' => "Sweden"
      },
      'error' => "API-nyckel saknas - det regnar alltid när man inte kan kolla vädret"
    }

    [200, { 'Content-Type' => 'application/json' }, [ Oj.dump(placeholder_data, mode: :compat) ]]
  end

  def transform_weather_data(raw_data)
    now = Time.now
    weather_history = analyze_weather_history(raw_data, now)

    {
      'current' => {
        'temp_c' => raw_data['current']['temp_c'],
        'condition' => {
          'text' => raw_data['current']['condition']['text'],
          'icon' => raw_data['current']['condition']['icon']
        },
        'humidity' => raw_data['current']['humidity'],
        'wind_kph' => raw_data['current']['wind_kph'],
        'wind_dir' => raw_data['current']['wind_dir'],
        'air_quality' => raw_data.dig('current', 'air_quality'),
        'last_updated' => raw_data['current']['last_updated'],
        'last_updated_timestamp' => Time.parse(raw_data['current']['last_updated']).to_i
      },
      'forecast' => {
        'forecastday' => raw_data['forecast']['forecastday'].map do |day|
          date = Date.parse(day['date'])
          {
            'date' => day['date'], # Keep original YYYY-MM-DD format
            'date_iso8601' => date.iso8601, # Add ISO 8601 format
            'date_timestamp' => date.to_time.to_i, # Add Unix timestamp for beginning of day
            'day' => {
              'maxtemp_c' => day['day']['maxtemp_c'],
              'mintemp_c' => day['day']['mintemp_c'],
              'condition' => {
                'text' => day['day']['condition']['text'],
                'icon' => day['day']['condition']['icon']
              },
              'chance_of_rain' => day['day']['chance_of_rain']
            }
          }
        end
      },
      'location' => {
        'name' => raw_data['location']['name'],
        'country' => raw_data['location']['country']
      },
      'weather_history' => weather_history,
      'generated_at' => now.utc.iso8601,
      'generated_timestamp' => now.to_i
    }
  end

  # Analyze recent weather to detect snow landscape conditions
  # Returns info about recent snow to influence vibe detection
  def analyze_weather_history(raw_data, now)
    current_temp = raw_data['current']['temp_c']
    forecast_days = raw_data['forecast']['forecastday'] || []

    # Collect snow data from today and yesterday (if available)
    recent_snow_cm = 0.0
    snow_hours_last_24h = 0

    forecast_days.first(2).each_with_index do |day, day_index|
      # Add daily snow totals
      daily_snow = day.dig('day', 'totalsnow_cm') || 0.0
      recent_snow_cm += daily_snow

      # Check hourly data for snow occurrences
      hours = day['hour'] || []
      hours.each do |hour_data|
        hour_time = Time.parse(hour_data['time']) rescue nil
        next unless hour_time

        # Only count hours within the last 24 hours
        hours_ago = (now - hour_time) / 3600.0
        next unless hours_ago >= 0 && hours_ago <= 24

        # Check if it snowed this hour (condition contains "snö" or snow_cm > 0)
        condition = (hour_data.dig('condition', 'text') || '').downcase
        snow_cm = hour_data['snow_cm'] || 0.0
        will_it_snow = hour_data['will_it_snow'] || 0

        if condition.include?('snö') || snow_cm > 0 || will_it_snow == 1
          snow_hours_last_24h += 1
        end
      end
    end

    # Determine if there's likely snow on the ground
    # Snow typically stays when: recent snow AND temp below 2°C
    snow_on_ground = recent_snow_cm > 0.5 && current_temp < 2.0

    # Recent snow event = significant snow in last 24 hours
    recent_snow_event = snow_hours_last_24h >= 2 || recent_snow_cm > 1.0

    {
      'recent_snow_cm' => recent_snow_cm.round(1),
      'snow_hours_last_24h' => snow_hours_last_24h,
      'snow_on_ground' => snow_on_ground,
      'recent_snow_event' => recent_snow_event,
      'current_temp' => current_temp
    }
  end
end 
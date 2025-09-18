require 'faraday'
require 'faraday/excon'
require 'oj'

class WeatherHandler
  WEATHER_API_KEY = ENV['WEATHER_API_KEY']
  LOCATION = 'Huddinge,Sweden'
  CACHE_THRESHOLD = 60 * 10 # 10 minutes cache

  def initialize
    @data = nil
    @fetched_at = nil
    @conn = Faraday.new("https://api.weatherapi.com") do |faraday|
      faraday.adapter :excon
    end
  end

  def call(req)
    # Check if we have a valid API key
    unless WEATHER_API_KEY
      return placeholder_response
    end

    # Check cache
    if @data.nil? || Time.now - @fetched_at > CACHE_THRESHOLD
      response = @conn.get("/v1/forecast.json?key=#{WEATHER_API_KEY}&q=#{LOCATION}&days=5&aqi=yes&alerts=no")

      if response.success?
        raw_data = Oj.load(response.body)
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
        'air_quality' => raw_data.dig('current', 'air_quality')
      },
      'forecast' => {
        'forecastday' => raw_data['forecast']['forecastday'].map do |day|
          {
            'date' => day['date'],
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
      }
    }
  end
end 
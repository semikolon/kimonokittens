require 'httparty'
require 'oj'

class ElectricityPriceHandler
  REGION = 'SE3' # Stockholm area (matches tibber.rb)
  CACHE_THRESHOLD = 60 * 60 # 1 hour cache

  def initialize
    @data = nil
    @fetched_at = nil
  end

  def call(req)
    # Check cache
    if @data.nil? || Time.now - @fetched_at > CACHE_THRESHOLD
      now = Time.now
      today = now.strftime('%Y/%m-%d')
      tomorrow = (now + 86400).strftime('%Y/%m-%d')

      # Fetch today's data
      today_response = HTTParty.get(
        "https://www.elprisetjustnu.se/api/v1/prices/#{today}_#{REGION}.json",
        timeout: 10
      )

      # Fetch tomorrow's data (may not be available yet)
      tomorrow_response = HTTParty.get(
        "https://www.elprisetjustnu.se/api/v1/prices/#{tomorrow}_#{REGION}.json",
        timeout: 10
      )

      if today_response.success?
        raw_data = today_response.parsed_response

        # Add tomorrow's data if available
        if tomorrow_response.success?
          raw_data += tomorrow_response.parsed_response
        end

        @data = transform_price_data(raw_data)
        @fetched_at = Time.now
      else
        return [500, { 'Content-Type' => 'application/json' }, [ Oj.dump({ 'error': 'Failed to fetch electricity prices' }) ]]
      end
    end

    [200, { 'Content-Type' => 'application/json' }, [ Oj.dump(@data, mode: :compat) ]]
  end

  private

  def transform_price_data(raw_data)
    now = Time.now

    # API returns 15-minute intervals, aggregate to hourly averages
    # Group by hour and calculate average price
    hourly_prices = raw_data.group_by do |entry|
      Time.parse(entry['time_start']).hour
    end.map do |hour, entries|
      avg_sek = entries.sum { |e| e['SEK_per_kWh'] } / entries.size
      avg_eur = entries.sum { |e| e['EUR_per_kWh'] } / entries.size

      # Use the first entry's time_start for this hour
      first_entry = entries.first

      {
        'time_start' => first_entry['time_start'],
        'time_end' => entries.last['time_end'],
        'price_sek' => avg_sek.round(5),
        'price_eur' => avg_eur.round(5)
      }
    end.sort_by { |p| Time.parse(p['time_start']) }

    {
      'region' => REGION,
      'prices' => hourly_prices,
      'generated_at' => now.utc.iso8601,
      'generated_timestamp' => now.to_i
    }
  end
end

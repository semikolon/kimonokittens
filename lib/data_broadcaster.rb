require 'httparty'
require 'json'

class DataBroadcaster
  def initialize(pubsub)
    @pubsub = pubsub
    @running = false
    @threads = []
  end

  def start
    return if @running
    @running = true

    # Start thread-based schedulers for different data sources
    @threads << periodic(30) { fetch_and_publish('train_data', 'http://localhost:3001/data/train_departures') }
    @threads << periodic(60) { fetch_and_publish('temperature_data', 'http://localhost:3001/data/temperature') }
    @threads << periodic(300) { fetch_and_publish('weather_data', 'http://localhost:3001/data/weather') }
    @threads << periodic(600) { fetch_and_publish('strava_data', 'http://localhost:3001/data/strava_stats') }

    puts "DataBroadcaster: All scheduled tasks started"
  end

  def stop
    @running = false
    @threads.each { |t| t.join(1) }
    @threads.clear
    puts "DataBroadcaster: All scheduled tasks stopped"
  end

  private

  def periodic(interval_sec, &block)
    Thread.new do
      next_tick = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      while @running
        begin
          block.call
        rescue => e
          puts "DataBroadcaster error: #{e.class}: #{e.message}"
        ensure
          next_tick += interval_sec
          sleep_time = next_tick - Process.clock_gettime(Process::CLOCK_MONOTONIC)
          sleep(sleep_time) if sleep_time.positive?
        end
      end
    end
  end

  def fetch_and_publish(type, url)
    response = HTTParty.get(url, timeout: 10)
    return unless response.success?

    message = {
      type: type,
      payload: JSON.parse(response.body),
      timestamp: Time.now.to_i
    }.to_json
    @pubsub.publish(message)
    puts "DataBroadcaster: #{type} broadcast"
  end
end 
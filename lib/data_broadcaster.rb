require 'httparty'
require 'json'

class DataBroadcaster
  def initialize(pubsub)
    @pubsub = pubsub
    @running = false
    @threads = []
    @base_url = ENV['API_BASE_URL'] || 'http://localhost:3001'
  end

  def start
    return if @running
    @running = true

    # Send immediate broadcasts for 1-2 second loading requirement
    initial_broadcast

    # Start thread-based schedulers for different data sources
    @threads << periodic(30) { fetch_and_publish('train_data', "#{@base_url}/data/train_departures") }
    @threads << periodic(60) { fetch_and_publish('temperature_data', "#{@base_url}/data/temperature") }
    @threads << periodic(300) { fetch_and_publish('weather_data', "#{@base_url}/data/weather") }
    @threads << periodic(600) { fetch_and_publish('strava_data', "#{@base_url}/data/strava_stats") }
    @threads << periodic(3600) { fetch_and_publish('rent_data', "#{@base_url}/api/rent/friendly_message") }
    @threads << periodic(300) { fetch_and_publish_todos }

    puts "DataBroadcaster: All scheduled tasks started"
  end

  def initial_broadcast
    # Send all data immediately on startup for fast loading
    Thread.new do
      puts "DataBroadcaster: Sending initial broadcasts..."
      fetch_and_publish('weather_data', "#{@base_url}/data/weather")
      fetch_and_publish('strava_data', "#{@base_url}/data/strava_stats")
      fetch_and_publish('train_data', "#{@base_url}/data/train_departures")
      fetch_and_publish('temperature_data', "#{@base_url}/data/temperature")
      fetch_and_publish('rent_data', "#{@base_url}/api/rent/friendly_message")
      fetch_and_publish_todos
      puts "DataBroadcaster: Initial broadcasts complete"
    end
  end

  def send_immediate_data_to_new_client
    # Send all data immediately when a new WebSocket client connects
    Thread.new do
      puts "DataBroadcaster: Sending immediate data to new client..."
      fetch_and_publish('weather_data', "#{@base_url}/data/weather")
      fetch_and_publish('strava_data', "#{@base_url}/data/strava_stats")
      fetch_and_publish('train_data', "#{@base_url}/data/train_departures")
      fetch_and_publish('temperature_data', "#{@base_url}/data/temperature")
      fetch_and_publish('rent_data', "#{@base_url}/api/rent/friendly_message")
      fetch_and_publish_todos
      puts "DataBroadcaster: Immediate data sent to new client"
    end
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

  def fetch_and_publish_todos
    response = HTTParty.get("#{@base_url}/api/todos", timeout: 10)
    return unless response.success?

    # Parse markdown list items into structured JSON
    # Use split(/\r?\n/) to handle different line endings
    lines = response.body.split(/\r?\n/)
    todo_items = []

    lines.each_with_index do |line, index|
      trimmed = line.strip
      if trimmed.start_with?('- ')
        todo_items << {
          text: trimmed[2..-1], # Remove '- ' prefix
          id: "todo-#{index}"
        }
      end
    end

    message = {
      type: 'todo_data',
      payload: todo_items,
      timestamp: Time.now.to_i
    }.to_json
    @pubsub.publish(message)
    puts "DataBroadcaster: todo_data broadcast (#{todo_items.length} items)"
  end
end 
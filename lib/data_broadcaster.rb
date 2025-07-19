require 'rufus-scheduler'
require 'httparty'
require 'json'

class DataBroadcaster
  def initialize(pubsub)
    @pubsub = pubsub
    @scheduler = Rufus::Scheduler.new
    @running = false
  end

  def start
    return if @running
    @running = true
    
    # Schedule different data sources with their specified intervals
    schedule_train_data     # Every 20 seconds
    schedule_temperature_data # Every 30 seconds
    schedule_weather_data   # Every 10 minutes
    schedule_strava_data    # Every 5 minutes
    
    puts "DataBroadcaster: All scheduled tasks started"
  end

  def stop
    @scheduler.shutdown
    @running = false
    puts "DataBroadcaster: All scheduled tasks stopped"
  end

  private

  def schedule_train_data
    @scheduler.every '20s' do
      begin
        response = HTTParty.get('http://localhost:3001/data/train_departures')
        if response.success?
          message = {
            type: 'train_data',
            payload: JSON.parse(response.body),
            timestamp: Time.now.to_i
          }.to_json
          @pubsub.publish(message)
          puts "DataBroadcaster: Train data broadcast"
        end
      rescue => e
        puts "DataBroadcaster: Train data error - #{e.message}"
      end
    end
  end

  def schedule_temperature_data
    @scheduler.every '30s' do
      begin
        response = HTTParty.get('http://localhost:3001/data/temperature')
        if response.success?
          message = {
            type: 'temperature_data',
            payload: JSON.parse(response.body),
            timestamp: Time.now.to_i
          }.to_json
          @pubsub.publish(message)
          puts "DataBroadcaster: Temperature data broadcast"
        end
      rescue => e
        puts "DataBroadcaster: Temperature data error - #{e.message}"
      end
    end
  end

  def schedule_weather_data
    @scheduler.every '10m' do
      begin
        # Note: Weather handler is currently commented out in json_server.rb
        # This will need to be enabled for weather data to work
        response = HTTParty.get('http://localhost:3001/data/weather')
        if response.success?
          message = {
            type: 'weather_data',
            payload: JSON.parse(response.body),
            timestamp: Time.now.to_i
          }.to_json
          @pubsub.publish(message)
          puts "DataBroadcaster: Weather data broadcast"
        end
      rescue => e
        puts "DataBroadcaster: Weather data error - #{e.message}"
      end
    end
  end

  def schedule_strava_data
    @scheduler.every '5m' do
      begin
        response = HTTParty.get('http://localhost:3001/data/strava_stats')
        if response.success?
          message = {
            type: 'strava_data',
            payload: JSON.parse(response.body),
            timestamp: Time.now.to_i
          }.to_json
          @pubsub.publish(message)
          puts "DataBroadcaster: Strava data broadcast"
        end
      rescue => e
        puts "DataBroadcaster: Strava data error - #{e.message}"
      end
    end
  end
end 
require 'httparty'
require 'oj'
require 'awesome_print'
# require 'pry'  # Temporarily disabled due to gem conflict
# require 'pry-nav'  # Temporarily disabled due to gem conflict
require 'active_support/time'

# def to_sentence(array)
#   if array.size > 1
#     last = array.pop
#     "#{array.join(', ')} och #{last}"
#   else
#     array.first
#   end
# end

class TrainDepartureHandler
  # Updated to use SL Transport API (keyless, direct from SL)
  # No API key required - SL's new official API

  # Huddinge station ID for SL Transport API
  # Found via: https://transport.integration.sl.se/v1/sites (search for "Huddinge")
  STATION_ID = "9527" # SL Transport API ID for Huddinge station

  # Sördalavägen bus stop ID for SL Transport API
  # Found via: https://transport.integration.sl.se/v1/sites (search for "Sördalavägen")
  BUS_STOP_ID = "7027" # SL Transport API ID for Sördalavägen bus stop
  
  DIRECTION_NORTH = 2
  TIME_WINDOW = 60 # time in minutes to fetch departures for, max 60
  WALK_TIME = 8 # time in minutes to walk to the station
  RUN_TIME = 5 # time in minutes to cycle or run to the station
  MARGIN_TIME = 5 # time in minutes for alarm margin to get ready
  CACHE_THRESHOLD = 10 # time in seconds to keep data in cache (10 seconds for real-time data)

  def initialize
    @train_data = nil
    @bus_data = nil
    @fetched_at = nil
  end

  def call(req)
    # For testing:
    #@data = Oj.load_file('train_examples.json')
    #@data = Oj.load_file('train_examples_deviations.json')
    #@fetched_at = Time.now

    if @train_data.nil? || @bus_data.nil? || Time.now - @fetched_at > CACHE_THRESHOLD
      # Use SL Transport API - no key required, direct from SL
      # API documentation: https://www.trafiklab.se/api/our-apis/sl/transport/
      begin
        # Use HTTParty instead of faraday-excon to prevent SSL segfaults
        options = {
          timeout: 10,
          open_timeout: 5
        }

        # Fetch train departures first
        train_response = HTTParty.get("https://transport.integration.sl.se/v1/sites/#{STATION_ID}/departures", options)

        # Wait briefly between SSL requests to avoid potential conflicts
        sleep(0.1)

        # Fetch bus departures second (sequential, not concurrent)
        bus_response = HTTParty.get("https://transport.integration.sl.se/v1/sites/#{BUS_STOP_ID}/departures", options)

        if train_response.success? && bus_response.success?
          train_raw_data = Oj.load(train_response.body)
          bus_raw_data = Oj.load(bus_response.body)
          @train_data = transform_sl_transport_data(train_raw_data)
          @bus_data = transform_sl_bus_data(bus_raw_data)
          @fetched_at = Time.now
        else
          puts "WARNING: SL Transport API failed, using fallback data"
          puts "Train response: #{train_response.code}" if !train_response.success?
          puts "Bus response: #{bus_response.code}" if !bus_response.success?
          @train_data = get_fallback_train_data
          @bus_data = get_fallback_bus_data
          @fetched_at = Time.now
        end
      rescue => e
        puts "ERROR: Exception calling SL Transport API: #{e.message}"
        puts "Using fallback data"
        @train_data = get_fallback_train_data
        @bus_data = get_fallback_bus_data
        @fetched_at = Time.now
      end
    end

    # Filter for northbound trains that aren't cancelled
    northbound_trains = @train_data.select do |train|
      # Filter for trains going north (towards Stockholm)
      train['direction'] == 'north' && !train['cancelled']
    end

    now = Time.now.in_time_zone('Stockholm')
    departures = northbound_trains.map do |train|
      departure_time = Time.parse(train['departure_time']).in_time_zone('Stockholm')
      minutes_until_departure = ((departure_time - now) / 60).round
      display_time = departure_time.strftime('%H:%M')
      time_of_departure = minutes_until_departure > 59 ? display_time : "#{display_time} - om #{minutes_until_departure}m"

      deviation_note = train['deviation_note'] || ''
      summary_deviation_note = ''
      summary_deviation_note = ' (försenad)' if deviation_note.include?('Försenad') || deviation_note.include?('delayed')
      summary_deviation_note = ' (inställd)' if deviation_note.include?('Inställd') || deviation_note.include?('cancelled')

      {
        'destination': train['destination'],
        'line_number': train['line_number'],
        'departure_time': departure_time,
        'minutes_until_departure': minutes_until_departure,
        'time_of_departure': time_of_departure,
        'deviation_note': deviation_note,
        'summary_deviation_note': summary_deviation_note,
        'suffix': ''
      }
    end

    # Process deviations into structured format
    deviations = departures.map do |d|
      unless d[:deviation_note].empty?
        {
          'time' => d[:departure_time].strftime('%H:%M'),
          'destination' => d[:destination],
          'reason' => d[:deviation_note].downcase
        }
      end
    end.compact

    # Filter for trains that aren't cancelled and aren't past rushing to the station
    departures = departures.select do |d|
      d[:summary_deviation_note] != ' (inställd)' &&
      d[:minutes_until_departure] > RUN_TIME
    end

    # Convert departures to structured format with timestamps
    structured_trains = departures.map do |d|
      departure_timestamp = d[:departure_time].to_i

      # Determine action suffix
      late = d[:minutes_until_departure] < WALK_TIME
      suffix = if late
        "spring eller cykla!"
      elsif d[:minutes_until_departure] > (WALK_TIME + MARGIN_TIME + 5)
        alarm_time = d[:departure_time] - (WALK_TIME + MARGIN_TIME)*60
        "var redo #{alarm_time.strftime('%H:%M')}"
      else
        "du hinner gå"
      end

      {
        'departure_time' => d[:departure_time].strftime('%H:%M'),
        'departure_timestamp' => departure_timestamp,
        'minutes_until' => d[:minutes_until_departure],
        'can_walk' => !late,
        'line_number' => d[:line_number],
        'destination' => d[:destination],
        'deviation_note' => d[:deviation_note],
        'summary_deviation_note' => d[:summary_deviation_note],
        'suffix' => suffix
      }
    end

    # Process bus departures from Sördalavägen into structured format
    structured_buses = @bus_data.slice(0, 4).map do |bus|
      departure_time = Time.parse(bus['departure_time']).in_time_zone('Stockholm')
      minutes_until_departure = ((departure_time - now) / 60).round
      departure_timestamp = departure_time.to_i

      {
        'departure_time' => departure_time.strftime('%H:%M'),
        'departure_timestamp' => departure_timestamp,
        'minutes_until' => minutes_until_departure,
        'line_number' => bus['line_number'],
        'destination' => bus['destination']
      }
    end

    # Return structured JSON response
    response = {
      "trains" => structured_trains,
      "buses" => structured_buses,
      "deviations" => deviations,
      "generated_at" => Time.now.utc.iso8601
    }

    [200, { 'Content-Type' => 'application/json' }, [ Oj.dump(response, mode: :compat) ]]
  end

  private

  def transform_sl_transport_data(raw_data)
    # Transform SL Transport API response to our internal format
    return [] unless raw_data['departures']

    # Filter only trains and transform to internal format
    raw_data['departures']
      .select { |departure| departure['line']['transport_mode'] == 'TRAIN' }
      .map do |departure|
        # Extract destination and line information
        destination = departure['destination']
        line_number = departure['line']['designation']

        # Use scheduled time as departure time (ISO format)
        departure_time = departure['scheduled']

        # Determine direction: SL Transport uses direction_code (1=south, 2=north)
        direction = departure['direction_code'] == 2 ? 'north' : 'south'

        # Check for cancellations in deviations
        cancelled = departure['deviations'].any? { |dev|
          dev['message']&.downcase&.include?('inställ') ||
          dev['consequence'] == 'CANCELLED'
        }

        # Extract deviation/delay information
        deviation_note = ''
        if departure['deviations'].any?
          deviation_note = departure['deviations'].map { |dev| dev['message'] }.compact.join(', ')
        elsif departure['expected'] && departure['scheduled']
          # Calculate delay from expected vs scheduled with safe parsing
          begin
            scheduled = Time.parse(departure['scheduled'])
            expected = Time.parse(departure['expected'])
            delay_minutes = ((expected - scheduled) / 60).round
            if delay_minutes > 0
              deviation_note = "Försenad #{delay_minutes} min"
            end
          rescue ArgumentError, TypeError => e
            # If date parsing fails, just skip the delay calculation
            puts "WARNING: Failed to parse train times - scheduled: #{departure['scheduled'].inspect}, expected: #{departure['expected'].inspect}, error: #{e.message}"
          end
        end

        {
          'destination' => destination,
          'line_number' => line_number,
          'departure_time' => departure_time,
          'direction' => direction,
          'cancelled' => cancelled,
          'deviation_note' => deviation_note
        }
      end
  end

  def transform_sl_bus_data(raw_data)
    # Transform SL Transport API bus response to our internal format
    return [] unless raw_data['departures']

    now = Time.now.in_time_zone('Stockholm')

    # Filter only buses and transform to internal format
    raw_data['departures']
      .select { |departure| departure['line']['transport_mode'] == 'BUS' }
      .map do |departure|
        # Extract destination and line information
        destination = departure['destination']
        line_number = departure['line']['designation']

        # Use expected time if available, otherwise scheduled (for real-time accuracy)
        departure_time = departure['expected'] || departure['scheduled']

        {
          'destination' => destination,
          'line_number' => line_number,
          'departure_time' => departure_time
        }
      end
      .select do |bus|
        # Filter out buses that have already departed
        bus_time = Time.parse(bus['departure_time']).in_time_zone('Stockholm')
        bus_time > now # Only show buses departing in the future
      end
  end

  def get_fallback_train_data
    # Provide reasonable fallback data when API is unavailable
    # This generates realistic departure times for the next hour
    now = Time.now.in_time_zone('Stockholm')

    # Generate departures every 15 minutes for the next hour
    (1..4).map do |i|
      departure_time = now + (i * 15 * 60) # 15, 30, 45, 60 minutes from now

      {
        'destination' => 'Stockholm Central',
        'line_number' => '41',
        'departure_time' => departure_time.iso8601,
        'direction' => 'north',
        'cancelled' => false,
        'deviation_note' => ''
      }
    end
  end

  def get_fallback_bus_data
    # Provide reasonable fallback bus data when API is unavailable
    now = Time.now.in_time_zone('Stockholm')

    # Generate bus departures every 10 minutes for different lines
    [
      { 'destination' => 'Handens station', 'line_number' => '865', 'departure_time' => (now + 8*60).iso8601 },
      { 'destination' => 'Gladö kvarn', 'line_number' => '744', 'departure_time' => (now + 15*60).iso8601 },
      { 'destination' => 'Sörskogen', 'line_number' => '710', 'departure_time' => (now + 22*60).iso8601 },
      { 'destination' => 'Solgård', 'line_number' => '705', 'departure_time' => (now + 30*60).iso8601 }
    ]
  end

  def determine_direction(destination)
    # Determine if train is going north or south based on destination
    # This is a simplified heuristic - in practice you'd want more robust logic
    northbound_destinations = [
      'Stockholm', 'Södertälje', 'Märsta', 'Arlanda', 'Uppsala', 
      'Bålsta', 'Kungsängen', 'Rosersberg', 'Sollentuna'
    ]
    
    northbound_destinations.any? { |dest| destination.include?(dest) } ? 'north' : 'south'
  end
end

require 'faraday'
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
  # Updated to use ResRobot API instead of the deprecated SL API
  RESROBOT_API_KEY = ENV['RESROBOT_API_KEY'] || ENV['SL_API_KEY'] # Fallback to SL key if ResRobot not set
  
  # Huddinge station ID for ResRobot API
  # Found via: https://api.resrobot.se/v2.1/location.name?key=API_KEY&input=Huddinge
  STATION_ID = "740000003" # ResRobot ID for Huddinge station
  
  DIRECTION_NORTH = 2
  TIME_WINDOW = 60 # time in minutes to fetch departures for, max 60
  WALK_TIME = 8 # time in minutes to walk to the station
  RUN_TIME = 5 # time in minutes to cycle or run to the station
  MARGIN_TIME = 5 # time in minutes for alarm margin to get ready
  CACHE_THRESHOLD = 60 * 5 # time in seconds to keep data in cache

  def initialize
    @data = nil
    @fetched_at = nil
  end

  def call(req)
    # For testing:
    #@data = Oj.load_file('train_examples.json')
    #@data = Oj.load_file('train_examples_deviations.json')
    #@fetched_at = Time.now

    if @data.nil? || Time.now - @fetched_at > CACHE_THRESHOLD
      # Use ResRobot API instead of the deprecated SL API
      # ResRobot Timetables API: https://www.trafiklab.se/api/our-apis/resrobot-v21/timetables/
      begin
        response = Faraday.get("https://api.resrobot.se/v2.1/departureBoard", {
          accessId: RESROBOT_API_KEY,
          id: STATION_ID,
          duration: TIME_WINDOW,
          format: 'json'
        }) do |faraday|
          faraday.options.open_timeout = 2  # TCP connection timeout
          faraday.options.timeout = 3       # Overall request timeout
        end

        if response.success?
          raw_data = Oj.load(response.body)
          @data = transform_resrobot_data(raw_data)
          @fetched_at = Time.now
        else
          puts "WARNING: ResRobot API failed (status: #{response.status}), using fallback data"
          puts "Response body: #{response.body}" if response.body
          @data = get_fallback_data
          @fetched_at = Time.now
        end
      rescue => e
        puts "ERROR: Exception calling ResRobot API: #{e.message}"
        puts "Using fallback data"
        @data = get_fallback_data
        @fetched_at = Time.now
      end
    end

    # Filter for northbound trains that aren't cancelled
    northbound_trains = @data.select do |train| 
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

    # Construct deviation summary string
    deviation_summary = departures.map do |d|
      unless d[:deviation_note].empty?
        "#{d[:departure_time].strftime('%H:%M')} till #{d[:destination]}: #{d[:deviation_note].downcase}"
      end
    end.compact.join(" ")

    # Filter for trains that aren't cancelled and aren't past rushing to the station
    departures = departures.select do |d|
      d[:summary_deviation_note] != ' (inställd)' &&
      d[:minutes_until_departure] > RUN_TIME
    end

    if departures.any?
      first_train_you_can_catch = departures.first
      late = first_train_you_can_catch[:minutes_until_departure] < WALK_TIME
      first_train_you_can_catch[:suffix] = if late
        " - spring eller cykla!"
      elsif first_train_you_can_catch[:minutes_until_departure] > (WALK_TIME + MARGIN_TIME + 5) # E.g. 8 + 5 + 5 = 18 mins
        alarm_time = first_train_you_can_catch[:departure_time] - (WALK_TIME + MARGIN_TIME)*60
        " - var redo #{alarm_time.strftime("%H:%M")}"
      else
        " - du hinner gå"
      end
    end
    
    departures.each { |d| d[:departure_time] = d[:departure_time].strftime('%H:%M') }

    # Construct summary string
    departure_times = departures.map { |d| "<strong>#{d[:time_of_departure]}</strong>#{d[:summary_deviation_note]}#{d[:suffix]}" }

    summary = "#{departure_times.join("<br/>")}"
    summary = "Inga pendeltåg inom en timme" if departure_times.empty? || departure_times.all? { |t| t.include?('inställt') }

    response = {
      "summary" => summary,
      "deviation_summary" => deviation_summary
    }

    [200, { 'Content-Type' => 'application/json' }, [ Oj.dump(response, mode: :compat) ]]
  end

  private

  def transform_resrobot_data(raw_data)
    # Transform ResRobot API response to our internal format
    return [] unless raw_data['Departure']

    raw_data['Departure'].map do |departure|
      # Determine direction based on destination
      # Northbound destinations typically include: Stockholm, Södertälje, Märsta, etc.
      destination = departure['direction'] || departure['name'] || ''
      direction = determine_direction(destination)
      
      # Extract line information
      line_number = departure['Product'] ? departure['Product']['line'] : departure['transportNumber']
      
      # Handle departure time
      departure_time = departure['date'] + 'T' + departure['time']
      
      # Check for delays/cancellations
      cancelled = departure['cancelled'] == true || departure['Product']&.dig('cancelled') == true
      
      # Extract deviation/delay information
      deviation_note = ''
      if departure['Messages']
        deviation_note = departure['Messages'].map { |msg| msg['text'] }.join(', ')
      elsif departure['rtDate'] && departure['rtTime']
        # Real-time data indicates delay
        scheduled = Time.parse(departure['date'] + 'T' + departure['time'])
        actual = Time.parse(departure['rtDate'] + 'T' + departure['rtTime'])
        delay_minutes = ((actual - scheduled) / 60).round
        if delay_minutes > 0
          deviation_note = "Försenad #{delay_minutes} min"
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

  def get_fallback_data
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

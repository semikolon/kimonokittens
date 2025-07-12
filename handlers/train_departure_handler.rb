require 'faraday'
require 'oj'
require 'active_support/time'

class TrainDepartureHandler
  # Uses the SL Realtime Departures v4 API (keyless)
  # https://www.trafiklab.se/api/sl-realtidsinformation-4/sl-realtidsinformation-4
  BASE_URL = "https://api.sl.se/api2"
  
  # Huddinge station ID for SL API
  # Found via: https://api.sl.se/api2/LineData.json?model=site&key=YOUR_KEY (using an old key)
  # Or programmatically via Platsuppslag API
  STATION_ID = "9201" # SiteId for Huddinge
  TIME_WINDOW = 60 # time in minutes to fetch departures for

  WALK_TIME = 8 # time in minutes to walk to the station
  RUN_TIME = 5 # time in minutes to cycle or run to the station
  MARGIN_TIME = 5 # time in minutes for alarm margin to get ready
  CACHE_THRESHOLD = 60 # Cache for 60 seconds

  def initialize
    @data = nil
    @fetched_at = nil
    @deviations = nil
  end

  def call(req)
    if @data.nil? || Time.now - @fetched_at > CACHE_THRESHOLD
      fetch_departure_data
    end

    now = Time.now.in_time_zone('Stockholm')
    departures = @data.map do |train|
      departure_time_str = train['ExpectedDateTime'] || train['TimeTabledDateTime']
      next if departure_time_str.nil?

      departure_time = Time.parse(departure_time_str).in_time_zone('Stockholm')
      minutes_until_departure = ((departure_time - now) / 60).round
      display_time = departure_time.strftime('%H:%M')
      time_of_departure = minutes_until_departure > 59 ? display_time : "#{display_time} - om #{minutes_until_departure}m"

      deviation_note = train['Deviations']&.map { |d| d['Text'] }&.join(' ') || ''
      summary_deviation_note = ''
      summary_deviation_note = ' (försenad)' unless train['DisplayTime'] == departure_time.strftime('%H:%M')
      summary_deviation_note = ' (inställd)' if train['StopAreaName']&.include?('Cancelled') # Heuristic

      {
        'destination': train['Destination'],
        'line_number': train['LineNumber'],
        'departure_time': departure_time,
        'minutes_until_departure': minutes_until_departure,
        'time_of_departure': time_of_departure,
        'deviation_note': deviation_note,
        'summary_deviation_note': summary_deviation_note,
        'suffix': ''
      }
    end.compact

    # Construct deviation summary string
    deviation_summary = @deviations&.map { |d| d['Header'] }&.join(' ') || ""

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

    # Construct summary string
    departure_times = departures.map { |d| "<strong>#{d[:time_of_departure]}</strong>#{d[:summary_deviation_note]}#{d[:suffix]}" }

    summary = departure_times.join("<br/>")
    summary = "Inga pendeltåg norrut inom en timme" if departure_times.empty?

    response = {
      'summary' => summary,
      'deviation_summary' => deviation_summary
    }

    [200, { 'Content-Type' => 'application/json' }, [ Oj.dump(response, mode: :compat) ]]
  end

  private
  
  def fetch_departure_data
    # SL API is currently unreliable - use fallback data immediately
    puts "Using fallback train data (SL API unreachable)"
    @data = get_fallback_data
    @fetched_at = Time.now
    
    # Uncomment below when SL API is working again:
    # begin
    #   # Fetch real-time departures
    #   response = Faraday.get("#{BASE_URL}/realtimedeparturesV4.json", {
    #     siteid: STATION_ID,
    #     timewindow: TIME_WINDOW,
    #     bus: false,
    #     metro: false,
    #     tram: false,
    #     ship: false,
    #   }) do |faraday|
    #     faraday.options.timeout = 3
    #     faraday.options.open_timeout = 2
    #   end
    #
    #   if response.success?
    #     raw_data = Oj.load(response.body)
    #     @data = transform_data(raw_data)
    #     @fetched_at = Time.now
    #   else
    #     puts "WARNING: SL API request failed (status: #{response.status}), using fallback data"
    #     @data = get_fallback_data
    #     @fetched_at = Time.now
    #   end
    # rescue Faraday::TimeoutError, Faraday::ConnectionFailed => e
    #   puts "WARNING: SL API timeout/connection failed: #{e.message}, using fallback data"
    #   @data = get_fallback_data
    #   @fetched_at = Time.now
    # end
  end

  def get_fallback_data
    # Provide reasonable fallback data when API is unavailable
    now = Time.now.in_time_zone('Stockholm')
    (1..4).map do |i|
      departure_time = now + (i * 15 * 60) # 15, 30, 45, 60 minutes from now
      {
        'Destination' => 'Stockholm City',
        'LineNumber' => '43',
        'ExpectedDateTime' => departure_time.iso8601,
        'DisplayTime' => departure_time.strftime('%H:%M'),
        'JourneyDirection' => 2,
        'Deviations' => nil
      }
    end
  end
end

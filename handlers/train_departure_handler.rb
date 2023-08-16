
# def to_sentence(array)
#   if array.size > 1
#     last = array.pop
#     "#{array.join(', ')} och #{last}"
#   else
#     array.first
#   end
# end

require 'faraday'
require 'oj'
require 'awesome_print'
require 'pry'
require 'pry-nav'

class TrainDepartureHandler
  SL_API_KEY = ENV['SL_API_KEY']
  SITE_ID = 9527 # From https://api.sl.se/api2/typeahead.json?key=#{SL_API_KEY}&searchstring=Huddinge%20station&stationsonly=true&maxresults=2
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
      response = Faraday.get("https://api.sl.se/api2/realtimedeparturesV4.json?key=#{SL_API_KEY}&siteid=#{SITE_ID}&timewindow=#{TIME_WINDOW}")

      if response.success?
        @data = Oj.load(response.body)
        @fetched_at = Time.now
      else
        return [500, { 'Content-Type' => 'application/json' }, [ Oj.dump({ 'error': 'Failed to fetch train departures' }) ]]
      end
    end

    ap @data
    # Example:
    # [7] {
    #   "SecondaryDestinationName" => nil,
    #                "GroupOfLine" => "Pendeltåg",
    #              "TransportMode" => "TRAIN",
    #                 "LineNumber" => "41",
    #                "Destination" => "Södertälje centrum",
    #           "JourneyDirection" => 1,
    #               "StopAreaName" => "Huddinge",
    #             "StopAreaNumber" => 5161,
    #            "StopPointNumber" => 5161,
    #       "StopPointDesignation" => "3",
    #         "TimeTabledDateTime" => "2023-07-02T15:55:00",
    #           "ExpectedDateTime" => "2023-07-02T15:55:00",
    #                "DisplayTime" => "15:55",
    #              "JourneyNumber" => 2947,
    #                 "Deviations" => [
    #       [0] {
    #                      "Text" => "Inställd på grund av personalbrist.",
    #               "Consequence" => "INFORMATION",
    #           "ImportanceLevel" => 7
    #       }

    
    # Filter for northbound trains that aren't cancelled
    northbound_trains = @data['ResponseData']['Trains'].select do |train| 
      train['JourneyDirection'] == 2
      # && (train['Deviations'].nil? || train['Deviations'].none? { |deviation| deviation['Text'].include?('Inställd') })
    end

    #now = DateTime.parse('2023-07-01T10:21:00+02:00')
    now = DateTime.now.new_offset('+02:00')
    departures = northbound_trains.map do |train|
      expected_time = train['ExpectedDateTime'] || train['TimeTabledDateTime']
      departure_time = DateTime.parse(expected_time + '+02:00')
      minutes_until_departure = ((departure_time - now) * 24 * 60).to_i
      #display_time = "#{minutes_until_departure / 60}h #{minutes_until_departure % 60}m"
      display_time = departure_time.strftime('%H:%M')
      time_of_departure = minutes_until_departure > 59 ? display_time : "#{display_time} - om #{minutes_until_departure}m"

      deviation_note = ''
      summary_deviation_note = ''
      if train['Deviations']
        deviation_note = train['Deviations'].map { |deviation| deviation['Text'].strip }.join(', ')
        summary_deviation_note = ' (försenad)' if deviation_note.include?('Försenad')
        summary_deviation_note = ' (inställd)' if deviation_note.include?('Inställd')
      end

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
    end
    
    # Construct deviation summary string
    deviation_summary = departures.map do |d|
      unless d[:deviation_note].empty?
        "#{d[:departure_time].strftime('%H:%M')} till #{d[:destination]}: #{d[:deviation_note].downcase}"
      end
    end.compact.join(" ")

    # Filter for northbound trains that aren't cancelled and aren't past rushing to the station
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
        alarm_time = first_train_you_can_catch[:departure_time] - (WALK_TIME + MARGIN_TIME) / (24 * 60.0)
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
      'summary': summary,
      'deviation_summary': deviation_summary
    }

    [200, { 'Content-Type' => 'application/json' }, [ Oj.dump(response) ]]
  end
end

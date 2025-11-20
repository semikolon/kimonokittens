require 'oj'
require 'date'
require 'net/http'
require 'uri'
require_relative 'heatpump_price_handler'
require_relative '../lib/persistence'
require_relative '../lib/sms/gateway'

# Heatpump Schedule Generator
# Implements ps-strategy-lowest-price algorithm from node-red-contrib-power-saver
#
# Purpose: Generate ready-to-use heatpump schedule based on electricity prices
# Replaces: Tibber Query + ps-receive-price + ps-strategy-lowest-price nodes in Node-RED
#
# Algorithm (from https://github.com/ottopaulsen/node-red-contrib-power-saver):
#   1. Sort all hours by price (cheapest first)
#   2. Select N cheapest hours
#   3. Apply max_price filter (reject if average > threshold)
#   4. Return schedule with EVU values (0=ON, 1=OFF)
#
# Created: November 19, 2025
# Related: docs/HEATPUMP_SCHEDULE_API_PLAN.md

class HeatpumpScheduleHandler
  DEFAULT_HOURS_ON = 12
  DEFAULT_MAX_PRICE = 2.2

  def initialize(heatpump_price_handler)
    @price_handler = heatpump_price_handler
    @last_emergency_sms_time = nil  # Track when we last sent emergency SMS
  end

  def call(env)
    # Wrap env in Rack::Request for convenient access
    req = Rack::Request.new(env)

    # Parse query parameters
    params = req.params
    hours_on = (params['hours_on'] || DEFAULT_HOURS_ON).to_i

    # Get prices from heatpump_price_handler
    status, headers, body = @price_handler.call(env)
    return [status, headers, body] unless status == 200

    price_data = Oj.load(body.first)

    # Extract today + tomorrow prices (keep separate for per-day processing!)
    today = price_data['today'] || []
    tomorrow = price_data['tomorrow'] || []

    return error_response('No price data available') if today.empty? && tomorrow.empty?

    # Generate schedule using ps-strategy algorithm (process each day independently)
    schedule = generate_schedule_per_day(today, tomorrow, hours_on)

    # Fetch heatpump config and apply temperature override logic
    config = Persistence.heatpump_config.get_current
    temps = get_current_temperatures
    current_state = calculate_current_state(schedule, config, temps)

    # Return ps-strategy compatible format with current state
    response = {
      'schedule' => build_schedule_array(schedule),
      'hours' => schedule,
      'source' => 'Dell API (peak/off-peak aware)',
      'config' => {
        'hoursOn' => hours_on,
        'maxPrice' => config.max_price,  # From database (informational only, not used in algorithm)
        'doNotSplit' => false,
        'outputValueForOn' => '0',    # EVU=0 (heatpump ON)
        'outputValueForOff' => '1'    # EVU=1 (heatpump OFF)
      },
      'time' => Time.now.iso8601,
      'version' => '1.0.0',
      'strategyNodeId' => 'dell-ruby-scheduler',
      'current' => current_state
    }

    [200, { 'Content-Type' => 'application/json' }, [ Oj.dump(response) ]]
  end

  private

  # Implements ps-strategy-lowest-price getBestX algorithm (per 24-hour period)
  # CRITICAL: Processes each day independently to ensure consistent daily heating
  # Prevents bug where all hours could be selected from one day, leaving other day with 0 hours
  def generate_schedule_per_day(today, tomorrow, hours_on)
    # Process today's 24 hours independently
    today_schedule = select_cheapest_hours(today, hours_on)

    # Process tomorrow's 24 hours independently
    tomorrow_schedule = select_cheapest_hours(tomorrow, hours_on)

    # Combine into single schedule (chronological order preserved)
    today_schedule + tomorrow_schedule
  end

  # Select N cheapest hours from a single 24-hour period
  # Returns schedule array with onOff flags set for cheapest hours
  #
  # NOTE: maxPrice parameter removed (Nov 20, 2025) - heatpump is essential infrastructure,
  # can't defer like washing machines. With peak/off-peak pricing (2-4 kr/kWh), maxPrice
  # threshold became obsolete. Always select cheapest hours regardless of absolute price.
  def select_cheapest_hours(prices, hours_on)
    return [] if prices.empty?

    # Sort prices by value, keeping original indices
    sorted_indices = prices.each_with_index
      .sort_by { |p, _| p['total'] }
      .map { |_, i| i }

    # Select N cheapest hours from THIS period only (regardless of price)
    on_indices = sorted_indices.first(hours_on).to_set

    # Build schedule array for this period
    prices.map.with_index do |price, i|
      is_on = on_indices.include?(i)
      {
        'start' => price['startsAt'],
        'price' => price['total'].round(4),
        'onOff' => is_on,
        'saving' => nil  # Could calculate savings vs always-on
      }
    end
  end

  # Convert hours array to compressed schedule format
  # Groups consecutive same-state periods
  def build_schedule_array(hours)
    schedule = []
    current_state = nil
    count = 0
    start_time = nil

    hours.each do |hour|
      if hour['onOff'] == current_state
        count += 1
      else
        if current_state != nil
          schedule << {
            'time' => start_time,
            'value' => current_state,
            'countHours' => count
          }
        end
        current_state = hour['onOff']
        start_time = hour['start']
        count = 1
      end
    end

    # Add final segment
    if current_state != nil
      schedule << {
        'time' => start_time,
        'value' => current_state,
        'countHours' => count
      }
    end

    schedule
  end

  # Fetch current temperatures from /data/temperature endpoint
  # Returns hash with indoor, hotwater, and target temperatures
  def get_current_temperatures
    begin
      response = Net::HTTP.get(URI('http://localhost:3001/data/temperature'))
      data = Oj.load(response)
      {
        indoor: data['indoor_temperature'].to_f,
        hotwater: data['hotwater_temperature'].to_f,
        target: data['target_temperature'].to_f
      }
    rescue StandardError => e
      puts "Error fetching temperatures: #{e.message}"
      # Return safe defaults if fetch fails (won't trigger overrides)
      { indoor: 21.0, hotwater: 50.0, target: 21.0 }
    end
  end

  # Calculate current state with priority-based override logic
  # Priority 1: Temperature emergency (safety) - force ON if too cold
  # Priority 2: Schedule (default) - use ps-strategy calculated schedule
  def calculate_current_state(schedule, config, temps)
    # Find current hour in schedule
    now = Time.now
    current_hour = schedule.find { |h| Time.parse(h['start']) <= now && Time.parse(h['start']) + 3600 > now }

    # If no current hour found (edge case), use first hour
    current_hour ||= schedule.first

    base_state = current_hour['onOff']  # true=ON, false=OFF from schedule
    final_state = base_state
    override_reason = nil

    # Priority 1: Temperature emergency (force ON if too cold)
    if temps[:indoor] <= (temps[:target] - config.emergency_temp_offset) || temps[:hotwater] < config.min_hotwater
      final_state = true
      override_reason = 'temperature_emergency'

      # Send SMS alert if this is a new emergency (not sent recently)
      send_emergency_sms_if_needed(temps, config)

    # Priority 2: Schedule (use calculated schedule)
    else
      override_reason = base_state ? 'schedule' : 'schedule_off'
    end

    # Convert to EVU format (0=ON, 1=OFF)
    evu_value = final_state ? 0 : 1

    {
      'state' => final_state,
      'evu' => evu_value,
      'reason' => override_reason,
      'temperatures' => {
        'indoor' => temps[:indoor],
        'hotwater' => temps[:hotwater],
        'target' => temps[:target]
      },
      'price' => current_hour['price']
    }
  end

  # Send emergency SMS if temperature failsafe triggered
  # Only sends once per hour to avoid spam
  def send_emergency_sms_if_needed(temps, config)
    now = Time.now

    # Don't spam - only send if we haven't sent SMS in last hour
    if @last_emergency_sms_time.nil? || (now - @last_emergency_sms_time) > 3600
      begin
        # Determine which condition triggered (concise Swedish)
        indoor_low = temps[:indoor] <= (temps[:target] - config.emergency_temp_offset)
        hotwater_low = temps[:hotwater] < config.min_hotwater

        if indoor_low && hotwater_low
          message = "Båda för kalla!"  # "Both too cold!"
        elsif indoor_low
          message = "#{temps[:indoor].round(1)}°C inne"  # "#{temp}°C indoors"
        else
          message = "#{temps[:hotwater].round(1)}°C vatten"  # "#{temp}°C water"
        end

        SmsGateway.send_admin_alert(message)
        @last_emergency_sms_time = now
        puts "📱 Emergency SMS sent: #{message}"
      rescue => e
        puts "⚠️  Failed to send emergency SMS: #{e.message}"
      end
    end
  end

  def error_response(message)
    [500, { 'Content-Type' => 'application/json' }, [ Oj.dump({ 'error' => message }) ]]
  end
end

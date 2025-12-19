require 'oj'
require 'date'
require 'net/http'
require 'uri'
require_relative 'heatpump_price_handler'
require_relative '../lib/persistence'
require_relative '../lib/sms/gateway'

# Heatpump Schedule Generator
# Implements ps-strategy-lowest-price algorithm from node-red-contrib-power-saver
# with DISTRIBUTION-AWARE hour selection to prevent long OFF gaps
#
# Purpose: Generate ready-to-use heatpump schedule based on electricity prices
# Replaces: Tibber Query + ps-receive-price + ps-strategy-lowest-price nodes in Node-RED
#
# Algorithm (enhanced from https://github.com/ottopaulsen/node-red-contrib-power-saver):
#   1. Ensure minimum hours per 6-hour block (prevents long gaps)
#   2. Fill remaining hours from globally cheapest
#   3. Return schedule with EVU values (0=ON, 1=OFF)
#
# Distribution rationale (Dec 2025):
#   Hot water tank has low thermal mass - depletes quickly during usage.
#   Pure "cheapest N hours" can cluster hours, leaving 4-6 hour gaps where
#   hot water cools below threshold, triggering expensive emergency overrides.
#   Minimum distribution ensures recovery periods throughout the day.
#
# Created: November 19, 2025
# Updated: December 2025 - Added distribution-aware scheduling
# Related: docs/HEATPUMP_SCHEDULE_API_PLAN.md

class HeatpumpScheduleHandler
  DEFAULT_HOURS_ON = 12

  # Minimum hours per 6-hour block to ensure hot water recovery throughout the day
  # With 14 hours_on: 8 distributed (2×4 blocks) + 6 from cheapest = 14 total
  # This prevents gaps > 4 hours which cause hot water to deplete below threshold
  MIN_HOURS_PER_BLOCK = 2

  # 6-hour blocks for distribution
  # Block 0: 00:00-05:59 (overnight - recovery while sleeping)
  # Block 1: 06:00-11:59 (morning - post-shower recovery)
  # Block 2: 12:00-17:59 (afternoon - maintain through day)
  # Block 3: 18:00-23:59 (evening - dinner/evening recovery)
  HOUR_BLOCKS = [
    (0..5),   # overnight
    (6..11),  # morning
    (12..17), # afternoon
    (18..23)  # evening
  ].freeze

  def initialize(heatpump_price_handler)
    @price_handler = heatpump_price_handler
    @last_emergency_sms_time = nil  # Track when we last sent emergency SMS
  end

  def call(env)
    # Wrap env in Rack::Request for convenient access
    req = Rack::Request.new(env)

    # Parse query parameters and load persisted config
    params = req.params
    config = Persistence.heatpump_config.get_current
    hours_on = params['hours_on'] ? params['hours_on'].to_i : (config&.hours_on || DEFAULT_HOURS_ON)
    skip_sms = params['skip_sms'] == 'true'  # Dashboard/polling callers set this to avoid SMS spam

    # Get prices from heatpump_price_handler
    status, headers, body = @price_handler.call(env)
    return [status, headers, body] unless status == 200

    price_data = Oj.load(body.first)

    # Extract today + tomorrow prices (keep separate for per-day processing!)
    today = price_data['today'] || []
    tomorrow = price_data['tomorrow'] || []

    # Get current temperatures (needed for emergency fallback and override logic)
    temps = get_current_temperatures

    # CRITICAL: Never return error! Tomorrow's prices don't exist until ~13:00 each day.
    # After midnight until 13:00, we work with today's data only - this is NORMAL.
    if today.empty? && tomorrow.empty?
      # Emergency fallback: return safe default (heatpump ON)
      puts "⚠️  WARNING: No price data available! Using emergency fallback (EVU=0, heatpump ON)"
      return emergency_fallback_response(config, temps, skip_sms)
    end

    # Generate schedule using ps-strategy algorithm (process each day independently)
    schedule = generate_schedule_per_day(today, tomorrow, hours_on)

    # Apply temperature override logic
    current_state = calculate_current_state(schedule, config, temps, skip_sms)

    # Return ps-strategy compatible format with current state
    response = {
      'schedule' => build_schedule_array(schedule),
      'hours' => schedule,
      'source' => 'Dell API (peak/off-peak aware)',
      'config' => {
        'hoursOn' => hours_on,
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

  # Select N cheapest hours from a single 24-hour period WITH DISTRIBUTION
  # Returns schedule array with onOff flags set
  #
  # Distribution algorithm (Dec 2025):
  #   1. First pass: Select MIN_HOURS_PER_BLOCK cheapest hours from EACH 6-hour block
  #      This guarantees coverage throughout the day (no gaps > 4 hours)
  #   2. Second pass: Fill remaining slots from globally cheapest available hours
  #      This optimizes cost while respecting distribution constraints
  #
  # Example with 14 hours_on and MIN_HOURS_PER_BLOCK=2:
  #   - 8 hours distributed (2 per block × 4 blocks)
  #   - 6 hours from cheapest remaining
  #   - Result: Good coverage + cost optimization
  #
  # NOTE: Always selects hours regardless of absolute price.
  # Heatpump is essential infrastructure - can't defer like washing machines.
  def select_cheapest_hours(prices, hours_on)
    return [] if prices.empty?

    selected = Set.new

    # First pass: ensure minimum coverage in each 6-hour block
    # Pick the cheapest MIN_HOURS_PER_BLOCK hours within each block
    HOUR_BLOCKS.each do |block_range|
      block_hours = block_range.to_a.select { |h| h < prices.length }
      next if block_hours.empty?

      # Sort hours in this block by price, pick cheapest
      cheapest_in_block = block_hours
        .sort_by { |h| prices[h]['total'] }
        .first(MIN_HOURS_PER_BLOCK)

      selected.merge(cheapest_in_block)
    end

    # Second pass: fill remaining slots from globally cheapest (not already selected)
    remaining_slots = hours_on - selected.size
    if remaining_slots > 0
      available_hours = (0...prices.length).to_a - selected.to_a
      cheapest_remaining = available_hours
        .sort_by { |h| prices[h]['total'] }
        .first(remaining_slots)

      selected.merge(cheapest_remaining)
    end

    # Build schedule array for this period
    prices.map.with_index do |price, i|
      is_on = selected.include?(i)
      {
        'start' => price['startsAt'],
        'price' => price['total'].round(4),
        'onOff' => is_on
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
  def calculate_current_state(schedule, config, temps, skip_sms = false)
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

      # Log override and send SMS alert only if we're actually overriding
      # (i.e., schedule said OFF but we're forcing ON)
      # If schedule already said ON, there's no override - just low temps during scheduled run
      unless skip_sms
        # Only log to database if this is a true override (schedule said OFF)
        unless base_state
          log_override(
            temps: temps,
            config: config,
            price: current_hour['price']
          )
        end

        # Always send SMS alert for temperature emergencies (throttled to 1/hour)
        send_emergency_sms(temps, config)
      end

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

  # Log override to database for self-learning analysis
  # Only called for TRUE overrides (schedule said OFF, we forced ON)
  #
  # @param temps [Hash] Current temperatures (indoor, hotwater, target)
  # @param config [HeatpumpConfig] Current configuration
  # @param price [Float] Current electricity price
  def log_override(temps:, config:, price:)
    now = Time.now

    # Determine which condition triggered
    indoor_low = temps[:indoor] <= (temps[:target] - config.emergency_temp_offset)
    hotwater_low = temps[:hotwater] < config.min_hotwater

    # Determine override type and temperature
    if indoor_low && hotwater_low
      override_type = 'indoor'  # Primary concern when both trigger
      override_temp = temps[:indoor]
    elsif indoor_low
      override_type = 'indoor'
      override_temp = temps[:indoor]
    else
      override_type = 'hotwater'
      override_temp = temps[:hotwater]
    end

    begin
      Persistence.heatpump_overrides.record(
        type: override_type,
        temperature: override_temp,
        price: price,
        hour_of_day: now.hour
      )
      puts "📊 Override logged: #{override_type} @ #{override_temp.round(1)}°C, hour #{now.hour}, price #{price.round(2)} kr/kWh"
    rescue => e
      puts "⚠️  Failed to log override: #{e.message}"
    end
  end

  # Send emergency SMS alert (throttled to max 1 per hour)
  #
  # @param temps [Hash] Current temperatures
  # @param config [HeatpumpConfig] Current configuration
  def send_emergency_sms(temps, config)
    now = Time.now

    # Don't spam - only send if we haven't sent SMS in last hour
    return if @last_emergency_sms_time && (now - @last_emergency_sms_time) <= 3600

    # Determine which condition triggered (concise Swedish)
    indoor_low = temps[:indoor] <= (temps[:target] - config.emergency_temp_offset)
    hotwater_low = temps[:hotwater] < config.min_hotwater

    message = if indoor_low && hotwater_low
      "Båda för kalla!"
    elsif indoor_low
      "#{temps[:indoor].round(0).to_i}°C inne"
    else
      "#{temps[:hotwater].round(0).to_i}°C vatten"
    end

    begin
      SmsGateway.send_admin_alert(message)
      @last_emergency_sms_time = now
      puts "📱 Emergency SMS sent: #{message}"
    rescue => e
      puts "⚠️  Failed to send emergency SMS: #{e.message}"
    end
  end

  def error_response(message)
    [500, { 'Content-Type' => 'application/json' }, [ Oj.dump({ 'error' => message }) ]]
  end

  # Emergency fallback when NO price data available
  # Returns safe default: EVU=0 (heatpump ON) to prevent freezing
  def emergency_fallback_response(config, temps, skip_sms = false)
    current_state = {
      'state' => true,
      'evu' => 0,  # Heatpump ON
      'reason' => 'emergency_no_price_data',
      'temperatures' => {
        'indoor' => temps[:indoor],
        'hotwater' => temps[:hotwater],
        'target' => temps[:target]
      },
      'price' => 0.0
    }

    response = {
      'schedule' => [],
      'hours' => [],
      'source' => 'Emergency fallback (no price data)',
      'config' => {
        'hoursOn' => config&.hours_on || DEFAULT_HOURS_ON,
        'doNotSplit' => false,
        'outputValueForOn' => '0',
        'outputValueForOff' => '1'
      },
      'time' => Time.now.iso8601,
      'version' => '1.0.0',
      'strategyNodeId' => 'dell-emergency-fallback',
      'current' => current_state
    }

    [200, { 'Content-Type' => 'application/json' }, [ Oj.dump(response) ]]
  end
end

require 'oj'
require 'date'
require_relative 'heatpump_price_handler'

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
  end

  def call(req)
    # Parse query parameters
    params = Rack::Utils.parse_query(req.query_string)
    hours_on = (params['hours_on'] || DEFAULT_HOURS_ON).to_i
    max_price = params['max_price'] ? params['max_price'].to_f : DEFAULT_MAX_PRICE

    # Get prices from heatpump_price_handler
    status, headers, body = @price_handler.call(req)
    return [status, headers, body] unless status == 200

    price_data = Oj.load(body.first)

    # Extract today + tomorrow prices into flat array
    today = price_data['viewer']['homes'][0]['currentSubscription']['priceInfo']['today'] || []
    tomorrow = price_data['viewer']['homes'][0]['currentSubscription']['priceInfo']['tomorrow'] || []
    all_prices = today + tomorrow

    return error_response('No price data available') if all_prices.empty?

    # Generate schedule using ps-strategy algorithm
    schedule = generate_schedule(all_prices, hours_on, max_price)

    # Return ps-strategy compatible format
    response = {
      'schedule' => build_schedule_array(schedule),
      'hours' => schedule,
      'source' => 'Dell API (peak/off-peak aware)',
      'config' => {
        'hoursOn' => hours_on,
        'maxPrice' => max_price,
        'doNotSplit' => false,
        'outputValueForOn' => '0',    # EVU=0 (heatpump ON)
        'outputValueForOff' => '1'    # EVU=1 (heatpump OFF)
      },
      'time' => Time.now.iso8601,
      'version' => '1.0.0',
      'strategyNodeId' => 'dell-ruby-scheduler',
      'current' => true
    }

    [200, { 'Content-Type' => 'application/json' }, [ Oj.dump(response) ]]
  end

  private

  # Implements ps-strategy-lowest-price getBestX algorithm
  def generate_schedule(prices, hours_on, max_price)
    # Sort prices by value, keeping original indices
    sorted_indices = prices.each_with_index
      .sort_by { |p, _| p['total'] }
      .map { |_, i| i }

    # Select N cheapest hours
    on_indices = sorted_indices.first(hours_on).to_set

    # Calculate average price of selected hours
    selected_prices = on_indices.map { |i| prices[i]['total'] }
    avg_price = selected_prices.sum / selected_prices.length.to_f

    # Apply max_price filter
    if max_price && avg_price > max_price
      # If average exceeds max, turn everything OFF
      on_indices = Set.new
    end

    # Build schedule array
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

  def error_response(message)
    [500, { 'Content-Type' => 'application/json' }, [ Oj.dump({ 'error' => message }) ]]
  end
end

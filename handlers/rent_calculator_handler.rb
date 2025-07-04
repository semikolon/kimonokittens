# RentCalculatorHandler provides a REST API for calculating rent shares among roommates.
# 
# This API is designed to be used by both humans (via direct HTTP requests) and AI assistants
# (particularly LLMs integrated into home voice assistants). The design prioritizes minimal
# required input to enable natural interactions like "What will my rent be?"
#
# Key Features:
# - Smart defaults to minimize required input
# - Integration with external data sources (e.g., electricity bills scraped from supplier)
# - Support for both one-off calculations and persistent history
# - Messenger-friendly output format for easy sharing
#
# Usage Scenarios:
# 1. Voice Assistant Integration:
#    User: "What will my rent be?"
#    Assistant: [Calls API with minimal config, using defaults and scraped data]
#    
# 2. Quarterly Invoice Updates:
#    User: "The quarterly invoice came, it's 2612 kr"
#    Assistant: [Updates the invoice amount via the API]
#    
#    Later...
#    User: "What's my rent?"
#    Assistant: [Calls API, which automatically includes current invoice data]
#
#    Note: The quarterly invoice amount is stored by the core RentCalculator system,
#    making it available for all calculations regardless of whether they come through
#    this API or command-line tools. This ensures consistency across all interfaces
#    and allows the invoice to be mentioned once by any roommate and automatically
#    included in all rent calculations for that period.
#
# 3. Manual Calculations:
#    Developer: [Makes HTTP request with custom configuration]
#
# The API aims to make rent calculations as automated as possible while maintaining
# flexibility for manual overrides when needed. It serves as a bridge between the
# RentCalculator core functionality and various client interfaces, with special
# consideration for AI assistant integration.
#
# Implementation Note:
# The persistence of quarterly invoices is handled by the core RentCalculator system
# (see rent.rb and related modules). This centralized approach ensures that all
# interfaces (API, CLI, etc.) work with the same data and simplifies the overall
# architecture. The API layer simply needs to provide endpoints for updating and
# retrieving this information.

require 'agoo'
require 'rack'
require_relative '../rent'
require_relative '../lib/rent_db'
require 'json'
require 'date'

class RentCalculatorHandler
  def call(req)
    case req['REQUEST_METHOD']
    when 'POST'
      if req['PATH_INFO'].include?('/roommates')
        handle_roommate_update(req)
      else
        handle_calculation(req)
      end
    when 'PUT'
      handle_config_update(req)
    when 'GET'
      if req['PATH_INFO'].include?('/forecast')
        handle_forecast_request(req)
      elsif req['PATH_INFO'].include?('/history')
        handle_history_request(req)
      elsif req['PATH_INFO'].include?('/roommates')
        handle_roommate_list(req)
      else
        handle_documentation(req)
      end
    else
      [405, { 'Content-Type' => 'application/json' }, [{ error: 'Method not allowed' }.to_json]]
    end
  rescue JSON::ParserError
    [400, { 'Content-Type' => 'application/json' }, [{ error: 'Invalid JSON in request body' }.to_json]]
  rescue RentCalculator::ValidationError => e
    [400, { 'Content-Type' => 'application/json' }, [{ error: e.message }.to_json]]
  rescue StandardError => e
    [500, { 'Content-Type' => 'application/json' }, [{ error: e.message }.to_json]]
  end

  private

  def handle_calculation(req)
    # Parse request body
    body = JSON.parse(req.body.read)
    
    # Fetch current state from the database
    config = extract_config(year: body['year'], month: body['month'])
    roommates = extract_roommates(year: body['year'], month: body['month'])
    history_options = extract_history_options(body)

    # Calculate rent
    if history_options
      # TODO: Refactor calculate_and_save to write to RentLedger
      results = RentCalculator.calculate_and_save(
        roommates: roommates,
        config: config,
        history_options: history_options
      )
    else
      results = RentCalculator.rent_breakdown(roommates: roommates, config: config)
    end

    # Add friendly message if requested
    if body['include_friendly_message']
      results['friendly_message'] = RentCalculator.friendly_message(
        roommates: roommates,
        config: config
      )
    end

    [200, { 'Content-Type' => 'application/json' }, [results.to_json]]
  end

  def handle_history_request(req)
    query = Rack::Utils.parse_query(req['QUERY_STRING'])
    year = query['year']&.to_i || Time.now.year
    month = query['month']&.to_i || Time.now.month

    history_data = RentDb.instance.get_rent_history(year: year, month: month)

    [200, { 'Content-Type' => 'application/json' }, [history_data.to_json]]
  end

  def handle_forecast_request(req)
    query = Rack::Utils.parse_query(req['QUERY_STRING'])
    year = query['year']&.to_i || Time.now.year
    month = query['month']&.to_i || Time.now.month

    forecast_data = generate_rent_forecast(year: year, month: month)
    [200, { 'Content-Type' => 'application/json' }, [forecast_data.to_json]]
  end

  def handle_documentation(req)
    docs = {
      description: 'API for calculating rent shares among roommates',
      endpoints: {
        'GET /api/rent': 'Get this documentation',
        'GET /api/rent/forecast?year=YYYY&month=MM': 'Generate a rent forecast for a future month',
        'GET /api/rent/history': 'List available versions for a month',
        'GET /api/rent/history?year=YYYY&month=MM&version=V': 'Get specific calculation version',
        'GET /api/rent/roommates': 'List current roommates',
        'GET /api/rent/roommates?year=YYYY&month=MM': 'List roommates for specific month',
        'GET /api/rent/roommates?history=true': 'Include history of changes',
        'POST /api/rent': 'Calculate rent shares',
        'POST /api/rent/roommates': 'Update roommate information',
        'PUT /api/rent/config': 'Update configuration values'
      },
      post_request_format: {
        config: {
          year: 'Year for calculation (optional, defaults to current)',
          month: 'Month for calculation (optional, defaults to current)',
          kallhyra: 'Base rent (required)',
          el: 'Electricity cost',
          bredband: 'Internet cost',
          vattenavgift: 'Water fee',
          va: 'Sewage fee',
          larm: 'Alarm system fee',
          drift_rakning: 'Quarterly invoice (optional)',
          saldo_innan: 'Previous balance (optional, defaults to 0)',
          extra_in: 'Extra income (optional, defaults to 0)'
        },
        roommates: {
          'name': {
            days: 'Days stayed (optional, defaults to full month)',
            room_adjustment: 'Room adjustment amount (optional, only include if non-zero)'
          }
        },
        history_options: {
          version: 'Version number (optional)',
          title: 'Version title (optional)',
          force: 'Whether to overwrite existing version'
        },
        include_friendly_message: 'Whether to include Messenger-friendly format (optional)'
      },
      put_config_format: {
        year: 'Year (optional, for month-specific values)',
        month: 'Month (optional, for month-specific values)',
        updates: {
          'key': 'value to set',
          'example': {
            'drift_rakning': 2612,
            'bredband': 450,
            'saldo_innan': 400
          }
        }
      },
      post_roommate_format: {
        action: 'One of: add_permanent, set_departure, set_temporary, update_adjustment',
        name: 'Roommate name',
        room_adjustment: 'Room adjustment amount (optional)',
        start_date: 'Start date for permanent roommate (optional)',
        end_date: 'End date when departing',
        year: 'Year for temporary stay',
        month: 'Month for temporary stay',
        days: 'Number of days for temporary stay'
      },
      example_request: {
        config: {
          kallhyra: 24530,
          el: 1600,
          bredband: 400,
          drift_rakning: 2612
        },
        roommates: {
          'Fredrik': {},  # Full month, no adjustment
          'Rasmus': {},  # Full month, no adjustment
          'Astrid': {    # Only specify what differs from defaults
            days: 15,
            room_adjustment: -1400
          }
        },
        history_options: {
          title: "December 2024 Calculation"
        },
        include_friendly_message: true
      },
      example_roommate_requests: {
        add_permanent: {
          action: 'add_permanent',
          name: 'Elvira',
          start_date: '2024-01-01'
        },
        set_departure: {
          action: 'set_departure',
          name: 'Astrid',
          end_date: '2024-12-15'
        },
        set_temporary: {
          action: 'set_temporary',
          name: 'Amanda',
          year: 2024,
          month: 12,
          days: 10
        },
        update_adjustment: {
          action: 'update_adjustment',
          name: 'Astrid',
          room_adjustment: -1500
        }
      }
    }

    [200, { 'Content-Type' => 'application/json' }, [docs.to_json]]
  end

  def handle_config_update(req)
    body = JSON.parse(req.body.read)
    updates = body['updates']

    unless updates.is_a?(Hash)
      return [400, { 'Content-Type' => 'application/json' }, [{ error: 'The "updates" key must be a JSON object.' }.to_json]]
    end

    db = RentDb.instance
    updates.each do |key, value|
      db.set_config(key, value.to_s)
    end

    [200, { 'Content-Type' => 'application/json' }, [{ status: 'success', updated: updates.keys }.to_json]]
  end

  def handle_roommate_update(req)
    body = JSON.parse(req.body.read)
    action = body['action']
    name = body['name']

    db = RentDb.instance
    response = { status: 'success' }

    case action
    when 'add_permanent'
      # For now, we only support adding a name.
      # TODO: Add support for email, avatarUrl, etc.
      new_tenant = db.add_tenant(name: name)
      response[:new_tenant] = new_tenant
    # TODO: Implement other actions like 'set_departure', 'set_temporary', etc.
    else
      return [400, { 'Content-Type' => 'application/json' }, [{ error: "Invalid action: #{action}" }.to_json]]
    end

    [200, { 'Content-Type' => 'application/json' }, [response.to_json]]
  end

  def handle_roommate_list(req)
    # TODO: Add support for querying by year/month to handle temporary stays.
    # For now, this just returns all current tenants.
    tenants = RentDb.instance.get_tenants
    [200, { 'Content-Type' => 'application/json' }, [tenants.to_json]]
  end

  def extract_config(year:, month:)
    # Fetches the active configuration for a specific month.
    # If a quarterly invoice (drift_rakning) is present for the month,
    # it takes precedence over regular monthly fees.
    config = RentDb.instance.get_rent_config(year: year, month: month)
    config_hash = Hash[config.map { |row| [row['key'].to_sym, row['value'].to_f] }]

    # If drift_rakning is present and non-zero, it replaces monthly fees
    if config_hash[:drift_rakning] && config_hash[:drift_rakning] > 0
      config_hash.delete(:vattenavgift)
      config_hash.delete(:va) # Assuming 'va' is another monthly fee
      config_hash.delete(:larm)
    end
    
    # Provide safe defaults if values are missing, to prevent crashes.
    defaults = RentCalculator::Config::DEFAULTS.merge({
      year: year,
      month: month
    })

    merged = defaults.merge(config_hash)

    # Ensure correct types by creating a new hash
    final_config = {}
    merged.each do |key, value|
      final_config[key] = if [:year, :month].include?(key)
        value.to_i
      else
        value
      end
    end
    final_config
  end

  def get_historical_electricity_cost(year:, month:)
    # This helper parses the electricity_bills_history.txt file to find the
    # total electricity cost for a given consumption month.
    # It assumes the bill for month M is paid in month M+1, so to find the
    # cost for July 2024 consumption, it looks for bills dated August 2024.
    history_file = File.expand_path('../../electricity_bills_history.txt', __FILE__)
    return 0 unless File.exist?(history_file)
    
    lines = File.readlines(history_file)
    
    # To find the cost for 'month', we look at bills from 'month + 1'.
    forecast_month = month + 1
    forecast_year = year - 1
    if forecast_month > 12
      forecast_month = 1
      forecast_year += 1
    end

    target_month_str = "#{forecast_year}-#{format('%02d', forecast_month)}"
    
    vattenfall_cost = 0
    fortum_cost = 0
    in_fortum_section = false
    
    lines.each do |line|
      next if line.strip.empty?
      
      if line.include?('Fortum')
        in_fortum_section = true
        next
      elsif line.include?('Vattenfall')
        in_fortum_section = false
        next
      end

      next unless line.start_with?(target_month_str)
      
      cost = line.split('kr').first.split.last.to_f
      
      if in_fortum_section
        fortum_cost = cost if fortum_cost == 0 # Take the first match
      else
        vattenfall_cost = cost if vattenfall_cost == 0 # Take the first match
      end
    end
    
    # Return the sum of the two costs
    (vattenfall_cost + fortum_cost).round
  end

  def extract_roommates(year:, month:)
    db = RentDb.instance
    tenants = db.get_tenants
    
    # The calculator expects a hash like:
    # { 'Fredrik' => { days: 30, room_adjustment: 0 } }
    # For now, we assume full month stays. Partial stays would require more logic.
    total_days = RentCalculator::Helpers.days_in_month(year, month)
    
    period_start = Date.new(year, month, 1)
    period_end   = Date.new(year, month, RentCalculator::Helpers.days_in_month(year, month))

    tenants.each_with_object({}) do |tenant, hash|
      # Parse dates; assume ISO strings like "2025-03-01"
      start_date_raw = tenant['startDate']
      start_date = start_date_raw ? Date.parse(start_date_raw) : nil
      departure_date = tenant['departureDate'] ? Date.parse(tenant['departureDate']) : nil

      # Exclude if departed before the period starts or not yet arrived
      next if departure_date && departure_date < period_start
      next if start_date && start_date > period_end

      # Calculate the actual days stayed within the period
      actual_start = [start_date, period_start].compact.max
      actual_end = [departure_date, period_end].compact.min
      days_stayed = (actual_end - actual_start).to_i + 1

      hash[tenant['name']] = {
        days: days_stayed,
        room_adjustment: (tenant['roomAdjustment'] || 0).to_i
      }
    end
  end

  def extract_history_options(body)
    return nil unless body['history_options']

    {
      version: body['history_options']['version'],
      title: body['history_options']['title'],
      force: body['history_options']['force']
    }
  end

  def month_data_to_json(month)
    {
      metadata: month.metadata,
      constants: month.constants,
      roommates: month.roommates,
      final_results: month.final_results
    }.to_json
  end

  def generate_rent_forecast(year:, month:)
    config_hash = extract_config(year: year, month: month)
    roommates_hash = extract_roommates(year: year, month: month)

    # Override the electricity cost with our historical forecast
    historical_el = get_historical_electricity_cost(year: year, month: month)
    config_hash[:el] = historical_el if historical_el > 0

    breakdown = RentCalculator.rent_breakdown(roommates: roommates_hash, config: config_hash)

    # We build a record that mimics the structure of a saved RentLedger entry
    # so the frontend can process it consistently.
    # The key is to match the frontend's `RentDetails` interface.
    final_results = {
      total: breakdown['Total'], # Align key from 'Total' to total
      rent_per_roommate: breakdown['Rent per Roommate'], # Align key
      config: config_hash, # Pass the config used for the calculation
      roommates: roommates_hash # Pass the roommate details used
    }
    
    {
      id: "forecast-#{Cuid.generate}",
      title: "Forecast for #{Date::MONTHNAMES[month]} #{year}",
      period: Time.new(year, month, 1).utc.iso8601,
      final_results: final_results, # Use the correctly structured hash
      createdAt: Time.now.utc.iso8601
    }
  end
end 
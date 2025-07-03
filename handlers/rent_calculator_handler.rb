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
require_relative '../rent'
require_relative '../lib/rent_history'
require 'json'

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
      if req['PATH_INFO'].include?('/history')
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
    
    # Extract data from request
    config = extract_config(body)
    roommates = extract_roommates(body)
    history_options = extract_history_options(body)

    # Calculate rent
    if history_options
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
    version = query['version']&.to_i

    if version
      month_data = RentHistory::Month.load(year: year, month: month, version: version)
      return [404, { 'Content-Type' => 'application/json' }, [{ error: 'Version not found' }.to_json]] unless month_data
      
      [200, { 'Content-Type' => 'application/json' }, [month_data_to_json(month_data)]]
    else
      versions = RentHistory::Month.versions(year: year, month: month)
      [200, { 'Content-Type' => 'application/json' }, [{ versions: versions }.to_json]]
    end
  end

  def handle_documentation(req)
    docs = {
      description: 'API for calculating rent shares among roommates',
      endpoints: {
        'GET /api/rent': 'Get this documentation',
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
    year = body['year']&.to_i
    month = body['month']&.to_i

    updates.each do |key, value|
      RentCalculator::ConfigStore.instance.set(key, value, year, month)
    end

    # Return current config state
    config = if year && month
      RentCalculator::ConfigStore.instance.month_config(year, month)
    else
      RentCalculator::ConfigStore.instance.current_config
    end

    [200, { 'Content-Type' => 'application/json' }, [config.to_json]]
  end

  def handle_roommate_update(req)
    body = JSON.parse(req.body.read)
    action = body['action']
    store = RentCalculator::RoommateStore.instance

    case action
    when 'add_permanent'
      store.add_permanent_roommate(
        body['name'],
        body['room_adjustment'],
        Date.parse(body['start_date'] || Date.today.to_s)
      )
    when 'set_departure'
      store.set_departure(
        body['name'],
        Date.parse(body['end_date'])
      )
    when 'set_temporary'
      store.set_monthly_stay(
        body['name'],
        body['year'],
        body['month'],
        days: body['days'],
        room_adjustment: body['room_adjustment']
      )
    when 'update_adjustment'
      store.update_room_adjustment(
        body['name'],
        body['room_adjustment']
      )
    else
      return [400, { 'Content-Type' => 'application/json' }, [{ error: 'Invalid action' }.to_json]]
    end

    # Return current roommate state
    roommates = if body['year'] && body['month']
      store.get_roommates(body['year'], body['month'])
    else
      store.get_permanent_roommates
    end

    [200, { 'Content-Type' => 'application/json' }, [roommates.to_json]]
  end

  def handle_roommate_list(req)
    query = Rack::Utils.parse_query(req['QUERY_STRING'])
    year = query['year']&.to_i
    month = query['month']&.to_i
    include_history = query['history'] == 'true'

    store = RentCalculator::RoommateStore.instance
    
    response = {
      roommates: if year && month
        store.get_roommates(year, month)
      else
        store.get_permanent_roommates
      end
    }

    response[:history] = store.get_changes if include_history

    [200, { 'Content-Type' => 'application/json' }, [response.to_json]]
  end

  def extract_config(body)
    config = body['config'] || {}
    {
      year: config['year'],
      month: config['month'],
      kallhyra: config['kallhyra'],
      el: config['el'],
      bredband: config['bredband'],
      vattenavgift: config['vattenavgift'],
      va: config['va'],
      larm: config['larm'],
      drift_rakning: config['drift_rakning'],
      saldo_innan: config['saldo_innan'] || 0,
      extra_in: config['extra_in'] || 0
    }
  end

  def extract_roommates(body)
    roommates = body['roommates'] || {}
    roommates.transform_values do |info|
      info ||= {}  # Handle case where roommate has empty object
      result = {}
      
      # Only include days if specified
      result[:days] = info['days'] if info['days']
      
      # Only include room_adjustment if non-zero
      if info['room_adjustment'] && info['room_adjustment'] != 0
        result[:room_adjustment] = info['room_adjustment']
      end
      
      result
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
end 
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

require 'rack'
require_relative '../rent'
require_relative '../lib/persistence'
require_relative '../lib/electricity_projector'
require_relative '../lib/heating_cost_calculator'
require_relative '../lib/services/quarterly_invoice_projector'
require 'json'
require 'date'

class RentCalculatorHandler
  def call(req)
    puts "DEBUG: PATH_INFO = #{req['PATH_INFO'].inspect}"
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
      elsif req['PATH_INFO'].include?('/friendly_message')
        handle_friendly_message(req)
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
    body_content = req['rack.input'].read
    req['rack.input'].rewind
    body = JSON.parse(body_content)
    
    # Fetch current state from the database
    config = extract_config(year: body['year'], month: body['month'])
    
    # Merge request body config overrides if present
    if body['config']
      body['config'].each do |key, value|
        config[key.to_sym] = value
      end
    end
    
    roommates = extract_roommates(year: body['year'], month: body['month'])
    history_options = extract_history_options(body)

    # Calculate rent
    if history_options
      # Config hash contains CONFIG year/month
      # Config.days_in_month auto-calculates from next month (rent month)
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

    history_data = Persistence.rent_ledger.get_rent_history(year: year, month: month)

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
        'GET /api/rent/forecast?year=YYYY&month=MM': 'Generate a rent forecast (month = config period)',
        'GET /api/rent/history': 'List available versions for a month',
        'GET /api/rent/history?year=YYYY&month=MM&version=V': 'Get specific calculation version (month = rent period)',
        'GET /api/rent/roommates': 'List current roommates',
        'GET /api/rent/roommates?year=YYYY&month=MM': 'List roommates for specific period (month = config period)',
        'GET /api/rent/roommates?history=true': 'Include history of changes',
        'POST /api/rent': 'Calculate rent shares',
        'POST /api/rent/roommates': 'Update roommate information',
        'PUT /api/rent/config': 'Update configuration values'
      },
      parameter_timing_explanation: {
        critical_concept: 'The month parameter represents CONFIG PERIOD MONTH, not rent month',
        example: 'month=9 (September config) calculates October rent due September 27',
        config_period: 'Contains electricity bills for consumption + advance payments for next month',
        rent_period: 'The month being paid for (always config_month + 1 in normal cases)'
      },
      post_request_format: {
        config: {
          year: 'Config period year (optional, defaults to current)',
          month: 'Config period month (optional, defaults to current)',
          kallhyra: 'Base rent (required)',
          el: 'Electricity cost',
          bredband: 'Internet cost',
          vattenavgift: 'Water fee',
          va: 'Sewage fee',
          larm: 'Alarm system fee',
          drift_rakning: 'Quarterly invoice (optional)',
          saldo_innan: 'Previous balance (optional, defaults to 0)',
          extra_in: 'Extra income (optional, defaults to 0)',
          gas: 'Gas for stove (optional, defaults to 0)'
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
    body_content = req['rack.input'].read
    req['rack.input'].rewind
    body = JSON.parse(body_content)
    updates = body['updates']

    unless updates.is_a?(Hash)
      return [400, { 'Content-Type' => 'application/json' }, [{ error: 'The "updates" key must be a JSON object.' }.to_json]]
    end

    period = if body['year'] && body['month']
      Time.utc(body['year'].to_i, body['month'].to_i, 1)
    else
      Time.now.utc
    end

    repo = Persistence.rent_configs

    updates.each do |key, value|
      repo.upsert(key: key, value: value.to_s, period: period)
    end

    $pubsub&.publish('rent_data_updated')

    [200, { 'Content-Type' => 'application/json' }, [{ status: 'success', updated: updates.keys }.to_json]]
  end

  def handle_roommate_update(req)
    body_content = req['rack.input'].read
    req['rack.input'].rewind
    body = JSON.parse(body_content)
    action = body['action']
    name = body['name']

    repo = Persistence.tenants
    response = { status: 'success' }

    case action
    when 'add_permanent'
      start_date = body['start_date']
      email = body['email'] || "#{name.downcase.gsub(/\s+/, '.')}@kimonokittens.com"
      room_adjustment = body['room_adjustment']
      departure_date = body['departure_date']

      new_tenant = Tenant.new(
        name: name,
        email: email,
        start_date: start_date,
        departure_date: departure_date,
        room_adjustment: room_adjustment
      )

      created = repo.create(new_tenant)
      $pubsub&.publish('rent_data_updated')
      response[:new_tenant] = created.id
      response[:tenant] = created.to_h
    when 'set_departure'
      end_date = body['end_date']
      unless end_date
        return [400, { 'Content-Type' => 'application/json' }, [{ error: 'end_date is required for set_departure action' }.to_json]]
      end
      tenant = repo.find_by_name(name)
      unless tenant
        return [404, { 'Content-Type' => 'application/json' }, [{ error: "Tenant not found: #{name}" }.to_json]]
      end

      repo.set_departure_date(tenant.id, end_date)
      $pubsub&.publish('rent_data_updated')
      response[:message] = "Set departure date for #{name} to #{end_date}"
    when 'update_adjustment'
      room_adjustment = body['room_adjustment']
      unless room_adjustment
        return [400, { 'Content-Type' => 'application/json' }, [{ error: 'room_adjustment is required for update_adjustment action' }.to_json]]
      end
      tenant = repo.find_by_name(name)
      unless tenant
        return [404, { 'Content-Type' => 'application/json' }, [{ error: "Tenant not found: #{name}" }.to_json]]
      end

      repo.set_room_adjustment(tenant.id, room_adjustment)
      $pubsub&.publish('rent_data_updated')
      response[:message] = "Updated room adjustment for #{name} to #{room_adjustment}"
    when 'set_temporary'
      # TODO: Implement temporary stay logic - this would require more complex logic
      # to handle month-specific stays rather than permanent tenant records
      return [400, { 'Content-Type' => 'application/json' }, [{ error: 'set_temporary action not yet implemented' }.to_json]]
    else
      return [400, { 'Content-Type' => 'application/json' }, [{ error: "Invalid action: #{action}" }.to_json]]
    end

    [200, { 'Content-Type' => 'application/json' }, [response.to_json]]
  end

  def handle_roommate_list(req)
    # TODO: Add support for querying by year/month to handle temporary stays.
    # For now, this just returns all current tenants.
    tenants = Persistence.tenants.all.map(&:to_h)
    [200, { 'Content-Type' => 'application/json' }, [tenants.to_json]]
  end

  # Extracts rent configuration for a specific CONFIGURATION PERIOD
  #
  # @param year [Integer] Configuration period year
  # @param month [Integer] Configuration period month (1-12)
  #
  # CRITICAL: This month parameter represents the CONFIG PERIOD MONTH, not the rent month!
  # The configuration retrieved is used to calculate rent for the FOLLOWING month.
  #
  # @example September Config → October Rent
  #   extract_config(year: 2025, month: 9)  # Gets September period config
  #   # Uses September electricity bills + October advance payments
  #   # Calculates rent for October 2025 (due September 27)
  #
  # @return [Hash] Configuration hash with symbolized keys for RentCalculator
  def extract_config(year:, month:, with_projection: true)
    repo = Persistence.rent_configs

    config_hash = begin
      RentConfig.for_period(
        year: year,
        month: month,
        repository: repo,
        with_projection: with_projection
      ).transform_keys(&:to_sym)
    rescue StandardError => e
      warn "WARNING: RentConfig lookup failed for #{year}-#{month}: #{e.message}"
      {}
    end

    # Check if drift_rakning is a projection (for API response transparency)
    @drift_rakning_is_projection = false
    if config_hash[:drift_rakning] && config_hash[:drift_rakning].to_f > 0
      # Query database to check projection status
      drift_config = repo.find_by_key_and_period('drift_rakning', Time.utc(year, month, 1))
      if drift_config
        row = repo.dataset.where(id: drift_config.id).first
        @drift_rakning_is_projection = row[:isProjection] if row
      end
    end

    numeric_config = config_hash.transform_values do |value|
      value.respond_to?(:to_f) ? value.to_f : value
    end

    # Pass CONFIG year/month directly (no conversion needed!)
    # Config.days_in_month auto-calculates from next month (rent month)
    # Example: year=2025, month=11 → days_in_month returns 31 (December)
    defaults = RentCalculator::Config::DEFAULTS.merge({
      year: year,   # CONFIG year
      month: month  # CONFIG month
    })

    merged = defaults.merge(numeric_config)

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
    # REPLACED with intelligent ElectricityProjector (see lib/electricity_projector.rb)
    #
    # Old implementation had critical flaws:
    # - Always used year-1 (ignored current year actual data)
    # - Added +1 to month incorrectly
    # - Returned 0 on failure (triggered bad defaults)
    # - Only used text file (ignored RentConfig and historical JSON files)
    #
    # New implementation:
    # - Uses trailing 12 months for baseline (captures current price trends)
    # - Applies multi-year seasonal patterns
    # - Sources from RentConfig + JSON files + text file (comprehensive)
    # - Never returns 0 (always provides intelligent projection)
    #
    # See lib/electricity_projector.rb for full algorithm documentation.
    projector = ElectricityProjector.new
    projector.project(config_year: year, config_month: month)
  end

  # Extracts roommate information for a specific CONFIGURATION PERIOD
  #
  # @param year [Integer] Configuration period year
  # @param month [Integer] Configuration period month (1-12)
  #
  # CRITICAL: Uses CONFIG month as INPUT, but filters/calculates using RENT month.
  # This is correct because rent is paid IN ADVANCE for the following month.
  #
  # @example November Config → December Rent
  #   extract_roommates(year: 2025, month: 11)  # November config period
  #   # Internally converts to December (rent month)
  #   # Filters tenants active in December
  #   # Calculates days stayed in December (31 days)
  #
  # @return [Hash] Roommate hash with days stayed (in RENT month) and room adjustments
  def extract_roommates(year:, month:)
    # Delegate to RentCalculator's extract_roommates_for_period (DRY)
    # Both methods do identical CONFIG→RENT conversion and tenant filtering
    RentCalculator.send(:extract_roommates_for_period, year, month)
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

  # Generates a friendly rent message for the current or specified period
  #
  # @example API Usage
  #   GET /api/rent/friendly_message
  #   GET /api/rent/friendly_message?year=2025&month=9
  #
  # CRITICAL TIMING: The month parameter is the CONFIGURATION PERIOD MONTH
  # - month=9 retrieves September config to calculate October rent
  # - Returns message: "Hyran för oktober 2025 ska betalas innan 27 sep"
  #
  # @param req [Hash] HTTP request object with optional query parameters
  # @return [Array] HTTP response array [status, headers, body]
  def handle_friendly_message(req)
    # Parse query parameters for year/month (optional)
    query_string = req['QUERY_STRING'] || ''
    params = CGI.parse(query_string)

    # Use current date if not specified
    # IMPORTANT: Current month = current config period (not rent period)
    now = Time.now
    year = params['year']&.first&.to_i || now.year
    month = params['month']&.first&.to_i || now.month

    begin
      config = extract_config(year: year, month: month)  # Projection now handled automatically
      roommates = extract_roommates(year: year, month: month)

      # Determine electricity data source for transparency
      data_source = determine_electricity_data_source(config, year, month)

      # Generate friendly message using RentCalculator
      friendly_text = RentCalculator.friendly_message(
        roommates: roommates,
        config: config
      )

      # Add projection indicator to message if quarterly invoice is projected
      if @drift_rakning_is_projection
        friendly_text += "\n_(uppskattad drifträkning - väntar på faktisk faktura)_"
      end

      # Get electricity amount and target month for the suffix
      electricity_amount = config[:el].to_i
      target_month = month - 1
      target_year = year
      if target_month < 1
        target_month = 12
        target_year -= 1
      end

      # Swedish month names
      swedish_months = [
        nil, 'januari', 'februari', 'mars', 'april', 'maj', 'juni',
        'juli', 'augusti', 'september', 'oktober', 'november', 'december'
      ]
      target_month_name = swedish_months[target_month]

      # Calculate heating cost impact using shared module
      heating_cost_data = calculate_heating_cost_for_period(
        config_year: year,
        config_month: month,
        roommates: roommates
      )

      # Calculate virtual pot status for savings tracking
      virtual_pot_data = calculate_virtual_pot_status(year: year, month: month)

      result = {
        message: friendly_text,
        year: year,
        month: month,
        generated_at: Time.now.utc.iso8601,
        data_source: data_source,
        electricity_amount: electricity_amount,
        electricity_month: target_month_name,
        heating_cost_line: heating_cost_data[:line],
        quarterly_invoice_projection: @drift_rakning_is_projection || false,
        drift_rakning_amount: config[:drift_rakning]&.to_i,
        virtual_pot: virtual_pot_data
      }

      [200, { 'Content-Type' => 'application/json' }, [result.to_json]]

    rescue => e
      puts "Error generating friendly message: #{e.message}"
      puts e.backtrace
      [500, { 'Content-Type' => 'application/json' }, [{ error: e.message }.to_json]]
    end
  end

  private

  def determine_electricity_data_source(config, year, month)
    el_cost = config[:el]
    default_el_cost = RentCalculator::Config::DEFAULTS[:el]

    # Check if using defaults (fallback)
    if el_cost == default_el_cost
      return {
        type: 'defaults',
        electricity_source: 'fallback_defaults',
        description_sv: 'Baserad på uppskattade elkostnader'
      }
    end

    # FIRST: Check if actual ElectricityBill records exist for this period
    # This prevents misclassifying actual bills as "historical projection"
    # when ElectricityProjector returns them (Bug fix: Nov 21, 2025)
    target_period = Date.new(year, month, 1)
    actual_bills = Persistence.electricity_bills.find_by_period(target_period)

    if actual_bills.any?
      return {
        type: 'actual',
        electricity_source: 'current_bills',
        description_sv: 'Baserad på aktuella elräkningar'
      }
    end

    # No actual bills exist - check if using historical projection
    historical_cost = get_historical_electricity_cost(year: year, month: month)
    if historical_cost > 0 && el_cost.to_i == historical_cost.to_i
      return {
        type: 'historical',
        electricity_source: 'historical_lookup',
        description_sv: 'Baserad på prognos från förra årets elräkningar'
      }
    end

    # If historical lookup failed (returned 0), it's a manual projection
    if historical_cost == 0
      return {
        type: 'projection',
        electricity_source: 'manual_projection',
        description_sv: 'Baserad på uppskattad prognos'
      }
    end

    # Otherwise, assume it's from manually entered current bills
    return {
      type: 'actual',
      electricity_source: 'current_bills',
      description_sv: 'Baserad på aktuella elräkningar'
    }
  end

  # Calculate heating cost impact for the given period
  #
  # @param config_year [Integer] Configuration year
  # @param config_month [Integer] Configuration month
  # @param roommates [Hash] Roommates hash from extract_roommates
  # @return [Hash] Heating cost data with :line key
  def calculate_heating_cost_for_period(config_year:, config_month:, roommates:)
    # Get electricity projection for the period
    monthly_cost = HeatingCostCalculator.get_electricity_projection(
      year: config_year,
      month: config_month
    )

    # Count active roommates
    active_roommates = roommates.keys.count
    active_roommates = 4 if active_roommates == 0 # Fallback

    # Calculate heating costs
    HeatingCostCalculator.calculate(
      base_monthly_cost: monthly_cost,
      active_roommates: active_roommates
    )
  end

  # Calculate virtual pot status for both building operations and gas
  #
  # @param year [Integer] Configuration year
  # @param month [Integer] Configuration month
  # @return [Hash] Virtual pot data with :building_ops and :gas keys
  def calculate_virtual_pot_status(year:, month:)
    {
      building_ops: calculate_building_ops_pot(year, month),
      gas: calculate_gas_pot(year, month)
    }
  end

  # Calculate building operations pot status
  #
  # @param year [Integer] Configuration year
  # @param month [Integer] Configuration month
  # @return [Hash] Pot status with next invoice projection and current balance
  def calculate_building_ops_pot(year, month)
    # Find last invoice date from database
    last_invoice = find_last_quarterly_invoice(year, month)

    # Calculate months since last invoice
    current_date = Date.new(year, month, 1)
    months_since = calculate_months_between(last_invoice[:date], current_date)

    # Virtual pot balance = months × 754 kr
    pot_balance = months_since * 754.0

    # Find next quarterly month (Apr/Jul/Oct)
    quarterly_months = [4, 7, 10]
    next_year = year
    next_month = nil

    # Try months in current year after current month
    quarterly_months.each do |qm|
      if qm > month
        next_month = qm
        break
      end
    end

    # If no upcoming month in current year, use April next year
    if next_month.nil?
      next_month = 4
      next_year += 1
    end

    # Calculate projection for next invoice
    next_amount_data = QuarterlyInvoiceProjector.calculate_projection(
      year: next_year,
      month: next_month
    )

    # Days until next invoice
    next_date = Date.new(next_year, next_month, 15)
    days_until = (next_date - current_date).to_i

    {
      next_invoice_date: next_date.to_s,
      next_invoice_amount: next_amount_data[:amount],
      days_until: days_until,
      pot_balance: pot_balance.round,
      shortfall: [next_amount_data[:amount] - pot_balance, 0].max.round
    }
  end

  # Calculate gas pot status
  #
  # @param year [Integer] Configuration year
  # @param month [Integer] Configuration month
  # @return [Hash] Pot status with next refill projection and current balance
  def calculate_gas_pot(year, month)
    # Simple baseline for now (6-month cycle)
    # Assume last refill: Jan 2025, next refill: Jul 2025, then Jan 2026, etc.
    base_refill_date = Date.new(2025, 1, 15)
    current_date = Date.new(year, month, 1)

    # Find next refill date (6-month intervals)
    months_since_base = (current_date.year - base_refill_date.year) * 12 +
                        (current_date.month - base_refill_date.month)
    cycles_passed = (months_since_base / 6).floor
    next_refill_date = base_refill_date >> ((cycles_passed + 1) * 6)

    # Months since last refill
    last_refill_date = base_refill_date >> (cycles_passed * 6)
    months_in_cycle = (current_date.year - last_refill_date.year) * 12 +
                      (current_date.month - last_refill_date.month)

    # Virtual pot balance = months × 83 kr
    pot_balance = months_in_cycle * 83.0

    # Days until next refill
    days_until = (next_refill_date - current_date).to_i

    {
      next_refill_date: next_refill_date.to_s,
      next_refill_amount: 500,
      days_until: days_until,
      pot_balance: pot_balance.round,
      shortfall: [500 - pot_balance, 0].max.round
    }
  end

  # Find the most recent quarterly invoice from database
  #
  # @param year [Integer] Configuration year
  # @param month [Integer] Configuration month
  # @return [Hash] Last invoice with :date and :amount keys
  def find_last_quarterly_invoice(year, month)
    repo = Persistence.rent_configs

    # Look back up to 12 months for last drift_rakning entry (check recent months FIRST)
    0.upto(12) do |months_back|
      check_date = Date.new(year, month, 1) << months_back
      config = repo.find_by_key_and_period('drift_rakning',
                                           Time.utc(check_date.year, check_date.month, 1))
      if config && config.value.to_f > 0
        return {
          date: check_date,
          amount: config.value.to_f
        }
      end
    end

    # Default: assume October 2024 if nothing found
    { date: Date.new(2024, 10, 1), amount: 2612 }
  end

  # Calculate number of months between two dates
  #
  # @param start_date [Date] Start date
  # @param end_date [Date] End date
  # @return [Integer] Number of months between dates
  def calculate_months_between(start_date, end_date)
    (end_date.year - start_date.year) * 12 + (end_date.month - start_date.month)
  end
end 

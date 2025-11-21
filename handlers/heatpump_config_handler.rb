require 'rack/request'
require 'oj'
require_relative '../lib/persistence'
require_relative '../lib/models/heatpump_config'
require_relative '../lib/admin_auth'

# Handles GET/PUT requests for heatpump configuration
class HeatpumpConfigHandler
  def call(env)
    request = Rack::Request.new(env)
    method = request.request_method

    case method
    when 'GET'
      handle_get
    when 'PUT'
      handle_put(request)
    else
      [405, { 'Content-Type' => 'application/json' }, [Oj.dump({ error: 'Method not allowed' })]]
    end
  rescue StandardError => e
    puts "Error in HeatpumpConfigHandler: #{e.message}"
    puts e.backtrace.join("\n")
    [500, { 'Content-Type' => 'application/json' }, [Oj.dump({ error: 'Internal server error' })]]
  end

  private

  def handle_get
    config = Persistence.heatpump_config.get_current

    response = {
      'id' => config.id,
      'hours_on' => config.hours_on,
      'emergency_temp_offset' => config.emergency_temp_offset,
      'min_hotwater' => config.min_hotwater,
      'created_at' => config.created_at.iso8601,
      'updated_at' => config.updated_at.iso8601
    }

    [200, { 'Content-Type' => 'application/json' }, [Oj.dump(response)]]
  end

  def handle_put(request)
    if (auth_error = require_admin_token(request))
      return auth_error
    end

    body = request.body.read
    params = Oj.load(body, symbol_keys: true)

    # Get current config to obtain ID
    current_config = Persistence.heatpump_config.get_current

    # Extract update parameters (only include provided fields)
    update_params = {}
    update_params[:hours_on] = params[:hours_on].to_i if params[:hours_on]
    update_params[:emergency_temp_offset] = params[:emergency_temp_offset].to_f if params[:emergency_temp_offset]
    update_params[:min_hotwater] = params[:min_hotwater].to_f if params[:min_hotwater]

    # Validate parameters
    errors = HeatpumpConfig.validate(update_params)

    unless errors.empty?
      return [400, { 'Content-Type' => 'application/json' }, [Oj.dump({ errors: errors })]]
    end

    # Update configuration
    updated_config = Persistence.heatpump_config.update(current_config.id, update_params)

    response = {
      'id' => updated_config.id,
      'hours_on' => updated_config.hours_on,
      'emergency_temp_offset' => updated_config.emergency_temp_offset,
      'min_hotwater' => updated_config.min_hotwater,
      'created_at' => updated_config.created_at.iso8601,
      'updated_at' => updated_config.updated_at.iso8601
    }

    [200, { 'Content-Type' => 'application/json' }, [Oj.dump(response)]]
  end

  def require_admin_token(request)
    token = request.get_header('HTTP_X_ADMIN_TOKEN')
    return nil if AdminAuth.authorized?(token)

    [
      401,
      { 'Content-Type' => 'application/json' },
      [Oj.dump({ error: 'Admin PIN krävs för denna åtgärd' })]
    ]
  end
end

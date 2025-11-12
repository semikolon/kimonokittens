# Handler for tenant management API
# Create tenants with or without contracts
require 'json'
require_relative '../lib/persistence'
require_relative '../lib/models/tenant'
require_relative '../lib/contract_signer'
require_relative '../lib/data_broadcaster'
require_relative '../lib/admin_auth'

class TenantHandler
  def call(env)
    req = Rack::Request.new(env)

    case req.path_info
    when '', '/'
      if req.post?
        create_tenant(req)
      elsif req.get?
        list_tenants
      else
        method_not_allowed
      end
    when '/with-contract'
      if req.post?
        create_tenant_with_contract(req)
      else
        method_not_allowed
      end
    else
      not_found
    end
  rescue StandardError => e
    error_response(e.message, 500)
  end

  private

  def create_tenant(req)
    if (auth_error = require_admin_token(req))
      return auth_error
    end

    body = req.body.read
    data = JSON.parse(body)

    # Validate required fields
    return error_response('Name is required', 400) unless data['name']
    return error_response('Email is required', 400) unless data['email']
    return error_response('Invalid email format', 400) unless data['email'].include?('@')

    # Check for duplicate email
    repo = Persistence.tenants
    existing = repo.find_by_email(data['email'])
    return error_response("Email already exists: #{data['email']}", 409) if existing

    # Create tenant
    tenant = Tenant.new(
      name: data['name'],
      email: data['email'],
      personnummer: data['personnummer'],
      phone: data['phone'],
      start_date: data['startDate'] ? Date.parse(data['startDate']) : nil,
      departure_date: data['departureDate'] && !data['departureDate'].empty? ? Date.parse(data['departureDate']) : nil,
      room_adjustment: 0.0
    )

    created = repo.create(tenant)

    # Broadcast update to WebSocket clients (triggers admin dashboard refresh)
    DataBroadcaster.broadcast_contract_list_changed

    success_response({
      id: created.id,
      name: created.name,
      email: created.email,
      personnummer: created.personnummer,
      phone: created.phone,
      startDate: created.start_date&.iso8601,
      departureDate: created.departure_date&.iso8601,
      createdAt: created.created_at.iso8601
    }, 201)
  end

  def create_tenant_with_contract(req)
    if (auth_error = require_admin_token(req))
      return auth_error
    end

    body = req.body.read
    data = JSON.parse(body)

    # Validate required fields for contract creation
    return error_response('Name is required', 400) unless data['name']
    return error_response('Email is required', 400) unless data['email']
    return error_response('Invalid email format', 400) unless data['email'].include?('@')
    return error_response('Start date is required for contract', 400) unless data['startDate']
    return error_response('Personnummer is required for contract', 400) unless data['personnummer']

    # Check for duplicate email
    repo = Persistence.tenants
    existing = repo.find_by_email(data['email'])
    return error_response("Email already exists: #{data['email']}", 409) if existing

    # Create tenant
    tenant = Tenant.new(
      name: data['name'],
      email: data['email'],
      personnummer: data['personnummer'],
      phone: data['phone'],
      start_date: Date.parse(data['startDate']),
      departure_date: data['departureDate'] && !data['departureDate'].empty? ? Date.parse(data['departureDate']) : nil,
      room_adjustment: 0.0
    )

    created_tenant = repo.create(tenant)

    # Generate and send contract
    # Note: Using test_mode=true and send_emails=false for development
    # In production, these should be configurable via environment variables
    contract_result = ContractSigner.create_and_send(
      tenant_id: created_tenant.id,
      test_mode: ENV['CONTRACT_TEST_MODE'] != 'false', # Default to test mode unless explicitly disabled
      send_emails: ENV['CONTRACT_SEND_EMAILS'] == 'true' # Default to no emails unless explicitly enabled
    )

    # Broadcast update to WebSocket clients (triggers admin dashboard refresh)
    DataBroadcaster.broadcast_contract_list_changed

    success_response({
      tenant: {
        id: created_tenant.id,
        name: created_tenant.name,
        email: created_tenant.email,
        personnummer: created_tenant.personnummer,
        phone: created_tenant.phone,
        startDate: created_tenant.start_date&.iso8601,
        departureDate: created_tenant.departure_date&.iso8601,
        createdAt: created_tenant.created_at.iso8601
      },
      contract: {
        pdf_path: contract_result[:pdf_path],
        case_id: contract_result[:case_id],
        landlord_link: contract_result[:landlord_link],
        tenant_link: contract_result[:tenant_link]
      }
    }, 201)
  end

  def list_tenants
    repo = Persistence.tenants
    tenants = repo.all

    success_response({
      tenants: tenants.map { |t|
        {
          id: t.id,
          name: t.name,
          email: t.email,
          personnummer: t.personnummer,
          phone: t.phone,
          startDate: t.start_date&.iso8601,
          departureDate: t.departure_date&.iso8601,
          roomAdjustment: t.room_adjustment
        }
      }
    })
  end

  def success_response(data, status = 200)
    [
      status,
      { 'Content-Type' => 'application/json' },
      [JSON.generate(data)]
    ]
  end

  def error_response(message, status = 400)
    [
      status,
      { 'Content-Type' => 'application/json' },
      [JSON.generate({ error: message })]
    ]
  end

  def require_admin_token(req)
    token = req.get_header('HTTP_X_ADMIN_TOKEN')
    return nil if AdminAuth.authorized?(token)

    [
      401,
      { 'Content-Type' => 'application/json' },
      [JSON.generate({ error: 'Admin PIN krävs för denna åtgärd' })]
    ]
  end

  def method_not_allowed
    [
      405,
      { 'Content-Type' => 'application/json' },
      [JSON.generate({ error: 'Method not allowed' })]
    ]
  end

  def not_found
    [
      404,
      { 'Content-Type' => 'application/json' },
      [JSON.generate({ error: 'Not found' })]
    ]
  end
end

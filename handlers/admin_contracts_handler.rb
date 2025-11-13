# Handler for admin contract management API
# Serves contract list with full lifecycle details for admin dashboard
class AdminContractsHandler
  def initialize
    require_relative '../lib/persistence'
    require_relative '../rent'
    require_relative '../lib/models/rent_config'
    require_relative '../lib/admin_auth'
    require_relative '../lib/landlord_profile'
  end

  def call(env)
    req = Rack::Request.new(env)

    case req.path_info
    when '', '/'
      if req.get?
        list_contracts(req)
      else
        method_not_allowed
      end
    when '/statistics'
      if req.get?
        get_statistics
      else
        method_not_allowed
      end
    else
      # Handle contract-specific actions: /contracts/:id/action
      if req.path_info =~ %r{^/contracts/([a-z0-9\-]+)/resend-email$}
        contract_id = $1
        if req.post?
          resend_email(req, contract_id)
        else
          method_not_allowed
        end
      elsif req.path_info =~ %r{^/contracts/([a-z0-9\-]+)/cancel$}
        contract_id = $1
        if req.post?
          cancel_contract(req, contract_id)
        else
          method_not_allowed
        end
      elsif req.path_info =~ %r{^/tenants/([a-z0-9\-]+)/departure-date$}
        tenant_id = $1
        if req.patch?
          set_tenant_departure_date(req, tenant_id)
        else
          method_not_allowed
        end
      elsif req.path_info =~ %r{^/tenants/([a-z0-9\-]+)/room$}
        tenant_id = $1
        if req.patch?
          set_tenant_room(req, tenant_id)
        else
          method_not_allowed
        end
      elsif req.path_info =~ %r{^/tenants/([a-z0-9\-]+)/create-contract$}
        tenant_id = $1
        if req.post?
          create_contract_for_tenant(req, tenant_id)
        else
          method_not_allowed
        end
      else
        not_found
      end
    end
  end

  private

  def list_contracts(req)
    landlord_profile = LandlordProfile.info

    # Fetch all data
    contract_repo = Persistence.signed_contracts
    tenant_repo = Persistence.tenants
    participant_repo = Persistence.contract_participants

    # Get all tenants
    all_tenants = tenant_repo.all

    # Calculate current rent ONCE for all active tenants (optimization: 10 queries instead of 80)
    now = Time.now
    year = now.year
    month = now.month

    # Build roommates hash for current period
    period_start = Date.new(year, month, 1)
    period_end = Date.new(year, month, RentCalculator::Helpers.days_in_month(year, month))

    roommates = {}
    all_tenants.each do |tenant|
      days_stayed = tenant.days_stayed_in_period(period_start, period_end)
      next if days_stayed <= 0

      roommates[tenant.name] = {
        days: days_stayed,
        room_adjustment: (tenant.room_adjustment || 0).to_i
      }
    end

    # Get config and calculate rent breakdown once
    # Projection is handled automatically by rent_breakdown_for_period
    rent_breakdown = if roommates.any?
      breakdown = RentCalculator.rent_breakdown_for_period(year: year, month: month)
      puts "DEBUG admin_contracts: rent_breakdown = #{breakdown.inspect}"
      breakdown
    else
      puts "DEBUG admin_contracts: No active roommates for period #{year}-#{month}"
      {}
    end

    # Get all contracts ordered by creation date (newest first)
    contracts = RentDb.instance.class.db[:SignedContract]
      .order(Sequel.desc(:createdAt))
      .all

    # Track which tenants have contracts
    tenant_ids_with_contracts = contracts.map { |c| c[:tenantId] }.to_set

    # Build enriched member list:
    # 1. Contracts (with tenant data merged in)
    # 2. Tenants without contracts
    members = []

    # Add contracts with full tenant data
    contracts.each do |contract|
      tenant = tenant_repo.find_by_id(contract[:tenantId])
      participants = participant_repo.find_by_contract_id(contract[:id])

      members << {
        type: 'contract',
        id: contract[:id],
        tenant_id: contract[:tenantId],
        tenant_name: tenant&.name || 'Unknown',
        tenant_email: tenant&.email,
        tenant_personnummer: tenant&.personnummer,
        tenant_room: tenant&.room,
        tenant_room_adjustment: tenant&.room_adjustment,
        tenant_start_date: tenant&.start_date,
        tenant_departure_date: tenant&.departure_date,
        tenant_deposit: tenant&.deposit,
        tenant_furnishing_deposit: tenant&.furnishing_deposit,
        current_rent: tenant ? (rent_breakdown.dig("rents", tenant.name) || 0) : 0,
        case_id: contract[:caseId],
        pdf_url: contract[:pdfUrl],
        status: contract[:status],
        landlord_signed: contract[:landlordSigned],
        landlord_email: landlord_profile[:email],
        landlord_name: landlord_profile[:name],
        landlord_personnummer: landlord_profile[:personnummer],
        tenant_signed: contract[:tenantSigned],
        landlord_signed_at: contract[:landlordSignedAt],
        tenant_signed_at: contract[:tenantSignedAt],
        landlord_signing_url: contract[:landlordSigningUrl],
        tenant_signing_url: contract[:tenantSigningUrl],
        test_mode: contract[:testMode],
        completed_at: contract[:completedAt],
        expires_at: contract[:expiresAt],
        created_at: contract[:createdAt],
        updated_at: contract[:updatedAt],
        # Lifecycle tracking
        generation_status: contract[:generationStatus],
        generation_started_at: contract[:generationStartedAt],
        generation_completed_at: contract[:generationCompletedAt],
        generation_failed_at: contract[:generationFailedAt],
        generation_error: contract[:generationError],
        validation_status: contract[:validationStatus],
        validation_started_at: contract[:validationStartedAt],
        validation_completed_at: contract[:validationCompletedAt],
        validation_failed_at: contract[:validationFailedAt],
        validation_errors: contract[:validationErrors],
        email_delivery_status: contract[:emailDeliveryStatus],
        landlord_email_delivered: contract[:landlordEmailDelivered],
        tenant_email_delivered: contract[:tenantEmailDelivered],
        email_delivery_failed_at: contract[:emailDeliveryFailedAt],
        email_delivery_error: contract[:emailDeliveryError],
        # Participants
        participants: participants.map do |p|
          {
            id: p.id,
            name: p.name,
            email: p.email,
            role: p.role,
            status: p.status,
            signed_at: p.signed_at,
            signing_url: p.signing_url,
            email_delivered: p.email_delivered,
            email_delivered_at: p.email_delivered_at
          }
        end
      }
    end

    # Add tenants without contracts
    all_tenants.each do |tenant|
      next if tenant_ids_with_contracts.include?(tenant.id)

      members << {
        type: 'tenant',
        id: tenant.id,
        tenant_id: tenant.id,
        tenant_name: tenant.name,
        tenant_email: tenant.email,
        tenant_room: tenant.room,
        tenant_room_adjustment: tenant.room_adjustment,
        tenant_start_date: tenant.start_date,
        tenant_departure_date: tenant.departure_date,
        tenant_deposit: tenant.deposit,
        tenant_furnishing_deposit: tenant.furnishing_deposit,
        current_rent: rent_breakdown.dig("rents", tenant.name) || 0,
        status: tenant.status || 'active',
        created_at: tenant.created_at
      }
    end

    # Sort members by start date (newest first), nil dates go to end
    members.sort_by! do |m|
      start_date = m[:tenant_start_date]
      start_date ? -start_date.to_time.to_i : 0
    end

    # Get statistics
    stats = contract_repo.statistics

    [
      200,
      { 'Content-Type' => 'application/json' },
      [Oj.dump({
        'members' => members,
        'total' => members.length,
        'contracts_count' => contracts.length,
        'tenants_without_contracts' => members.count { |m| m[:type] == 'tenant' },
        'statistics' => stats
      }, mode: :compat)]
    ]
  rescue => e
    puts "❌ Error fetching members: #{e.message}"
    puts e.backtrace.first(5)
    internal_error(e.message)
  end

  def get_statistics
    contract_repo = Persistence.signed_contracts
    stats = contract_repo.statistics

    [
      200,
      { 'Content-Type' => 'application/json' },
      [Oj.dump(stats, mode: :compat)]
    ]
  rescue => e
    puts "❌ Error fetching statistics: #{e.message}"
    internal_error(e.message)
  end

  def resend_email(req, contract_id)
    if (auth_error = require_admin_token(req))
      return auth_error
    end

    # Find contract
    contract_repo = Persistence.signed_contracts
    contract = contract_repo.find_by_id(contract_id)

    unless contract
      return [404, { 'Content-Type' => 'application/json' }, [Oj.dump({ error: 'Contract not found' })]]
    end

    # Check if contract is in a state where reminders make sense
    if contract.status == 'completed'
      return [400, { 'Content-Type' => 'application/json' }, [Oj.dump({ error: 'Cannot send reminder for completed contract' })]]
    end

    if contract.status == 'cancelled'
      return [400, { 'Content-Type' => 'application/json' }, [Oj.dump({ error: 'Cannot send reminder for cancelled contract' })]]
    end

    if contract.status == 'expired'
      return [400, { 'Content-Type' => 'application/json' }, [Oj.dump({ error: 'Cannot send reminder for expired contract' })]]
    end

    # Send reminder via Zigned API
    require_relative '../lib/zigned_client_v3'
    client = ZignedClientV3.new(
      client_id: ENV['ZIGNED_CLIENT_ID'],
      client_secret: ENV['ZIGNED_API_KEY'],
      test_mode: contract.test_mode
    )

    begin
      result = client.send_reminder(contract.case_id)

      [
        200,
        { 'Content-Type' => 'application/json' },
        [Oj.dump({
          success: true,
          message: 'Reminder sent successfully',
          reminders: result
        }, mode: :compat)]
      ]
    rescue => e
      puts "❌ Error sending reminder: #{e.message}"
      [
        500,
        { 'Content-Type' => 'application/json' },
        [Oj.dump({ error: "Failed to send reminder: #{e.message}" })]
      ]
    end
  end

  def cancel_contract(req, contract_id)
    if (auth_error = require_admin_token(req))
      return auth_error
    end

    # Find contract
    contract_repo = Persistence.signed_contracts
    contract = contract_repo.find_by_id(contract_id)

    unless contract
      return [404, { 'Content-Type' => 'application/json' }, [Oj.dump({ error: 'Contract not found' })]]
    end

    # Check if contract is in a state where cancellation makes sense
    if contract.status == 'completed'
      return [400, { 'Content-Type' => 'application/json' }, [Oj.dump({ error: 'Cannot cancel completed contract' })]]
    end

    if contract.status == 'cancelled'
      return [400, { 'Content-Type' => 'application/json' }, [Oj.dump({ error: 'Contract already cancelled' })]]
    end

    # Cancel via Zigned API
    require_relative '../lib/zigned_client_v3'
    client = ZignedClientV3.new(
      client_id: ENV['ZIGNED_CLIENT_ID'],
      client_secret: ENV['ZIGNED_API_KEY'],
      test_mode: contract.test_mode
    )

    begin
      success = client.cancel_agreement(contract.case_id)

      if success
        # Update contract status in database
        contract_repo.update(contract_id, { status: 'cancelled' })

        # Broadcast update to WebSocket clients (triggers admin dashboard refresh)
        require_relative '../lib/data_broadcaster'
        DataBroadcaster.broadcast_contract_list_changed

        [
          200,
          { 'Content-Type' => 'application/json' },
          [Oj.dump({
            success: true,
            message: 'Contract cancelled successfully'
          }, mode: :compat)]
        ]
      else
        [
          500,
          { 'Content-Type' => 'application/json' },
          [Oj.dump({ error: 'Failed to cancel contract' })]
        ]
      end
    rescue => e
      puts "❌ Error cancelling contract: #{e.message}"
      [
        500,
        { 'Content-Type' => 'application/json' },
        [Oj.dump({ error: "Failed to cancel contract: #{e.message}" })]
      ]
    end
  end

  def set_tenant_departure_date(req, tenant_id)
    if (auth_error = require_admin_token(req))
      return auth_error
    end

    # Parse JSON body
    begin
      body = Oj.load(req.body.read)
      date_string = body['date']

      unless date_string
        return [400, { 'Content-Type' => 'application/json' }, [Oj.dump({ error: 'Missing date parameter' })]]
      end

      # Parse date
      departure_date = Date.parse(date_string)
    rescue Oj::ParseError => e
      return [400, { 'Content-Type' => 'application/json' }, [Oj.dump({ error: 'Invalid JSON body' })]]
    rescue ArgumentError => e
      return [400, { 'Content-Type' => 'application/json' }, [Oj.dump({ error: "Invalid date format: #{e.message}" })]]
    end

    # Find tenant
    tenant_repo = Persistence.tenants
    tenant = tenant_repo.find_by_id(tenant_id)

    unless tenant
      return [404, { 'Content-Type' => 'application/json' }, [Oj.dump({ error: 'Tenant not found' })]]
    end

    # Update departure date
    begin
      success = tenant_repo.set_departure_date(tenant_id, departure_date)

      if success
        # Broadcast update to WebSocket clients
        require_relative '../lib/data_broadcaster'
        DataBroadcaster.broadcast_contract_list_changed

        [
          200,
          { 'Content-Type' => 'application/json' },
          [Oj.dump({
            success: true,
            message: 'Departure date updated successfully',
            tenant_id: tenant_id,
            departure_date: departure_date.to_s
          }, mode: :compat)]
        ]
      else
        [
          500,
          { 'Content-Type' => 'application/json' },
          [Oj.dump({ error: 'Failed to update departure date' })]
        ]
      end
    rescue => e
      puts "❌ Error updating departure date: #{e.message}"
      [
        500,
        { 'Content-Type' => 'application/json' },
        [Oj.dump({ error: "Failed to update departure date: #{e.message}" })]
      ]
    end
  end

  def set_tenant_room(req, tenant_id)
    if (auth_error = require_admin_token(req))
      return auth_error
    end

    begin
      body = Oj.load(req.body.read)
      room = body['room']&.to_s
      unless room && !room.strip.empty?
        return [400, { 'Content-Type' => 'application/json' }, [Oj.dump({ error: 'Missing room parameter' })]]
      end
    rescue Oj::ParseError
      return [400, { 'Content-Type' => 'application/json' }, [Oj.dump({ error: 'Invalid JSON body' })]]
    end

    tenant_repo = Persistence.tenants
    tenant = tenant_repo.find_by_id(tenant_id)
    unless tenant
      return [404, { 'Content-Type' => 'application/json' }, [Oj.dump({ error: 'Tenant not found' })]]
    end

    begin
      tenant.room = room.strip
      tenant_repo.update(tenant)
      require_relative '../lib/data_broadcaster'
      DataBroadcaster.broadcast_contract_list_changed

      [
        200,
        { 'Content-Type' => 'application/json' },
        [Oj.dump({ success: true, tenant_id: tenant_id, room: tenant.room })]
      ]
    rescue => e
      [
        500,
        { 'Content-Type' => 'application/json' },
        [Oj.dump({ error: "Failed to update room: #{e.message}" })]
      ]
    end
  end

  def create_contract_for_tenant(req, tenant_id)
    if (auth_error = require_admin_token(req))
      return auth_error
    end

    # Find tenant
    tenant_repo = Persistence.tenants
    tenant = tenant_repo.find_by_id(tenant_id)

    unless tenant
      return [404, { 'Content-Type' => 'application/json' }, [Oj.dump({ error: 'Tenant not found' })]]
    end

    # Validate tenant has required fields for contract
    unless tenant.name && tenant.email && tenant.personnummer && tenant.start_date
      return [400, { 'Content-Type' => 'application/json' }, [Oj.dump({
        error: 'Tenant missing required fields (name, email, personnummer, start_date)'
      })]]
    end

    # Check if tenant already has a contract
    contract_repo = Persistence.signed_contracts
    existing = contract_repo.find_by_tenant_id(tenant_id)
    if existing.any?
      return [409, { 'Content-Type' => 'application/json' }, [Oj.dump({
        error: 'Tenant already has a contract'
      })]]
    end

    # Generate and send contract
    begin
      require_relative '../lib/contract_signer'
      contract_result = ContractSigner.create_and_send(
        tenant_id: tenant_id,
        test_mode: ENV['CONTRACT_TEST_MODE'] != 'false',
        send_emails: ENV['CONTRACT_SEND_EMAILS'] == 'true'
      )

      # Broadcast update to WebSocket clients (triggers admin dashboard refresh)
      require_relative '../lib/data_broadcaster'
      DataBroadcaster.broadcast_contract_list_changed

      [
        201,
        { 'Content-Type' => 'application/json' },
        [Oj.dump({
          success: true,
          message: 'Contract created successfully',
          contract: {
            pdf_path: contract_result[:pdf_path],
            case_id: contract_result[:case_id],
            landlord_link: contract_result[:landlord_link],
            tenant_link: contract_result[:tenant_link]
          }
        }, mode: :compat)]
      ]
    rescue => e
      puts "❌ Error creating contract: #{e.message}"
      puts e.backtrace.first(5)
      [
        500,
        { 'Content-Type' => 'application/json' },
        [Oj.dump({ error: "Failed to create contract: #{e.message}" })]
      ]
    end
  end

  def not_found
    [404, { 'Content-Type' => 'application/json' }, [Oj.dump({ error: 'Not found' })]]
  end

  def method_not_allowed
    [405, { 'Content-Type' => 'application/json' }, [Oj.dump({ error: 'Method not allowed' })]]
  end

  def internal_error(message)
    [500, { 'Content-Type' => 'application/json' }, [Oj.dump({ error: message })]]
  end

  def require_admin_token(req)
    token = req.get_header('HTTP_X_ADMIN_TOKEN')
    return nil if AdminAuth.authorized?(token)

    [
      401,
      { 'Content-Type' => 'application/json' },
      [Oj.dump({ error: 'Admin PIN krävs för denna åtgärd' })]
    ]
  end
end

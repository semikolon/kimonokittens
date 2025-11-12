# Handler for admin contract management API
# Serves contract list with full lifecycle details for admin dashboard
class AdminContractsHandler
  def initialize
    require_relative '../lib/persistence'
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
      else
        not_found
      end
    end
  end

  private

  def list_contracts(req)
    # Fetch all data
    contract_repo = Persistence.signed_contracts
    tenant_repo = Persistence.tenants
    participant_repo = Persistence.contract_participants

    # Get all tenants
    all_tenants = tenant_repo.all

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
        tenant_room: tenant&.room,
        tenant_room_adjustment: tenant&.room_adjustment,
        tenant_start_date: tenant&.start_date,
        tenant_departure_date: tenant&.departure_date,
        case_id: contract[:caseId],
        pdf_url: contract[:pdfUrl],
        status: contract[:status],
        landlord_signed: contract[:landlordSigned],
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

  def not_found
    [404, { 'Content-Type' => 'application/json' }, [Oj.dump({ error: 'Not found' })]]
  end

  def method_not_allowed
    [405, { 'Content-Type' => 'application/json' }, [Oj.dump({ error: 'Method not allowed' })]]
  end

  def internal_error(message)
    [500, { 'Content-Type' => 'application/json' }, [Oj.dump({ error: message })]]
  end
end

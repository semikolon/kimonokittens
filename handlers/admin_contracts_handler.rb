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
      not_found
    end
  end

  private

  def list_contracts(req)
    # Fetch all contracts
    contract_repo = Persistence.signed_contracts
    tenant_repo = Persistence.tenants
    participant_repo = Persistence.contract_participants

    # Get all contracts ordered by creation date (newest first)
    contracts = RentDb.instance.class.db[:SignedContract]
      .order(Sequel.desc(:createdAt))
      .all

    # Enrich with tenant names and participants
    enriched_contracts = contracts.map do |contract|
      # Get tenant name
      tenant = tenant_repo.find_by_id(contract[:tenantId])

      # Get participants for this contract
      participants = participant_repo.find_by_contract_id(contract[:id])

      {
        id: contract[:id],
        tenant_id: contract[:tenantId],
        tenant_name: tenant&.name || 'Unknown',
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

    # Get statistics
    stats = contract_repo.statistics

    [
      200,
      { 'Content-Type' => 'application/json' },
      [Oj.dump({
        'contracts' => enriched_contracts,
        'total' => stats[:total],
        'statistics' => stats
      }, mode: :compat)]
    ]
  rescue => e
    puts "❌ Error fetching contracts: #{e.message}"
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

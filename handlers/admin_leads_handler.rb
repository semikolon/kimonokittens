# Handler for admin lead management API
# Serves tenant lead list and actions for admin dashboard
class AdminLeadsHandler
  def initialize
    require 'json'
    require_relative '../lib/rent_db'
    require_relative '../lib/admin_auth'
    require_relative '../lib/persistence'
  end

  def call(env)
    req = Rack::Request.new(env)

    case req.path_info
    when '', '/'
      if req.get?
        list_leads(req)
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
      # Handle lead-specific actions: /leads/:id/action
      if req.path_info =~ %r{^/([a-z0-9\-]+)/notes$}
        lead_id = $1
        if req.patch?
          update_notes(req, lead_id)
        else
          method_not_allowed
        end
      elsif req.path_info =~ %r{^/([a-z0-9\-]+)/status$}
        lead_id = $1
        if req.patch?
          update_status(req, lead_id)
        else
          method_not_allowed
        end
      elsif req.path_info =~ %r{^/([a-z0-9\-]+)/convert$}
        lead_id = $1
        if req.post?
          convert_to_tenant(req, lead_id)
        else
          method_not_allowed
        end
      elsif req.path_info =~ %r{^/([a-z0-9\-]+)$}
        lead_id = $1
        if req.delete?
          delete_lead(req, lead_id)
        else
          method_not_allowed
        end
      else
        not_found
      end
    end
  end

  private

  def list_leads(req)
    db = RentDb.instance.class.db

    # Fetch all leads, newest first
    leads = db[:TenantLead]
      .order(Sequel.desc(:createdAt))
      .all

    # Transform to camelCase for frontend
    leads_json = leads.map do |lead|
      {
        id: lead[:id],
        name: lead[:name],
        email: lead[:email],
        facebookId: lead[:facebookId],
        phone: lead[:phone],
        contactMethod: lead[:contactMethod],
        moveInFlexibility: lead[:moveInFlexibility],
        moveInExtra: lead[:moveInExtra],
        motivation: lead[:motivation],
        status: lead[:status],
        adminNotes: lead[:adminNotes],
        source: lead[:source],
        createdAt: lead[:createdAt].iso8601,
        updatedAt: lead[:updatedAt].iso8601,
        convertedToTenantId: lead[:convertedToTenantId]
      }
    end

    # Wrap in object with leads array and total count (matches AdminLeadsData interface)
    response = {
      leads: leads_json,
      total: leads_json.length
    }

    [200, { 'Content-Type' => 'application/json' }, [response.to_json]]
  end

  def get_statistics
    db = RentDb.instance.class.db

    stats = {
      total: db[:TenantLead].count,
      by_status: {}
    }

    # Count by status
    db[:TenantLead]
      .group_and_count(:status)
      .each do |row|
        stats[:by_status][row[:status]] = row[:count]
      end

    [200, { 'Content-Type' => 'application/json' }, [stats.to_json]]
  end

  def update_notes(req, lead_id)
    return unauthorized unless AdminAuth.verify(req)

    data = JSON.parse(req.body.read)
    db = RentDb.instance.class.db

    # Update notes
    updated_count = db[:TenantLead]
      .where(id: lead_id)
      .update(
        adminNotes: data['admin_notes'],
        updatedAt: Time.now
      )

    return not_found if updated_count.zero?

    lead = db[:TenantLead].where(id: lead_id).first

    [200, { 'Content-Type' => 'application/json' }, [transform_lead(lead).to_json]]

  rescue JSON::ParserError
    bad_request(['Invalid JSON'])
  rescue StandardError => e
    puts "Update notes error: #{e.message}"
    internal_error
  end

  def update_status(req, lead_id)
    return unauthorized unless AdminAuth.verify(req)

    data = JSON.parse(req.body.read)
    new_status = data['status']

    # Validate status
    valid_statuses = %w[pending_review contacted interview_scheduled approved rejected converted]
    unless valid_statuses.include?(new_status)
      return bad_request(['Invalid status'])
    end

    db = RentDb.instance.class.db

    # Update status
    updated_count = db[:TenantLead]
      .where(id: lead_id)
      .update(
        status: new_status,
        updatedAt: Time.now
      )

    return not_found if updated_count.zero?

    lead = db[:TenantLead].where(id: lead_id).first

    [200, { 'Content-Type' => 'application/json' }, [transform_lead(lead).to_json]]

  rescue JSON::ParserError
    bad_request(['Invalid JSON'])
  rescue StandardError => e
    puts "Update status error: #{e.message}"
    internal_error
  end

  def convert_to_tenant(req, lead_id)
    return unauthorized unless AdminAuth.verify(req)

    db = RentDb.instance.class.db

    # Fetch lead
    lead = db[:TenantLead].where(id: lead_id).first
    return not_found if lead.nil?

    # Check if already converted
    if lead[:convertedToTenantId]
      return bad_request(['Lead already converted to tenant'])
    end

    # Create tenant from lead data
    tenant_id = SecureRandom.uuid
    now = Time.now

    # Determine which contact field to use for email
    email = if lead[:contactMethod] == 'email'
              lead[:email]
            else
              # For Facebook contact, we'll need to generate a placeholder email
              # or require it to be filled in separately
              nil
            end

    # Create tenant record
    tenant_repo = Persistence.tenants

    # For now, we'll create a basic tenant record
    # The admin can fill in other details (start_date, room, etc.) later
    db[:Tenant].insert(
      id: tenant_id,
      name: lead[:name],
      email: email || "#{lead[:name].downcase.gsub(/\s+/, '.')}@placeholder.local",
      facebookId: lead[:facebookId],
      phone: lead[:phone],
      createdAt: now,
      updatedAt: now,
      status: 'pending' # Not yet active - needs contract
    )

    # Update lead to mark as converted
    db[:TenantLead]
      .where(id: lead_id)
      .update(
        status: 'converted',
        convertedToTenantId: tenant_id,
        updatedAt: now
      )

    # Return updated lead
    updated_lead = db[:TenantLead].where(id: lead_id).first

    [200, { 'Content-Type' => 'application/json' },
     [{ success: true, tenant_id: tenant_id, lead: transform_lead(updated_lead) }.to_json]]

  rescue StandardError => e
    puts "Convert to tenant error: #{e.message}"
    puts e.backtrace.join("\n")
    internal_error
  end

  def delete_lead(req, lead_id)
    return unauthorized unless AdminAuth.verify(req)

    db = RentDb.instance.class.db

    deleted_count = db[:TenantLead]
      .where(id: lead_id)
      .delete

    return not_found if deleted_count.zero?

    [200, { 'Content-Type' => 'application/json' }, [{ success: true }.to_json]]

  rescue StandardError => e
    puts "Delete lead error: #{e.message}"
    internal_error
  end

  def transform_lead(lead)
    {
      id: lead[:id],
      name: lead[:name],
      email: lead[:email],
      facebookId: lead[:facebookId],
      phone: lead[:phone],
      contactMethod: lead[:contactMethod],
      moveInFlexibility: lead[:moveInFlexibility],
      moveInExtra: lead[:moveInExtra],
      motivation: lead[:motivation],
      status: lead[:status],
      adminNotes: lead[:adminNotes],
      source: lead[:source],
      createdAt: lead[:createdAt].iso8601,
      updatedAt: lead[:updatedAt].iso8601,
      convertedToTenantId: lead[:convertedToTenantId]
    }
  end

  def bad_request(errors)
    [400, { 'Content-Type' => 'application/json' },
     [{ error: errors.join(', '), errors: errors }.to_json]]
  end

  def unauthorized
    [401, { 'Content-Type' => 'application/json' },
     [{ error: 'Unauthorized' }.to_json]]
  end

  def not_found
    [404, { 'Content-Type' => 'application/json' },
     [{ error: 'Lead not found' }.to_json]]
  end

  def method_not_allowed
    [405, { 'Content-Type' => 'application/json' },
     [{ error: 'Method not allowed' }.to_json]]
  end

  def internal_error
    [500, { 'Content-Type' => 'application/json' },
     [{ error: 'Internal server error' }.to_json]]
  end
end

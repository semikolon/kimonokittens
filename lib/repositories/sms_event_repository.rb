require_relative 'base_repository'
require_relative '../models/sms_event'
require 'cuid'
require 'json'

# SmsEventRepository handles persistence for SMS events
#
# Provides:
# - CRUD operations via Sequel
# - Tenant-scoped queries
# - Failed SMS tracking
# - 46elks message ID lookups
# - Cost aggregation for periods
#
# Database table: SmsEvent
# Actual schema fields:
#   - id (String/CUID)
#   - tenantId (String, nullable)
#   - month (String, "YYYY-MM" for rent reminders)
#   - direction (String: "out", "in", "dlr")
#   - providerId (String, 46elks message ID)
#   - body (String, message text)
#   - parts (Integer, SMS part count)
#   - status (String: "sent", "delivered", "failed")
#   - meta (JSONB: type, tone, cost, timestamps, phone numbers)
#   - createdAt (DateTime)
class SmsEventRepository < BaseRepository
  def table_name
    :SmsEvent
  end

  # Get all SMS events
  # @param limit [Integer] Maximum number of results (default: 1000)
  # @return [Array<SmsEvent>] All events ordered by created_at descending
  def all(limit: 1000)
    dataset
      .order(Sequel.desc(:createdAt))
      .limit(limit)
      .map { |row| hydrate(row) }
  end

  # Find event by ID
  # @param id [String] Event ID
  # @return [SmsEvent, nil]
  def find_by_id(id)
    row = dataset.where(id: id).first
    row && hydrate(row)
  end

  # Find all events for a specific tenant
  # @param tenant_id [String] Tenant ID
  # @param limit [Integer] Maximum number of results (default: 50)
  # @return [Array<SmsEvent>] Events ordered by sent_at descending
  def find_by_tenant(tenant_id, limit: 50)
    dataset
      .where(tenantId: tenant_id)
      .order(Sequel.desc(:createdAt))
      .limit(limit)
      .map { |row| hydrate(row) }
  end

  # Find all failed SMS events
  # @param limit [Integer] Maximum number of results (default: 20)
  # @return [Array<SmsEvent>] Failed events ordered by sent_at descending
  def find_failed(limit: 20)
    dataset
      .where(status: 'failed')
      .order(Sequel.desc(:createdAt))
      .limit(limit)
      .map { |row| hydrate(row) }
  end

  # Find event by 46elks message ID
  # @param message_id [String] Elks message ID (for webhook deduplication)
  # @return [SmsEvent, nil]
  def find_by_elks_message_id(message_id)
    row = dataset.where(providerId: message_id).first
    row && hydrate(row)
  end

  # Alias for schema consistency
  alias find_by_provider_id find_by_elks_message_id

  # Save SMS event (create or update)
  # @param event [SmsEvent] Event to persist
  # @return [SmsEvent] Saved event with ID assigned
  def save(event)
    if event.id
      update(event)
    else
      create(event)
    end
  end

  # Update delivery status after webhook callback
  # @param event_id [String] Event ID (positional argument for backward compatibility)
  # @param status [String] New delivery status
  # @param delivered_at [Time, nil] Delivery timestamp (optional)
  # @param failure_reason [String, nil] Failure reason (optional)
  # @return [Boolean] True if updated
  def update_delivery_status(event_id, status:, delivered_at: nil, failure_reason: nil)
    # Fetch current meta to preserve existing data
    current = dataset.where(id: event_id).first
    return false unless current

    meta = parse_json(current[:meta]) || {}
    meta['delivered_at'] = delivered_at.iso8601(6) if delivered_at  # Keep microseconds
    meta['failure_reason'] = failure_reason if failure_reason

    updates = {
      status: status,
      meta: JSON.generate(meta)
    }

    dataset.where(id: event_id).update(updates) > 0
  end

  # Calculate total cost for SMS events in date range
  # @param start_date [Time] Period start
  # @param end_date [Time] Period end
  # @return [Integer] Total cost in 10,000ths (e.g., 11500 = 1.15 SEK)
  def total_cost_for_period(start_date:, end_date:)
    rows = dataset.where(createdAt: start_date..end_date).all

    rows.sum do |row|
      meta = parse_json(row[:meta])
      meta&.dig('cost')&.to_i || 0
    end
  end

  private

  # Create new event record
  # @param event [SmsEvent] Event to create
  # @return [SmsEvent] Event with ID assigned
  def create(event)
    id = dataset.insert(dehydrate(event))

    # Fetch the created row to get the full data including JSONB
    row = dataset.where(id: id).first
    hydrate(row)
  end

  # Update existing event
  # @param event [SmsEvent] Event to update
  # @return [SmsEvent] Updated event
  def update(event)
    raise ArgumentError, "Cannot update event without ID" unless event.id

    rows_affected = dataset.where(id: event.id).update(dehydrate(event).except(:id, :createdAt))

    raise "Update failed for event #{event.id}" if rows_affected == 0

    event
  end

  # Convert database row to domain object
  # @param row [Hash] Database row
  # @return [SmsEvent]
  def hydrate(row)
    meta = parse_json(row[:meta]) || {}

    # Extract legacy fields from meta for backward compatibility
    SmsEvent.new(
      id: row[:id],
      tenant_id: row[:tenantId],
      month: row[:month],  # Rent month in "YYYY-MM" format
      direction: row[:direction],
      provider_id: row[:providerId],
      body: row[:body],
      status: row[:status],
      meta: meta,
      created_at: normalize_time(row[:createdAt]),
      # Legacy fields extracted from meta
      phone_number: meta['to'] || meta['from'] || '',
      message_body: row[:body],
      sms_type: meta['type'] || 'reminder',
      tone: meta['tone'] || 'neutral',
      delivery_status: row[:status] || 'queued',
      elks_message_id: row[:providerId],
      cost: meta['cost'],
      sent_at: normalize_time(row[:createdAt]),
      delivered_at: meta['delivered_at'] ? Time.parse(meta['delivered_at']) : nil,
      failure_reason: meta['failure_reason']
    )
  end

  # Convert domain object to database hash
  # @param event [SmsEvent] Domain object
  # @return [Hash] Database columns
  def dehydrate(event)
    # Calculate SMS parts (160 chars per part)
    parts = (event.body.length / 160.0).ceil

    {
      id: event.id || generate_id,
      tenantId: event.tenant_id,
      month: event.month,  # Rent month in "YYYY-MM" format (e.g., "2025-11")
      direction: event.direction,
      providerId: event.provider_id,
      body: event.body,
      parts: parts,
      status: event.status,
      meta: JSON.generate(event.meta),
      createdAt: event.created_at || now_utc
    }
  end

  # Parse JSONB meta field
  # @param value [String, Hash, nil]
  # @return [Hash, nil]
  def parse_json(value)
    case value
    when String
      JSON.parse(value)
    when Hash
      value
    when nil
      nil
    else
      value
    end
  rescue JSON::ParserError
    nil
  end

  # Normalize time values from database
  # @param value [Time, String, nil]
  # @return [Time, nil]
  def normalize_time(value)
    case value
    when Time
      value
    when String
      Time.parse(value)
    when nil
      nil
    else
      value
    end
  end
end

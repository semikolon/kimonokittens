require 'securerandom'

# Domain model for signed contracts (Zigned integration)
# Represents a contract that has been sent for e-signature via Zigned
#
# Business rules:
# - Each contract belongs to exactly one tenant
# - Each contract has a unique Zigned case ID
# - Status progression: pending → signed by one party → completed
# - Stores final signed PDF URL (S3 or similar)
# - Tracks individual signature timestamps
class SignedContract
  attr_reader :id, :tenant_id, :case_id, :pdf_url, :status,
              :landlord_signed, :tenant_signed,
              :landlord_signed_at, :tenant_signed_at,
              :completed_at, :expires_at,
              :created_at, :updated_at

  def initialize(id: nil, tenant_id:, case_id:, pdf_url:, status: 'pending',
                 landlord_signed: false, tenant_signed: false,
                 landlord_signed_at: nil, tenant_signed_at: nil,
                 completed_at: nil, expires_at: nil,
                 created_at: nil, updated_at: nil)
    @id = id || generate_id
    @tenant_id = tenant_id
    @case_id = case_id
    @pdf_url = pdf_url
    @status = status
    @landlord_signed = landlord_signed
    @tenant_signed = tenant_signed
    @landlord_signed_at = landlord_signed_at
    @tenant_signed_at = tenant_signed_at
    @completed_at = completed_at
    @expires_at = expires_at
    @created_at = created_at || Time.now
    @updated_at = updated_at || Time.now

    validate!
  end

  # Query methods

  def completed?
    status == 'completed'
  end

  def expired?
    status == 'expired'
  end

  def cancelled?
    status == 'cancelled'
  end

  def pending?
    status == 'pending' || status == 'awaiting_signatures'
  end

  def both_signed?
    landlord_signed && tenant_signed
  end

  def awaiting_landlord?
    !landlord_signed
  end

  def awaiting_tenant?
    !tenant_signed
  end

  def days_until_expiry
    return nil unless expires_at
    return 0 if expired?
    ((expires_at - Time.now) / 86400).ceil
  end

  private

  def generate_id
    "signed-contract-#{SecureRandom.hex(8)}"
  end

  def validate!
    raise ArgumentError, "tenant_id is required" if tenant_id.nil? || tenant_id.empty?
    raise ArgumentError, "case_id is required" if case_id.nil? || case_id.empty?
    raise ArgumentError, "pdf_url is required" if pdf_url.nil? || pdf_url.empty?

    valid_statuses = ['pending', 'awaiting_signatures', 'completed', 'expired', 'cancelled']
    unless valid_statuses.include?(status)
      raise ArgumentError, "status must be one of: #{valid_statuses.join(', ')}"
    end

    if completed? && (!landlord_signed || !tenant_signed)
      raise ArgumentError, "completed contracts must have both signatures"
    end

    if both_signed? && status == 'pending'
      raise ArgumentError, "contract with both signatures should not be pending"
    end
  end
end

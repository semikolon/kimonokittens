require 'securerandom'
require_relative '../landlord_profile'

# Domain model for contract participants (individual signers)
# Represents a person who needs to sign a contract (landlord, tenant, observer)
#
# Business rules:
# - Each participant belongs to exactly one contract
# - Each participant has a unique Zigned participant ID
# - Status progression: pending → invited → viewed → signing → fulfilled
# - Tracks email delivery and identity enforcement
# - Supports multi-party agreements (3-4 signers for handbook contracts)
class ContractParticipant
  attr_reader :id, :contract_id, :participant_id, :name, :email, :personal_number,
              :role, :status, :signing_url, :signed_at,
              :email_delivered, :email_delivered_at,
              :email_delivery_failed, :email_delivery_error,
              :sms_delivered, :sms_delivered_at,
              :identity_enforcement_passed, :identity_enforcement_failed_at,
              :created_at, :updated_at

  def initialize(id: nil, contract_id:, participant_id:, name:, email:, personal_number:,
                 role: 'signer', status: 'pending', signing_url: nil, signed_at: nil,
                 email_delivered: false, email_delivered_at: nil,
                 email_delivery_failed: false, email_delivery_error: nil,
                 sms_delivered: false, sms_delivered_at: nil,
                 identity_enforcement_passed: nil, identity_enforcement_failed_at: nil,
                 created_at: nil, updated_at: nil)
    @id = id || generate_id
    @contract_id = contract_id
    @participant_id = participant_id
    @name = name
    @email = email
    @personal_number = personal_number
    @role = role
    @status = status
    @signing_url = signing_url
    @signed_at = signed_at
    @email_delivered = email_delivered
    @email_delivered_at = email_delivered_at
    @email_delivery_failed = email_delivery_failed
    @email_delivery_error = email_delivery_error
    @sms_delivered = sms_delivered
    @sms_delivered_at = sms_delivered_at
    @identity_enforcement_passed = identity_enforcement_passed
    @identity_enforcement_failed_at = identity_enforcement_failed_at
    @created_at = created_at || Time.now
    @updated_at = updated_at || Time.now

    validate!
  end

  # Writer methods for mutable fields
  attr_writer :status, :signing_url, :signed_at,
              :email_delivered, :email_delivered_at,
              :email_delivery_failed, :email_delivery_error,
              :sms_delivered, :sms_delivered_at,
              :identity_enforcement_passed, :identity_enforcement_failed_at

  # Query methods

  def fulfilled?
    status == 'fulfilled'
  end

  def pending?
    status == 'pending'
  end

  def invited?
    status == 'invited'
  end

  def rejected?
    status == 'rejected'
  end

  def has_signed?
    fulfilled?
  end

  def landlord?
    personal_number&.gsub(/\D/, '') == LandlordProfile.info[:personnummer]&.gsub(/\D/, '')
  end

  def tenant?
    !landlord?
  end

  def email_bounce?
    email_delivery_failed
  end

  def identity_failed?
    identity_enforcement_passed == false
  end

  private

  def generate_id
    "participant-#{SecureRandom.hex(8)}"
  end

  def validate!
    raise ArgumentError, "contract_id is required" if contract_id.nil? || contract_id.empty?
    # participant_id is nil initially, set by Zigned webhook after agreement creation
    # raise ArgumentError, "participant_id is required" if participant_id.nil? || participant_id.empty?
    raise ArgumentError, "name is required" if name.nil? || name.empty?
    raise ArgumentError, "email is required" if email.nil? || email.empty?
    raise ArgumentError, "personal_number is required" if personal_number.nil? || personal_number.empty?

    valid_roles = ['signer', 'observer', 'approver', 'landlord', 'tenant']
    unless valid_roles.include?(role)
      raise ArgumentError, "role must be one of: #{valid_roles.join(', ')}"
    end

    valid_statuses = ['pending', 'invited', 'viewed', 'signing', 'fulfilled', 'rejected']
    unless valid_statuses.include?(status)
      raise ArgumentError, "status must be one of: #{valid_statuses.join(', ')}"
    end

    if fulfilled? && signed_at.nil?
      raise ArgumentError, "fulfilled participants must have signed_at timestamp"
    end
  end
end

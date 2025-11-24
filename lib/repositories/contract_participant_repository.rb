require 'sequel'
require_relative '../rent_db'
require_relative '../models/contract_participant'

# Repository for ContractParticipant persistence
# Handles database operations for individual contract signers
class ContractParticipantRepository
  def initialize(db = RentDb.instance)
    @db = db
  end

  # Find by Zigned participant ID (unique)
  def find_by_participant_id(participant_id)
    row = @db.class.db[:ContractParticipant].where(participantId: participant_id).first
    row ? hydrate(row) : nil
  end

  # Find all participants for a contract
  def find_by_contract_id(contract_id)
    @db.class.db[:ContractParticipant]
      .where(contractId: contract_id)
      .order(Sequel.asc(:createdAt))
      .map { |row| hydrate(row) }
  end

  # Find by internal ID
  def find_by_id(id)
    row = @db.class.db[:ContractParticipant].where(id: id).first
    row ? hydrate(row) : nil
  end

  # Find by personal number (Swedish personnummer)
  def find_by_personal_number(personal_number, contract_id: nil)
    query = @db.class.db[:ContractParticipant].where(personalNumber: personal_number)
    query = query.where(contractId: contract_id) if contract_id
    query.map { |row| hydrate(row) }
  end

  # Find participant by contract ID and email (used for sign_event webhook matching)
  def find_by_contract_and_email(contract_id, email)
    row = @db.class.db[:ContractParticipant]
      .where(contractId: contract_id, email: email)
      .first
    row ? hydrate(row) : nil
  end

  # Find fulfilled (signed) participants for a contract
  def find_fulfilled(contract_id)
    @db.class.db[:ContractParticipant]
      .where(contractId: contract_id, status: 'fulfilled')
      .map { |row| hydrate(row) }
  end

  # Find pending participants (not yet signed)
  def find_pending(contract_id)
    @db.class.db[:ContractParticipant]
      .where(contractId: contract_id)
      .exclude(status: 'fulfilled')
      .map { |row| hydrate(row) }
  end

  # Find participants with email delivery failures
  def find_email_failures(contract_id)
    @db.class.db[:ContractParticipant]
      .where(contractId: contract_id, emailDeliveryFailed: true)
      .map { |row| hydrate(row) }
  end

  # Save (insert or update)
  def save(participant)
    data = dehydrate(participant)

    existing = @db.class.db[:ContractParticipant].where(id: participant.id).first

    if existing
      rows_affected = @db.class.db[:ContractParticipant].where(id: participant.id).update(data)
      raise "Update failed: no rows affected for participant #{participant.id}" if rows_affected == 0
    else
      result = @db.class.db[:ContractParticipant].insert(data)
      raise "Insert failed: no result returned for participant #{participant.id}" if result.nil?
    end

    participant
  end

  # Update (must exist)
  def update(participant)
    data = dehydrate(participant)
    rows_affected = @db.class.db[:ContractParticipant].where(id: participant.id).update(data)
    raise "Update failed: participant not found #{participant.id}" if rows_affected == 0
    participant
  end

  # Delete participant
  def delete(id)
    @db.class.db[:ContractParticipant].where(id: id).delete
  end

  # Delete all participants for a contract (called on contract deletion via CASCADE)
  def delete_by_contract_id(contract_id)
    @db.class.db[:ContractParticipant].where(contractId: contract_id).delete
  end

  # Get statistics
  def statistics(contract_id: nil)
    query = @db.class.db[:ContractParticipant]
    query = query.where(contractId: contract_id) if contract_id

    {
      total: query.count,
      fulfilled: query.where(status: 'fulfilled').count,
      pending: query.where(status: 'pending').count,
      invited: query.where(status: 'invited').count,
      email_delivered: query.where(emailDelivered: true).count,
      email_failed: query.where(emailDeliveryFailed: true).count
    }
  end

  private

  def hydrate(row)
    ContractParticipant.new(
      id: row[:id],
      contract_id: row[:contractId],
      participant_id: row[:participantId],
      name: row[:name],
      email: row[:email],
      personal_number: row[:personalNumber],
      role: row[:role],
      status: row[:status],
      signing_url: row[:signingUrl],
      signed_at: row[:signedAt],
      email_delivered: row[:emailDelivered],
      email_delivered_at: row[:emailDeliveredAt],
      email_delivery_failed: row[:emailDeliveryFailed],
      email_delivery_error: row[:emailDeliveryError],
      sms_delivered: row[:smsDelivered],
      sms_delivered_at: row[:smsDeliveredAt],
      identity_enforcement_passed: row[:identityEnforcementPassed],
      identity_enforcement_failed_at: row[:identityEnforcementFailedAt],
      created_at: row[:createdAt],
      updated_at: row[:updatedAt]
    )
  end

  def dehydrate(participant)
    {
      id: participant.id,
      contractId: participant.contract_id,
      participantId: participant.participant_id,
      name: participant.name,
      email: participant.email,
      personalNumber: participant.personal_number,
      role: participant.role,
      status: participant.status,
      signingUrl: participant.signing_url,
      signedAt: participant.signed_at,
      emailDelivered: participant.email_delivered,
      emailDeliveredAt: participant.email_delivered_at,
      emailDeliveryFailed: participant.email_delivery_failed,
      emailDeliveryError: participant.email_delivery_error,
      smsDelivered: participant.sms_delivered,
      smsDeliveredAt: participant.sms_delivered_at,
      identityEnforcementPassed: participant.identity_enforcement_passed,
      identityEnforcementFailedAt: participant.identity_enforcement_failed_at,
      createdAt: participant.created_at,
      updatedAt: Time.now
    }
  end
end

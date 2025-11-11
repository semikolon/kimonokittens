require 'sequel'
require_relative '../rent_db'
require_relative '../models/signed_contract'

# Repository for SignedContract persistence
# Handles database operations for signed contracts from Zigned
class SignedContractRepository
  def initialize(db = RentDb.instance)
    @db = db
  end

  # Find by Zigned case ID (unique)
  def find_by_case_id(case_id)
    row = @db.class.db[:SignedContract].where(caseId: case_id).first
    row ? hydrate(row) : nil
  end

  # Find all contracts for a tenant
  def find_by_tenant_id(tenant_id)
    @db.class.db[:SignedContract]
      .where(tenantId: tenant_id)
      .order(Sequel.desc(:createdAt))
      .map { |row| hydrate(row) }
  end

  # Find by internal ID
  def find_by_id(id)
    row = @db.class.db[:SignedContract].where(id: id).first
    row ? hydrate(row) : nil
  end

  # Find all completed contracts
  def find_completed
    @db.class.db[:SignedContract]
      .where(status: 'completed')
      .order(Sequel.desc(:completedAt))
      .map { |row| hydrate(row) }
  end

  # Find contracts expiring soon
  def find_expiring_soon(days: 7)
    cutoff = Time.now + (days * 86400)
    @db.class.db[:SignedContract]
      .where(status: 'pending')
      .where { expiresAt < cutoff }
      .order(Sequel.asc(:expiresAt))
      .map { |row| hydrate(row) }
  end

  # Save (insert or update)
  def save(signed_contract)
    data = dehydrate(signed_contract)

    existing = @db.class.db[:SignedContract].where(id: signed_contract.id).first

    if existing
      rows_affected = @db.class.db[:SignedContract].where(id: signed_contract.id).update(data)
      raise "Update failed: no rows affected for contract #{signed_contract.id}" if rows_affected == 0
    else
      result = @db.class.db[:SignedContract].insert(data)
      raise "Insert failed: no result returned for contract #{signed_contract.id}" if result.nil?
    end

    signed_contract
  end

  # Delete contract
  def delete(id)
    @db.class.db[:SignedContract].where(id: id).delete
  end

  # Get statistics
  def statistics
    {
      total: @db.class.db[:SignedContract].count,
      completed: @db.class.db[:SignedContract].where(status: 'completed').count,
      pending: @db.class.db[:SignedContract].where(status: 'pending').count,
      expired: @db.class.db[:SignedContract].where(status: 'expired').count,
      cancelled: @db.class.db[:SignedContract].where(status: 'cancelled').count
    }
  end

  private

  def hydrate(row)
    SignedContract.new(
      id: row[:id],
      tenant_id: row[:tenantId],
      case_id: row[:caseId],
      pdf_url: row[:pdfUrl],
      status: row[:status],
      landlord_signed: row[:landlordSigned],
      tenant_signed: row[:tenantSigned],
      landlord_signed_at: row[:landlordSignedAt],
      tenant_signed_at: row[:tenantSignedAt],
      landlord_signing_url: row[:landlordSigningUrl],
      tenant_signing_url: row[:tenantSigningUrl],
      test_mode: row[:testMode],
      completed_at: row[:completedAt],
      expires_at: row[:expiresAt],
      created_at: row[:createdAt],
      updated_at: row[:updatedAt]
    )
  end

  def dehydrate(contract)
    {
      id: contract.id,
      tenantId: contract.tenant_id,
      caseId: contract.case_id,
      pdfUrl: contract.pdf_url,
      status: contract.status,
      landlordSigned: contract.landlord_signed,
      tenantSigned: contract.tenant_signed,
      landlordSignedAt: contract.landlord_signed_at,
      tenantSignedAt: contract.tenant_signed_at,
      landlordSigningUrl: contract.landlord_signing_url,
      tenantSigningUrl: contract.tenant_signing_url,
      testMode: contract.test_mode,
      completedAt: contract.completed_at,
      expiresAt: contract.expires_at,
      createdAt: contract.created_at,
      updatedAt: Time.now
    }
  end
end

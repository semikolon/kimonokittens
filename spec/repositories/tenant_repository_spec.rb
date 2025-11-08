require_relative '../spec_helper'
require_relative '../../lib/repositories/tenant_repository'
require_relative '../../lib/models/tenant'
require_relative '../rent_calculator/support/test_helpers'

RSpec.describe TenantRepository, 'deposit persistence' do
  include RentCalculatorSpec::TestHelpers
  let(:repo) { described_class.new }

  before do
    clean_database
  end

  describe '#create' do
    it 'persists deposits to database' do
      tenant = Tenant.new(
        name: 'Test',
        email: 'test@example.com',
        deposit: 6200,
        furnishing_deposit: 2200
      )

      created = repo.create(tenant)
      retrieved = repo.find_by_id(created.id)

      expect(retrieved.deposit).to eq(6200.0)
      expect(retrieved.furnishing_deposit).to eq(2200.0)
    end

    it 'handles nil deposits' do
      tenant = Tenant.new(name: 'Test', email: 'test@example.com')

      created = repo.create(tenant)
      retrieved = repo.find_by_id(created.id)

      expect(retrieved.deposit).to be_nil
      expect(retrieved.furnishing_deposit).to be_nil
    end

    it 'persists personnummer and phone' do
      tenant = Tenant.new(
        name: 'Test',
        email: 'test@example.com',
        personnummer: '9001011234',
        phone: '070-123 45 67'
      )

      created = repo.create(tenant)
      retrieved = repo.find_by_id(created.id)

      expect(retrieved.personnummer).to eq('9001011234')
      expect(retrieved.phone).to eq('070-123 45 67')
    end
  end

  describe '#update' do
    it 'updates deposit fields' do
      tenant = Tenant.new(
        name: 'Test',
        email: 'test@example.com',
        deposit: 6200,
        furnishing_deposit: 2200
      )

      created = repo.create(tenant)

      # Update deposits
      updated_tenant = Tenant.new(
        id: created.id,
        name: created.name,
        email: created.email,
        deposit: 6500,
        furnishing_deposit: 2500
      )

      repo.update(updated_tenant)
      retrieved = repo.find_by_id(created.id)

      expect(retrieved.deposit).to eq(6500.0)
      expect(retrieved.furnishing_deposit).to eq(2500.0)
    end

    it 'can clear deposits by setting to nil' do
      tenant = Tenant.new(
        name: 'Test',
        email: 'test@example.com',
        deposit: 6200,
        furnishing_deposit: 2200
      )

      created = repo.create(tenant)

      # Clear deposits
      updated_tenant = Tenant.new(
        id: created.id,
        name: created.name,
        email: created.email,
        deposit: nil,
        furnishing_deposit: nil
      )

      repo.update(updated_tenant)
      retrieved = repo.find_by_id(created.id)

      expect(retrieved.deposit).to be_nil
      expect(retrieved.furnishing_deposit).to be_nil
    end

    it 'updates personnummer and phone' do
      tenant = Tenant.new(
        name: 'Test',
        email: 'test@example.com',
        personnummer: '9001011234',
        phone: '070-123 45 67'
      )

      created = repo.create(tenant)

      # Update contact info
      updated_tenant = Tenant.new(
        id: created.id,
        name: created.name,
        email: created.email,
        personnummer: '8906223386',
        phone: '073-976 44 79'
      )

      repo.update(updated_tenant)
      retrieved = repo.find_by_id(created.id)

      expect(retrieved.personnummer).to eq('8906223386')
      expect(retrieved.phone).to eq('073-976 44 79')
    end
  end

  describe '#find_by_email' do
    it 'retrieves tenant with deposit fields' do
      tenant = Tenant.new(
        name: 'Test',
        email: 'test@example.com',
        deposit: 6200,
        furnishing_deposit: 2200,
        personnummer: '9001011234'
      )

      repo.create(tenant)
      retrieved = repo.find_by_email('test@example.com')

      expect(retrieved).not_to be_nil
      expect(retrieved.deposit).to eq(6200.0)
      expect(retrieved.furnishing_deposit).to eq(2200.0)
      expect(retrieved.personnummer).to eq('9001011234')
    end
  end

  describe '#find_active' do
    it 'includes deposit fields in active tenants' do
      tenant1 = Tenant.new(
        name: 'Active',
        email: 'active@example.com',
        deposit: 6200,
        furnishing_deposit: 2200
      )

      tenant2 = Tenant.new(
        name: 'Departed',
        email: 'departed@example.com',
        deposit: 6500,
        furnishing_deposit: 2500,
        departure_date: Date.new(2025, 1, 1)
      )

      repo.create(tenant1)
      repo.create(tenant2)

      active_tenants = repo.find_active

      expect(active_tenants.length).to eq(1)
      expect(active_tenants.first.name).to eq('Active')
      expect(active_tenants.first.deposit).to eq(6200.0)
      expect(active_tenants.first.furnishing_deposit).to eq(2200.0)
    end
  end
end

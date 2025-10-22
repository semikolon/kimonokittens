require_relative 'repositories/tenant_repository'
require_relative 'repositories/rent_config_repository'
require_relative 'repositories/rent_ledger_repository'
require_relative 'repositories/electricity_bill_repository'

# Persistence provides memoized access to repository instances. This keeps RentDb
# focused on connection management while giving the rest of the application a
# single place to obtain repositories.
module Persistence
  class << self
    def tenants
      @tenants ||= TenantRepository.new
    end

    def rent_configs
      @rent_configs ||= RentConfigRepository.new
    end

    def rent_ledger
      @rent_ledger ||= RentLedgerRepository.new
    end

    def electricity_bills
      @electricity_bills ||= ElectricityBillRepository.new
    end

    # Reset memoized repositories (useful for tests swapping connection context).
    def reset!
      @tenants = nil
      @rent_configs = nil
      @rent_ledger = nil
      @electricity_bills = nil
    end
  end
end

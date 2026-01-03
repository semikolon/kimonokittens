require_relative 'repositories/tenant_repository'
require_relative 'repositories/rent_config_repository'
require_relative 'repositories/rent_ledger_repository'
require_relative 'repositories/electricity_bill_repository'
require_relative 'repositories/signed_contract_repository'
require_relative 'repositories/contract_participant_repository'
require_relative 'repositories/bank_transaction_repository'
require_relative 'repositories/rent_receipt_repository'
require_relative 'repositories/sms_event_repository'
require_relative 'repositories/heatpump_config_repository'
require_relative 'repositories/heatpump_override_repository'
require_relative 'repositories/heatpump_adjustment_repository'

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

    def signed_contracts
      @signed_contracts ||= SignedContractRepository.new
    end

    def contract_participants
      @contract_participants ||= ContractParticipantRepository.new
    end

    def bank_transactions
      @bank_transactions ||= BankTransactionRepository.new
    end

    def rent_receipts
      @rent_receipts ||= RentReceiptRepository.new
    end

    def sms_events
      @sms_events ||= SmsEventRepository.new
    end

    def heatpump_config
      @heatpump_config ||= HeatpumpConfigRepository.new
    end

    def heatpump_overrides
      @heatpump_overrides ||= HeatpumpOverrideRepository.new
    end

    def heatpump_adjustments
      @heatpump_adjustments ||= HeatpumpAdjustmentRepository.new
    end

    # Reset memoized repositories (useful for tests swapping connection context).
    def reset!
      @tenants = nil
      @rent_configs = nil
      @rent_ledger = nil
      @electricity_bills = nil
      @signed_contracts = nil
      @contract_participants = nil
      @bank_transactions = nil
      @rent_receipts = nil
      @sms_events = nil
      @heatpump_config = nil
      @heatpump_overrides = nil
      @heatpump_adjustments = nil
    end
  end
end

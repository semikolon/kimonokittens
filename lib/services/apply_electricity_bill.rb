require_relative '../persistence'
require_relative '../repositories/electricity_bill_repository'
require_relative '../repositories/rent_config_repository'
require_relative '../models/electricity_bill'
require_relative '../models/rent_config'

# ApplyElectricityBill service orchestrates electricity bill processing
#
# Multi-table transaction workflow:
# 1. Store individual bill (with deduplication)
# 2. Aggregate all bills for that billing period
# 3. Update RentConfig with aggregated total
#
# This is the MISSING AUTOMATION piece that completes the flow:
#   Scraper → ElectricityBill (raw) → [THIS SERVICE] → RentConfig (aggregate)
#
# @example Apply a Vattenfall invoice
#   result = ApplyElectricityBill.call(
#     provider: 'Vattenfall',
#     amount: 1685.69,
#     due_date: Date.new(2025, 11, 3)
#   )
#   # => {
#   #   inserted: true,
#   #   bill: #<ElectricityBill>,
#   #   aggregated_total: 2424,
#   #   config_updated: true
#   # }
class ApplyElectricityBill
  # Apply electricity bill and update RentConfig
  #
  # @param provider [String] Provider name
  # @param amount [Float] Bill amount
  # @param due_date [Date] Due date
  # @param electricity_repo [ElectricityBillRepository] Optional repository (for testing)
  # @param config_repo [RentConfigRepository] Optional repository (for testing)
  #
  # @return [Hash] Result with :inserted, :bill, :aggregated_total, :config_updated
  def self.call(provider:, amount:, due_date:,
                electricity_repo: nil, config_repo: nil)

    # Initialize repositories (allow injection for testing)
    electricity_repo ||= Persistence.electricity_bills
    config_repo ||= Persistence.rent_configs

    # Execute in transaction
    electricity_repo.transaction do
      # Step 1: Store bill (with deduplication)
      store_result = electricity_repo.store_with_deduplication(
        provider: provider,
        amount: amount,
        due_date: due_date
      )

      bill = store_result[:bill]
      bill_period = store_result[:bill_period]

      # Step 2: Aggregate all bills for this period
      aggregated_total = ElectricityBill.aggregate_for_period(
        bill_period,
        repository: electricity_repo
      )

      # Step 3: Update RentConfig with aggregated total
      # Check if config already exists for this period
      existing_config = config_repo.find_by_key_and_period('el', bill_period)

      if existing_config
        # Update existing (rare - only if manual correction needed)
        updated_config = RentConfig.new(
          id: existing_config.id,
          key: 'el',
          value: aggregated_total.to_i.to_s,
          period: bill_period
        )
        config_repo.update(updated_config)
        config_updated = :updated
      else
        # Create new config entry
        new_config = RentConfig.new(
          key: 'el',
          value: aggregated_total.to_i.to_s,
          period: bill_period
        )
        config_repo.create(new_config)
        config_updated = :created
      end

      # Notify WebSocket clients (if available)
      begin
        $pubsub&.publish("rent_data_updated")
      rescue => e
        # Non-critical - log but don't fail transaction
        warn "WebSocket publish failed: #{e.message}"
      end

      # Return comprehensive result
      {
        inserted: store_result[:inserted],
        bill: bill,
        bill_period: bill_period,
        aggregated_total: aggregated_total.to_i,
        config_updated: config_updated,
        reason: store_result[:reason]
      }
    end
  end
end

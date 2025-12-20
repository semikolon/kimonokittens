require_relative 'base_repository'
require_relative '../models/heatpump_adjustment'

# HeatpumpAdjustmentRepository handles persistence for auto-tuning audit log
#
# Provides:
# - Recording adjustment events
# - Querying adjustment history
# - Checking last adjustment time for rate limiting
#
class HeatpumpAdjustmentRepository < BaseRepository
  def table_name
    :HeatpumpAdjustment
  end

  # Record a new adjustment event
  #
  # @param adjustment_type [String] 'hours_on' or 'block_distribution'
  # @param previous_value [Hash] Previous config values
  # @param new_value [Hash] New config values
  # @param reason [String] Human-readable explanation
  # @param override_stats [Hash] Stats that triggered this adjustment
  # @return [HeatpumpAdjustment]
  def record(adjustment_type:, previous_value:, new_value:, reason:, override_stats:)
    id = SecureRandom.uuid
    now = Time.now

    dataset.insert(
      id: id,
      adjustmentType: adjustment_type,
      previousValue: previous_value.to_json,
      newValue: new_value.to_json,
      reason: reason,
      overrideStats: override_stats.to_json,
      createdAt: now
    )

    find_by_id(id)
  end

  # Find adjustment by ID
  # @param id [String] Adjustment ID
  # @return [HeatpumpAdjustment, nil]
  def find_by_id(id)
    row = dataset.where(id: id).first
    row && hydrate(row)
  end

  # Get recent adjustments
  # @param limit [Integer] Max records to return
  # @return [Array<HeatpumpAdjustment>]
  def recent(limit: 10)
    dataset
      .order(Sequel.desc(:createdAt))
      .limit(limit)
      .map { |row| hydrate(row) }
  end

  # Get the most recent adjustment
  # @return [HeatpumpAdjustment, nil]
  def last_adjustment
    row = dataset.order(Sequel.desc(:createdAt)).first
    row && hydrate(row)
  end

  # Get adjustments of a specific type
  # @param type [String] 'hours_on' or 'block_distribution'
  # @param limit [Integer] Max records to return
  # @return [Array<HeatpumpAdjustment>]
  def by_type(type, limit: 10)
    dataset
      .where(adjustmentType: type)
      .order(Sequel.desc(:createdAt))
      .limit(limit)
      .map { |row| hydrate(row) }
  end

  # Count adjustments in the last N days
  # @param days [Integer] Number of days
  # @return [Integer]
  def count_recent(days:)
    cutoff = Time.now - (days * 24 * 60 * 60)
    dataset.where { createdAt >= cutoff }.count
  end

  # Calculate days since last adjustment
  # @return [Float, nil] Days since last adjustment, or nil if no adjustments
  def days_since_last_adjustment
    last = last_adjustment
    return nil unless last

    (Time.now - last.created_at) / (24 * 60 * 60)
  end

  private

  # Convert database row to domain model
  # @param row [Hash] Database row
  # @return [HeatpumpAdjustment]
  def hydrate(row)
    HeatpumpAdjustment.new(
      id: row[:id],
      adjustment_type: row[:adjustmentType],
      previous_value: row[:previousValue],
      new_value: row[:newValue],
      reason: row[:reason],
      override_stats: row[:overrideStats],
      created_at: row[:createdAt]
    )
  end
end

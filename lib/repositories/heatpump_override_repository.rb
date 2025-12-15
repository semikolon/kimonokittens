require_relative 'base_repository'
require_relative '../models/heatpump_override'

# HeatpumpOverrideRepository handles persistence for override tracking
#
# Provides:
# - Recording override events when temperature emergency triggers
# - Querying override history for self-learning analysis
# - Aggregation methods for pattern detection
#
class HeatpumpOverrideRepository < BaseRepository
  def table_name
    :HeatpumpOverride
  end

  # Record a new override event
  # @param type [String] 'indoor' or 'hotwater'
  # @param temperature [Float] Temperature when triggered
  # @param price [Float] Electricity price at that hour
  # @param scheduled_on [Boolean] Was heatpump scheduled to be ON?
  # @param hour_of_day [Integer] Hour 0-23
  # @return [HeatpumpOverride]
  def record(type:, temperature:, price:, scheduled_on:, hour_of_day:)
    id = SecureRandom.uuid
    now = Time.now

    dataset.insert(
      id: id,
      type: type,
      temperature: temperature,
      price: price,
      scheduledOn: scheduled_on,
      hourOfDay: hour_of_day,
      createdAt: now
    )

    find_by_id(id)
  end

  # Find override by ID
  # @param id [String] Override ID
  # @return [HeatpumpOverride, nil]
  def find_by_id(id)
    row = dataset.where(id: id).first
    row && hydrate(row)
  end

  # Get overrides from the last N days
  # @param days [Integer] Number of days to look back
  # @return [Array<HeatpumpOverride>]
  def last_n_days(days)
    cutoff = Time.now - (days * 24 * 60 * 60)
    dataset
      .where { createdAt >= cutoff }
      .order(Sequel.desc(:createdAt))
      .map { |row| hydrate(row) }
  end

  # Get all overrides (for analysis)
  # @param limit [Integer] Max records to return
  # @return [Array<HeatpumpOverride>]
  def all(limit: 100)
    dataset
      .order(Sequel.desc(:createdAt))
      .limit(limit)
      .map { |row| hydrate(row) }
  end

  # Count overrides by type in last N days
  # @param days [Integer] Number of days
  # @return [Hash] { 'indoor' => count, 'hotwater' => count }
  def count_by_type(days:)
    cutoff = Time.now - (days * 24 * 60 * 60)
    result = dataset
      .where { createdAt >= cutoff }
      .group(:type)
      .select { [type, count(id).as(count)] }
      .all

    result.each_with_object({ 'indoor' => 0, 'hotwater' => 0 }) do |row, hash|
      hash[row[:type]] = row[:count]
    end
  end

  # Count overrides by hour of day in last N days
  # @param days [Integer] Number of days
  # @return [Hash] { 0 => count, 1 => count, ..., 23 => count }
  def count_by_hour(days:)
    cutoff = Time.now - (days * 24 * 60 * 60)
    result = dataset
      .where { createdAt >= cutoff }
      .group(:hourOfDay)
      .select { [hourOfDay, count(id).as(count)] }
      .all

    # Initialize all hours to 0
    counts = (0..23).each_with_object({}) { |h, hash| hash[h] = 0 }

    result.each do |row|
      counts[row[:hourOfDay]] = row[:count]
    end

    counts
  end

  # Count timing vs capacity issues in last N days
  # @param days [Integer] Number of days
  # @return [Hash] { timing: count, capacity: count }
  def count_by_issue_type(days:)
    cutoff = Time.now - (days * 24 * 60 * 60)
    result = dataset
      .where { createdAt >= cutoff }
      .group(:scheduledOn)
      .select { [scheduledOn, count(id).as(count)] }
      .all

    counts = { timing: 0, capacity: 0 }
    result.each do |row|
      if row[:scheduledOn]
        counts[:capacity] = row[:count]
      else
        counts[:timing] = row[:count]
      end
    end

    counts
  end

  # Calculate average override cost (price during override hours)
  # @param days [Integer] Number of days
  # @return [Float] Average price in kr/kWh
  def average_override_price(days:)
    cutoff = Time.now - (days * 24 * 60 * 60)
    result = dataset
      .where { createdAt >= cutoff }
      .select { avg(price).as(avg_price) }
      .first

    result[:avg_price]&.to_f || 0.0
  end

  private

  # Convert database row to domain model
  # @param row [Hash] Database row
  # @return [HeatpumpOverride]
  def hydrate(row)
    HeatpumpOverride.new(
      id: row[:id],
      type: row[:type],
      temperature: row[:temperature],
      price: row[:price],
      scheduled_on: row[:scheduledOn],
      hour_of_day: row[:hourOfDay],
      created_at: row[:createdAt]
    )
  end
end

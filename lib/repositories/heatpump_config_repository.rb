require_relative 'base_repository'
require_relative '../models/heatpump_config'

# HeatpumpConfigRepository handles persistence for heatpump configuration
#
# Provides:
# - Singleton config access (only one config record exists)
# - Config updates with validation
# - Default config creation
#
class HeatpumpConfigRepository < BaseRepository
  def table_name
    :HeatpumpConfig
  end

  # Get the current heatpump configuration (singleton pattern)
  # Creates default config if none exists
  # @return [HeatpumpConfig]
  def get_current
    row = dataset.first

    if row
      hydrate(row)
    else
      create_default
    end
  end

  # Update heatpump configuration
  # @param id [String] Config ID
  # @param params [Hash] Update parameters
  # @return [HeatpumpConfig]
  def update(id, params)
    # Build update hash with only provided fields
    update_hash = { updatedAt: Time.now }
    update_hash[:hoursOn] = params[:hours_on] if params[:hours_on]
    update_hash[:emergencyTempOffset] = params[:emergency_temp_offset] if params[:emergency_temp_offset]
    update_hash[:minHotwater] = params[:min_hotwater] if params[:min_hotwater]

    dataset.where(id: id).update(update_hash)

    find_by_id(id)
  end

  # Find config by ID
  # @param id [String] Config ID
  # @return [HeatpumpConfig, nil]
  def find_by_id(id)
    row = dataset.where(id: id).first
    row && hydrate(row)
  end

  private

  # Create default configuration
  # @return [HeatpumpConfig]
  def create_default
    id = SecureRandom.uuid
    now = Time.now

    dataset.insert(
      id: id,
      hoursOn: 12,
      emergencyTempOffset: 1.0,
      minHotwater: 40.0,
      createdAt: now,
      updatedAt: now
    )

    find_by_id(id)
  end

  # Convert database row to domain model
  # @param row [Hash] Database row
  # @return [HeatpumpConfig]
  def hydrate(row)
    HeatpumpConfig.new(
      id: row[:id],
      hours_on: row[:hoursOn],
      emergency_temp_offset: row[:emergencyTempOffset],
      min_hotwater: row[:minHotwater],
      created_at: row[:createdAt],
      updated_at: row[:updatedAt]
    )
  end
end

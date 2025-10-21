require_relative '../rent_db'

# Base repository class providing common persistence operations
#
# All repositories inherit from this and implement:
# - table_name (returns symbol for Sequel dataset)
# - hydrate(row) (DB row → domain object)
# - dehydrate(object) (domain object → DB hash)
#
# Repositories are PERSISTENCE ONLY - no business logic allowed.
# Business logic belongs in models.
#
# @example
#   class ElectricityBillRepository < BaseRepository
#     def table_name
#       :ElectricityBill
#     end
#
#     def hydrate(row)
#       ElectricityBill.new(...)
#     end
#   end
class BaseRepository
  attr_reader :db, :dataset

  def initialize(db: RentDb.db)
    @db = db
    @dataset = db[table_name]
  end

  # Override in subclass to specify table name
  # @return [Symbol] Table name for Sequel dataset
  def table_name
    raise NotImplementedError, "#{self.class} must implement #table_name"
  end

  # Execute block within a database transaction
  # @yield Block to execute within transaction
  # @return Result of block
  def transaction(&block)
    db.transaction(&block)
  end

  # Convert database row to domain object
  # Override in subclass
  # @param row [Hash] Database row (Sequel dataset result)
  # @return [Object] Domain model instance
  def hydrate(row)
    raise NotImplementedError, "#{self.class} must implement #hydrate"
  end

  # Convert domain object to database hash
  # Override in subclass
  # @param object [Object] Domain model instance
  # @return [Hash] Database column hash
  def dehydrate(object)
    raise NotImplementedError, "#{self.class} must implement #dehydrate"
  end

  private

  # Helper: Generate CUID for new records
  # @return [String] Generated CUID
  def generate_id
    Cuid.generate
  end

  # Helper: Current UTC timestamp
  # @return [Time] Current time in UTC
  def now_utc
    Time.now.utc
  end
end

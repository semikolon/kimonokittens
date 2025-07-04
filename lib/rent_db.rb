require 'pg'
require 'singleton'
require 'cuid'

# RentDb provides a unified interface to the PostgreSQL database for the
# Kimonokittens handbook and rent calculation system.
# It replaces the legacy SQLite and file-based persistence mechanisms.
class RentDb
  include Singleton
  attr_reader :conn

  def initialize
    @conn = PG.connect(ENV.fetch('DATABASE_URL'))
  rescue PG::Error => e
    puts "Error connecting to PostgreSQL: #{e.message}"
    # In a real app, you'd want more robust error handling, logging,
    # or a retry mechanism.
    raise
  end

  # Example method to fetch tenants.
  # We will build this out with more specific methods to get rent configs,
  # roommates for a specific month, etc.
  def get_tenants
    tenants = []
    @conn.exec("SELECT id, name, email FROM \"Tenant\" ORDER BY name") do |result|
      result.each do |row|
        tenants << row
      end
    end
    tenants
  end

  def get_rent_history(year:, month:)
    history = []
    # Note: Prisma stores dates in UTC. We construct the date range carefully.
    start_date = Time.new(year, month, 1).utc.iso8601
    end_date = (Time.new(year, month, 1) + (31 * 24 * 60 * 60)).utc.iso8601 # A safe way to get to the next month

    query = <<-SQL
      SELECT * FROM "RentLedger"
      WHERE period >= $1::timestamp AND period < $2::timestamp
      ORDER BY "createdAt" ASC
    SQL

    @conn.exec_params(query, [start_date, end_date]) do |result|
      result.each do |row|
        history << row
      end
    end
    history
  end

  def get_config(key)
    query = 'SELECT value FROM "RentConfig" WHERE key = $1'
    result = @conn.exec_params(query, [key])
    result.ntuples.zero? ? nil : result.getvalue(0, 0)
  end

  def set_config(key, value)
    # Use an UPSERT-like query to either insert a new key or update an existing one.
    query = <<-SQL
      INSERT INTO "RentConfig" (id, key, value, "createdAt", "updatedAt")
      VALUES ($1, $2, $3, NOW(), NOW())
      ON CONFLICT (key) DO UPDATE
      SET value = $3, "updatedAt" = NOW()
    SQL
    id = Cuid.generate
    @conn.exec_params(query, [id, key, value])
  end

  def add_tenant(name:)
    id = Cuid.generate
    email = "#{name.downcase.gsub(/\s+/, '.')}@kimonokittens.com"
    @conn.exec_params('INSERT INTO "Tenant" (id, name, email, "createdAt", "updatedAt") VALUES ($1, $2, $3, NOW(), NOW())', [id, name, email])
  end

  def set_room_adjustment(name:, adjustment:)
    query = <<-SQL
      UPDATE "Tenant"
      SET "roomAdjustment" = $1
      WHERE name = $2
    SQL
    @conn.exec_params(query, [adjustment, name])
  end

  private

  # Method to gracefully close the connection when the application shuts down.
  def close_connection
    @conn&.close
  end
end 
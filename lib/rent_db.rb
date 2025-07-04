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
    @conn.exec("SELECT id, name, email, \"startDate\", \"departureDate\", \"roomAdjustment\" FROM \"Tenant\" ORDER BY name") do |result|
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

  def get_rent_config(year:, month:)
    # This query finds the most recent value for each configuration key
    # for a given month. It uses a window function to partition by key
    # and order by creation date, taking only the latest one (rank = 1)
    # at or before the end of the specified month.
    end_of_month = Time.new(year, month, 1, 23, 59, 59, '+00:00') + (31 * 24 * 60 * 60)
    query = <<-SQL
      WITH ranked_configs AS (
        SELECT
          key,
          value,
          "createdAt",
          ROW_NUMBER() OVER(PARTITION BY key ORDER BY "createdAt" DESC) as rn
        FROM "RentConfig"
        WHERE "createdAt" <= $1
      )
      SELECT key, value FROM ranked_configs WHERE rn = 1;
    SQL
    @conn.exec_params(query, [end_of_month.utc.iso8601])
  end

  def set_config(key, value, period = Time.now)
    # This method now saves configuration values with a specific period.
    query = <<-SQL
      INSERT INTO "RentConfig" (id, key, value, period, "createdAt", "updatedAt")
      VALUES ($1, $2, $3, $4, NOW(), NOW())
    SQL
    id = Cuid.generate
    @conn.exec_params(query, [id, key, value, period.utc.iso8601])
  end

  def find_tenant_by_facebook_id(facebook_id)
    query = 'SELECT * FROM "Tenant" WHERE "facebookId" = $1'
    result = @conn.exec_params(query, [facebook_id])
    result.ntuples.zero? ? nil : result.first
  end

  def find_tenant_by_email(email)
    query = 'SELECT * FROM "Tenant" WHERE email = $1'
    result = @conn.exec_params(query, [email])
    result.ntuples.zero? ? nil : result.first
  end

  def add_tenant(name:, email: nil, facebookId: nil, avatarUrl: nil)
    id = Cuid.generate
    # Generate a placeholder email if none is provided, preserving old behavior
    # for test setups and other non-OAuth tenant creation.
    email ||= "#{name.downcase.gsub(/\s+/, '.')}@kimonokittens.com"
    query = <<-SQL
      INSERT INTO "Tenant" (id, name, email, "facebookId", "avatarUrl", "createdAt", "updatedAt")
      VALUES ($1, $2, $3, $4, $5, NOW(), NOW())
    SQL
    @conn.exec_params(query, [id, name, email, facebookId, avatarUrl])
  end

  def set_start_date(name:, date:)
    query = <<-SQL
      UPDATE "Tenant"
      SET "startDate" = $1
      WHERE name = $2
    SQL
    @conn.exec_params(query, [date, name])
  end

  def set_departure_date(name:, date:)
    query = <<-SQL
      UPDATE "Tenant"
      SET "departureDate" = $1
      WHERE name = $2
    SQL
    @conn.exec_params(query, [date, name])
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
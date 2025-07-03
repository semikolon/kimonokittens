require 'sqlite3'
require 'singleton'
require 'fileutils'

module RentCalculator
  # RentConfigStore manages persistent configuration for the rent calculator.
  # It stores all configurable values (costs, adjustments, balances) in SQLite,
  # making them available across all interfaces (API, CLI, etc.).
  #
  # This allows for natural interactions like:
  # "The internet cost went up to 450kr"
  # "We have 400kr left from last month"
  # "The quarterly invoice came in at 2612kr"
  #
  # The values are then automatically used in all future calculations until updated.
  class ConfigStore
    include Singleton

    def initialize
      setup_database
    end

    # Get current value for a config key
    def get(key, year = nil, month = nil)
      if year && month
        # Try to get month-specific value first
        stmt = db.prepare("SELECT value FROM monthly_configs WHERE key = ? AND year = ? AND month = ? ORDER BY updated_at DESC LIMIT 1")
        result = stmt.execute(key.to_s, year, month).first
        return result[0] if result
      end

      # Fall back to current value
      stmt = db.prepare("SELECT value FROM configs WHERE key = ? ORDER BY updated_at DESC LIMIT 1")
      result = stmt.execute(key.to_s).first
      result ? result[0] : nil
    end

    # Update a config value
    def set(key, value, year = nil, month = nil)
      if year && month
        db.execute(
          "INSERT INTO monthly_configs (key, value, year, month, updated_at) VALUES (?, ?, ?, ?, datetime('now'))",
          [key.to_s, value, year, month]
        )
      else
        db.execute(
          "INSERT INTO configs (key, value, updated_at) VALUES (?, ?, datetime('now'))",
          [key.to_s, value]
        )
      end
    end

    # Get all current config values
    def current_config
      {
        kallhyra: get('kallhyra')&.to_i || 24530,
        el: get('el')&.to_i || 0,
        bredband: get('bredband')&.to_i || 400,
        vattenavgift: get('vattenavgift')&.to_i || 375,
        va: get('va')&.to_i || 300,
        larm: get('larm')&.to_i || 150,
        drift_rakning: get('drift_rakning')&.to_i,
        saldo_innan: get('saldo_innan')&.to_i || 0,
        extra_in: get('extra_in')&.to_i || 0
      }
    end

    # Get config for specific month
    def month_config(year, month)
      base = current_config
      
      # Override with any month-specific values
      base.keys.each do |key|
        value = get(key, year, month)
        base[key] = value.to_i if value
      end
      
      base
    end

    # Clear monthly values (e.g., drift_rakning, saldo_innan) after they're used
    def clear_monthly_values(year, month)
      db.execute(
        "DELETE FROM monthly_configs WHERE year = ? AND month = ? AND key IN ('drift_rakning', 'saldo_innan', 'extra_in')",
        [year, month]
      )
    end

    private

    def db
      @db ||= begin
        path = File.expand_path('../data/rent_config.db', __dir__)
        FileUtils.mkdir_p(File.dirname(path))
        SQLite3::Database.new(path)
      end
    end

    def setup_database
      # Create tables if they don't exist
      db.execute <<-SQL
        CREATE TABLE IF NOT EXISTS configs (
          id INTEGER PRIMARY KEY,
          key TEXT NOT NULL,
          value TEXT NOT NULL,
          updated_at DATETIME NOT NULL
        );
      SQL

      db.execute <<-SQL
        CREATE TABLE IF NOT EXISTS monthly_configs (
          id INTEGER PRIMARY KEY,
          key TEXT NOT NULL,
          value TEXT NOT NULL,
          year INTEGER NOT NULL,
          month INTEGER NOT NULL,
          updated_at DATETIME NOT NULL
        );
      SQL

      # Create indexes
      db.execute "CREATE INDEX IF NOT EXISTS idx_configs_key ON configs(key);"
      db.execute "CREATE INDEX IF NOT EXISTS idx_monthly_configs_key_date ON monthly_configs(key, year, month);"
    end
  end
end 
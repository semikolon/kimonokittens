require 'sqlite3'
require 'singleton'
require 'fileutils'

module RentCalculator
  class RoommateError < StandardError; end

  # RoommateStore manages persistent roommate information for the rent calculator.
  # It stores both permanent roommates and their adjustments, as well as temporary
  # stays and changes in the living situation.
  #
  # This allows for natural interactions like:
  # "Elvira is moving in next month"
  # "Astrid is moving out on the 15th"
  # "Amanda is staying for 10 days in December"
  # "The small room now has a 1500kr discount"
  #
  # The data is then automatically used in all calculations until updated.
  #
  # Validation Rules:
  # - Warns if total roommates would be less than 3 or more than 4
  # - Requires confirmation for room adjustments over 2000kr
  # - Never accepts stay days over 31
  # - Suggests using default full month when days are set to 30/31
  class RoommateStore
    include Singleton

    MIN_RECOMMENDED_ROOMMATES = 3
    MAX_RECOMMENDED_ROOMMATES = 4
    MAX_ROOM_ADJUSTMENT = 2000
    MAX_DAYS_IN_MONTH = 31

    def initialize
      setup_database
    end

    # Get current roommates and their default adjustments
    def get_permanent_roommates
      stmt = db.prepare(<<-SQL)
        SELECT name, room_adjustment
        FROM roommates
        WHERE end_date IS NULL
        ORDER BY name
      SQL
      
      results = stmt.execute.map do |row|
        [row[0], { room_adjustment: row[1]&.to_i }]
      end
      
      Hash[results]
    end

    # Get all roommates for a specific month, including temporary stays
    def get_roommates(year, month)
      base = get_permanent_roommates
      
      # Get any month-specific overrides or temporary stays
      stmt = db.prepare(<<-SQL)
        SELECT name, days, room_adjustment
        FROM monthly_stays
        WHERE year = ? AND month = ?
      SQL
      
      stmt.execute(year, month).each do |row|
        name, days, adjustment = row
        base[name] ||= {}
        base[name][:days] = days.to_i if days
        base[name][:room_adjustment] = adjustment.to_i if adjustment
      end
      
      base
    end

    # Add or update a permanent roommate
    def add_permanent_roommate(name, room_adjustment = nil, start_date = Date.today, force: false)
      validate_room_adjustment!(room_adjustment) if room_adjustment
      future_count = count_future_roommates(start_date) + 1
      
      unless force
        if future_count < MIN_RECOMMENDED_ROOMMATES
          raise RoommateError, "Adding #{name} would result in #{future_count} roommates, which is fewer than recommended (#{MIN_RECOMMENDED_ROOMMATES}). Use force: true to override."
        elsif future_count > MAX_RECOMMENDED_ROOMMATES
          raise RoommateError, "Adding #{name} would result in #{future_count} roommates, which is more than recommended (#{MAX_RECOMMENDED_ROOMMATES}). Use force: true to override."
        end
      end

      db.execute(<<-SQL, [name, room_adjustment, start_date.to_s])
        INSERT INTO roommates (name, room_adjustment, start_date)
        VALUES (?, ?, ?)
      SQL
    end

    # Record a roommate's departure
    def set_departure(name, end_date, force: false)
      future_count = count_future_roommates(end_date) - 1
      
      unless force
        if future_count < MIN_RECOMMENDED_ROOMMATES
          raise RoommateError, "Removing #{name} would result in #{future_count} roommates, which is fewer than recommended (#{MIN_RECOMMENDED_ROOMMATES}). Use force: true to override."
        end
      end

      db.execute(<<-SQL, [end_date.to_s, name])
        UPDATE roommates
        SET end_date = ?
        WHERE name = ? AND end_date IS NULL
      SQL
    end

    # Add or update a temporary stay or month-specific override
    def set_monthly_stay(name, year, month, days: nil, room_adjustment: nil)
      if days
        validate_days!(days, year, month)
        if [30, 31].include?(days)
          raise RoommateError, "For a full month stay, omit the days parameter and let the system calculate the correct number of days automatically."
        end
      end
      
      validate_room_adjustment!(room_adjustment) if room_adjustment

      db.execute(<<-SQL, [name, year, month, days, room_adjustment])
        INSERT INTO monthly_stays (name, year, month, days, room_adjustment)
        VALUES (?, ?, ?, ?, ?)
      SQL
    end

    # Update a room adjustment (affects all future calculations)
    def update_room_adjustment(name, adjustment, force: false)
      validate_room_adjustment!(adjustment, force: force)

      db.execute(<<-SQL, [adjustment, name])
        UPDATE roommates
        SET room_adjustment = ?
        WHERE name = ? AND end_date IS NULL
      SQL
    end

    # Get history of changes
    def get_changes(limit = 10)
      changes = []
      
      # Get permanent roommate changes
      stmt = db.prepare(<<-SQL)
        SELECT name, room_adjustment, start_date, end_date
        FROM roommates
        ORDER BY start_date DESC
        LIMIT ?
      SQL
      
      stmt.execute(limit).each do |row|
        name, adjustment, start_date, end_date = row
        changes << {
          type: end_date ? 'departure' : 'arrival',
          name: name,
          date: end_date || start_date,
          room_adjustment: adjustment
        }
      end

      # Get temporary stays
      stmt = db.prepare(<<-SQL)
        SELECT name, year, month, days, room_adjustment
        FROM monthly_stays
        ORDER BY year DESC, month DESC
        LIMIT ?
      SQL
      
      stmt.execute(limit).each do |row|
        name, year, month, days, adjustment = row
        changes << {
          type: 'temporary_stay',
          name: name,
          year: year,
          month: month,
          days: days,
          room_adjustment: adjustment
        }
      end

      changes.sort_by { |c| c[:date] || "#{c[:year]}-#{c[:month]}" }.reverse
    end

    private

    def db
      @db ||= begin
        path = File.expand_path('../data/roommate_config.db', __dir__)
        FileUtils.mkdir_p(File.dirname(path))
        SQLite3::Database.new(path)
      end
    end

    def setup_database
      # Create tables if they don't exist
      db.execute <<-SQL
        CREATE TABLE IF NOT EXISTS roommates (
          id INTEGER PRIMARY KEY,
          name TEXT NOT NULL,
          room_adjustment INTEGER,
          start_date DATE NOT NULL,
          end_date DATE,
          created_at DATETIME DEFAULT CURRENT_TIMESTAMP
        );
      SQL

      db.execute <<-SQL
        CREATE TABLE IF NOT EXISTS monthly_stays (
          id INTEGER PRIMARY KEY,
          name TEXT NOT NULL,
          year INTEGER NOT NULL,
          month INTEGER NOT NULL,
          days INTEGER,
          room_adjustment INTEGER,
          created_at DATETIME DEFAULT CURRENT_TIMESTAMP
        );
      SQL

      # Create indexes
      db.execute "CREATE INDEX IF NOT EXISTS idx_roommates_name ON roommates(name);"
      db.execute "CREATE INDEX IF NOT EXISTS idx_monthly_stays_date ON monthly_stays(year, month);"
    end

    def count_future_roommates(date)
      stmt = db.prepare(<<-SQL)
        SELECT COUNT(*)
        FROM roommates
        WHERE (end_date IS NULL OR end_date > ?)
        AND start_date <= ?
      SQL
      
      stmt.execute(date.to_s, date.to_s).first[0]
    end

    def validate_room_adjustment!(adjustment, force: false)
      return unless adjustment
      
      if adjustment.abs > MAX_ROOM_ADJUSTMENT && !force
        raise RoommateError, "Room adjustment (#{adjustment}kr) exceeds maximum recommended value (±#{MAX_ROOM_ADJUSTMENT}kr). Use force: true to override."
      end
    end

    def validate_days!(days, year, month)
      return unless days
      
      max_days = Date.new(year, month, -1).day
      if days > max_days
        raise RoommateError, "Days (#{days}) exceeds maximum days in #{year}-#{month} (#{max_days})"
      elsif days <= 0
        raise RoommateError, "Days must be positive"
      end
    end
  end
end
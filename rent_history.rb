module RentCalculator
  class RentHistory
    def initialize(history_file)
      @history_file = history_file
      @history = load_history
    end

    def add_month(roommates:, config: {})
      results = RentCalculator.rent_breakdown(roommates: roommates, config: config)
      month = config[:month] || Date.today.month
      year = config[:year] || Date.today.year
      
      @history[year] ||= {}
      @history[year][month] = {
        'config' => config,
        'roommates' => roommates,
        'results' => results
      }
      
      save_history
      results
    end

    def get_month(year:, month:)
      @history.dig(year, month)
    end

    def get_latest
      return nil if @history.empty?
      
      latest_year = @history.keys.max
      latest_month = @history[latest_year].keys.max
      
      get_month(year: latest_year, month: latest_month)
    end

    private

    def load_history
      return {} unless File.exist?(@history_file)
      
      content = File.read(@history_file)
      return {} if content.empty?
      
      Helpers.symbolize_keys(JSON.parse(content))
    end

    def save_history
      File.write(@history_file, JSON.pretty_generate(@history))
    end
  end
end 
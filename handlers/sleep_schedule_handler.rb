require 'oj'

class SleepScheduleHandler
  CONFIG_PATH = File.join(__dir__, '..', 'config', 'sleep_schedule.json')

  def self.get_config
    unless File.exist?(CONFIG_PATH)
      return {
        success: false,
        error: 'Sleep schedule config not found'
      }
    end

    begin
      content = File.read(CONFIG_PATH)
      config = Oj.load(content)

      {
        success: true,
        config: config,
        timestamp: Time.now.to_i
      }
    rescue => e
      {
        success: false,
        error: "Failed to read config: #{e.message}"
      }
    end
  end
end

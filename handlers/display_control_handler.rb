require 'open3'

class DisplayControlHandler
  # Pragmatic security: whitelist exact commands, no user input injection
  DISPLAY_COMMANDS = {
    'off' => 'xset dpms force off',
    'on' => 'xset dpms force on'
  }.freeze

  def self.handle_display_power(params)
    action = params['action']

    # Validate action exists in whitelist
    unless DISPLAY_COMMANDS.key?(action)
      return { success: false, error: 'Invalid action' }
    end

    # Execute with DISPLAY environment set
    stdout, stderr, status = Open3.capture3(
      { 'DISPLAY' => ':0' },
      DISPLAY_COMMANDS[action]
    )

    if status.success?
      { success: true, state: action, timestamp: Time.now.to_i }
    else
      { success: false, error: stderr.strip }
    end
  rescue => e
    { success: false, error: e.message }
  end

  def self.handle_brightness(params)
    level = params['level'].to_f

    # Validate brightness range (0.7-1.5 for our use case)
    unless level >= 0.7 && level <= 1.5
      return { success: false, error: 'Brightness must be 0.7-1.5' }
    end

    # Execute xrandr brightness command
    stdout, stderr, status = Open3.capture3(
      { 'DISPLAY' => ':0' },
      'xrandr', '--output', 'HDMI-0', '--brightness', level.to_s
    )

    if status.success?
      { success: true, brightness: level, timestamp: Time.now.to_i }
    else
      { success: false, error: stderr.strip }
    end
  rescue => e
    { success: false, error: e.message }
  end
end

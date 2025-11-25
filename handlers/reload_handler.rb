# Handler for triggering frontend reload after deployments
class ReloadHandler
  RELOAD_COOLDOWN = 120 # seconds (2 minutes) - matches webhook debounce, prevents reload loops
  RELOAD_WINDOW = 120   # seconds (2 minutes) - send reload to new connections within this window

  def initialize(pubsub)
    @pubsub = pubsub
    @last_reload_broadcast = nil
    @reload_window_until = nil
    @reload_message = nil
  end

  def call(env)
    # Only allow POST requests
    return [405, {'Content-Type' => 'application/json'}, [{error: 'Method not allowed'}.to_json]] unless env['REQUEST_METHOD'] == 'POST'

    now = Time.now.to_i

    # Throttle: Only allow one reload broadcast per 30 seconds
    if @last_reload_broadcast && (now - @last_reload_broadcast) < RELOAD_COOLDOWN
      time_remaining = RELOAD_COOLDOWN - (now - @last_reload_broadcast)
      puts "ReloadHandler: Throttled - #{time_remaining}s remaining since last reload"
      return [429, {'Content-Type' => 'application/json'},
              [{error: 'Reload cooldown active',
                time_remaining: time_remaining,
                message: "Please wait #{time_remaining} seconds before triggering another reload"}.to_json]]
    end

    # Broadcast reload message to all connected WebSocket clients
    @reload_message = {
      type: 'reload',
      payload: {message: 'New version deployed, reloading...'},
      timestamp: now
    }.to_json

    @pubsub.publish(@reload_message)
    @last_reload_broadcast = now
    @reload_window_until = now + RELOAD_WINDOW
    puts "ReloadHandler: Broadcast reload message to all clients (reload window active for #{RELOAD_WINDOW}s)"

    [200, {'Content-Type' => 'application/json'}, [{success: true, message: 'Reload triggered'}.to_json]]
  end

  # Check if we're in the reload window (send reload to new connections)
  def in_reload_window?
    @reload_window_until && Time.now.to_i < @reload_window_until
  end

  # Get the reload message to send to new connections
  def reload_message
    @reload_message
  end
end

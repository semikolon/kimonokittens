# Handler for triggering frontend reload after deployments
class ReloadHandler
  def initialize(pubsub)
    @pubsub = pubsub
  end

  def call(req)
    # Only allow POST requests
    return [405, {'Content-Type' => 'application/json'}, [{error: 'Method not allowed'}.to_json]] unless req.post?

    # Broadcast reload message to all connected WebSocket clients
    message = {
      type: 'reload',
      payload: {message: 'New version deployed, reloading...'},
      timestamp: Time.now.to_i
    }.to_json

    @pubsub.publish(message)
    puts "ReloadHandler: Broadcast reload message to all clients"

    [200, {'Content-Type' => 'application/json'}, [{success: true, message: 'Reload triggered'}.to_json]]
  end
end

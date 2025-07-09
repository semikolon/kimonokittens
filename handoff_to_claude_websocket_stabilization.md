# OBSOLETE: See DEVELOPMENT.md for the canonical Agoo/WebSocket fix (July 2025)

## Handoff Plan: Stabilizing the WebSocket Server

**To Claude:**

Hello! We've been experiencing persistent `500 Internal Server Errors` with our WebSocket implementation for the Kimonokittens Handbook. Your task is to apply a critical fix to `json_server.rb` to resolve this instability.

### 1. The Problem: Unreliable Client Identification

The root cause of the errors is in how we track WebSocket clients. The current `PubSub` module uses the `client.hash` value as a unique key for each connection. This hash is not a stable identifier throughout the connection's lifecycle, especially when a connection closes unexpectedly. This leads to lookup failures when trying to `unsubscribe` a client, causing the server to crash.

The server logs confirm this with repeated connection failures on the `/handbook/ws` endpoint.

### 2. The Solution: Use Agoo's Connection ID

The Agoo web server provides a stable and unique identifier for each connection called `con_id`. We must refactor our code to use this `con_id` as the key for managing WebSocket clients in our `PubSub` module.

This involves two main changes:
1.  Update the `PubSub` module to key its client list by `con_id`.
2.  Update the `WsHandler` to correctly manage the WebSocket lifecycle and pass the `con_id` to `PubSub`. The current `WsHandler` implementation is also functionally incorrect for the version of Agoo we are using and needs to be replaced.

### 3. Step-by-Step Implementation Guide

Please apply the following changes to the `json_server.rb` file.

**Step 1: Replace the `PubSub` class**

Delete the entire existing `PubSub` class (from `class PubSub` to the corresponding `end`) and replace it with this improved version. This new version uses a `con_id` to track clients.

```ruby
# --- WebSocket Pub/Sub Manager ---
# A simple in-memory manager for WebSocket connections.
class PubSub
  def initialize
    @clients = {}
    @mutex = Mutex.new
  end

  def subscribe(con_id, client)
    @mutex.synchronize do
      @clients[con_id] = client
    end
    puts "Client subscribed with con_id: #{con_id}"
  end

  def unsubscribe(con_id)
    @mutex.synchronize do
      @clients.delete(con_id)
    end
    puts "Client unsubscribed with con_id: #{con_id}"
  end

  def publish(message)
    @mutex.synchronize do
      @clients.values.each do |client|
        # Agoo's #write is thread-safe
        client.write(message)
      end
    end
    puts "Published message to #{@clients.size} clients: #{message}"
  end
end
```

**Step 2: Replace the `WsHandler` class**

Delete the entire existing `WsHandler` class and replace it with this new implementation. This version correctly handles the Agoo WebSocket lifecycle callbacks and uses the `con_id`.

```ruby
class WsHandler
  # Called once when the WebSocket connection is established.
  def on_open(client)
    @con_id = client.con_id
    $pubsub.subscribe(@con_id, client)
  end

  # Called when the connection is closed.
  def on_close(client)
    $pubsub.unsubscribe(@con_id) if @con_id
  end

  # Called when a message is received from the client.
  def on_message(client, msg)
    puts "Received WebSocket message from #{@con_id}: #{msg}"
    # Echo back messages for debugging
    client.write("echo: #{msg}")
  end

  # This method is required by Agoo for handling the initial HTTP upgrade request.
  # We leave it empty because the on_* callbacks handle the logic.
  def call(env)
    # The 'rack.upgrade' check is implicitly handled by Agoo when assigning
    # a handler to a route, so we don't need to check for it here.
    # The return value of [0, {}, []] is a valid empty Rack response,
    # though it's not strictly used after the upgrade.
    [0, {}, []]
  end
end
```

**Step 3: Verify the changes**

After applying these edits, the `json_server.rb` file should contain the two new classes you just inserted. The rest of the file should remain unchanged.

Thank you for applying this fix! This should stabilize our real-time features. 
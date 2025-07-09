# Handoff Plan: Stabilizing WebSocket Server & Fixing Critical Issues

**To Claude:**

Hello! We have multiple critical issues in the Kimonokittens project that need immediate attention. Your task is to systematically fix these problems to restore stability.

## 1. Critical Issues Identified

### Issue A: WebSocket Server Crashes (500 Internal Server Errors)
- **Problem**: The `/handbook/ws` endpoint consistently returns 500 errors
- **Root Cause**: The `WsHandler` class is using an incorrect Agoo WebSocket implementation
- **Impact**: No real-time updates work, causing persistent `ECONNRESET` errors in Vite proxy

### Issue B: Ruby Server Segfaults
- **Problem**: The `json_server.rb` crashes with segmentation faults
- **Root Cause**: Likely related to WebSocket connection handling or memory management
- **Impact**: Complete server failure requiring manual restarts

### Issue C: Train API Connection Failures
- **Problem**: SL API calls fail with DNS resolution errors: `getaddrinfo: nodename nor servname provided, or not known`
- **Root Cause**: The old SL API endpoint may be deprecated or unreliable
- **Impact**: Train departure widget shows errors instead of data

## 2. Systematic Fix Plan

### Step 1: Fix WebSocket Handler (Critical Priority)

The current `WsHandler` implementation is fundamentally broken. Replace the entire `WsHandler` class in `json_server.rb` with this corrected version:

```ruby
class WsHandler
  def call(env)
    if env['rack.upgrade?'] == :websocket
      env['rack.upgrade'] = self.class   # hand the CLASS, not an instance
      # DO NOT CHANGE THIS STATUS CODE! Agoo+Rack requires 101 (Switching Protocols) for WebSocket upgrades.
      # See: https://github.com/ohler55/agoo/issues/216
      return [101, {}, []]               # 101 Switching Protocols is the correct status
    end
    [404, { 'Content-Type' => 'text/plain' }, ['Not Found']]
  end

  def on_open(client)
    con_id = client.con_id
    client.vars[:con_id] = con_id        # store per-connection state
    $pubsub.subscribe(con_id, client)
    puts "HANDBOOK WS: open #{con_id}"
  end

  def on_message(client, msg)
    con_id = client.vars[:con_id]
    puts "HANDBOOK WS: #{con_id} -> #{msg}"
    client.write("echo: #{msg}")
  end

  def on_close(client)
    con_id = client.vars[:con_id]
    $pubsub.unsubscribe(con_id) if con_id
    puts "HANDBOOK WS: close #{con_id}"
  end
end
```

### Step 2: Fix PubSub Manager (Critical Priority)

The `PubSub` class needs to use stable connection IDs. Replace the entire `PubSub` class with:

```ruby
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

### Step 3: Migrate Train API (High Priority)

The user has identified two potential replacement APIs for the failing SL train API:

1. **Trafiklab Realtime APIs** (Recommended): https://www.trafiklab.se/api/our-apis/trafiklab-realtime-apis/
   - Requires API key but more reliable
   - Better performance and higher quotas
   - CC-BY license (just needs attribution)

2. **SL Transport API** (Fallback): https://www.trafiklab.se/api/our-apis/sl/transport/
   - No API key needed
   - May have lower reliability/quotas

**Action Required**: Update `handlers/train_departure_handler.rb` to use the new Trafiklab Realtime API. The current endpoint `https://api.sl.se/api2/realtimedeparturesV4.json` should be replaced with the new API endpoint.

### Step 4: Test and Verify

After making these changes:

1. **Test WebSocket Connection**: 
   - Start both servers (`bundle exec ruby json_server.rb` and `npm run dev` in dashboard/)
   - Open browser to `http://localhost:5175/`
   - Check browser console for WebSocket connection success (no more ECONNRESET errors)

2. **Test Train API**:
   - Verify `/data/train_departures` endpoint returns data instead of 500 errors
   - Check that TrainWidget displays departure times

3. **Test Server Stability**:
   - Leave server running for extended period
   - Monitor for segfaults or crashes

## 3. Key Implementation Notes

### WebSocket Status Codes
- **CRITICAL**: Use `[101, {}, []]` for WebSocket upgrades, not `[0, {}, []]`
- Status code 0 is invalid in Rack and causes 500 errors
- Status code 101 is the HTTP standard for "Switching Protocols"

### Connection Management
- Always use `client.con_id` as the stable identifier
- Store per-connection state in `client.vars[:key]`
- Never use `client.hash` as it's unreliable

### Error Handling
- Add proper error handling to prevent segfaults
- Use mutex synchronization for thread-safe operations
- Log all connection events for debugging

## 4. Expected Outcomes

After implementing these fixes:
- ✅ WebSocket connections should establish successfully
- ✅ Real-time updates should work in the dashboard
- ✅ Train departure data should load correctly
- ✅ Server should run stably without segfaults
- ✅ Browser console should show no more ECONNRESET errors

## 5. Testing Commands

```bash
# Start backend server
bundle exec ruby json_server.rb

# Start frontend server (in separate terminal)
cd dashboard && npm run dev

# Test WebSocket endpoint
curl -i -N -H "Connection: Upgrade" -H "Upgrade: websocket" -H "Sec-WebSocket-Key: test" -H "Sec-WebSocket-Version: 13" http://localhost:3001/handbook/ws

# Test train API
curl http://localhost:3001/data/train_departures
```

Thank you for implementing these critical fixes! This should resolve all the stability issues and restore full functionality to the dashboard. 
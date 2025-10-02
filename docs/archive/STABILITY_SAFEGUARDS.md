# Kiosk Stability Safeguards

## The Reload Loop Incident (Oct 2, 2025)

**What Happened:**
- Auto-reload feature caused infinite reload loop
- `sudo systemctl stop kimonokittens-kiosk` FAILED (wrong user session)
- Only `machinectl shell kimonokittens@ /usr/bin/systemctl --user stop kimonokittens-kiosk` worked
- CPU usage: 758% across 24 Chrome processes
- System nearly unusable

**Root Cause:**
1. No client-side reload throttling/circuit breaker
2. No deduplication of reload messages
3. Chrome reconnects immediately, retriggering reload
4. User systemd services require `machinectl` from root

---

## Multi-Layer Protection System

### Layer 1: Client-Side Circuit Breaker (CRITICAL)

**Location:** `dashboard/src/context/DataContext.tsx`

```typescript
// Circuit breaker to prevent reload loops
const RELOAD_WINDOW_MS = 60000 // 1 minute
const MAX_RELOADS = 3 // Max reloads per window
const CIRCUIT_BREAKER_KEY = 'kiosk_reload_circuit_breaker'
const LAST_RELOAD_KEY = 'kiosk_last_reload'

function checkReloadCircuitBreaker(): boolean {
  const now = Date.now()
  const circuitBreakerData = localStorage.getItem(CIRCUIT_BREAKER_KEY)

  if (circuitBreakerData) {
    const { reloads, windowStart } = JSON.parse(circuitBreakerData)

    // Reset window if expired
    if (now - windowStart > RELOAD_WINDOW_MS) {
      localStorage.setItem(CIRCUIT_BREAKER_KEY, JSON.stringify({
        reloads: 1,
        windowStart: now
      }))
      return true
    }

    // Check if circuit breaker should trip
    if (reloads >= MAX_RELOADS) {
      console.error('🚨 RELOAD CIRCUIT BREAKER TRIPPED - Too many reloads in 60s')
      // Show error screen instead of reloading
      document.body.innerHTML = `
        <div style="background: #991b1b; color: white; padding: 40px; text-align: center; font-family: sans-serif;">
          <h1>⚠️ System Protection Active</h1>
          <p>Too many page reloads detected (${reloads} in 60 seconds)</p>
          <p>Circuit breaker has been activated to prevent system instability</p>
          <p style="margin-top: 20px; opacity: 0.8;">
            Will auto-reset in ${Math.ceil((RELOAD_WINDOW_MS - (now - windowStart)) / 1000)}s
          </p>
          <button onclick="localStorage.clear(); location.reload()"
                  style="margin-top: 20px; padding: 10px 20px; font-size: 16px;">
            Manual Reset
          </button>
        </div>
      `
      return false
    }

    // Increment reload count
    localStorage.setItem(CIRCUIT_BREAKER_KEY, JSON.stringify({
      reloads: reloads + 1,
      windowStart
    }))
    return true
  }

  // First reload in window
  localStorage.setItem(CIRCUIT_BREAKER_KEY, JSON.stringify({
    reloads: 1,
    windowStart: now
  }))
  return true
}

// In WebSocket message handler:
case 'reload':
  console.log('Reload message received from server')

  // Check circuit breaker
  if (!checkReloadCircuitBreaker()) {
    console.error('Reload blocked by circuit breaker')
    break
  }

  // Check minimum time since last reload (deduplication)
  const lastReload = localStorage.getItem(LAST_RELOAD_KEY)
  const now = Date.now()
  if (lastReload && (now - parseInt(lastReload)) < 30000) {
    console.warn('Reload ignored - too soon after previous reload')
    break
  }

  localStorage.setItem(LAST_RELOAD_KEY, now.toString())
  console.log('Reloading page...')
  window.location.reload()
  break
```

**Protection:**
- Max 3 reloads per 60 seconds
- Shows error screen if limit exceeded
- Auto-resets after timeout
- Manual reset button available

---

### Layer 2: Server-Side Reload Message Tracking

**Location:** `puma_server.rb` or `handlers/reload_handler.rb`

```ruby
# Track which connections have been sent reload messages
$reload_message_sent = {}
$last_reload_broadcast = nil

class ReloadHandler
  def call(req)
    return [405, {'Content-Type' => 'application/json'},
            [{error: 'Method not allowed'}.to_json]] unless req.post?

    now = Time.now.to_i

    # Throttle: Only allow one reload broadcast per 30 seconds
    if $last_reload_broadcast && (now - $last_reload_broadcast) < 30
      puts "ReloadHandler: Throttled - reload sent #{now - $last_reload_broadcast}s ago"
      return [429, {'Content-Type' => 'application/json'},
              [{error: 'Too many reload requests'}.to_json]]
    end

    message = {
      type: 'reload',
      payload: {
        message: 'New version deployed, reloading...',
        timestamp: now
      },
      timestamp: now
    }.to_json

    @pubsub.publish(message)
    $last_reload_broadcast = now

    puts "ReloadHandler: Broadcast reload message to all clients"

    [200, {'Content-Type' => 'application/json'},
     [{success: true, message: 'Reload triggered', timestamp: now}.to_json]]
  end
end
```

**Protection:**
- Only ONE reload broadcast per 30 seconds
- Prevents webhook from spamming reload messages

---

### Layer 3: WebSocket Connection Handling

**Never send reload on reconnection:**

```ruby
# In puma_server.rb WebSocket handler:
ws.onopen do |handshake|
  con_id = rand(1000..9999)
  puts "WS: Connection opened #{con_id}"

  $pubsub.subscribe do |message|
    begin
      # Parse message to check type
      msg_data = JSON.parse(message)

      # NEVER send reload messages to newly connected clients
      # Only send reload to clients that were already connected
      if msg_data['type'] == 'reload'
        # Skip reload for new connections (first 5 seconds)
        next if (Time.now.to_i - handshake_time) < 5
      end

      ws.send(message)
    rescue => e
      puts "Error sending message: #{e.message}"
    end
  end
end
```

---

### Layer 4: Systemd Management Tools

**Create helper script:** `/home/fredrik/Projects/kimonokittens/bin/kiosk-control`

```bash
#!/bin/bash
# Kiosk control script - manages kimonokittens user services from any user

COMMAND="$1"
SERVICE="${2:-kimonokittens-kiosk}"

case "$COMMAND" in
  start)
    machinectl shell kimonokittens@.host /usr/bin/systemctl --user start "$SERVICE"
    ;;
  stop)
    machinectl shell kimonokittens@.host /usr/bin/systemctl --user stop "$SERVICE"
    ;;
  restart)
    machinectl shell kimonokittens@.host /usr/bin/systemctl --user restart "$SERVICE"
    ;;
  status)
    machinectl shell kimonokittens@.host /usr/bin/systemctl --user status "$SERVICE"
    ;;
  *)
    echo "Usage: $0 {start|stop|restart|status} [service-name]"
    echo "Default service: kimonokittens-kiosk"
    exit 1
    ;;
esac
```

**Make executable:**
```bash
chmod +x /home/fredrik/Projects/kimonokittens/bin/kiosk-control
```

**Usage:**
```bash
# Stop kiosk (works from any user, including root)
./bin/kiosk-control stop

# Restart dashboard
./bin/kiosk-control restart kimonokittens-dashboard

# Check status
./bin/kiosk-control status
```

---

### Layer 5: Chrome Kiosk Service Restart Delay

**Update service file:** `/home/kimonokittens/.config/systemd/user/kimonokittens-kiosk.service`

Add restart protection:

```ini
[Service]
# ... existing config ...

# Prevent rapid restart loops
Restart=on-failure
RestartSec=10s
StartLimitBurst=3
StartLimitIntervalSec=60s

# If Chrome crashes 3 times in 60s, stop trying
```

**Apply:**
```bash
machinectl shell kimonokittens@.host /usr/bin/systemctl --user daemon-reload
machinectl shell kimonokittens@.host /usr/bin/systemctl --user restart kimonokittens-kiosk
```

---

### Layer 6: Emergency Kill Switch

**Create emergency script:** `/home/fredrik/Projects/kimonokittens/bin/emergency-stop`

```bash
#!/bin/bash
# EMERGENCY: Stop all kiosk processes immediately

echo "🚨 EMERGENCY STOP INITIATED"

# Method 1: Stop via machinectl
echo "Stopping kiosk service..."
machinectl shell kimonokittens@.host /usr/bin/systemctl --user stop kimonokittens-kiosk

# Method 2: Kill Chrome processes
echo "Killing Chrome processes..."
pkill -u kimonokittens chrome

# Method 3: Stop dashboard if needed
echo "Stopping dashboard..."
machinectl shell kimonokittens@.host /usr/bin/systemctl --user stop kimonokittens-dashboard

echo "✅ Emergency stop complete"
echo "To restart: ./bin/kiosk-control start"
```

**Make executable:**
```bash
chmod +x /home/fredrik/Projects/kimonokittens/bin/emergency-stop
```

---

## Implementation Priority

1. **IMMEDIATE (Critical):**
   - ✅ Disable reload feature (already done)
   - [ ] Create `bin/kiosk-control` helper script
   - [ ] Create `bin/emergency-stop` script
   - [ ] Update kiosk service with RestartSec protection

2. **HIGH (Before re-enabling reload):**
   - [ ] Implement client-side circuit breaker
   - [ ] Implement server-side reload throttling
   - [ ] Add WebSocket reconnection protection

3. **MEDIUM (Monitoring):**
   - [ ] Add reload event logging
   - [ ] Monitor reload frequency
   - [ ] Alert on abnormal reload patterns

---

## Testing the Safeguards

**Test 1: Circuit Breaker**
1. Manually trigger 3 reloads in 30 seconds
2. 4th reload should show error screen
3. Wait 60 seconds - should auto-reset

**Test 2: Server Throttling**
1. Call `/api/reload` endpoint 5 times rapidly
2. Should get 429 (Too Many Requests) after first call within 30s

**Test 3: Emergency Stop**
1. Run `./bin/emergency-stop`
2. All Chrome processes should die
3. Kiosk service should stop
4. Should be able to restart with `./bin/kiosk-control start`

---

## Why This Works

**Defense in Depth:**
- Client prevents excessive reloads (circuit breaker)
- Server prevents reload spam (throttling)
- WebSocket prevents reconnection loops (connection time check)
- Systemd prevents crash loops (RestartSec)
- Emergency tools provide manual override (machinectl scripts)

**No Single Point of Failure:**
- If one layer fails, others catch the problem
- Multiple kill switches available
- Clear escalation path for emergencies

---

## References

- [Circuit Breaker Pattern - Martin Fowler](https://martinfowler.com/bliki/CircuitBreaker.html)
- [systemd User Services Management](https://unix.stackexchange.com/questions/552922/stop-systemd-user-services-as-root-user)
- [Android Kiosk Browser Recovery Screen](https://help.android-kiosk.com/en/article/kiosk-browser-changelog-v200-and-up-1p1yqrh/)

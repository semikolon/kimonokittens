# Smart Appliance Monitoring - Implementation Plan

**Created**: 2025-11-23
**Status**: Deferred to Dec 2025/Jan 2026
**Related**: ChatGPT conversation `/Users/fredrikbranstrom/Downloads/Smart Washing Machine Dishwasher.md`

---

## Current Progress

### ✅ Completed
- TinyTuya 1.17.4 installed (Nov 24, 2025)
- Network scan completed: 24 Tuya devices discovered on 192.168.4.x
- Device protocol versions identified: 7× v3.3, 15× v3.4, 2× v3.5
- Scan results saved to `snapshot.json`
- **Clarified**: TinyTuya still requires Tuya IoT Platform API setup (not a workaround)

### ⏳ Deferred Until Dec 2025/Jan 2026
**Blocker**: Tuya IoT Platform API access required for local_key extraction

**Next steps when resuming:**
1. **Renew Tuya IoT Core subscription** on iot.tuya.com (1-6 month renewal via form)
2. **Run TinyTuya wizard** with API credentials (Access ID + Secret + Region)
   ```bash
   python -m tinytuya wizard
   # Enter API ID, Secret, Region when prompted
   # Wizard fetches local_keys from cloud and saves to devices.json
   ```
3. Extract device names and local_keys from generated `devices.json`
4. Identify washing machine plug from device list
5. Set DHCP reservation for stable IP
6. Continue with Phase 1 Node-RED integration

---

## Vision

Monitor washing machine, tumble dryer, and dishwasher usage via **Deltaco smart plugs** (energy monitoring) to show real-time status on hallway dashboard and send notifications when cycles complete.

**Goal**: Eliminate the "is the washing machine free?" question for 4 housemates sharing basement appliances.

---

## Hardware Setup (Current State)

### Installed
- ✅ **1× Deltaco smart plug** on washing machine
  - Device ID: `bf011c1842a8f0201fxjdy` (from Smart Life app)
  - Visible in Smart Life app
  - Energy monitoring: Yes (13A/16A capable)
  - Network discovered: Device present in TinyTuya scan results
  - Local key: Pending extraction via TinyTuya wizard

### Planned
- [ ] **2× more Deltaco plugs** for tumble dryer + dishwasher
  - Same model, same setup process
  - Budget: ~320 kr for 2 more plugs

---

## Architecture Overview

```
Smart Plugs (basement)
  ↓ [Local Tuya protocol via WiFi]
Node-RED (Pi in hallway)
  ↓ [HTTP/JSON endpoint]
Dashboard Backend (puma_server.rb)
  ↓ [WebSocket broadcast]
Hallway Dashboard (React)
```

**Key principle**: **Local control only** - no cloud dependency after initial setup. Uses Tuya `local_key` for direct UDP communication.

---

## Implementation Phases

### Phase 1: Node-RED Integration (Foundation)

**Goal**: Get washing machine power readings into Node-RED with state detection.

**Tasks**:
1. **Get device credentials** (using TinyTuya):
   ```bash
   # Prerequisites: Tuya IoT Platform account + Cloud Project setup
   # 1. Renew IoT Core subscription on iot.tuya.com (1-6 month renewal)
   # 2. Get API credentials: Access ID + Secret + Region
   # 3. Link Smart Life app via QR code in Cloud Project

   # On Pi (or Mac for testing)
   pip install tinytuya
   python -m tinytuya wizard
   # Enter API ID, Secret, Region when prompted
   # Wizard fetches local_keys from Tuya cloud
   # Auto-discovers device IPs via network scan
   # Saves complete device info to devices.json
   ```
   - Device ID: `bf011c1842a8f0201fxjdy` (confirm from wizard output)
   - Local key: Extract from `devices.json` after wizard completes
   - LAN IP: Auto-discovered by TinyTuya wizard (or find via router DHCP MAC: `18:de:50:3e:f4:a5`)
   - Set DHCP reservation for stable IP

2. **Install Node-RED module**:
   ```bash
   # On Pi (192.168.4.66)
   cd ~/.node-red
   npm install node-red-contrib-tuya-smart-device
   ```

3. **Create Tuya device node**:
   - Config: device_id, local_key, IP, version 3.3/3.4
   - Mode: Listen/receive status updates
   - Output: DPS object with power readings

4. **Build state machine flow**:
   ```javascript
   // State detection logic (function node)
   const watts = msg.payload.dps["19"] || 0;  // Power in watts

   const RUNNING_W = 10;   // > 10W = running
   const IDLE_W = 3;       // < 3W for 3 min = finished

   // States: idle, running, finished
   // Track transitions for notification triggers
   ```

5. **Test & calibrate**:
   - Run actual wash cycle
   - Capture power signature (start spike, running steady, drain/spin spikes, idle)
   - Tune thresholds for reliable detection
   - Add debouncing (3-5 min quiet period before "finished")

**Deliverable**: Node-RED flow that outputs `{watts, state, finished}` JSON every few seconds.

**Effort**: ~2 hours

---

### Phase 2: Dashboard Backend Integration

**Goal**: Expose appliance status via existing backend API + WebSocket.

**Tasks**:

1. **Create appliance status handler** (`handlers/appliance_status_handler.rb`):
   ```ruby
   # GET /api/appliances/status
   # Returns: { washing_machine: {state, watts, last_updated}, ... }
   ```

2. **Node-RED HTTP endpoint**:
   - Expose `/appliances/washing_machine` on Pi's Node-RED (port 1880)
   - Backend polls this endpoint every 10-30s (or Node-RED pushes to backend webhook)

3. **WebSocket broadcast integration**:
   - Add appliance data to `DataBroadcaster` refresh cycle
   - Broadcast on state changes (idle→running, running→finished)
   - Clients auto-update without polling

4. **Data model considerations**:
   - Store in memory (no DB needed for live status)
   - Optional: Log cycle completions to SQLite for usage stats
   - Track: current state, power draw, cycle start time, estimated completion

**Deliverable**: Backend API serving appliance status with WebSocket updates.

**Effort**: ~2 hours

---

### Phase 3: Dashboard UI Widget

**Goal**: Display appliance status on hallway dashboard.

**Tasks**:

1. **Create ApplianceWidget component** (`dashboard/src/components/ApplianceWidget.tsx`):
   - Shows 1-3 appliances (washing machine, dryer, dishwasher)
   - Visual states:
     - **Idle**: Muted gray, "Available"
     - **Running**: Blue glow, animated spinner, "In use - XX min"
     - **Finished**: Cyan glow (success color), "Ready to unload!"
   - Display power draw for nerds

2. **State transitions**:
   - Smooth CSS transitions (match existing widget style)
   - Pulsing glow for "finished" state (attention-grabbing)
   - Cycle timer: Estimate based on average cycle duration

3. **Data integration**:
   - Subscribe to WebSocket appliance updates
   - Use existing DataContext pattern
   - Handle offline/connection lost states

4. **Layout**:
   - Compact row/column layout (fits existing dashboard grid)
   - Mobile-friendly (visible on phone when checking from upstairs)

**Deliverable**: Working widget on dashboard showing live appliance status.

**Effort**: ~3 hours

---

### Phase 4: Notifications (Future Enhancement)

**Goal**: SMS alerts when cycles complete.

**Deferred until rent reminders SMS infrastructure exists** (46elks integration).

**Tasks** (when ready):
1. Subscribe to "finished" state transitions in Node-RED
2. Send SMS via 46elks API
3. Rate limit: Only notify once per cycle
4. Optional: Reminder pings if not emptied after 20 min
5. Optional: Booking system (Google Calendar or simple DB table)

**Deliverable**: SMS sent when washing machine finishes.

**Effort**: ~1 hour (after SMS infrastructure ready)

---

### Phase 5: Multi-Appliance Expansion

**Goal**: Add dryer and dishwasher monitoring.

**Tasks**:
1. Buy 2 more Deltaco plugs (~320 kr)
2. Add to Smart Life app
3. Extract local_key for each (via API Explorer)
4. Duplicate Node-RED flow (3 parallel flows)
5. Update backend to return all 3 appliances
6. Update UI widget to show all 3

**Deliverable**: Complete basement appliance monitoring.

**Effort**: ~1 hour (mostly hardware setup)

---

## Technical Considerations

### Network & Connectivity

**WiFi coverage in basement**:
- Concrete walls can weaken 2.4 GHz signal
- Check RSSI on plugs (aim for > -70 dBm)
- If needed: Add WiFi repeater or mesh node

**DHCP reservations**:
- Assign static IPs to all 3 plugs
- Prevents Node-RED connection failures after router reboot

**Fallback behavior**:
- If plug offline: Show "Disconnected" state (not "Idle")
- Store last known state for brief outages
- WebSocket clients handle reconnection gracefully

### Power Consumption Patterns

**Washing machine** (typical):
- Idle: 0-2W
- Running: 50-300W (varies by cycle phase)
- Heating phase: 1500-2000W spike
- Spin cycle: 400-600W
- Duration: 60-120 min

**Tumble dryer** (heat pump type):
- Idle: 0-2W
- Running: 500-1000W
- Duration: 90-150 min

**Dishwasher**:
- Idle: 0-2W
- Running: 1200-1800W (heating water)
- Duration: 120-180 min

**State detection challenges**:
- Brief pauses between cycle phases (don't trigger "finished")
- Door open mid-cycle (power drops to 0)
- Solution: Require 3-5 min below threshold before "finished"

### Existing Infrastructure Integration

**Pi Node-RED** (already running):
- Location: Basement/hallway Pi
- Purpose: MQTT broker, heatpump data aggregation
- New role: Appliance state machine + HTTP endpoint

**Dashboard backend** (`puma_server.rb`):
- Already has WebSocket broadcaster (`DataBroadcaster`)
- Already polls various endpoints (weather, temperature, etc.)
- Pattern: Add appliances to refresh cycle

**Dashboard frontend**:
- React + TypeScript
- Existing widget patterns (RentWidget, ClockWidget, etc.)
- Color scheme: Purple primary, Cyan success, NO GREEN

---

## Future Enhancements (Beyond MVP)

### Cost Tracking
- Log kWh per cycle (from energy monitoring)
- Calculate per-person usage
- Monthly cost breakdown on dashboard
- Integrate with NordPool spot prices

### Smart Scheduling
- Show "cheapest hours" overlay on price sparkline
- Suggest running during off-peak (< 21.4 öre/kWh grid fee)
- Estimate savings: "Running now costs 4.2 kr, wait 3h for 2.8 kr"

### Booking System
- Shared Google Calendar for laundry slots
- Auto-release if slot starts but machine not running (no-show)
- Reminders 10 min before booked slot

### Ambient Indicators
- LED strip in hallway (blue=running, green=finished)
- Existing LED infrastructure from Borderland project
- MQTT subscription to appliance state topics

### Usage Statistics
- Cycle count per month
- Average cycle duration
- Busiest days/times
- Per-person fairness metrics

---

## Cost Summary

### Hardware
- Smart plugs: 159 kr × 3 = **477 kr** (one already purchased)
- WiFi repeater (if needed): **300 kr**

### Services
- Tuya IoT Platform: **Free** (IoT Core subscription renewal required every 1-6 months)
- TinyTuya: **Free** (open source Python tool)
- SMS (future): 46elks ~0.65 kr/SMS

### Development Time
- Phase 1 (Node-RED): 2h
- Phase 2 (Backend): 2h
- Phase 3 (UI): 3h
- **Total MVP**: ~7 hours

---

## Dependencies

### External Services
- ✅ Smart Life app (for device pairing)
- ⏳ Tuya IoT Platform (for local_key extraction - subscription renewal required)
- ✅ TinyTuya (Python CLI tool - simplifies extraction after API setup)
- ✅ Local WiFi network (2.4 GHz required for plugs)

### Existing Infrastructure
- ✅ Pi with Node-RED (basement/hallway)
- ✅ Dashboard backend (puma_server.rb + WebSocket)
- ✅ React dashboard (hallway display)

### Future Dependencies
- ⏳ 46elks SMS API (for Phase 4 notifications)
- ⏳ Rent reminders infrastructure (for SMS integration)

---

## Risk Mitigation

### Tuya IoT Platform Dependency
**Reality**: Local_key extraction requires Tuya IoT Platform API access (unavoidable)
**Status**: IoT Core subscription expired Aug 28, 2025 - requires renewal

**TinyTuya Clarification**:
- TinyTuya simplifies local_key extraction AFTER you have API credentials
- Does NOT eliminate need for Tuya IoT Platform account + Cloud Project
- Requires: API ID + Secret + Region from iot.tuya.com
- Once extracted, local_keys work forever (until device reset/re-pair)

**Renewal Process** (as of Nov 2024):
- IoT Core subscription can be renewed for 1, 3, or 6 months
- Renewal via simple form (purpose, developer type)
- Less complex than initial setup

**Alternatives Considered**:
- Packet sniffing Smart Life app traffic (complex, fragile)
- Flash with Tasmota/ESPHome (hardware-dependent, may not support Deltaco plugs)
- Different hardware (Shelly, etc.) - requires buying new plugs

**Decision**: Defer until time permits Tuya renewal hassle (Dec 2025/Jan 2026)

### WiFi Signal Weak in Basement
**Risk**: Plugs disconnect frequently, status unreliable.
**Mitigation**:
- Test signal strength before full deployment
- Add WiFi repeater if RSSI < -70 dBm
- DHCP reservations prevent IP changes

### Power Signature Variations
**Risk**: Threshold-based detection fails with different wash programs.
**Mitigation**:
- Capture data from multiple cycle types
- Use conservative thresholds (fewer false positives)
- Add manual override in UI ("Mark as empty")

### Node-RED Reliability
**Risk**: Pi crashes, Node-RED stops, data stream breaks.
**Mitigation**:
- Systemd service for Node-RED (auto-restart)
- Dashboard shows "No data" vs stale data
- Plugs continue working (local control), just no monitoring

---

## Success Criteria

**MVP Complete When**:
1. ✅ Washing machine status visible on dashboard (idle/running/finished)
2. ✅ State updates in real-time via WebSocket
3. ✅ Reliable detection (< 5% false positives/negatives)
4. ✅ Works for 1 week without manual intervention

**Full System Complete When**:
1. ✅ All 3 appliances monitored (washer, dryer, dishwasher)
2. ✅ SMS notifications on cycle completion
3. ✅ Cost tracking per cycle
4. ✅ 30-day uptime with zero missed notifications

---

## References

- **ChatGPT Conversation**: `/Users/fredrikbranstrom/Downloads/Smart Washing Machine Dishwasher.md`
- **TinyTuya**: Simplifies local_key extraction after Tuya IoT Platform setup
  - GitHub: https://github.com/jasonacox/tinytuya
  - Setup Guide: https://github.com/jasonacox/tinytuya/blob/master/README.md#setup-wizard-getting-local-keys
  - Requires: Tuya IoT Platform API credentials (Access ID + Secret + Region)
- **Tuya IoT Platform**: https://iot.tuya.com (Cloud Project + IoT Core subscription required)
- **Node-RED Module**: `node-red-contrib-tuya-smart-device` (npm)
- **Tuya Local Protocol**: Community docs on GitHub
- **Existing Dashboard Patterns**: See `RentWidget.tsx`, `DataBroadcaster.rb`
- **Smart Life App**: Device pairing + linking to Cloud Project via QR code

---

## Next Steps (When Resuming Dec 2025/Jan 2026)

1. **Renew Tuya IoT Core subscription** on iot.tuya.com (1-6 month renewal)
2. **Run TinyTuya wizard** with API credentials to extract local_keys
3. **Find plug LAN IP** (router DHCP table, MAC: `18:de:50:3e:f4:a5`)
4. **Install Node-RED module** on Pi
5. **Build test flow** with state detection
6. **Run calibration cycle** to tune thresholds
7. **Implement backend handler**
8. **Build dashboard widget**
9. **Deploy & monitor for 1 week**
10. **Add dryer + dishwasher** (repeat process)
11. **SMS notifications** (after rent reminders infrastructure)

---

**Status**: Deferred to Dec 2025/Jan 2026 - awaiting time for Tuya IoT Platform renewal process.

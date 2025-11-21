# Heatpump Emergency Fixes - TODO List

**Created:** 2025-11-20
**Updated:** 2025-11-20 (same day - emergency resolved)
**Context:** Emergency troubleshooting session - house temperature dropping due to broken schedule generation
**Status:** ✅ **CRITICAL FIXES DEPLOYED** - Schedule generation working, SMS alerts active

---

## 🎯 COMPLETION SUMMARY (Nov 20, 2025)

### ✅ FIXED - Priority 1: Schedule Generation Bug

**Root cause:** Lines 115-117 cleared all selected hours if average price > maxPrice threshold (2.2 kr/kWh). With peak/off-peak pricing (2-4 kr/kWh), algorithm selected 0 hours → house would freeze.

**Solution implemented:**
- Removed maxPrice parameter from `select_cheapest_hours()` method
- Removed maxPrice parameter from `generate_schedule_per_day()` method
- Algorithm now ALWAYS selects N cheapest hours regardless of absolute price
- Heatpump is essential infrastructure - can't defer like washing machines

**Rationale documented in code:**
```ruby
# NOTE: maxPrice parameter removed (Nov 20, 2025) - heatpump is essential infrastructure,
# can't defer like washing machines. With peak/off-peak pricing (2-4 kr/kWh), maxPrice
# threshold became obsolete. Always select cheapest hours regardless of absolute price.
```

**Commits:** [To be added after commit]

### ✅ ADDED - Priority 2: Temperature Emergency SMS Alerts

**Feature:** SMS notification when temperature failsafe triggers
**Sender:** "Katten" (existing SMS config)
**Rate limit:** Max once per hour (prevents spam)
**Messages (Swedish, concise):**
- Indoor temp low: "19.2°C inne"
- Hot water low: "38.5°C vatten"
- Both low: "Båda för kalla!"

**Implementation:** `send_emergency_sms_if_needed()` in `handlers/heatpump_schedule_handler.rb`

### ✅ COMPLETED - maxPrice Field Removal (Nov 21, 2025)

**User decision:** Remove maxPrice from HeatpumpConfig entirely

**Reasoning:**
- **Semantic mismatch:** HeatpumpConfig is for heatpump operation (hours_on, emergency_temp_offset), not cost awareness
- **Wrong architectural layer:** Price thresholds apply to ALL appliances (washing machine, dryer), not just heatpump
- **No persistence needed:** Auto-calculated values don't require database storage (calculate on-demand, cache in memory)
- **Manual override not needed:** If 100% auto-calculated, no reason for user configuration
- **Follows existing pattern:** Electricity anomaly detection uses in-memory caching (works great)

**Implementation completed (Nov 21, 2025):**
1. ✅ Remove from schedule generation algorithm (Nov 20, 2025)
   - `handlers/heatpump_schedule_handler.rb` - Removed maxPrice parameter from methods
2. ✅ Remove from database schema (Nov 21, 2025)
   - `prisma/schema.prisma` - Removed maxPrice field from HeatpumpConfig model
   - Migration generated: `20251121XXXXXX_remove_max_price_from_heatpump_config`
   - Migration applied to development database
   - ⏳ **Production migration pending:** Run `npx prisma migrate deploy` manually
3. ✅ Remove from model, repository, handler (Nov 21, 2025)
   - `lib/models/heatpump_config.rb` - Removed max_price attribute and validation
   - `lib/repositories/heatpump_config_repository.rb` - Removed from default config
   - `handlers/heatpump_config_handler.rb` - Removed from GET/PUT responses
4. 📋 Future work: Build proper price awareness service when implementing TODO.md #9

**Files cleaned (6 total):**
- ✅ `handlers/heatpump_schedule_handler.rb`
- ✅ `lib/models/heatpump_config.rb`
- ✅ `lib/repositories/heatpump_config_repository.rb`
- ✅ `handlers/heatpump_config_handler.rb`
- ✅ `prisma/schema.prisma`
- ✅ Migration file generated and applied (development only)

**Architecture analysis:** See `docs/PRICE_AWARENESS_ARCHITECTURE_ANALYSIS.md` for complete pros/cons, decision matrix, and recommended implementation approach (on-demand calculation via PriceAwarenessService, cached in DataBroadcaster like electricity anomaly data)

### 📋 Remaining Tasks (Lower Priority)

**Priority 3:** Fix Node-RED "Extract current schedule state" function
- User's emergency one-liner fix incomplete (extracts but doesn't assign to msg.payload)
- Recommend: Trust backend's `current.evu` directly, simplify function
- Test MQTT receives correct EVU values

**Priority 4:** Clean up Node-RED redundant logic
- Remove duplicate temperature override nodes (backend already handles)
- Remove "Remember current schedule" node (no longer needed)
- Simplify flow: cronplus → Dell API → Extract → MQTT

**Priority 5:** Update dashboard schedule widget - **ARCHITECTURAL PIVOT** (Nov 21, 2025)
- ~~Change fetch from `/data/temperature` to `/api/heatpump/schedule`~~ ❌ WRONG APPROACH
- **NEW APPROACH:** Enhance `/data/temperature` WebSocket broadcast with schedule data
  - Backend: Add `schedule_enhanced` field to temperature WebSocket broadcast
  - Frontend: Read `temperatureData.schedule_enhanced` instead of polling separate endpoint
  - Benefits: Consistent architecture (all data via WebSocket), no polling timer needed
- See "Frontend Migration Status" section below for complete context

---

## 📸 Screenshot Evidence Captured

### Screenshot #1: Node-RED Flow Overview
**Location:** Energy price optimization tab
**Shows:**
- "Dell Schedule API" HTTP request node (tan/beige color)
- "Tibber price template" node (gray, likely deprecated)
- "At a time interval (20 mins)" cronplus trigger
- "Extract current schedule state" function (orange)
- "EVU" template node (purple)
- "ThermIQ" MQTT output node (purple)
- "prices" output node (green)
- Flow from cronplus → Dell API → Extract → EVU → MQTT

**Key observation:** Shows the migrated flow structure after Tibber→Dell migration

### Screenshot #2: "Extract current schedule state" Function Code
**Location:** Function node editor, "On Message" tab
**Code visible (lines 1-20):**
```javascript
// Extract current ON/OFF state from Dell schedule API
const hours = msg.payload.hours || [];
const now = new Date();

// Find current hour in the schedule
let currentState = 1; // Default to OFF (EVU=1)

for (const hour of hours) {
    const hourStart = new Date(hour.start);
    const hourEnd = new Date(hourStart.getTime() + 60*60*1000); // +1 hour

    if (now >= hourStart && now < hourEnd) {
        // Convert onOff to EVU value: true=ON(0), false=OFF(1)
        currentState = hour.onOff ? 0 : 1;
        break;
    }
}

msg.payload = msg.payload.current.evu;
return msg;
```

**Problem identified:** Line 19 assigns `msg.payload.current.evu` which overwrites all the logic above

### Screenshot #3: HTTP Request Node Configuration
**Location:** Dell Schedule API node editor
**Settings captured:**
- **Method:** GET
- **URL:** `http://192.168.4.84:3001/api/heatpump/schedule`
- **Payload:** Ignore
- **Return:** "a parsed JSON object" (dropdown selected)
- **Tip shown:** "If the JSON parse fails the fetched string is returned as-is."
- **Name:** Dell Schedule API
- **Enabled:** Yes (radio button selected)

**Key observation:** Configured to auto-parse JSON, which is causing parse errors

### Screenshot #4: Return Type Dropdown Options
**Location:** Same HTTP request node, Return field expanded
**Options visible:**
1. a UTF-8 string
2. a binary buffer
3. ✓ a parsed JSON object (selected)

**User's question:** "Should I just set it to return a string?"

### Screenshot #5: Browser Pretty-Print of API Response
**Location:** Browser window at `http://192.168.4.84:3001/api/heatpump/schedule`
**Shows:** Valid JSON response (partial view)
```json
{
  "schedule": [{
    "time": "2025-11-20T00:00:00+01:00",
    "value": false,
    "countHours": 24
  }],
  "hours": [
    {"start": "2025-11-20T00:00:00+01:00", "price": 2.1, "onOff": false, "saving": null},
    {"start": "2025-11-20T01:00:00+01:00", "price": 2.0407, "onOff": false, "saving": null},
    ...
  ],
  "source": "Dell API (peak/off-peak aware)",
  "config": {
    "hoursOn": 12,
    "maxPrice": 2.2,
    ...
  }
}
```

**Critical observation:** Valid JSON when fetched in browser, but Node-RED throws parse errors

### Screenshot #6: User's Emergency One-Liner Fix
**Location:** Same function editor, line 19 highlighted
**Shows:**
- Old code: `msg.payload = msg.payload.current.evu;` (crossed out/commented)
- New code: `currentState = msg.payload.current.evu;` (highlighted)

**User's comment:** "Had to figure it out myself. With cold fucking fingers. Made this oneliner fix as you can see."

**Analysis:** Fix extracts EVU value but doesn't assign to msg.payload, so MQTT gets nothing

### Screenshot #7: All Hours Show onOff=false
**Location:** Browser showing compact JSON view
**Critical data:**
```json
"hours": [
  {"start": "2025-11-20T00:00:00+01:00", "price": 2.1, "onOff": false, "saving": null},
  {"start": "2025-11-20T01:00:00+01:00", "price": 2.0407, "onOff": false, "saving": null},
  {"start": "2025-11-20T02:00:00+01:00", "price": 1.9972, "onOff": false, "saving": null},
  ...
  {"start": "2025-11-20T20:00:00+01:00", "price": 3.1024, "onOff": false, "saving": null},
  {"start": "2025-11-20T21:00:00+01:00", "price": 2.8163, "onOff": false, "saving": null},
  {"start": "2025-11-20T22:00:00+01:00", "price": 2.2409, "onOff": false, "saving": null},
  {"start": "2025-11-20T23:00:00+01:00", "price": 2.074, "onOff": false, "saving": null}
]
```

**User's question:** "How the fuck can EVERY hour have the same onOff:false value?!?!?"

**Price range observed:** 1.9972 - 4.1332 kr/kWh (most above 2.2 threshold)

---

## 🐛 Issues Identified

### CRITICAL: Issue #1 - Schedule Generation Returns All Hours OFF

**Symptoms:**
- Every hour in 48-hour schedule shows `"onOff": false`
- Compressed schedule: `{"time": "2025-11-20T00:00:00", "value": false, "countHours": 24}`
- Expected: 12 hours ON per day with `hours_on=12`

**Root cause found:**
```ruby
# handlers/heatpump_schedule_handler.rb, lines 115-117
if max_price && avg_price > max_price
  # If average exceeds max, turn everything OFF for this period
  on_indices = Set.new  # ← CATASTROPHIC BUG!
end
```

**What happens:**
1. Algorithm selects 12 cheapest hours correctly
2. Calculates average price of selected hours (~2.5 kr/kWh)
3. If average > max_price (2.2) → **clears entire selection**
4. Returns all 24 hours as OFF
5. House would freeze without emergency override

**User's insight - Why this triggers now:**
> "This is different with the new Dell API endpoint because it is taking into account peak/off-peak pricing, which the old spot-price-only (Tibber) pricing data did not take into account, so it never triggered the max price threshold in the same way"

**Price comparison:**
- **Old Tibber:** Spot prices only (e.g., 0.80-2.00 kr/kWh)
- **New Dell:** Spot + distribution fees (e.g., 2.00-4.13 kr/kWh)
- **Result:** Dell composite prices consistently exceed 2.2 threshold

**Current workaround:**
- Temperature emergency override forces heatpump ON
- Backend detects indoor 20°C < target 22°C
- Sets `current.evu = 0` (ON) with `reason = "temperature_emergency"`
- **Not sustainable:** Bypasses entire schedule system

**Fix needed:**
- [ ] Remove max_price absolute cutoff logic
- [ ] Always select hours_on cheapest hours regardless of price
- [ ] Make max_price advisory only (log warning if exceeded)
- [ ] Research original ps-strategy maxPrice behavior
- [ ] Test with current high prices (2-4 kr/kWh range)
- [ ] Verify 12 hours selected per day consistently

---

### CRITICAL: Issue #2 - Node-RED JSON Parse Error

**Symptoms:**
- Debug panel shows repeated "JSON parse error" every 20 minutes
- Errors coincide with cronplus trigger (20-minute interval)
- Same URL returns valid JSON when fetched in browser
- HTTP request node configured to return "a parsed JSON object"

**Evidence from screenshots:**
- Debug timestamps: 7:47:29 PM, 8:07:37 PM, 8:07:53 PM (multiple errors)
- Error source: "Dell Schedule API" node
- Browser fetch at same time: Valid JSON response

**Possible causes:**
1. **Network timing issue:** Node-RED timeout shorter than API response time
2. **Malformed response edge case:** Extra whitespace/BOM characters
3. **Connection refused:** Backend not ready when request arrives
4. **Race condition:** API still processing when Node-RED fetches

**User's question:** "Should I just set it to return a string?"

**Fix options:**
- [ ] Change return type to "a UTF-8 string"
- [ ] Add manual JSON parsing in function node with try/catch
- [ ] Increase HTTP request timeout
- [ ] Add retry logic for failed requests
- [ ] Log actual response string on error to debug

**Temporary workaround:** System limps along when requests succeed

---

### HIGH: Issue #3 - "Extract Current Schedule State" Function Incomplete

**User's criticism:**
> "You forgot that whole 'extract current schedule state' node before when you updated the flow :("

**What happened during Tibber→Dell migration:**
- Updated HTTP request URL to Dell API ✓
- Updated response format (prices endpoint) ✓
- **FORGOT** to update extraction function for schedule endpoint ✗

**Current code problems:**
```javascript
// Lines 1-17: Sophisticated logic to find current hour
let currentState = 1; // Default to OFF
for (const hour of hours) {
    // ... find matching hour, extract onOff ...
    currentState = hour.onOff ? 0 : 1;
}

// Line 19: USER'S FIX - But incomplete!
currentState = msg.payload.current.evu;  // ← Extracts but doesn't assign to msg
return msg;  // ← Returns msg with WRONG payload!
```

**What should happen:**
```javascript
// Option A: Use backend's current.evu directly (trust backend logic)
msg.payload = msg.payload.current.evu;
return msg;

// Option B: Keep hour-finding logic, assign to msg.payload
msg.payload = currentState;
return msg;
```

**User's emergency fix:**
- Changed line 19 from `msg.payload = ...` to `currentState = ...`
- **Problem:** Extracts value but doesn't send it to MQTT!
- **Result:** EVU template gets wrong payload structure

**Recommended approach:**
- [ ] Trust backend's `current.evu` value (already has temperature override logic)
- [ ] Simplify function to just: `msg.payload = msg.payload.current.evu; return msg;`
- [ ] Remove redundant hour-finding logic (backend calculates current state)
- [ ] Test MQTT receives correct EVU value (0 or 1)

---

### MEDIUM: Issue #4 - Redundant Temperature Override Logic

**Architecture discovered:**
Temperature override exists in TWO places:

**1. Dell Backend (CORRECT):**
```ruby
# handlers/heatpump_schedule_handler.rb:187-226
def calculate_current_state(hours, temperatures, config)
  # Priority 1: Temperature emergency override
  if temperatures[:indoor] <= (temperatures[:target] - config.emergency_temp_offset) ||
     temperatures[:hotwater] < config.min_hotwater
    return {
      state: true,
      evu: 0,  # Force ON
      reason: 'temperature_emergency',
      ...
    }
  end

  # Priority 2: Schedule (ps-strategy result)
  # ... find current hour in schedule ...
end
```

**2. Node-RED Function (BROKEN):**
- Nodes visible in screenshot: "IF heatpumpOn", "Indoor or hotwater temp TOO LOW"
- Depends on removed Tibber data flow
- **User's insight:** "You forgot... when you updated the flow"

**Problem:**
- Duplication creates confusion about which logic is active
- Node-RED version is broken after Tibber migration
- Backend already provides complete current state with overrides applied

**Correct architecture:**
```
Dell Backend                Node-RED
-----------                 --------
Calculate schedule     →
Apply temp override    →    Trust backend
Return current.evu     →    Extract & forward to MQTT
                            (no logic needed!)
```

**Fix needed:**
- [ ] Remove Node-RED temperature override nodes
- [ ] Remove "IF heatpumpOn" node
- [ ] Remove "Indoor or hotwater temp TOO LOW" node
- [ ] Remove "OR price lower than 0.3 SEK" node
- [ ] Remove "turn heat ON IF temp too low" node
- [ ] Simplify to: cronplus → Dell API → Extract current.evu → EVU template → MQTT

---

### MEDIUM: Issue #5 - "Remember Current Schedule" Node Disconnected

**Original architecture (Tibber):**
```
ps-strategy node
    ↓
remember schedule (store in Node-RED global variables)
    ↓
/data/temperature endpoint reads globals
    ↓
Dashboard schedule bar widget fetches /data/temperature
```

**Current state:**
- Node visible in flow but disconnected
- No longer receives schedule data after Tibber→Dell migration
- /data/temperature endpoint missing schedule data
- Dashboard schedule bar widget showing stale/empty data

**Better architecture:**
```
Dashboard schedule bar widget
    ↓
Fetch /api/heatpump/schedule directly (skip Node-RED)
    ↓
Get authoritative schedule from Dell backend
```

**Why better:**
- Eliminates roundtrip through Node-RED globals
- Dashboard always sees current schedule (not stale Node-RED cache)
- One source of truth (Dell backend)
- Simpler data flow

**Fix needed:**
- [ ] Remove "Remember current schedule" node from Node-RED
- [ ] Update dashboard schedule bar widget (see Issue #6)
- [ ] Remove schedule enrichment from /data/temperature endpoint

---

### LOW: Issue #6 - Dashboard Schedule Widget Outdated

**Current behavior:**
- Widget fetches schedule from `/data/temperature` endpoint
- Endpoint no longer includes schedule data (removed during migration)
- Widget shows empty/stale schedule

**Should be:**
- Widget fetches directly from `/api/heatpump/schedule`
- Extracts `response.hours` array (48-hour breakdown)
- Or extracts `response.schedule` array (compressed format)

**Location (estimated):**
- Likely `dashboard/src/components/` or `dashboard/src/widgets/`
- Search for: `/data/temperature`, `schedule`, `heatpump`

**Fix needed:**
- [ ] Find schedule widget component
- [ ] Change fetch URL to `/api/heatpump/schedule`
- [ ] Update data extraction logic for new response format
- [ ] Test locally with dev server
- [ ] Deploy to production

---

## 🎯 Priority Order & Next Steps

### Priority 1: Fix Schedule Generation (CRITICAL)
**Status:** 🔴 BLOCKING - System unusable without this
**Impact:** House would freeze without emergency override
**Assignee:** Claude
**Steps:**
1. Research ps-strategy maxPrice original behavior (Google search)
2. Understand design intent vs current broken implementation
3. Fix lines 115-117 in `heatpump_schedule_handler.rb`
4. Options to consider:
   - Remove max_price check entirely (always select hours_on cheapest)
   - Make max_price advisory (log warning, continue anyway)
   - Apply max_price per-hour (filter before selection, not after)
5. Test with current high prices (2-4 kr/kWh)
6. Verify API returns ~12 hours ON per day
7. Deploy to production
8. Monitor schedule generation over 24-48 hours

**Success criteria:**
- Schedule shows ~12 hours ON per day (not all OFF)
- System runs on schedule, not emergency override
- No unexpected shutdowns during cheap hours

---

### Priority 2: Fix Node-RED JSON Parse Error (CRITICAL)
**Status:** 🟡 DEGRADED - Works intermittently
**Impact:** Schedule updates fail every few cycles
**Steps:**
1. Investigate error pattern (timing, frequency, conditions)
2. Test HTTP request timeout settings
3. Change return type to "UTF-8 string" + manual parse
4. Add error handling with retry logic
5. Log actual response string on parse failures
6. Monitor debug panel after changes

**Success criteria:**
- No "JSON parse error" messages in debug panel
- Consistent 20-minute schedule updates
- Reliable MQTT EVU commands

---

### Priority 3: Fix "Extract Current Schedule State" Function (HIGH)
**Status:** 🟡 PARTIAL - User's fix incomplete
**Impact:** MQTT might receive wrong EVU values
**Steps:**
1. Review user's one-liner fix
2. Decide: trust backend current.evu OR keep hour-finding logic
3. Update function code appropriately
4. Test MQTT receives correct values (0=ON, 1=OFF)
5. Monitor heatpump response to commands

**Recommended approach:**
```javascript
// Simple: Trust backend's current state calculation
msg.payload = msg.payload.current.evu;
return msg;
```

**Success criteria:**
- MQTT receives correct EVU values
- Heatpump responds to schedule changes
- No logic duplication with backend

---

### Priority 4: Clean Up Node-RED Redundant Logic (MEDIUM)
**Status:** 🟢 NON-BLOCKING - Causes confusion only
**Impact:** Code maintainability, debugging difficulty
**Steps:**
1. Remove temperature override nodes
2. Remove "Remember current schedule" node
3. Simplify flow to: cronplus → Dell API → Extract → MQTT
4. Document simplified architecture
5. Test end-to-end flow

**Success criteria:**
- Clean, simple Node-RED flow
- One source of truth (Dell backend)
- Easier to understand and debug

---

### Priority 5: Update Dashboard Schedule Widget (LOW)
**Status:** 🟢 NON-BLOCKING - Visual only
**Impact:** User can't see schedule in dashboard
**Steps:**
1. Find widget component in dashboard codebase
2. Update fetch URL to `/api/heatpump/schedule`
3. Update data extraction for new response format
4. Test locally
5. Deploy when convenient

**Success criteria:**
- Dashboard shows current 48-hour schedule
- Visual matches actual heatpump behavior
- Updates every time schedule changes

---

## 📝 User's Insights & Requirements

### User's Requirement #1: Comprehensive Understanding
> "We need to really think things through - the data and logic flow inside node-red and how it interacts with our system. This can never happen again."

**Action items:**
- Document complete data flow: Dell API → Node-RED → MQTT → ThermIQ → Heatpump
- Create architecture diagram showing all components
- Identify all decision points and override logic
- Test edge cases (high prices, temperature emergencies, API failures)

### User's Requirement #2: Systematic Approach
> "Let's deal with everything. Take one thing at a time, in order of importance."

**Following priority order above** (1→5)

### User's Requirement #3: Context Preservation
> "Make a detailed todolist for all of this with comprehensive descriptions of what info I gave you in the screenshots and everything, so we don't lose all that."

**This document** captures all screenshot details and context

### User's Peak/Off-Peak Insight
> "This is different with the new Dell API endpoint because it is taking into account peak/off-peak pricing, which the old spot-price-only (Tibber) pricing data did not take into account"

**Implications:**
- max_price threshold (2.2 kr/kWh) is now too low for composite pricing
- Either raise threshold to 3.0-3.5 kr/kWh OR remove absolute cutoff
- Old ps-strategy assumptions don't apply to new pricing model

### User's Research Question
> "How did ps-strategy use its maxPrice parameter, out of curiosity? Google it."

**TODO:** Research ps-strategy-lowest-price node maxPrice behavior before implementing fix

---

## 🔬 Research Needed

### ps-strategy maxPrice Behavior
**Question:** How does original ps-strategy node use maxPrice parameter?

**Research tasks:**
- [ ] Google "ps-strategy-lowest-price maxPrice"
- [ ] Check Node-RED flows library documentation
- [ ] Review ps-strategy node source code if available
- [ ] Understand original design intent
- [ ] Compare with our broken implementation

**Key questions:**
1. Is maxPrice meant to be absolute cutoff or advisory?
2. Does it filter before selection or after?
3. How does it handle cases where ALL hours exceed maxPrice?
4. What's the fallback behavior?

---

## 🎯 Success Metrics

### System Health Indicators
- [ ] Schedule shows ~12 hours ON per day consistently
- [ ] No "JSON parse error" messages in Node-RED debug
- [ ] Heatpump runs on schedule, not emergency override only
- [ ] Indoor temperature maintains 22°C ± 1°C
- [ ] Hot water maintains 40°C+ minimum
- [ ] MQTT commands sent every 20 minutes reliably

### Code Quality Indicators
- [ ] Single source of truth (Dell backend for all logic)
- [ ] Node-RED is transport layer only (no business logic)
- [ ] No logic duplication (temperature override, schedule calculation)
- [ ] Clear error handling and logging
- [ ] Documented architecture and data flows

### User Experience Indicators
- [ ] Dashboard shows accurate current schedule
- [ ] No unexpected cold house incidents
- [ ] System resilient to high electricity prices
- [ ] Easy to troubleshoot when issues occur

---

## 📚 Related Documentation

- `docs/HEATPUMP_SCHEDULE_API_PLAN.md` - Complete implementation plan
- `docs/HEATPUMP_CONFIG_UI_PLAN.md` - UI design specs (future work)
- `handlers/heatpump_schedule_handler.rb` - Schedule generation logic
- `handlers/heatpump_config_handler.rb` - Configuration endpoints
- Node-RED flow: "Energy price optimization" tab on Pi

---

## 🔄 Session Context

**Date:** 2025-11-20
**User state:** Frustrated, cold, troubleshooting emergency
**System state:** Limping on temperature emergency override
**Git state:** heatpump-schedule branch, worktree active
**Deployment status:** Code deployed via webhook, migrations NOT applied yet

**User's emotional state captured:**
- "Had to figure it out myself. With cold fucking fingers."
- "You forgot that whole 'extract current schedule state' node before when you updated the flow :("
- "How the fuck can EVERY hour have the same onOff:false value?!?!?"
- "This can never happen again."

**Commitment:** Systematic, thorough fixes with deep understanding. No more half-migrations that break in production.

---

## 🏗️ Frontend Migration Status (Nov 21, 2025)

### Architectural Pivot: REST Polling → WebSocket Broadcast

**Original Plan (Initial Implementation):**
```typescript
// DataContext.tsx - Poll /api/heatpump/schedule every 5 minutes
useEffect(() => {
  const fetchSchedule = async () => {
    const response = await fetch('/api/heatpump/schedule')
    const data = await response.json()
    dispatch({ type: 'SET_HEATPUMP_SCHEDULE_DATA', payload: data })
  }

  fetchSchedule()  // Initial
  const interval = setInterval(fetchSchedule, 300000)  // 5 min polling
  return () => clearInterval(interval)
}, [])
```

**User's Challenge (Nov 21, 2025):**
> "Does it really make sense for this to make the roundtrip via REST if it could be accessed more directly?"

**Critical Insight:**
- Dashboard architecture uses **WebSocket broadcast for ALL data** (temperature, rent, weather, electricity)
- Schedule data already flows via WebSocket in `temperatureData.schedule_data` (old Node-RED format)
- Creating separate REST polling violates unified architecture
- Frontend would have **two data flows:** WebSocket for everything else, polling for schedule only

**Better Architecture - WebSocket Enhancement:**

Instead of polling separate endpoint, enhance existing `/data/temperature` WebSocket broadcast:

```ruby
# In puma_server.rb, enhance temperature broadcast handler
def broadcast_temperature_data
  # Existing: Fetch current temperature readings from Node-RED
  temperature_data = fetch_node_red_temperature()

  # NEW: Add authoritative schedule data from schedule handler
  env = build_rack_env_for_schedule_request()
  schedule_response = heatpump_schedule_handler.call(env)

  if schedule_response[0] == 200
    schedule_data = Oj.load(schedule_response[2].first)

    # Enhance temperature data with richer schedule
    temperature_data['schedule_enhanced'] = {
      'current' => schedule_data['current'],  # EVU + reason + temps
      'hours' => schedule_data['hours'],      # 48-hour breakdown
      'config' => schedule_data['config']     # hoursOn, outputValues
    }
  end

  # Single WebSocket broadcast with everything
  broadcast(temperature_data)
end
```

**Benefits:**
- ✅ Architectural consistency (all data via WebSocket)
- ✅ No frontend polling timer (one less thing to manage/debug)
- ✅ Backend-controlled refresh frequency (centralized decision)
- ✅ Single broadcast with all widget data
- ✅ Temperature override logic included (backend calculates `current.evu`)
- ✅ Reduced network overhead (no separate HTTP requests)

**Current State (Work Paused Nov 21, 2025):**

**Files Modified (NOT Committed - TO BE REVERTED):**

1. **`dashboard/src/context/DataContext.tsx`**
   - ✅ Lines 143-175: HeatpumpScheduleData interface (KEEP - good TypeScript)
   - ✅ DashboardState.heatpumpScheduleData field (KEEP for now)
   - ⏸️ Lines 642-665: Polling useEffect (REVERT - not needed)
   - ⏸️ SET_HEATPUMP_SCHEDULE_DATA action/reducer (REVERT - different approach)

2. **`dashboard/src/components/TemperatureWidget.tsx`**
   - ✅ Line 84: Added `heatpumpScheduleData` to state destructuring (KEEP)
   - ⏸️ Lines 125-240: Schedule visualization logic reads `temperatureData.schedule_data`
   - ⏸️ Needs update to read `temperatureData.schedule_enhanced` after backend changes

**Implementation Plan:**

**Phase 1: Backend WebSocket Enhancement**
1. Modify `puma_server.rb` temperature broadcast handler
2. Call `HeatpumpScheduleHandler` internally (Ruby object call, not HTTP)
3. Merge schedule data into temperature_data hash under `schedule_enhanced` key
4. Test WebSocket broadcast includes new fields

**Phase 2: Frontend Migration**
1. Revert polling useEffect from DataContext.tsx
2. Update TemperatureWidget to read `temperatureData.schedule_enhanced`
3. Extract current state from `schedule_enhanced.current.evu`
4. Extract schedule from `schedule_enhanced.hours` array
5. Test with live WebSocket data

**Phase 3: Cleanup**
1. Remove old `temperatureData.schedule_data` (Node-RED format)
2. Simplify Node-RED flow (no schedule storage in globals)
3. Update documentation with final architecture

**Technical Context:**
- `temperatureData.schedule_data` = Old format from Node-RED (stale, stored in globals)
- `temperatureData.schedule_enhanced` = New format from schedule handler (authoritative, with overrides)
- TemperatureWidget lines 125-240 ready to adapt to new data source
- Schedule handler already returns complete current state with temperature override logic

**Why This Matters - Lessons Learned:**

Initial implementation focused on "make it work quickly" (REST polling) without considering:
- Existing dashboard data flow patterns (WebSocket for everything)
- Code consistency across widgets (all consume via WebSocket)
- Maintenance burden (additional polling timer to manage)

**User's question forced architectural re-evaluation.** Sometimes the "quick solution" violates core design principles. Taking time to align with existing patterns prevents technical debt accumulation and creates more maintainable systems.

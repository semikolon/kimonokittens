# Heatpump Schedule Configuration UI Plan

**Created:** November 20, 2025
**Status:** ✅ BACKEND COMPLETE - UI Pending
**Goal:** Make heatpump schedule parameters configurable via dashboard + move temperature override logic to backend

**Progress (Dec 20, 2025):**
- ✅ Database schema complete (HeatpumpConfig table with emergencyTempOffset, blockDistribution)
- ✅ Backend API complete (GET/PUT /api/heatpump/config)
- ✅ Field rename complete (minTemp → emergencyTempOffset, dynamic offset design)
- ✅ Temperature override logic implemented and working (Dec 19, 2025)
- ✅ **ALGORITHM BUG FIXED**: ps-strategy now processes each 24-hour period independently
- ✅ **REMOVED**: Price opportunity logic + emergencyPrice field (Nov 20, 2025)
- ✅ **DEPLOYED**: Auto-learning system adjusts hours_on + block distribution (Dec 20, 2025)
- ⏳ **PENDING**: Build heatpump config UI widget (manual config via database for now)

**Key Decisions (Nov 20):**
1. **Removed price opportunity logic**: emergencyPrice field was redundant with hours_on control, rarely triggered in winter
2. **Self-learning COMPLETE**: System now auto-adjusts hours_on weekly based on override patterns (see `docs/HEATPUMP_AUTO_LEARNING_PLAN.md`)

**Algorithm Fix (COMPLETED):**
- ✅ **Refactored**: `generate_schedule_per_day()` processes today and tomorrow independently
- ✅ **Verified**: Each 24-hour period selects N cheapest hours (tested with real data)
- ✅ **Guarantees**: Consistent daily heating - no risk of 0 hours on any day
- Implementation: `select_cheapest_hours()` applies ps-strategy to single 24-hour period
- Test result: 12 hours selected from today's 24 hours, avg price 2.35 kr/kWh

---

## Executive Summary

**Problem:**
1. Schedule parameters (hours_on, max_price) are hardcoded in Node-RED flow
2. Temperature override logic in Node-RED depends on removed Tibber data (broken)
3. Price-based emergency override (< 0.3 kr) also broken

**Solution:**
1. Add heatpump config UI to Dell dashboard
2. Move ALL override logic to backend Ruby code
3. Simplify Node-RED to: timer → HTTP request → MQTT (pure transport layer)

**Timeline:** 2-3 hours implementation

---

## Part 1: Configuration Storage & API

### Database Schema

**New table:** `HeatpumpConfig`
```prisma
model HeatpumpConfig {
  id                  String   @id @default(cuid())
  hoursOn             Int      @default(12)     // 5-22 hours/day
  maxPrice            Float    @default(2.2)    // 1.5-3.0 kr/kWh
  emergencyTempOffset Float    @default(1.0)    // 0.5-5.0°C below target
  minHotwater         Float    @default(40.0)   // 35-50°C hotwater threshold
  emergencyPrice      Float    @default(0.3)    // 0.1-1.0 kr/kWh - force ON below
  updatedAt           DateTime @updatedAt
  createdAt           DateTime @default(now())
}
```

**Key design:** `emergencyTempOffset` = degrees below target_temperature (from heatpump MQTT) before triggering override
- Example: target=21°C, offset=1°C → override at 20°C (dynamic!)
- Benefits: Single control point (target on physical heatpump), economic tradeoff configurable

### Backend API Endpoints

**GET /api/heatpump/config**
```ruby
# handlers/heatpump_config_handler.rb
class HeatpumpConfigHandler
  def call(req)
    config = HeatpumpConfigRepository.get_current
    [200, {'Content-Type' => 'application/json'}, [Oj.dump(config.to_h)]]
  end
end
```

**PUT /api/heatpump/config**
```ruby
def update(req)
  params = Oj.load(req.body.read)

  # Validation
  validate_range(params['hoursOn'], 5, 22)
  validate_range(params['maxPrice'], 1.5, 3.0)
  validate_range(params['emergencyTempOffset'], 0.5, 5.0)
  validate_range(params['minHotwater'], 35.0, 50.0)
  validate_range(params['emergencyPrice'], 0.1, 1.0)

  config = HeatpumpConfigRepository.update(params)
  [200, {'Content-Type' => 'application/json'}, [Oj.dump(config.to_h)]]
end
```

---

## Part 2: Smart Schedule Endpoint with Override Logic

### Modified /api/heatpump/schedule

**Current behavior:** Returns schedule based on hours_on + max_price from query params

**New behavior:**
1. Read config from database
2. Calculate optimal schedule
3. **Check temperature override conditions**
4. **Check emergency price override**
5. Return CURRENT state (not just schedule)

**Implementation:**
```ruby
class HeatpumpScheduleHandler
  def call(req)
    config = HeatpumpConfigRepository.get_current
    temps = get_current_temperatures  # From global context or MQTT

    # Generate base schedule
    schedule = calculate_schedule(
      hours_on: config.hours_on,
      max_price: config.max_price
    )

    # Find current hour state
    current_hour = schedule.hours.find { |h| Time.parse(h['start']) <= Time.now }
    base_state = current_hour['onOff']  # true=ON, false=OFF

    # Override logic (highest priority wins)
    override_reason = nil
    final_state = base_state

    # Priority 1: Temperature too low (safety)
    # Check if indoor temp has dropped below (target - offset)
    # Example: target=21°C, offset=1°C → override at 20°C
    if temps[:indoor] <= (temps[:target] - config.emergency_temp_offset) || temps[:hotwater] < config.min_hotwater
      final_state = true  # Force ON
      override_reason = "temperature_emergency"

    # Priority 2: Price extremely low (opportunistic)
    elsif current_hour['price'] < config.emergency_price
      final_state = true  # Force ON
      override_reason = "price_opportunity"

    # Priority 3: Schedule (default)
    else
      override_reason = base_state ? "schedule" : "schedule_off"
    end

    # Convert to EVU format
    evu_value = final_state ? 0 : 1

    {
      schedule: schedule.schedule,
      hours: schedule.hours,
      config: schedule.config,
      current: {
        state: final_state,
        evu: evu_value,
        reason: override_reason,
        temperatures: temps,
        price: current_hour['price']
      }
    }
  end

  private

  def get_current_temperatures
    # Read from MQTT broker or HTTP endpoint
    response = Net::HTTP.get(URI('http://localhost:3001/data/temperature'))
    data = Oj.load(response)
    {
      indoor: data['indoor_temperature'].to_f,
      hotwater: data['hotwater_temperature'].to_f,
      target: data['target_temperature'].to_f
    }
  end
end
```

---

## Part 3: Node-RED Simplification

### Remove Temperature Override Nodes

**Delete these nodes:**
- "Get Current Price and..." function
- "delay 2s" delay node
- "turn heat ON IF temp too low" function
- "IF heatPumpOn" switch
- "OR price lower than 0.3 SEK" switch
- "ON" template (if not used elsewhere)

**Why:** All override logic now happens in Dell backend before Node-RED receives data.

### Simplified Flow

```
cronplus (20 min)
  ↓
Dell Schedule API (HTTP request)
  ↓
Extract current state (function - reads msg.payload.current.evu)
  ↓
EVU template
  ↓
ThermIQ MQTT
```

**Extract function updated:**
```javascript
// Backend already calculated overrides - just extract EVU value
const current = msg.payload.current || {};
msg.payload = current.evu || 1;  // Default to OFF if missing
return msg;
```

---

## Part 4: Frontend Dashboard Widget

### UI Component Location

**File:** `dashboard/src/components/HeatpumpConfigModal.tsx`

**Trigger:** Settings icon/button in existing dashboard

### UI Design

**Modal with sliders:**
```typescript
interface HeatpumpConfig {
  hoursOn: number             // 5-22, step 1
  maxPrice: number            // 1.5-3.0 kr, step 0.1
  emergencyTempOffset: number // 0.5-5.0°C, step 0.5
  minHotwater: number         // 35-50°C, step 1
  emergencyPrice: number      // 0.1-1.0 kr, step 0.05
}
```

**Sections:**
1. **Schedule Settings**
   - Hours ON per day: [5...12...22] slider
   - Max price: [1.5...2.2...3.0] kr/kWh slider

2. **Temperature Overrides** (Safety)
   - Emergency temp offset: [0.5...1.0...5.0]°C slider
     - Helper text: "Force ON when indoor drops X°C below target"
     - Example: "Target 21°C, offset 1°C → override at 20°C"
   - Min hotwater: [35...40...50]°C slider

3. **Price Override** (Opportunistic)
   - Emergency price: [0.1...0.3...1.0] kr slider
   - Helper text: "Force ON when price drops below this"

**Save behavior:**
- PUT /api/heatpump/config
- Show success toast
- Next cronplus trigger (within 20 min) uses new settings

---

## Part 5: Migration Steps

### Step 1: Backend (30 min)

1. Create Prisma migration for HeatpumpConfig table
2. Create repository: `lib/repositories/heatpump_config_repository.rb`
3. Create model: `lib/models/heatpump_config.rb`
4. Create handlers: `handlers/heatpump_config_handler.rb`
5. Update `handlers/heatpump_schedule_handler.rb` with override logic
6. Add routes to `puma_server.rb`
7. Seed initial config (hours_on=12, max_price=2.2, etc.)

### Step 2: Node-RED Cleanup (10 min)

1. Delete temperature override nodes
2. Update "Extract current schedule state" function to read `current.evu`
3. Deploy flows
4. Test: Verify MQTT messages still sent every 20 min

### Step 3: Frontend (1 hour)

1. Create `HeatpumpConfigModal.tsx`
2. Add API client methods (GET/PUT config)
3. Add settings button to dashboard
4. Test: Adjust sliders, verify backend updates
5. Wait for next trigger, verify heatpump responds

### Step 4: Testing (30 min)

**Test matrix:**
- [ ] Schedule works with default config (12h, 2.2kr)
- [ ] Adjust hours_on → schedule changes
- [ ] Adjust max_price → expensive hours rejected
- [ ] Simulate low indoor temp → forces ON (override schedule)
- [ ] Simulate low hotwater → forces ON
- [ ] Find hour with price < 0.3kr → forces ON
- [ ] All overrides visible in dashboard

---

## Part 6: Temperature Override Logic Details

### Current Node-RED Logic (BROKEN)

**Path:** tibber-query → "Get Current Price" → delay → "turn heat ON IF temp too low" → switch

**Code:**
```javascript
const indoor = global.get('indoor_temperature');
const hotwater = global.get('hotwater_temperature');
const target = global.get('target_temperature');

if (indoor <= target || hotwater < 40) {
    msg.heatPumpOn = true;  // Force ON
} else {
    msg.heatPumpOn = false;
}
```

**Critical insight:** Original logic uses `indoor <= target` (dynamic comparison!)
- `target` comes from physical heatpump controls (user sets with +/- buttons)
- Triggers override when temp drops below desired setting
- No fixed minimum temperature

**Problem:** Depends on Tibber query trigger which no longer exists.

### New Backend Logic (ROBUST)

**Advantages:**
1. **Always runs** - checked on every schedule request (20 min intervals)
2. **Uses fresh data** - reads from temperature endpoint (including target from MQTT)
3. **Logged** - override reason visible in response
4. **Testable** - unit tests for each override condition
5. **Priority-based** - temperature > price > schedule
6. **Economic tradeoff** - configurable offset allows balancing comfort vs cost

**Override priority:**
```
1. Temperature Emergency
   - Indoor: indoor ≤ (target - emergency_temp_offset)
   - Hotwater: hotwater < min_hotwater
   ↓
2. Price Opportunity (current price < emergency threshold)
   ↓
3. Schedule (default calculated schedule)
```

**Key design improvement over Node-RED:**
- Original: `indoor <= target` (override immediately when below desired temp)
- New: `indoor <= (target - offset)` (tolerate small drop during expensive hours)
- Benefit: Economic optimization while preventing TOO cold

---

## Part 7: Database Migration

**File:** `prisma/migrations/YYYYMMDD_add_heatpump_config/migration.sql`

```sql
CREATE TABLE "HeatpumpConfig" (
    "id" TEXT NOT NULL PRIMARY KEY,
    "hoursOn" INTEGER NOT NULL DEFAULT 12,
    "maxPrice" REAL NOT NULL DEFAULT 2.2,
    "emergencyTempOffset" REAL NOT NULL DEFAULT 1.0,
    "minHotwater" REAL NOT NULL DEFAULT 40.0,
    "emergencyPrice" REAL NOT NULL DEFAULT 0.3,
    "updatedAt" DATETIME NOT NULL,
    "createdAt" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- Seed initial config
INSERT INTO "HeatpumpConfig" (id, hoursOn, maxPrice, emergencyTempOffset, minHotwater, emergencyPrice, updatedAt, createdAt)
VALUES ('default', 12, 2.2, 1.0, 40.0, 0.3, datetime('now'), datetime('now'));
```

---

## Success Metrics

**Technical:**
- [ ] Config persisted in database
- [ ] UI updates config via API
- [ ] Schedule endpoint reads from config
- [ ] Temperature override works without Tibber
- [ ] Price override works with Dell prices
- [ ] Node-RED flow simplified (no broken logic)

**Operational:**
- [ ] User can adjust schedule hours via dashboard
- [ ] User can adjust price threshold
- [ ] User can adjust safety temperature thresholds
- [ ] Override reason visible in dashboard (why ON when scheduled OFF)
- [ ] System responds to temperature drops within 20 minutes

---

## Rollback Plan

1. **Database:** Migration is additive, no data loss
2. **Backend:** Old schedule endpoint still works with query params
3. **Node-RED:** Backup flows available
4. **Frontend:** UI is additive, no breaking changes

**Rollback command:**
```bash
# Restore old Node-RED flows (if needed)
scp flows-backup-20251120-1447.json pi:.node-red/flows.json
ssh pi 'sudo systemctl restart nodered'
```

---

## Future Enhancements

1. **Schedule visualization** - Show 24h timeline with ON/OFF periods
2. **Cost projection** - "If you run 12h at max 2.2kr, estimated daily cost: 26kr"
3. **History tracking** - Log actual vs scheduled runtime
4. **Manual override** - "Force ON for next 2 hours" button
5. **Smart scheduling** - ML-based prediction of heating demand

---

**Document Version:** 1.0
**Next Steps:** Review plan → implement backend → test → add frontend UI

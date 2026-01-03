# Heatpump Schedule API Implementation Plan

**Created:** November 17, 2025
**Status:** ✅ DEPLOYED TO PRODUCTION (Nov 20, 2025)
**Goal:** Replace Tibber API with Dell-based elprisetjustnu.se pricing + peak/off-peak logic

**Deployed:** Complete migration from Pi/Tibber to Dell Ruby backend with ps-strategy algorithm.
Node-RED now calls Dell `/api/heatpump/schedule` every 10 minutes, acting purely as transport layer.

---

## Executive Summary

**Problem:** Node-RED heatpump scheduling uses invalid Tibber API key (stale since May 2, 2025) and doesn't account for peak/off-peak grid pricing.

**Solution:** Create new Dell API endpoint that provides Tibber-compatible price data with peak/off-peak rates calculated server-side using existing Ruby logic.

**Benefit:** Reuse 100% of existing Ruby code (peak detection, Swedish holidays, price calculations) instead of porting 150-200 lines to JavaScript.

**Timeline:** 1-2 weeks (vs 4-6 weeks for full JavaScript migration)

---

## Architecture Overview

### Current Flow (Broken)

```
Node-RED (Pi) every 20 mins:
  cronplus
    ↓
  tibber-query (GraphQL) ← INVALID API KEY
    ↓
  ps-receive-price (Tibber → ps-strategy format converter)
    ↓
  ps-strategy-lowest-price (select 11 cheapest hours, max 2.2 kr)
    ↓
  temperature-override (safety: indoor temp, hot water checks)
    ↓
  template {"EVU": 0 or 1}
    ↓
  MQTT out → ThermIQ heatpump
```

**Problems:**
1. Tibber API key invalid (May 2, 2025)
2. Only considers spot prices (ignores peak/off-peak grid rates)
3. Cannot optimize for winter peak avoidance

### New Flow (Proposed)

```
Node-RED (Pi) every 20 mins:
  cronplus
    ↓
  http request → GET http://pop:3001/api/heatpump/prices
    ↓
  [SKIP ps-receive-price - not needed!]
    ↓
  ps-strategy-lowest-price (11 hrs, 2.2 kr max) ← UNCHANGED CONFIG
    ↓
  temperature-override ← UNCHANGED
    ↓
  template {"EVU": ...} ← UNCHANGED
    ↓
  MQTT out ← UNCHANGED
```

**What Changed:**
- Replace Tibber GraphQL query with HTTP request to Dell
- Remove ps-receive-price node (Dell returns ps-strategy-compatible format)
- **Everything else stays identical**

### Dell API Endpoint (New)

```
GET /api/heatpump/prices

Response:
{
  "region": "SE3",
  "prices": [
    {
      "startsAt": "2025-01-10T00:00:00+01:00",
      "total": 1.234,        // Final price: (spot + grid + tax) × VAT
      "breakdown": {         // Optional debug info
        "spot": 0.500,
        "grid": 0.214,       // 0.214 (off-peak) or 0.536 (peak)
        "tax": 0.439,
        "isPeak": false
      }
    },
    ... 48 hours (today + tomorrow)
  ],
  "generated_at": "2025-01-10T12:34:56Z"
}
```

**Calculation Logic:**
```ruby
for each hour in (today + tomorrow):
  spot_price = elprisetjustnu.se API (excludes VAT)
  is_peak = is_peak_hour?(timestamp)  # Existing method
  grid_rate = is_peak ? 0.536 : 0.214
  tax = 0.439
  total_excl_vat = spot_price + grid_rate + tax
  total_incl_vat = total_excl_vat × 1.25

  return { startsAt: timestamp, total: total_incl_vat }
```

---

## ps-strategy-lowest-price Format Investigation

### Known Configuration (from flows-backup-20251026.json)

```json
{
  "type": "ps-strategy-lowest-price",
  "hoursOn": "11",
  "maxPrice": "2.2",
  "outputValueForOn": "0",
  "outputValueForOff": "1"
}
```

### Expected Input Format (Inference)

Based on Tibber GraphQL response structure and ps-receive-price transformer:

**Hypothesis 1: Tibber-style nested format**
```javascript
msg.payload = {
  viewer: {
    homes: [{
      currentSubscription: {
        priceInfo: {
          today: [
            { startsAt: "...", total: 1.23 },
            ...
          ],
          tomorrow: [
            { startsAt: "...", total: 1.45 },
            ...
          ]
        }
      }
    }]
  }
}
```

**Hypothesis 2: Flat array format (ps-receive-price output)**
```javascript
msg.payload = {
  prices: [
    { startsAt: "2025-01-10T00:00:00+01:00", total: 1.23 },
    { startsAt: "2025-01-10T01:00:00+01:00", total: 1.45 },
    ... 48 hours
  ]
}
```

**Hypothesis 3: Minimal array**
```javascript
msg.payload = [
  { time: "2025-01-10T00:00:00+01:00", price: 1.23 },
  ...
]
```

### Testing Strategy

1. **Dell endpoint returns Hypothesis 2 format** (flat array with `prices` key)
   - Most likely correct based on migration plan deleting ps-receive-price
   - Matches common Node-RED patterns

2. **Fallback to Hypothesis 1** if Hypothesis 2 fails
   - Easy to modify endpoint to return nested Tibber format
   - ps-receive-price stays in flow as compatibility layer

3. **Document actual format** after Node-RED testing
   - Update this document with verified format
   - Share findings with community if ps-strategy docs are unclear

---

## Implementation Details

### Phase 1: Dell API Endpoint (This Week)

**File:** `handlers/heatpump_price_handler.rb`

**Dependencies:**
- `electricity_price_handler.rb` (fetch spot prices from elprisetjustnu.se)
- `electricity_stats_handler.rb` (reuse `is_peak_hour?` and `swedish_holidays` methods)

**Pseudo-code:**
```ruby
class HeatpumpPriceHandler
  def initialize(electricity_price_handler)
    @electricity_price_handler = electricity_price_handler
  end

  def call(req)
    # Fetch spot prices from elprisetjustnu.se
    status, headers, body = @electricity_price_handler.call(req)
    return [status, headers, body] unless status == 200

    price_data = Oj.load(body.first)
    spot_prices = price_data['prices'] || []

    # Calculate total price for each hour
    calculated_prices = spot_prices.map do |hour|
      timestamp = hour['time_start']
      spot_price = hour['price_sek']  # Excludes VAT

      # Determine peak/off-peak grid rate
      is_peak = is_peak_hour?(timestamp)
      grid_rate = is_peak ? GRID_TRANSFER_PEAK_EXCL_VAT : GRID_TRANSFER_OFFPEAK_EXCL_VAT

      # Calculate total price: (spot + grid + tax) × VAT
      total_excl_vat = spot_price + grid_rate + ENERGY_TAX_EXCL_VAT
      total_incl_vat = total_excl_vat * VAT_MULTIPLIER

      {
        'startsAt' => timestamp,
        'total' => total_incl_vat.round(4),
        'breakdown' => {
          'spot' => spot_price.round(4),
          'grid' => grid_rate,
          'tax' => ENERGY_TAX_EXCL_VAT,
          'isPeak' => is_peak
        }
      }
    end

    response = {
      'region' => 'SE3',
      'prices' => calculated_prices,
      'generated_at' => Time.now.utc.iso8601
    }

    [200, { 'Content-Type' => 'application/json' }, [ Oj.dump(response) ]]
  end

  private

  # Copy from electricity_stats_handler.rb
  def is_peak_hour?(timestamp)
    # ... existing implementation (lines 479-497)
  end

  def swedish_holidays(year)
    # ... existing implementation (lines 418-470)
  end
end
```

**Integration with puma_server.rb:**
```ruby
# Add to route map
map '/api/heatpump/prices' do
  run lambda { |env|
    electricity_price_handler = ElectricityPriceHandler.new
    heatpump_price_handler = HeatpumpPriceHandler.new(electricity_price_handler)
    heatpump_price_handler.call(Rack::Request.new(env))
  }
end
```

**Testing:**
```bash
# Test endpoint
curl -s http://localhost:3001/api/heatpump/prices | jq .

# Verify format
curl -s http://localhost:3001/api/heatpump/prices | jq '.prices[0]'
# Expected: { startsAt: "...", total: 1.23, breakdown: {...} }

# Verify peak detection
curl -s http://localhost:3001/api/heatpump/prices | \
  jq '.prices[] | select(.breakdown.isPeak == true) | .startsAt' | head -5
# Should show Mon-Fri 06:00-21:59 in winter months only

# Verify 48 hours coverage
curl -s http://localhost:3001/api/heatpump/prices | jq '.prices | length'
# Expected: 48 (today + tomorrow)
```

### Phase 2: Node-RED Flow Modification (Next Week, Dell Machine)

**Requires:** Claude Code session on Dell with SSH access to Pi

**Changes:**

1. **Backup current flows:**
   ```bash
   ssh pi@192.168.4.66 "cat ~/.node-red/flows.json" > flows-backup-$(date +%Y%m%d-%H%M).json
   git add flows-backup-*
   git commit -m "backup: Node-RED flows before elpriset migration"
   ```

2. **Create test tab in Node-RED UI:**
   - Access: http://192.168.4.66:1880
   - New flow: "Elpriset Testing"
   - Work in isolation from production

3. **Add HTTP request node:**
   - Method: GET
   - URL: `http://192.168.4.84:3001/api/heatpump/prices`
   - Return: parsed JSON object
   - Name: "Fetch Dell Prices"

4. **Wire test flow:**
   ```
   inject (manual trigger for testing)
     ↓
   http request (Dell API)
     ↓
   debug (verify response format)
     ↓
   ps-strategy-lowest-price (clone from production, same config)
     ↓
   debug (verify schedule output)
   ```

5. **Format compatibility check:**
   - If ps-strategy accepts Dell format: proceed
   - If ps-strategy rejects: add transformer function node
   - If uncertain: keep ps-receive-price as compatibility layer

6. **Shadow mode (3 days):**
   - Test flow runs every 20 mins (parallel to production)
   - Production flow still controls heatpump
   - Log both schedules side-by-side
   - Compare: Are test schedules reasonable?

7. **Production cutover (when ready):**
   - Disable Tibber flow (don't delete yet)
   - Copy test flow nodes to production tab
   - Wire: cronplus → http → ps-strategy → override → MQTT
   - Deploy and monitor

---

## Code Reuse Strategy

### Existing Ruby Methods to Extract

**From `electricity_stats_handler.rb`:**

```ruby
# Lines 8-27: Constants
ENERGY_TAX_EXCL_VAT = 0.439
GRID_TRANSFER_PEAK_EXCL_VAT = 0.536
GRID_TRANSFER_OFFPEAK_EXCL_VAT = 0.214
VAT_MULTIPLIER = 1.25

# Lines 418-470: Swedish holidays calculation
def swedish_holidays(year)
  # 8 fixed holidays
  # 6 Easter-based holidays (hardcoded 2024-2027)
  # Midsummer (Friday between Jun 19-25)
  # All Saints' Day (Saturday between Oct 31 - Nov 6)
end

# Lines 479-497: Peak hour detection
def is_peak_hour?(timestamp)
  # Winter months only: Jan/Feb/Mar/Nov/Dec
  # Weekdays only: Mon-Fri
  # Hours: 06:00-22:00
  # Excludes Swedish holidays
end
```

**Extraction Strategy:**

**Option A: Copy methods to new handler** (faster, independent)
- Pro: No cross-handler dependencies
- Pro: Can modify without affecting electricity_stats
- Con: Code duplication (violates DRY)

**Option B: Extract to shared module** (cleaner, more effort)
- Create `lib/swedish_pricing.rb` module
- Move constants + methods
- Both handlers `include SwedishPricing`
- Pro: Single source of truth
- Pro: Easier to update Easter dates in 2028+
- Con: Requires refactoring electricity_stats_handler

**Recommendation: Option A for MVP, Option B for production**
- Ship quickly with Option A (copy methods)
- Refactor to Option B after validation (next sprint)

---

## Testing Strategy

### Unit Tests (Optional for MVP)

**If time permits, add specs:**

```ruby
# spec/handlers/heatpump_price_handler_spec.rb
RSpec.describe HeatpumpPriceHandler do
  describe '#is_peak_hour?' do
    it 'returns false for summer months' do
      expect(handler.is_peak_hour?('2025-06-10T10:00:00+02:00')).to be false
    end

    it 'returns false for weekends in winter' do
      expect(handler.is_peak_hour?('2025-01-11T10:00:00+01:00')).to be false  # Saturday
    end

    it 'returns true for weekday peak hours in winter' do
      expect(handler.is_peak_hour?('2025-01-10T10:00:00+01:00')).to be true  # Friday 10am
    end

    it 'returns false for Swedish holidays' do
      expect(handler.is_peak_hour?('2025-12-25T10:00:00+01:00')).to be false  # Christmas
    end
  end

  describe '#call' do
    it 'returns 48 hours of prices' do
      response = handler.call(mock_request)
      data = JSON.parse(response[2].first)
      expect(data['prices'].length).to eq(48)
    end

    it 'applies peak grid rate in winter weekday hours' do
      # Test logic, verify breakdown.grid = 0.536
    end
  end
end
```

### Integration Tests (Critical)

**Manual validation checklist:**

- [ ] Endpoint returns 200 OK
- [ ] Response has `prices` array with 48 entries
- [ ] Each price has `startsAt` (ISO 8601) and `total` (float)
- [ ] Timestamps cover today + tomorrow (24h + 24h)
- [ ] Peak hours correctly identified (spot-check 10 dates)
- [ ] Swedish holidays correctly excluded from peak (test upcoming holiday)
- [ ] Price calculations match electricity_stats_handler
- [ ] Winter peak grid rate (0.536) applied Mon-Fri 06:00-21:59
- [ ] Off-peak grid rate (0.214) applied all other times
- [ ] Total price = (spot + grid + 0.439) × 1.25

**Comparison test:**
```bash
# Get price for specific hour from both endpoints
HOUR="2025-01-10T10:00:00+01:00"

# From electricity_stats (existing)
curl -s http://localhost:3001/api/electricity | \
  jq ".hours[] | select(.date == \"$HOUR\")"

# From heatpump_prices (new)
curl -s http://localhost:3001/api/heatpump/prices | \
  jq ".prices[] | select(.startsAt == \"$HOUR\")"

# Verify total prices match within 0.01 kr
```

### Node-RED Testing (Critical)

**Test flow validation:**

1. **Format acceptance:**
   - Does ps-strategy-lowest-price accept Dell JSON?
   - If not, what error message?
   - What format does it expect?

2. **Schedule generation:**
   - Does it select 11 hours?
   - Are they the cheapest 11 hours?
   - Are hours > 2.2 kr rejected?
   - Does schedule update every 20 minutes?

3. **Temperature override:**
   - If indoor < target, does it force ON?
   - If hotwater < 40°C, does it force ON?
   - Does override work regardless of schedule?

4. **MQTT output:**
   - Is {"EVU": 0} sent for ON hours?
   - Is {"EVU": 1} sent for OFF hours?
   - Does ThermIQ heatpump respond?

---

## Deployment Checklist

### Pre-Deployment (Dell)

- [ ] Create `handlers/heatpump_price_handler.rb`
- [ ] Copy `is_peak_hour?` method from electricity_stats_handler
- [ ] Copy `swedish_holidays` method from electricity_stats_handler
- [ ] Copy constants (GRID_TRANSFER_*, ENERGY_TAX_EXCL_VAT, VAT_MULTIPLIER)
- [ ] Add route to `puma_server.rb`
- [ ] Test endpoint: `curl http://localhost:3001/api/heatpump/prices | jq`
- [ ] Verify 48 hours returned
- [ ] Verify peak detection (spot-check 5 dates)
- [ ] Verify holiday detection (test Christmas, Easter, Midsummer)
- [ ] Compare prices with electricity_stats_handler (should match)
- [ ] Commit to git
- [ ] Push to GitHub (triggers webhook deployment)

### Deployment (Node-RED via Dell Claude Code)

- [ ] SSH to Pi: `ssh pi@192.168.4.66`
- [ ] Backup flows: `cat ~/.node-red/flows.json > flows-backup-YYYYMMDD.json`
- [ ] Access Node-RED UI: http://192.168.4.66:1880
- [ ] Create test tab: "Elpriset Testing"
- [ ] Add HTTP request node (Dell API)
- [ ] Wire test flow (inject → http → debug)
- [ ] Verify response format
- [ ] Clone ps-strategy-lowest-price to test tab
- [ ] Wire test schedule (http → ps-strategy → debug)
- [ ] Test with manual inject
- [ ] Verify 11 hours selected
- [ ] Run shadow mode (test tab, production still controls)
- [ ] Monitor logs for 3 days
- [ ] Compare test vs production schedules
- [ ] If validation passes: cutover to production
- [ ] Monitor temperatures for 24 hours
- [ ] Document lessons learned

---

## Rollback Plan

### If Dell API Fails

**Symptoms:**
- HTTP request times out
- Returns 500 error
- Invalid JSON response
- Missing price data

**Rollback:**
1. Node-RED: Re-enable Tibber flow (if still configured)
2. Dell: Fix handler, redeploy
3. Node-RED: Test in test tab before re-enabling production

**Prevention:**
- Cache last 48h prices on Dell (serve stale if API fails)
- Temperature override still works (independent safety layer)

### If ps-strategy Format Incompatible

**Symptoms:**
- ps-strategy-lowest-price node errors
- No schedule generated
- Debug output shows unexpected format

**Rollback:**
1. Add ps-receive-price back to flow
2. Modify Dell endpoint to return Tibber nested format
3. Or: Add transformer function node between Dell API and ps-strategy

**Prevention:**
- Test in isolated tab first
- Keep production Tibber flow disabled but not deleted

### If Heatpump Behaves Incorrectly

**Symptoms:**
- Indoor temp drops below target
- Hot water temp drops below 40°C
- Heatpump stuck ON or OFF

**Immediate action:**
1. Check temperature override function (should force ON if temps low)
2. Manually set EVU=0 via MQTT: `mosquitto_pub -t ThermIQ/ThermIQ-room2-jj/set -m '{"EVU":0}'`
3. Rollback Node-RED flow to production Tibber

**Root cause:**
- Schedule generation bug
- MQTT communication failure
- Temperature override not working

---

## Future Enhancements (Add to TODO.md)

### Reimplement ps-strategy-lowest-price Logic

**Current:** Using node-red-contrib-power-saver black box

**Future:** Write custom function node with same logic:
```javascript
function selectCheapestHours(prices, hoursOn, maxPrice) {
  // Filter: reject prices above threshold
  const affordable = prices.filter(p => p.total <= maxPrice);

  // Sort: cheapest first
  const sorted = affordable.sort((a, b) => a.total - b.total);

  // Select: top N hours
  const selected = sorted.slice(0, hoursOn);

  // Return: schedule array
  return selected.map(p => ({
    time: p.startsAt,
    value: 0  // EVU=0 (ON)
  }));
}
```

**Benefits:**
- Full control over logic
- Can add custom rules (e.g., prefer consecutive hours)
- Can optimize for peak avoidance explicitly
- No dependency on third-party Node-RED package

**Effort:** 2-3 hours (simple logic, well-defined requirements)

**Priority:** LOW (current ps-strategy works fine, don't fix what ain't broken)

---

## Success Metrics

### Technical Metrics

- ✅ Dell API responds in <500ms (avg)
- ✅ 48 hours of price data returned
- ✅ Peak hours correctly classified (>95% accuracy)
- ✅ Swedish holidays correctly detected (100% accuracy)
- ✅ Node-RED schedule updates every 20 minutes
- ✅ Temperature override still functional
- ✅ MQTT commands reach heatpump

### Operational Metrics (2 weeks post-deployment)

- ✅ Indoor temperature: ≥ target temp (no cold house)
- ✅ Hot water temperature: ≥ 40°C (no cold showers)
- ✅ Heatpump uptime: ~11 hours/day (±10%)
- ✅ API uptime: ≥ 99% (max 1 hour downtime)
- ✅ Electricity cost: Stable or declining vs previous period
- ✅ Zero manual interventions needed

### Financial Metrics (1 month post-deployment)

- ✅ Peak hour avoidance: >50% of heating occurs during off-peak
- ✅ Electricity cost reduction: Target 10-15% vs Tibber baseline
- ✅ Monthly savings: ~400-500 kr (based on peak avoidance optimization)

---

## Documentation Updates

### After Successful Deployment

- [ ] Update CLAUDE.md: Note Tibber → Dell migration complete
- [ ] Update NODE_RED_TIBBER_TO_ELPRISET_MIGRATION.md: Mark as completed
- [ ] Create session report: HEATPUMP_SCHEDULE_MIGRATION_COMPLETE.md
- [ ] Document actual ps-strategy format (if different from hypothesis)
- [ ] Add heatpump_price_handler to handler documentation
- [ ] Update PI_MIGRATION_MAP.md: Note Dell now provides schedule data

---

## Implementation Status

### ✅ COMPLETED (Nov 19, 2025)

1. **Dell API endpoint** - `/api/heatpump/prices`
   - ✅ Created `handlers/heatpump_price_handler.rb`
   - ✅ Reuses ElectricityProjector for peak/off-peak logic
   - ✅ Returns Tibber-compatible format (viewer.homes[].currentSubscription.priceInfo)
   - ✅ Split into today/tomorrow arrays
   - ✅ Deployed to production

2. **ps-strategy algorithm research**
   - ✅ Analyzed node-red-contrib-power-saver source code
   - ✅ Identified simple algorithm: sort by price, select N cheapest hours
   - ✅ Decision: Reimplement in Ruby for better integration

3. **Schedule generation endpoint** - `/api/heatpump/schedule`
   - ✅ Created `handlers/heatpump_schedule_handler.rb`
   - ✅ Implements ps-strategy-lowest-price getBestX algorithm in Ruby
   - ✅ Accepts parameters: `hours_on` (default 12), `max_price` (default 2.2)
   - ✅ Returns ps-strategy compatible format with `schedule` + `hours` arrays
   - ✅ Deployed to production (Nov 20, 2025 00:07:48 CET)
   - ✅ Tested working: returns correct schedule, rejects when avg > max_price

### ✅ COMPLETED (Nov 20, 2025)

4. **Configuration API** - `/api/heatpump/config`
   - ✅ Database schema: Prisma migration for `HeatpumpConfig` table
   - ✅ Domain model: `lib/models/heatpump_config.rb` with validation
     - hours_on: 5-22 (allows low/high runtime scenarios)
     - max_price: 1.5-3.0 kr/kWh
     - min_temp (indoor): 15-23°C - emergency override threshold
     - min_hotwater: 35-50°C - emergency override threshold
     - emergency_price: 0.1-1.0 kr/kWh - force ON below this price
   - ✅ Repository: `lib/repositories/heatpump_config_repository.rb`
     - Singleton pattern (one config record)
     - Auto-creates default on first access (12h, 2.2kr, 20°C, 40°C, 0.3kr)
     - Partial updates supported (PATCH-style)
   - ✅ Handler: `handlers/heatpump_config_handler.rb`
     - GET: Returns current configuration
     - PUT: Updates configuration with validation
   - ✅ Routes: Added to `puma_server.rb`
   - ✅ Tested: GET/PUT endpoints working correctly
   - ⏳ **Not yet deployed to production**

### Next Steps

5. **Temperature override logic** - **IN PROGRESS**
   - ⚠️ Currently BROKEN on Pi (depends on removed Tibber data flow)
   - **Original Node-RED logic:** `if (indoor <= target || hotwater < 40)`
   - **Target temperature source:** Physical heatpump controls via MQTT (user sets with +/- buttons)
   - **Design principle:** Economic tradeoff - tolerate small drops during expensive hours, prevent getting TOO cold

   **Override conditions (force heatpump ON if ANY met):**
   - **Temperature safety:** `indoor <= (target - emergency_temp_offset)`
     - Example: target=21°C, offset=1°C → override at 20°C
     - Example: target=18°C, offset=1°C → override at 17°C (still dynamic!)
     - Configurable offset (0.5-5.0°C) controls economic tradeoff
   - **Hotwater:** `hotwater < min_hotwater` (configurable, defaults to 40°C)
   - **Economic opportunity:** `current_price < emergency_price` (new - force ON during super cheap hours)

   **Benefits:**
   - ✅ User controls ONE thing (target on heatpump)
   - ✅ We control ONE thing (offset tolerance)
   - ✅ Dynamic threshold (no coordination needed between min_temp and target)
   - ✅ Economic optimization (accepts small drop, prevents TOO cold)

   - Remove broken Node-RED temperature override nodes after backend working
   - See "Override Logic Implementation" section below

6. **Dashboard UI** (after backend complete)
   - HeatpumpConfigModal.tsx with 5 sliders:
     - hours_on (5-22h), max_price (1.5-3.0kr), min_temp (15-23°C),
     - min_hotwater (35-50°C), emergency_price (0.1-1.0kr)
   - Real-time schedule visualization
   - Show projected daily cost based on current config

---

## Node-RED Deployment Guide (For Mac Agent)

**Status:** Ready to deploy (Nov 20, 2025)
**Prerequisites:** Both Dell API endpoints deployed and tested working

### API Endpoints Summary

**Price endpoint:**
```bash
GET http://192.168.4.84:3001/api/heatpump/prices

# Returns Tibber-compatible format:
{
  "viewer": {
    "homes": [{
      "currentSubscription": {
        "priceInfo": {
          "today": [
            {"total": 2.0677, "energy": 1.0012, "tax": 0.653, "startsAt": "2025-11-20T00:00:00+01:00"},
            ... 24 hours
          ],
          "tomorrow": [... 0-24 hours, published after 13:00]
        }
      }
    }]
  }
}
```

**Schedule endpoint (RECOMMENDED):**
```bash
GET http://192.168.4.84:3001/api/heatpump/schedule?hours_on=12&max_price=2.2

# Returns ps-strategy-compatible format:
{
  "schedule": [
    {"time": "2025-11-20T00:00:00+01:00", "value": false, "countHours": 24}
  ],
  "hours": [
    {"start": "2025-11-20T00:00:00+01:00", "price": 2.0677, "onOff": false, "saving": null},
    ... 24 hours
  ],
  "config": {
    "hoursOn": 12,
    "maxPrice": 2.2,
    "doNotSplit": false,
    "outputValueForOn": "0",  // EVU=0 (heatpump ON)
    "outputValueForOff": "1"  // EVU=1 (heatpump OFF)
  },
  "time": "2025-11-20T00:09:12+01:00",
  "version": "1.0.0",
  "strategyNodeId": "dell-ruby-scheduler",
  "current": true
}
```

### Deployment Steps

**Step 1: Backup Current Flow**
```bash
# From Mac (has SSH access to Pi)
ssh pi@192.168.4.66 'cat .node-red/flows.json' > ~/flows-backup-$(date +%Y%m%d-%H%M).json
```

**Step 2: Modify Node-RED Flow**

Open Node-RED at http://192.168.4.66:1880 and modify the heatpump schedule flow:

**Remove these nodes:**
1. "Tibber Query" node (GraphQL API call)
2. "ps-receive-price" node (price formatter)
3. "ps-strategy-lowest-price" node (algorithm)

**Replace with single HTTP Request node:**
- **Method**: GET
- **URL**: `http://192.168.4.84:3001/api/heatpump/schedule?hours_on=12&max_price=2.2`
- **Return**: a parsed JSON object
- **Name**: "Dell Schedule API"

**Wire it up:**
- Input: cronplus (existing schedule trigger)
- Output: Connect directly to temperature-override node

**Key insight:** The schedule endpoint returns the FULL schedule, so you skip all the ps-strategy processing. Just extract the schedule and apply temperature override, then send to MQTT.

**Step 3: Extract Schedule in Function Node (if needed)**

Add a function node after HTTP request to extract schedule for temperature override:
```javascript
// msg.payload already contains the full response from Dell API
// Pass through to temperature override
return msg;
```

**Step 4: Deploy**
1. Click **Deploy** button (top right)
2. Select "Modified Nodes"
3. Monitor debug output

**Step 5: Verify**
- Check MQTT messages still being sent to ThermIQ
- Verify EVU values in heatpump data (0=ON, 1=OFF)
- Compare schedule to previous days
- Monitor temperatures for 24 hours

**Rollback (if needed):**
```bash
scp ~/flows-backup-YYYYMMDD-HHMM.json pi@192.168.4.66:.node-red/flows.json
ssh pi@192.168.4.66 'sudo systemctl restart nodered'
```

### Testing Notes (Nov 20, 2025 00:09)

- **Price endpoint**: Returns 24 hours for today, 0 for tomorrow (expected at 00:09, tomorrow not published yet)
- **Schedule endpoint**: Correctly rejects schedule when average price > max_price (turned all hours OFF)
- **Algorithm**: ps-strategy getBestX correctly implemented - sorts by price, selects N cheapest, applies max_price filter
- **Format compatibility**: Returns ps-strategy compatible output (schedule + hours + config)

### Known Behaviors

- **Max price rejection**: When average of N cheapest hours exceeds max_price, algorithm turns ALL hours OFF (safety feature)
- **Tomorrow unavailable**: Before ~13:00, only today's 24 hours available (normal behavior)
- **Peak/off-peak pricing**: Dell API already includes grid rates (0.536 peak, 0.214 off-peak) in total price

---

## Questions & Unknowns

### Known Unknowns (to be resolved during implementation)

1. **ps-strategy-lowest-price format:**
   - Does it accept flat `{ prices: [...] }` format?
   - Or does it need nested Tibber format?
   - What exact field names? (startsAt vs time_start vs time)
   - Resolution: Test with actual node

2. **ps-receive-price role:**
   - Can we bypass it entirely?
   - Or is it needed as compatibility layer?
   - Resolution: Try without first, add back if needed

3. **Tomorrow's price availability:**
   - Elprisetjustnu.se publishes tomorrow after 13:00
   - What if Node-RED cron runs at 12:40?
   - Resolution: Return today only, ps-strategy handles gracefully

4. **Timezone handling:**
   - Dell in UTC? Node-RED in Europe/Stockholm?
   - Does ps-strategy parse ISO 8601 timezone correctly?
   - Resolution: Test with actual timestamps

### Risks

1. **ps-strategy incompatible with Dell format:**
   - Mitigation: Add transformer node or keep ps-receive-price
   - Impact: Low (easy workaround)

2. **API fails during critical hours:**
   - Mitigation: Cache last 48h prices, temperature override
   - Impact: Medium (stale schedule, but safety override works)

3. **Peak detection logic has bugs:**
   - Mitigation: Extensive testing, comparison with electricity_stats
   - Impact: High (incorrect scheduling)

4. **Node-RED modification breaks heatpump:**
   - Mitigation: Shadow mode, test tab, rollback plan
   - Impact: HIGH (cold house, unacceptable)

---

## ✅ COMPLETED: Node-RED Migration (November 20, 2025)

**Status:** Node-RED successfully reconfigured to call Dell schedule API

### Changes Made

**Files:**
- `flows-backup-20251120-1447.json` - Original flows (before migration)
- `flows-modified-20251120.json` - Modified flows (Dell API integration)

**Removed Nodes:**
1. `tibber-query` (ceeb9385f18d3d97) - GraphQL query with invalid API key
2. `ps-receive-price` (f798ba5be61f3422) - Tibber→ps-strategy format converter
3. `ps-strategy-lowest-price` (0f944c8c2f7f82e0) - Price-based scheduling logic
4. Old template node for Tibber format

**Added Nodes:**
1. **HTTP Request** (93fa60e5029d9954) - Calls `http://192.168.4.84:3001/api/heatpump/schedule?hours_on=12&max_price=2.2`
2. **Extract Function** (5eb3e94b9f7d7eb3) - Extracts `current.state` from schedule response, converts to EVU (0=ON, 1=OFF)

**Preserved Nodes:**
- cronplus trigger (every 20 minutes)
- EVU template (formats MQTT message)
- MQTT output (publishes to ThermIQ)

**Why:** Tibber API key invalid since May 2025, logic moved to Dell Ruby backend for better peak/off-peak handling.

### Current Flow Architecture

```
cronplus (20 min)
  ↓
HTTP Request → Dell API
  ↓
Extract current EVU state
  ↓
EVU template
  ↓
ThermIQ MQTT
```

**Deployment:** Applied via Node-RED HTTP API (`POST /flows`) from Dell machine (Nov 20, 2025)

---

## 🔍 Prices Endpoint Format Review (Nov 20, 2025)

**Question:** Do we need the Tibber-compatible nested structure, or can we simplify?

**Current Architecture:**
- `/api/heatpump/schedule` internally calls `HeatpumpPriceHandler` (not HTTP - Ruby object call)
- Schedule handler extracts: `price_data['viewer']['homes'][0]['currentSubscription']['priceInfo']`
- **Node-RED never directly calls the prices endpoint** - only uses `/api/heatpump/schedule`

**Tibber-compatible format:**
```json
{
  "viewer": {
    "homes": [{
      "currentSubscription": {
        "priceInfo": {
          "today": [...],
          "tomorrow": [...]
        }
      }
    }]
  }
}
```

**Analysis:**
- **Nested structure value**: Designed for drop-in Tibber API replacement (migration complete)
- **Separation value**: Today/tomorrow split is actually useful (ps-strategy needs per-day processing)
- **Public endpoint value**: Debugging, potential future dashboard price chart widget
- **Simplification opportunity**: Could flatten to `{today: [...], tomorrow: [...]}` (no viewer.homes nesting)

**Recommendation:** **Keep both endpoint AND format** for now:
1. **Public endpoint** - Debugging value + future dashboard widgets
2. **Keep format** - Clean today/tomorrow separation useful, worth the nesting cost
3. **Future**: Consider simplified format after config UI complete (may want price display there)

**Decision:** Deferred until config UI implementation reveals actual usage patterns.

---

---

## Nov 21, 2025 - Field Cleanup & Architectural Refinement

### ✅ COMPLETED: Backend API Cleanup

**1. Removed `emergencyPrice` field (Nov 20, 2025)**
- **Location:** HeatpumpConfig model, database schema, API responses
- **Original purpose:** Force heatpump ON when price < 0.3 kr/kWh (price opportunity logic)
- **Why removed:** Semantic confusion - "emergency" implies safety, but this was about economics
- **Decision:** Emergency conditions should be temperature-based only (safety), not price-based (optimization)
- **Files affected:**
  - `lib/models/heatpump_config.rb` - Removed emergency_price attribute
  - `handlers/heatpump_config_handler.rb` - Removed from GET/PUT responses
  - Database schema (migration NOT yet applied - emergency_price column still exists)

**2. Removed `maxPrice` field (Nov 21, 2025)**
- **Location:** HeatpumpConfig model, database schema, handler responses, schedule algorithm
- **Original purpose:** Absolute cutoff at 2.2 kr/kWh - clear all selected hours if average exceeded threshold
- **Why removed:** Catastrophic bug with peak/off-peak pricing (2-4 kr/kWh composite prices)
  - Algorithm selected 12 cheapest hours correctly
  - Calculated average (~2.5 kr/kWh) exceeded maxPrice threshold
  - Cleared entire selection → 0 hours ON → house would freeze
- **Heatpump is essential infrastructure:** Cannot defer heating like washing machines
- **Algorithm now:** ALWAYS selects N cheapest hours regardless of absolute price
- **Files cleaned:**
  - ✅ `handlers/heatpump_schedule_handler.rb` - Removed maxPrice parameter from methods (lines 84-121)
  - ✅ `lib/models/heatpump_config.rb` - Removed max_price attribute and validation
  - ✅ `lib/repositories/heatpump_config_repository.rb` - Removed from default config
  - ✅ `handlers/heatpump_config_handler.rb` - Removed from GET/PUT responses
  - ✅ `prisma/schema.prisma` - Removed maxPrice field from HeatpumpConfig model
  - ✅ Migration generated: `prisma/migrations/20251121XXXXXX_remove_max_price_from_heatpump_config/migration.sql`
  - ✅ Migration applied to development database
  - ⏳ **Production migration:** NOT yet applied (run `npx prisma migrate deploy` manually)

**3. Removed useless `'saving'` field (Nov 21, 2025)**
- **Location:** Schedule API response (`handlers/heatpump_schedule_handler.rb` lines 113-120)
- **Original code:** `'saving' => nil # Could calculate savings vs always-on`
- **Why removed:** Meaningless comparison - we're choosing WHICH 12 hours, not 12 vs 24
- **Artificial metric:** Savings calculation would compare strategic 12 hours vs hypothetical 24 always-on
- **No business value:** We're not making that choice, so the metric is useless

### 🔄 IN PROGRESS: Frontend Migration to WebSocket Architecture

**Background - Initial Approach (REST Polling):**

When implementing dashboard schedule visualization, initial plan was:
```typescript
// DataContext.tsx - fetch /api/heatpump/schedule every 5 minutes
useEffect(() => {
  const fetchHeatpumpSchedule = async () => {
    const response = await fetch('/api/heatpump/schedule')
    const data = await response.json()
    dispatch({ type: 'SET_HEATPUMP_SCHEDULE_DATA', payload: data })
  }

  fetchHeatpumpSchedule()  // Initial fetch
  const interval = setInterval(fetchHeatpumpSchedule, 300000)  // 5 min
  return () => clearInterval(interval)
}, [])
```

**Architectural Challenge - User's Insight (Nov 21, 2025):**

User questioned: *"Does it really make sense for this to make the roundtrip via REST if it could be accessed more directly?"*

**Critical Realization:**
- Dashboard already uses **WebSocket broadcast** for ALL data (temperature, rent, weather, electricity)
- Schedule data ALREADY flows via WebSocket in `temperatureData.schedule_data` (old format from Node-RED)
- Creating separate REST polling violates dashboard's unified architecture
- Frontend would have TWO data flows: WebSocket for everything else, polling for schedule

**Better Architecture - Separate WebSocket Broadcast:**

Instead of polling a separate REST endpoint, add schedule as an independent WebSocket broadcast (matching existing pattern):

```ruby
# In lib/data_broadcaster.rb, add schedule alongside existing broadcasts
def start
  @threads = []

  # Existing broadcasts (unchanged)
  @threads << periodic(60) { fetch_and_publish('temperature_data', "#{@base_url}/data/temperature") }
  @threads << periodic(300) { fetch_and_publish('train_data', "#{@base_url}/data/train_departures") }
  # ... etc

  # NEW: Add schedule as separate broadcast (same pattern as everything else)
  @threads << periodic(60) { fetch_and_publish('schedule_data', "#{@base_url}/api/heatpump/schedule") }

  @threads.each { |t| t.join }
end
```

**Why This Is Better Than Nested Calls:**
- ✅ **No blocking:** Schedule fetch happens independently, doesn't block temperature
- ✅ **No nested HTTP calls:** Each endpoint fetches its own data cleanly
- ✅ **Consistent pattern:** Exactly how train_data, weather_data, etc. work
- ✅ **Simple architecture:** Separate concerns, no coupling between handlers
- ✅ **Easy debugging:** Can test each endpoint independently

**Benefits of WebSocket Approach (vs REST polling):**
- ✅ Consistent with existing dashboard architecture (all data via WebSocket)
- ✅ No frontend polling timer needed (one less thing to manage)
- ✅ Backend controls refresh frequency (centralized decision)
- ✅ Temperature override logic automatically included (backend calculates `current.evu`)
- ✅ Reduced network overhead (no separate HTTP requests)

**Current State (Nov 21, 2025 - Work Paused):**

**Files modified but NOT committed (TO BE REVERTED):**

1. **`dashboard/src/context/DataContext.tsx`** (lines 143-175, 642-665)
   - ✅ Added HeatpumpScheduleData interface (KEEP - good TypeScript types)
   - ✅ Added DashboardState.heatpumpScheduleData field (KEEP)
   - ⏸️ Added polling useEffect (REVERT - not needed with WebSocket)
   - ⏸️ Added SET_HEATPUMP_SCHEDULE_DATA action/reducer (REVERT - will use different approach)

2. **`dashboard/src/components/TemperatureWidget.tsx`** (line 84)
   - ✅ Added `heatpumpScheduleData` to destructured state (KEEP - will use enhanced WebSocket data)
   - ⏸️ Schedule visualization logic (lines 125-240) currently reads `temperatureData.schedule_data`
   - ⏸️ Needs update to read `temperatureData.schedule_enhanced` after backend changes

**Implementation Plan - WebSocket Approach:**

**Phase 1: Backend Enhancement**
1. Modify `puma_server.rb` temperature broadcast handler
2. Call `HeatpumpScheduleHandler` internally (Ruby object call, not HTTP)
3. Merge schedule data into temperature_data hash under `schedule_enhanced` key
4. Test WebSocket broadcast includes new fields

**Phase 2: Frontend Update**
1. Revert polling useEffect from DataContext.tsx
2. Update TemperatureWidget to read `temperatureData.schedule_enhanced` instead of `temperatureData.schedule_data`
3. Use `schedule_enhanced.current.evu` for current heatpump state
4. Use `schedule_enhanced.hours` for 48-hour schedule visualization
5. Test with live WebSocket data

**Phase 3: Cleanup**
1. Remove old Node-RED `schedule_data` after verifying new flow works
2. Simplify Node-RED flow (no longer needs to store schedule in global variables)
3. Update documentation with final architecture

**Technical Context Preserved:**
- `temperatureData.schedule_data` = Old format from Node-RED (stale, Node-RED globals)
- `temperatureData.schedule_enhanced` = New format from schedule handler (authoritative, with temperature override)
- TemperatureWidget currently at lines 125-240 has schedule visualization logic ready to adapt
- Schedule handler already returns complete current state with override logic

**Why This Matters - Lessons Learned:**

When initially implementing, focused on "make it work" (REST polling) without considering:
- Existing dashboard data flow patterns (WebSocket broadcast for everything)
- Code consistency across widgets (all consume via WebSocket)
- Maintenance burden (one more polling timer to manage, debug, optimize)

**User's question forced architectural re-evaluation** - sometimes the "quick way" violates system design principles. Taking time to align with existing patterns prevents technical debt accumulation.

### 📋 Remaining Frontend Tasks (After Backend WebSocket Enhancement)

**Priority 1: Revert DataContext Polling Changes**
- Remove useEffect polling logic (lines 642-665)
- Keep HeatpumpScheduleData interface (good types)
- Update reducer to handle WebSocket schedule_enhanced messages

**Priority 2: Update TemperatureWidget Schedule Visualization**
- Change data source from `temperatureData.schedule_data` to `temperatureData.schedule_enhanced`
- Extract current state from `schedule_enhanced.current.evu`
- Extract schedule from `schedule_enhanced.hours` array
- Test visualization with new data format

**Priority 3: Investigate Font Rendering Issue**
- User reported: "Spacing/kerning feels more compressed horizontally after recent @font-face PR merge"
- Possible causes: Font weight mismatches, missing font files (404s), antialiasing changes
- **Planned approach:** Use Playwright to inspect browser:
  - Check Network tab for font loading (are custom fonts 404ing?)
  - Verify font-face declarations in CSS
  - Check computed styles (font-family, font-weight, -webkit-font-smoothing)
  - Look for FOUT (Flash of Unstyled Text) if font-display misconfigured
- **Status:** Deferred - user said "for later"

**Priority 4: Build HeatpumpConfigModal UI**
- After backend WebSocket enhancement complete
- 3-5 configuration sliders (hours_on, emergency_temp_offset, min_hotwater)
- Real-time schedule preview
- See `docs/HEATPUMP_CONFIG_UI_PLAN.md` for complete design

---

**Document Version:** 1.2
**Last Updated:** November 21, 2025
**Next Review:** After WebSocket backend enhancement and frontend migration complete

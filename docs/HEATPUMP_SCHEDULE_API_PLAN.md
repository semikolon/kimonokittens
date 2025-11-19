# Heatpump Schedule API Implementation Plan

**Created:** November 17, 2025
**Status:** Planning → Implementation
**Goal:** Replace Tibber API with Dell-based elprisetjustnu.se pricing + peak/off-peak logic

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

### 🚀 IN PROGRESS (Nov 19, 2025)

3. **Schedule generation endpoint** - `/api/heatpump/schedule`
   - Implements ps-strategy-lowest-price algorithm in Ruby
   - Accepts parameters: hours_on, max_price
   - Returns ready-to-use schedule (no Node-RED processing needed)
   - Benefits: Dashboard integration, simpler Node-RED, single source of truth

### Next Steps

4. **Node-RED integration** (simpler than originally planned)
   - Replace Tibber Query + ps-strategy nodes with single HTTP request
   - Point to: `http://192.168.4.84:3001/api/heatpump/schedule?hours_on=12&max_price=2.2`
   - Shadow mode testing (3 days)
   - Production cutover

5. **Dashboard integration** (future enhancement)
   - Add widget to adjust hours_on slider (9-14 hours)
   - Show projected daily cost based on schedule
   - Real-time schedule visualization

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

**Document Version:** 1.0
**Last Updated:** November 17, 2025
**Next Review:** After Phase 1 completion (Dell endpoint working)

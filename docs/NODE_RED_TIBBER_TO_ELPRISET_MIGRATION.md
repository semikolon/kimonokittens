# Node-RED Tibber → Elprisetjustnu Migration Plan

**Created**: October 26, 2025
**Status**: PLANNING - Do NOT implement yet
**Backup**: `/Users/fredrikbranstrom/Projects/kimonokittens/node-red/flows-backup-20251026.json`

---

## Executive Summary

**Problem**: Node-RED heatpump scheduler has been using invalid
Tibber API demo key since May 2025 (5 months). Demo data
inflated prices by +96.5%, and missing customer-specific
Vattenfall T4 grid rates.

**Impact**: Potentially 2,000 kr wasted electricity over 5
months due to incorrect scheduling.

**Solution**: Replace Tibber API with elprisetjustnu.se (free
public API) + implement complete Vattenfall T4 peak/off-peak
pricing logic in Node-RED JavaScript.

**Complexity**: HIGH - Requires porting 150+ lines of Ruby
pricing logic, Swedish holiday calculations (31+ dates),
timezone handling, and testing without disrupting production
heatpump control.

---

## Current Architecture Analysis

### Flow Structure (20 nodes)

**Flow Tab ID**: `29fc90c7785979ef` ("Energy price optimization")

**Data Flow Path**:
```
cronplus (every 20 mins) [1f2a08915384f40d]
  ↓
template "Tibber price today and tomorrow" [d8725861d54f9a5d]
  ↓
tibber-query [ceeb9385f18d3d97]
  ↓ (3 outputs)
  ├→ debug "prices" [757efe3d87323580]
  ├→ function "Get Current Price and..." [4641c44af4a68a5a]
  │   ↓
  │   delay 2s [756c8209cce0e2e7]
  │   ↓
  │   function "turn heat ON IF temp too low" [b9e0daf8ecbd2227]
  │   ↓
  │   switch "IF heatPumpOn" [77bc6bf212a78b30]
  │   ├→ (true) template "ON" [8751928b946fab25] → EVU
  │   └→ (false) switch "OR price lower than 0.3 SEK" [8133a2344010b22a]
  │                └→ (≤0.3) template "ON" [8751928b946fab25] → EVU
  └→ ps-receive-price [f798ba5be61f3422]
      ↓
      ps-strategy-lowest-price [0f944c8c2f7f82e0]
      ↓ (3 outputs)
      ├→ template "EVU" [a50afa96508b9cab]
      │   ↓
      │   ├→ mqtt out "ThermIQ" [bdaf999070569c65]
      │   └→ debug "on/off" [636ccfb79c3a5ca8]
      ├→ debug "schedule" [4a8289ccae6a1764]
      └→ function "Remember current schedule" [2e9d337a36533938]
```

### Critical Node Configurations

**1. Tibber API Endpoint** (ce5b57bc09b0b3d9):
```json
{
  "type": "tibber-api-endpoint",
  "queryUrl": "https://api.tibber.com/v1-beta/gql"
}
```

**2. Tibber Query GraphQL** (d8725861d54f9a5d):
```graphql
{
  viewer {
    homes {
      currentSubscription {
        priceInfo {
          current { total energy tax startsAt }
          today { total energy tax startsAt }
          tomorrow { total energy tax startsAt }
        }
      }
    }
  }
}
```

**3. ps-strategy-lowest-price** (0f944c8c2f7f82e0):
```json
{
  "name": "Select lowest price hours",
  "hoursOn": "11",
  "maxPrice": "2.2",
  "doNotSplit": false,
  "sendCurrentValueWhenRescheduling": true,
  "outputValueForOn": "0",
  "outputValueForOff": "1"
}
```
**Schedule Logic**: Select 11 cheapest hours per day,
reject hours > 2.2 kr/kWh.

**4. Temperature Override** (b9e0daf8ecbd2227):
```javascript
const indoor = global.get('indoor_temperature');
const hotwater = global.get('hotwater_temperature');
const target = global.get('target_temperature');

if (indoor <= target || hotwater < 40) {
    msg.heatPumpOn = true;  // Override to ON if too cold
} else {
    msg.heatPumpOn = false; // No override
}
```
**Safety**: Prevents cold house even if schedule says OFF.

**5. MQTT Output** (bdaf999070569c65):
```json
{
  "topic": "ThermIQ/ThermIQ-room2-jj/set",
  "payload": "{\"EVU\": 0}"  // or "{\"EVU\": 1}"
}
```
**Control**: EVU=0 allows compressor, EVU=1 blocks it.

### Control Hierarchy

**Priority Order** (highest to lowest):
1. **EVU Hardware Lockout** (Terminal 307/308)
   - Blocks compressor at permission level
   - MQTT: `{"EVU": 1}` = blocked, `{"EVU": 0}` = allowed
   - Cannot be overridden by software

2. **Temperature Override** (Node-RED function)
   - Triggers when: `indoor ≤ target` OR `hotwater < 40°C`
   - Forces heatpump ON regardless of schedule
   - Only effective when EVU allows operation

3. **Tibber Schedule** (ps-strategy-lowest-price)
   - Selects 11 cheapest hours per day
   - Max price threshold: 2.2 kr/kWh
   - Subordinate to temperature override

**Location**: Raspberry Pi at `192.168.4.66:1880`

---

## Ruby Pricing Logic to Port

### Constants (From electricity_stats_handler.rb)

```ruby
# Vattenfall Tidstariff T4 grid transfer rates (excl VAT)
GRID_TRANSFER_PEAK_EXCL_VAT = 0.536     # kr/kWh
GRID_TRANSFER_OFFPEAK_EXCL_VAT = 0.214  # kr/kWh

# Energy tax (excl VAT)
ENERGY_TAX_EXCL_VAT = 0.439  # kr/kWh

# VAT
VAT_MULTIPLIER = 1.25  # 25%

# Monthly fees (not needed for scheduling, only billing)
MONTHLY_FEE_VATTENFALL = 590  # kr/month
MONTHLY_FEE_FORTUM = 88       # kr/month
```

### Peak Hour Detection Logic

**Rules** (From electricity_stats_handler.rb lines 200-220):

1. **Summer months (Apr-Oct) = NO peak pricing**
   - Months 4, 5, 6, 7, 8, 9, 10: Always off-peak

2. **Winter months ONLY** (Jan, Feb, Mar, Nov, Dec)
   - Months: 1, 2, 3, 11, 12

3. **Weekends = NO peak pricing**
   - Saturday (wday=6), Sunday (wday=0)

4. **Swedish holidays = NO peak pricing**
   - 31+ holidays per year (fixed + movable)

5. **Peak hours: 06:00-22:00 local time**
   - Hours 6, 7, 8, ..., 21 (inclusive)
   - Local timezone: Europe/Stockholm (UTC+1/+2)

**Ruby Reference Implementation**:
```ruby
def is_peak_hour?(timestamp)
  dt = DateTime.parse(timestamp)

  # Summer months have NO peak pricing
  return false unless [1, 2, 3, 11, 12].include?(dt.month)

  # Weekends have NO peak pricing
  return false if [0, 6].include?(dt.wday)

  # Swedish holidays have NO peak pricing
  date_only = Date.new(dt.year, dt.month, dt.day)
  return false if swedish_holidays(dt.year).include?(date_only)

  # Peak hours: 06:00-22:00 local time
  local_dt = dt.new_offset('+01:00')
  local_dt.hour >= 6 && local_dt.hour < 22
end
```

### Swedish Holidays Function

**31+ holidays per year** (From electricity_projector.rb
lines 250-290):

**Fixed holidays**:
- January 1: New Year's Day
- January 6: Epiphany
- May 1: International Workers' Day
- June 6: National Day
- December 24: Christmas Eve
- December 25: Christmas Day
- December 26: Boxing Day
- December 31: New Year's Eve

**Movable holidays** (Easter-based):
- Good Friday (Easter - 2 days)
- Easter Sunday
- Easter Monday (Easter + 1 day)
- Ascension Day (Easter + 39 days)
- Whitsun (Easter + 49 days)
- Whit Monday (Easter + 50 days)

**Complex calculation holidays**:
- **Midsummer Eve**: Friday between June 19-25
- **Midsummer Day**: Saturday after Midsummer Eve
- **All Saints' Day**: Saturday between Oct 31 - Nov 6

**Easter dates** (hardcoded lookup table):
```javascript
const EASTER_DATES = {
  2024: new Date('2024-03-31'),
  2025: new Date('2025-04-20'),
  2026: new Date('2026-04-05'),
  2027: new Date('2027-03-28'),
  2028: new Date('2028-04-16')
};
```

**JavaScript Implementation Required**:
```javascript
function swedishHolidays(year) {
  const holidays = [];

  // Fixed holidays
  holidays.push(new Date(year, 0, 1));   // Jan 1
  holidays.push(new Date(year, 0, 6));   // Jan 6
  holidays.push(new Date(year, 4, 1));   // May 1
  holidays.push(new Date(year, 5, 6));   // Jun 6
  holidays.push(new Date(year, 11, 24)); // Dec 24
  holidays.push(new Date(year, 11, 25)); // Dec 25
  holidays.push(new Date(year, 11, 26)); // Dec 26
  holidays.push(new Date(year, 11, 31)); // Dec 31

  // Easter-based holidays
  const easter = EASTER_DATES[year];
  if (easter) {
    holidays.push(addDays(easter, -2));  // Good Friday
    holidays.push(easter);                // Easter Sunday
    holidays.push(addDays(easter, 1));   // Easter Monday
    holidays.push(addDays(easter, 39));  // Ascension
    holidays.push(addDays(easter, 49));  // Whitsun
    holidays.push(addDays(easter, 50));  // Whit Monday
  }

  // Midsummer (Friday between Jun 19-25)
  for (let day = 19; day <= 25; day++) {
    const date = new Date(year, 5, day);
    if (date.getDay() === 5) { // Friday
      holidays.push(date);                // Midsummer Eve
      holidays.push(addDays(date, 1));   // Midsummer Day
      break;
    }
  }

  // All Saints' Day (Saturday between Oct 31 - Nov 6)
  for (let day = 31; day <= 37; day++) {
    const month = day <= 31 ? 9 : 10;  // Oct or Nov
    const dayOfMonth = day <= 31 ? day : day - 31;
    const date = new Date(year, month, dayOfMonth);
    if (date.getDay() === 6) { // Saturday
      holidays.push(date);
      break;
    }
  }

  return holidays;
}

function addDays(date, days) {
  const result = new Date(date);
  result.setDate(result.getDate() + days);
  return result;
}
```

### Price Calculation Formula

**Total price per kWh** (incl VAT):
```
price_per_kwh = (spot_price + grid_rate + energy_tax) × 1.25

Where:
- spot_price: From elprisetjustnu.se (EXCLUDES VAT)
- grid_rate: 0.536 (peak) or 0.214 (off-peak) kr/kWh
- energy_tax: 0.439 kr/kWh
- VAT: 1.25 (multiply by 25%)
```

**Example calculation**:
```
Spot price: 0.50 kr/kWh (no VAT)
Peak hour: 0.536 kr/kWh grid rate
Energy tax: 0.439 kr/kWh

Total excl VAT: 0.50 + 0.536 + 0.439 = 1.475 kr/kWh
Total incl VAT: 1.475 × 1.25 = 1.844 kr/kWh
```

---

## Elprisetjustnu API Integration

### API Endpoints

**Today's prices**:
```
GET https://www.elprisetjustnu.se/api/v1/prices/
    {YYYY}/{MM-DD}_{REGION}.json

Example:
https://www.elprisetjustnu.se/api/v1/prices/
    2025/10-27_SE3.json
```

**Tomorrow's prices** (available after ~13:00 each day):
```
GET https://www.elprisetjustnu.se/api/v1/prices/
    {YYYY}/{MM-DD}_{REGION}.json

Where {MM-DD} = tomorrow's date
```

**Region**: SE3 (Stockholm)

### API Response Format

```json
{
  "region": "SE3",
  "prices": [
    {
      "time_start": "2025-10-27T00:00:00+01:00",
      "time_end": "2025-10-28T01:00:00+01:00",
      "price_sek": 0.19953,
      "price_eur": 0.01829
    },
    ...
  ],
  "generated_at": "2025-10-26T14:30:00+01:00",
  "generated_timestamp": 1730000000
}
```

**Important**:
- `price_sek`: Spot price in kr/kWh (EXCLUDES VAT)
- `time_start`: ISO 8601 timestamp with timezone
- Returns 24 hours of data per request
- Timezone: Europe/Stockholm (UTC+1 winter, UTC+2 summer)

### API Fetching Strategy

**Schedule**: Every 20 minutes (keep existing cronplus)

**Logic**:
1. Fetch today's prices on first run
2. After 13:00, attempt to fetch tomorrow's prices
3. Cache both today + tomorrow in Node-RED global context
4. If tomorrow unavailable, use today's data for scheduling

**Error handling**:
- Retry on network errors (3 attempts)
- Fall back to cached data if API unavailable
- Log errors but don't crash (keep heatpump running)

---

## Migration Implementation Plan

### Phase 1: Preparation & Backups ✅ DONE

**Status**: COMPLETE (October 26, 2025)

- [x] Backup current flows: `flows-backup-20251026.json`
- [x] Document current architecture (this document)
- [x] Identify all nodes to modify/replace
- [x] Map Ruby pricing logic for JavaScript port

### Phase 2: JavaScript Function Development

**Create standalone JavaScript files** (NOT in Node-RED yet):

**File 1**: `pricing_logic.js` (Swedish holidays + peak detection)
```javascript
// Port complete swedish_holidays() function
// Port is_peak_hour() function
// Test with known dates (e.g., Christmas 2024, Midsummer 2025)
```

**File 2**: `price_calculator.js` (Price calculation)
```javascript
// Implement calculate_total_price(spot_price, timestamp)
// Test with known peak/off-peak hours
```

**File 3**: `elpriset_fetcher.js` (API fetching)
```javascript
// Implement fetch_prices(date, region)
// Test with real API calls
// Handle errors gracefully
```

**Testing Strategy**:
1. Run JavaScript files with Node.js locally
2. Test edge cases:
   - Christmas Day 2024 (should be off-peak)
   - Monday Jan 8, 2025 at 10:00 (should be peak)
   - Saturday Feb 1, 2025 at 10:00 (should be off-peak)
   - Midsummer Eve 2025 (should be off-peak)
3. Compare results with Ruby implementation
4. Validate price calculations match within 0.01 kr

### Phase 3: Node-RED Development Environment

**Set up safe testing**:

1. **Export production flow**:
   - Node-RED UI → Menu → Export → Download
   - Save as `production-flow-backup.json`

2. **Create test tab** in Node-RED:
   - New flow tab: "Elpriset Testing"
   - Duplicate key nodes from production
   - Disable MQTT output (don't control heatpump)
   - Add debug nodes everywhere

3. **Test data flow**:
   - Inject test timestamps manually
   - Verify holiday detection
   - Verify peak/off-peak classification
   - Verify price calculations
   - Verify schedule generation

### Phase 4: Node Replacement Strategy

**Nodes to Replace**:

1. **DELETE**: tibber-query node [ceeb9385f18d3d97]
2. **DELETE**: ps-receive-price node [f798ba5be61f3422]
3. **MODIFY**: cronplus template payload (new API URLs)
4. **ADD**: New function node "Fetch Elpriset API"
5. **ADD**: New function node "Calculate Peak Prices"
6. **ADD**: New function node "Select Cheapest Hours"
7. **KEEP**: ps-strategy-lowest-price (or reimplement if needed)
8. **KEEP**: Temperature override function [b9e0daf8ecbd2227]
9. **KEEP**: MQTT output [bdaf999070569c65]
10. **KEEP**: EVU template [a50afa96508b9cab]

**New Flow Architecture**:
```
cronplus (every 20 mins)
  ↓
function "Fetch Elpriset API"
  ↓ (fetches today + tomorrow)
  ↓
function "Calculate Peak Prices"
  ↓ (adds grid rates based on peak detection)
  ↓
ps-strategy-lowest-price (11 hrs, max 2.2 kr)
  OR
function "Select Cheapest Hours" (custom implementation)
  ↓
function "Temperature Override"
  ↓
template "EVU"
  ↓
mqtt out "ThermIQ"
```

### Phase 5: Incremental Deployment

**Step-by-step activation**:

**5.1 Deploy to Test Tab** (1-2 days):
- Run test flow in parallel with production
- Compare schedules: test vs production
- Verify no crashes, no missing data
- Monitor debug logs

**5.2 Shadow Mode** (2-3 days):
- Test flow generates schedule
- Production flow controls heatpump
- Log differences between test and production schedules
- Analyze: Are test schedules reasonable?

**5.3 A/B Testing** (1 week):
- Odd days: Test flow controls heatpump
- Even days: Production flow controls heatpump
- Monitor electricity costs
- Monitor indoor temperature (no cold house!)

**5.4 Full Cutover**:
- Disable production Tibber flow (don't delete yet)
- Rename test flow to production name
- Monitor for 2 weeks
- Delete old Tibber flow after validation

### Phase 6: Monitoring & Validation

**Metrics to Track**:

1. **Heatpump uptime**: Should remain ~11 hours/day
2. **Indoor temperature**: Must stay ≥ target temp
3. **Hot water temperature**: Must stay ≥ 40°C
4. **Electricity cost**: Compare week-to-week trends
5. **API failures**: Log all fetch errors

**Alerting**:
- Send notification if API fails for > 1 hour
- Send notification if indoor temp drops below target
- Send notification if schedule generation fails

**Dashboard**: Create Node-RED UI dashboard showing:
- Current schedule (ON/OFF hours)
- Next API fetch time
- Last successful fetch time
- Peak vs off-peak hour count
- Price distribution histogram

---

## Safe Node-RED Editing Procedures

### Before Making ANY Changes

**Checklist**:
1. ✅ Export current flows: Menu → Export → Download
2. ✅ Save export with timestamp: `flows-backup-YYYYMMDD.json`
3. ✅ Verify backup file is valid JSON
4. ✅ Commit backup to git repository
5. ✅ Note current flow state (heatpump ON or OFF?)

### During Editing

**Rules**:
- Work in a NEW test tab, NOT production tab
- Disable nodes before deleting (prevent accidental triggers)
- Save frequently: Ctrl+S or Deploy button
- Test each change incrementally (don't batch 10 changes)

### Node-RED Quirks to Avoid

**Data Loss Risks**:
1. **Browser refresh during edit = lost changes**
   - Always click Deploy before refresh

2. **Multiple tabs = conflicts**
   - Only edit from ONE browser tab at a time

3. **Node deletion = wire deletion**
   - Wires to/from deleted nodes are lost
   - Reconnect wires manually after re-adding nodes

4. **Global context = NOT persisted by default**
   - Store critical data in flow context if needed
   - Configure context storage in settings.js if required

### Rollback Procedures

**If something breaks**:

**Option A: Quick Rollback (UI)**:
1. Node-RED → Menu → Import
2. Paste backup JSON
3. Deploy

**Option B: File System Rollback**:
1. Stop Node-RED: `sudo systemctl stop nodered`
2. Replace flows file:
   ```bash
   cp /path/to/flows-backup-20251026.json \
      ~/.node-red/flows.json
   ```
3. Start Node-RED: `sudo systemctl start nodered`

**Option C: Git Rollback**:
```bash
cd ~/.node-red
git checkout HEAD~1 flows.json
sudo systemctl restart nodered
```

---

## Testing Strategy

### Unit Testing (JavaScript Functions)

**Test file**: `pricing_logic.test.js`

**Test cases**:
```javascript
// Peak hour detection
assert(isPeakHour('2025-01-10T10:00:00+01:00') === true);
  // Jan 10 2025 is Friday, 10:00 is peak

assert(isPeakHour('2025-01-11T10:00:00+01:00') === false);
  // Jan 11 2025 is Saturday, no peak on weekends

assert(isPeakHour('2025-12-25T10:00:00+01:00') === false);
  // Christmas Day, no peak on holidays

assert(isPeakHour('2025-05-01T10:00:00+02:00') === false);
  // May 1 is holiday AND summer month

// Swedish holidays
const holidays2025 = swedishHolidays(2025);
assert(holidays2025.includes('2025-06-20')); // Midsummer Eve
assert(holidays2025.includes('2025-04-20')); // Easter Sunday
assert(holidays2025.length >= 31); // At least 31 holidays

// Price calculation
const testPrice = calculateTotalPrice(0.50, '2025-01-10T10:00:00+01:00');
// 0.50 (spot) + 0.536 (peak grid) + 0.439 (tax) = 1.475
// 1.475 × 1.25 (VAT) = 1.844 kr/kWh
assert(Math.abs(testPrice - 1.844) < 0.01);
```

### Integration Testing (Node-RED Flow)

**Test scenarios**:

1. **API Fetch Success**:
   - Inject timestamp → Fetch API → Verify 24 prices received
   - Check price range: 0.10 - 2.00 kr reasonable
   - Check timezone: All timestamps have +01:00 or +02:00

2. **API Fetch Failure**:
   - Mock network error → Verify fallback to cache
   - Verify no crash, no empty schedule

3. **Schedule Generation**:
   - Feed 24 hourly prices → Generate schedule
   - Verify 11 hours selected
   - Verify all hours ≤ 2.2 kr threshold
   - Verify cheapest hours prioritized

4. **Temperature Override**:
   - Set indoor_temperature = 17°C (below target 19°C)
   - Verify EVU = 0 (ON) regardless of schedule
   - Set indoor_temperature = 20°C (above target)
   - Verify EVU follows schedule

5. **Holiday Detection**:
   - Test Christmas Day 2024 at 10:00
   - Verify classified as off-peak (0.214 grid rate)
   - Test regular Monday at 10:00
   - Verify classified as peak (0.536 grid rate)

### System Testing (End-to-End)

**Test duration**: 2 weeks minimum

**Validation criteria**:
- ✅ No cold house (indoor temp ≥ target temp)
- ✅ No cold showers (hotwater temp ≥ 40°C)
- ✅ Heatpump uptime ~11 hours/day average
- ✅ Indoor temp stable (no wild swings)
- ✅ API fetch success rate > 95%
- ✅ Schedule updates every 20 minutes
- ✅ Electricity cost trend: declining or stable

**Monitoring tools**:
- Node-RED debug panel (live logs)
- ThermIQ MQTT data (heatpump state)
- Shelly HT sensor (indoor temp/humidity)
- Dashboard temperature widgets

---

## Risk Assessment

### High Risk Scenarios

**1. Cold House**:
- **Risk**: Broken temperature override logic
- **Impact**: Indoor temp drops below comfortable level
- **Mitigation**: Test override thoroughly before deployment
- **Rollback**: Immediate - revert to production flow

**2. API Outage**:
- **Risk**: Elprisetjustnu.se unavailable for extended period
- **Impact**: No schedule updates, heatpump stuck ON or OFF
- **Mitigation**:
  - Cache last known good schedule for 48 hours
  - Temperature override still works
  - Manual override via MQTT if needed
- **Fallback**: Revert to Tibber flow (even with bad data)

**3. Incorrect Peak Detection**:
- **Risk**: Bug in holiday calculation or peak hour logic
- **Impact**: Scheduled during expensive peak hours
- **Mitigation**:
  - Extensive testing with known dates
  - Compare with Ruby implementation
  - Log all peak/off-peak classifications
- **Detection**: Monitor daily cost trends

**4. Data Loss During Edit**:
- **Risk**: Browser crash, network issue, or user error
- **Impact**: Lost flow configuration, broken heatpump control
- **Mitigation**:
  - Frequent backups before/during editing
  - Work in test tab first
  - Deploy incrementally
- **Recovery**: Import from backup JSON

### Medium Risk Scenarios

**5. Schedule Generation Bug**:
- **Risk**: Logic error in cheapest hour selection
- **Impact**: Suboptimal scheduling, higher costs
- **Mitigation**: A/B testing, shadow mode
- **Detection**: Cost tracking over 2 weeks

**6. Timezone Handling Error**:
- **Risk**: Misalignment between API timestamps and local time
- **Impact**: Wrong hours selected as peak/off-peak
- **Mitigation**: Test with DST transitions (Mar/Oct)
- **Detection**: Manual spot-check schedule vs clock

**7. MQTT Communication Issue**:
- **Risk**: Node-RED → ThermIQ connection drops
- **Impact**: Heatpump doesn't receive commands
- **Mitigation**:
  - MQTT broker on same Pi (low latency)
  - Retained messages ensure delivery
- **Detection**: Monitor ThermIQ data feed

### Low Risk Scenarios

**8. Node-RED Performance**:
- **Risk**: New functions slow down Node-RED
- **Impact**: Delayed schedule updates
- **Mitigation**: JavaScript is fast enough for this
- **Detection**: Monitor Node-RED CPU usage

**9. Price Threshold Outdated**:
- **Risk**: 2.2 kr/kWh threshold becomes unrealistic
- **Impact**: Too few hours scheduled, cold house
- **Mitigation**: Temperature override prevents cold house
- **Adjustment**: Easy to change threshold in config

---

## Implementation Checklist

### Pre-Migration (1-2 weeks)

- [ ] Read this entire document
- [ ] Understand current flow architecture
- [ ] Review Ruby pricing logic
- [ ] Set up local JavaScript testing environment
- [ ] Port Swedish holiday calculation to JavaScript
- [ ] Port peak hour detection to JavaScript
- [ ] Port price calculation to JavaScript
- [ ] Test all JavaScript functions with known dates
- [ ] Verify calculations match Ruby within 0.01 kr
- [ ] Create test flow tab in Node-RED
- [ ] Document rollback procedures

### Development Phase (1 week)

- [ ] Create "Fetch Elpriset API" function node
- [ ] Test API fetching with real requests
- [ ] Create "Calculate Peak Prices" function node
- [ ] Test peak detection with today's date
- [ ] Create "Select Cheapest Hours" function node
- [ ] Test schedule generation with real prices
- [ ] Wire up test flow (without MQTT)
- [ ] Add extensive debug logging
- [ ] Compare test schedule vs production schedule
- [ ] Fix any discrepancies

### Testing Phase (2 weeks)

- [ ] Deploy to test tab (parallel to production)
- [ ] Run shadow mode for 3 days
- [ ] Log test vs production schedule differences
- [ ] Analyze differences: Are they reasonable?
- [ ] Start A/B testing (odd/even days)
- [ ] Monitor indoor temperature continuously
- [ ] Monitor heatpump uptime
- [ ] Monitor API fetch success rate
- [ ] Calculate daily electricity costs
- [ ] Compare costs: test vs production weeks

### Deployment Phase (1 day)

- [ ] Final backup of production flow
- [ ] Disable production Tibber flow (don't delete)
- [ ] Rename test flow to production name
- [ ] Update MQTT wiring to live topic
- [ ] Deploy changes
- [ ] Monitor for first 4 hours (1 cron cycle)
- [ ] Verify schedule updates every 20 minutes
- [ ] Verify temperature override still works
- [ ] Verify indoor temp stable

### Post-Deployment (2 weeks)

- [ ] Monitor indoor temperature daily
- [ ] Monitor electricity costs weekly
- [ ] Check API fetch logs for errors
- [ ] Verify holiday detection on next holiday
- [ ] Test DST transition if occurs (Mar/Oct)
- [ ] Document any issues encountered
- [ ] Delete old Tibber flow after 2 weeks success
- [ ] Update this document with lessons learned

---

## Technical Reference

### Node-RED Global Context Variables

**Used by temperature override**:
```javascript
global.get('indoor_temperature')      // From Shelly HT sensor
global.get('hotwater_temperature')    // From ThermIQ heatpump
global.get('target_temperature')      // From ThermIQ heatpump
```

**Used by schedule tracking**:
```javascript
global.set('current_schedule', '10-12');  // Current hour range
global.set('schedule_data', scheduleArray); // Full schedule
```

### MQTT Topics

**Listen** (from ThermIQ heatpump):
```
ThermIQ/ThermIQ-room2-jj/data
```

**Publish** (to ThermIQ heatpump):
```
ThermIQ/ThermIQ-room2-jj/set
```

**Payload format**:
```json
{"EVU": 0}  // Allow compressor
{"EVU": 1}  // Block compressor
```

### JavaScript Date Handling

**Important**:
- Node-RED runs in Europe/Stockholm timezone
- API returns timestamps with +01:00 or +02:00 offset
- JavaScript Date() respects timezone in ISO strings
- Always use ISO 8601 format with timezone

**Example**:
```javascript
const timestamp = '2025-01-10T10:00:00+01:00';
const date = new Date(timestamp);
const hour = date.getHours();  // 10 (local time)
const wday = date.getDay();    // 5 (Friday, 0=Sunday)
const month = date.getMonth() + 1;  // 1 (January)
```

### Price Threshold Logic

**Current**: Max 2.2 kr/kWh

**Why this value**:
- Historical Swedish electricity prices: 0.50-3.00 kr/kWh range
- 2.2 kr is ~75th percentile (expensive but not extreme)
- Ensures ~11 hours/day selected (33% duty cycle)

**Adjusting threshold**:
- Lower → fewer hours, more savings, risk of cold house
- Higher → more hours, less savings, comfort maintained
- Temperature override prevents cold house regardless

---

## Questions & Answers

**Q: Why not keep Tibber API?**
A: Demo key has inflated prices (+96.5%), missing
customer-specific Vattenfall T4 grid rates, and user isn't
a Tibber customer.

**Q: Why not just fix Tibber API key?**
A: User doesn't have Tibber account, can't get valid API key.
Elprisetjustnu is free and complete.

**Q: Can we test without affecting heatpump?**
A: Yes! Test flow in parallel, disable MQTT output, compare
schedules side-by-side.

**Q: What if API is down during cold winter day?**
A: Temperature override forces heatpump ON if
indoor temp drops below target. House stays warm.

**Q: How do we validate JavaScript matches Ruby?**
A: Test with known dates (Christmas, Midsummer, regular
Monday), compare peak/off-peak classification and prices
within 0.01 kr.

**Q: Can we revert quickly if it breaks?**
A: Yes! Import backup JSON in Node-RED UI takes 30 seconds.
Or restart Node-RED with backup flows.json file.

**Q: How much electricity cost savings expected?**
A: Unknown. Potentially 400 kr/month if Tibber data was
causing bad scheduling. Need 2 weeks data to measure.

**Q: What if we discover bugs after 2 weeks?**
A: Fix bugs incrementally, deploy to test tab first,
A/B test again. Never change production directly.

---

## Success Criteria

**Migration considered successful when**:

1. ✅ No cold house incidents (indoor temp ≥ target)
2. ✅ No cold showers (hotwater ≥ 40°C)
3. ✅ Heatpump uptime ~11 hours/day (within 10%)
4. ✅ API fetch success rate ≥ 95%
5. ✅ Schedule updates every 20 minutes reliably
6. ✅ Peak hours correctly classified (spot-check 10 dates)
7. ✅ Swedish holidays correctly detected (test 5 holidays)
8. ✅ Electricity cost trend: declining or stable
9. ✅ No manual interventions needed for 2 weeks
10. ✅ Team confidence in new system

**If any criterion fails**: Investigate, fix, re-test, don't
rush to production.

---

## Appendix A: File Locations

**Node-RED**:
- Flows file: `/home/pi/.node-red/flows.json`
- Backup: `/Users/fredrikbranstrom/Projects/kimonokittens/node-red/flows-backup-20251026.json`
- UI: `http://192.168.4.66:1880`

**Ruby Implementation**:
- Peak logic: `handlers/electricity_stats_handler.rb` lines 200-220
- Holiday calc: `lib/electricity_projector.rb` lines 250-290
- Price calc: `handlers/electricity_stats_handler.rb` lines 280-295

**Documentation**:
- This plan: `docs/NODE_RED_TIBBER_TO_ELPRISET_MIGRATION.md`
- Tibber accuracy: `docs/SESSION_WORK_REPORT_2025-10-09_TIBBER_INVESTIGATION.md`
- Electricity analysis: `docs/ELECTRICITY_PRICE_DATA_ANALYSIS.md`

---

## Appendix B: Acronyms & Terms

- **EVU**: External blocking signal (German: "Energieversorgungsunternehmen")
- **ThermIQ**: MQTT bridge for Thermia heatpump control
- **Peak hours**: Mon-Fri 06:00-22:00 in winter months only
- **Off-peak hours**: All other times (2.5× cheaper grid rate)
- **Grid transfer rate**: Vattenfall T4 contract fee for electricity
  transmission
- **Spot price**: Market price for electricity (varies hourly)
- **Energy tax**: Swedish government tax on electricity consumption
- **VAT**: 25% value-added tax on total electricity cost
- **DST**: Daylight Saving Time (Mar/Oct transitions)
- **SE3**: Swedish electricity region (Stockholm)

---

**END OF MIGRATION PLAN**

**Next Steps**: Review this document completely. Ask questions.
Start JavaScript porting when ready. Do NOT implement in
Node-RED until all testing complete.

**Estimated Timeline**: 4-6 weeks from start to full deployment.

**Contact**: Discuss implementation details before proceeding.

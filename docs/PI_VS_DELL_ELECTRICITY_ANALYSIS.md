# Pi vs Dell: Electricity Data Architecture Analysis

**Created:** October 6, 2025
**Purpose:** Understand current electricity data flow and decide migration strategy

---

## 🔍 Current State Analysis

### Pi Setup (Active, Generating Data)

**Cron Jobs Running Every 2 Hours:**
```bash
0 0,2,4,6,8,10,12,14,16,18,20,22 * * * bundle exec ruby vattenfall.rb
0 0,2,4,6,8,10,12,14,16,18,20,22 * * * bundle exec ruby tibber.rb
```

**Data Files (Pi):**
- `/home/pi/kimonokittens/electricity_usage.json` (712KB! - **actively growing**)
- `/home/pi/kimonokittens/tibber_price_data.json` (26KB)

**What the scripts do:**
- `vattenfall.rb`: Web scrapes actual hourly consumption data from Vattenfall (using Ferrum browser automation)
- `tibber.rb`: Fetches electricity prices via Tibber GraphQL API (62 days of hourly prices)

**Legacy Handler (Pi):**
- `json_server.rb` includes `ElectricityStatsHandler` (Agoo server, ports 6464/6465)
- Serves `/data/electricity_stats` endpoint
- Calculates: daily costs, weekly summaries, monthly projections

---

### Dell Setup (Scripts Present, Not Running)

**Files in Repo:**
- `vattenfall.rb` ✅ (Same as Pi, Jan 2024)
- `tibber.rb` ✅ (Same as Pi, Jan 2024)
- `handlers/electricity_stats_handler.rb` ✅ (Present but **not mounted** in Puma)
- `electricity_usage.json` (19KB - **stale, Jan 2024**)
- `tibber_price_data.json` (52KB - **stale, Jan 2024**)

**What's Actually Used on Dell:**
- `lib/electricity_projector.rb` ✅ **PRODUCTION USE**
  - Used by rent calculator when actual bills aren't available yet
  - Reads from **RentConfig database** (key='el')
  - Trailing 12-month baseline + seasonal multipliers
  - Smart prediction algorithm

**What's NOT Used on Dell:**
- Electricity stats handler (not mounted in `puma_server.rb`)
- Dashboard has no electricity widget
- JSON data files are stale and unused

---

## 🎯 Key Insight: Data Flow Disconnect

**Problem:** Pi generates electricity data but Dell doesn't consume it!

1. **Pi cron jobs** → generate `electricity_usage.json` + `tibber_price_data.json`
2. **Pi's Agoo server** → serves via `/data/electricity_stats` (legacy endpoint)
3. **Dell's dashboard** → ❌ **Does NOT display electricity stats**
4. **Dell's rent calculator** → ✅ Uses `ElectricityProjector` which reads from **database**, not JSON files

---

## 📊 Migration Options

### Option A: Keep Everything on Pi (Status Quo)
**Pros:**
- No migration work needed
- Pi continues working as-is
- If you ever want to display electricity stats, Pi already has the data

**Cons:**
- Data lives on Pi, not accessible to Dell services
- Requires Pi to stay online and functional
- Future handbook features can't easily access electricity data

**Recommendation:** ❌ Not ideal for monorepo consolidation

---

### Option B: Migrate Cron Jobs to Dell (Recommended)
**What to migrate:**
- `vattenfall.rb` execution (every 2 hours)
- `tibber.rb` execution (every 2 hours)
- Write data files to Dell's project root

**What stays on Pi:**
- Node-RED (temperature, heatpump schedules)
- Mosquitto MQTT broker
- DDClient (dynamic DNS)
- Pycalima (fan control)

**Pros:**
- ✅ Consolidates dashboard-related data on dashboard machine
- ✅ Enables future electricity widget on dashboard
- ✅ Data available for handbook features (cost tracking, trends, etc.)
- ✅ Reduces Pi's workload and dependencies
- ✅ Aligns with monorepo architecture (dashboard + data on same machine)

**Cons:**
- Requires setting up cron on Dell
- Need to verify Ferrum/Vessel work on Dell (browser automation for Vattenfall)
- One-time migration effort (~1 hour)

**Implementation Steps:**
1. Verify Dell has required gems (`bundle install` should handle it)
2. Test `ruby vattenfall.rb` and `ruby tibber.rb` on Dell manually
3. Add cron jobs to Dell (either via `config/schedule.rb` or systemd timers)
4. Verify data files write correctly
5. Monitor for 24-48 hours
6. Remove Pi cron jobs

---

### Option C: Migrate to Database-First Architecture
**Concept:** Store electricity data in PostgreSQL, not JSON files

**What this would entail:**
- Modify `vattenfall.rb` to write to database (new `ElectricityConsumption` table)
- Modify `tibber.rb` to write to database (new `ElectricityPrice` table)
- Update `ElectricityStatsHandler` to read from database
- Update `ElectricityProjector` to read from database (currently reads from RentConfig)

**Pros:**
- ✅ Professional, scalable architecture
- ✅ Enables complex queries and analytics
- ✅ Data backup via PostgreSQL dumps
- ✅ Multi-user access (future handbook features)

**Cons:**
- ❌ Significant refactoring work (~4-6 hours)
- ❌ Migration of historical JSON data to database
- ❌ Overkill for current needs

**Recommendation:** ⏳ Future enhancement, not for initial migration

---

## 🔄 Data Usage Matrix

| Component | Uses Electricity Data? | Data Source | Notes |
|-----------|----------------------|-------------|-------|
| **Pi Cron Jobs** | Generates | N/A | vattenfall.rb + tibber.rb |
| **Pi Agoo Server** | Serves | JSON files (Pi) | Legacy `/data/electricity_stats` |
| **Dell Dashboard** | ❌ No | N/A | No electricity widget exists |
| **Dell Rent Calculator** | ✅ Yes | PostgreSQL RentConfig | For projections only |
| **Dell Puma Server** | ❌ No | N/A | Handler exists but not mounted |
| **Future Handbook** | 🔮 Could | PostgreSQL/JSON | Cost tracking, trends, etc. |

---

## 📝 Historical Context

### What Existed on Pi (Legacy Agoo Server)
From `/home/pi/kimonokittens/json_server.rb` (559 lines, May 31 2024):

```ruby
class ElectricityStatsHandler
  def call(req)
    electricity_usage = Oj.load_file('electricity_usage.json')
    tibber_prices = Oj.load_file('tibber_price_data.json')

    # Calculate:
    # - Last 7 days of consumption and cost
    # - Peak price hours
    # - Monthly projection
    # - Daily savings vs fixed price

    stats = {
      electricity_stats: last_days_summed,
      daily_savings: daily_savings,
      monthly_savings_summary: monthly_savings_summary
    }

    [200, { 'Content-Type' => 'application/json' }, [ Oj.dump(stats) ]]
  end
end
```

**Features that were available:**
- Daily cost breakdown for last 7 days
- Peak price hour identification
- Monthly cost projection
- Savings calculation (dynamic pricing vs fixed)

**Why it's not on Dell:**
- Dashboard redesign focused on different priorities:
  - Temperature/heatpump schedules (via Node-RED/MQTT)
  - Train/bus departures
  - Weather
  - Rent calculations
  - Strava workouts
- Electricity stats widget was not carried forward

---

## 🎨 Future Dashboard Integration

### If You Want to Display Electricity Stats Again

**Option 1: Mount Existing Handler (Quick)**
```ruby
# In puma_server.rb
require_relative 'handlers/electricity_stats_handler'
electricity_stats_handler = ElectricityStatsHandler.new

map "/data/electricity_stats" do
  run electricity_stats_handler
end
```

**Option 2: Create New Widget (Better UX)**
- Design new electricity widget for dashboard
- Fetch from `/data/electricity_stats`
- Display: daily costs, weekly trends, monthly projection
- Visual graph of consumption patterns

**Requires:**
- Cron jobs generating data (either Pi or Dell)
- Handler mounted in Puma
- React component in `dashboard/src/components/`

---

## 🏆 Recommendation: Option B (Migrate Cron to Dell)

**Why:**
1. **Dashboard-centric architecture**: Data lives where dashboard lives
2. **Future-proof**: Enables electricity widget if desired
3. **Reduces Pi dependency**: One less thing Pi needs to do
4. **Aligns with monorepo goals**: All dashboard-related code/data on Dell

**What stays on Pi:**
- Node-RED (temperature sensors, heatpump automation)
- Mosquitto MQTT (heatpump messages)
- DDClient (kimonokittens.com DNS)
- Pycalima (bathroom fan control)

**Migration effort:** ~1 hour
- Test scripts on Dell
- Setup cron/systemd timer
- Monitor for 24-48 hours
- Remove Pi cron jobs

---

## 📋 Migration Checklist (Option B)

### Phase 1: Preparation
- [ ] Backup Pi's current data files:
  ```bash
  rsync -av pi@192.168.4.66:/home/pi/kimonokittens/*.json ./pi_backup/
  ```
- [ ] Verify Dell has all required gems:
  ```bash
  cd ~/Projects/kimonokittens
  bundle install
  ```

### Phase 2: Testing
- [ ] Test Vattenfall scraper on Dell:
  ```bash
  cd ~/Projects/kimonokittens
  ruby vattenfall.rb
  # Should create/update electricity_usage.json
  ```
- [ ] Test Tibber API on Dell:
  ```bash
  ruby tibber.rb
  # Should create/update tibber_price_data.json
  ```
- [ ] Verify `.env` has required keys:
  ```bash
  grep -E "VATTENFALL|TIBBER" .env
  ```

### Phase 3: Cron Setup
- [ ] Add to Dell's crontab or use systemd timers:
  ```bash
  # Via whenever gem (already in repo):
  # Update config/schedule.rb
  # Run: bundle exec whenever --update-crontab

  # Or direct crontab:
  crontab -e
  # Add:
  # 0 0,2,4,6,8,10,12,14,16,18,20,22 * * * cd /path/to/kimonokittens && bundle exec ruby vattenfall.rb >> log/electricity.log 2>&1
  # 0 0,2,4,6,8,10,12,14,16,18,20,22 * * * cd /path/to/kimonokittens && bundle exec ruby tibber.rb >> log/electricity.log 2>&1
  ```

### Phase 4: Monitoring
- [ ] Watch logs for 24-48 hours:
  ```bash
  tail -f log/electricity.log
  ```
- [ ] Verify data files update every 2 hours
- [ ] Check file sizes grow over time
- [ ] Spot-check data quality (compare with Pi's files)

### Phase 5: Pi Cleanup
- [ ] Stop Pi cron jobs:
  ```bash
  ssh pi
  crontab -e
  # Comment out vattenfall.rb and tibber.rb lines
  ```
- [ ] Archive Pi data files:
  ```bash
  ssh pi 'mv ~/kimonokittens/*.json ~/kimonokittens/archive/'
  ```
- [ ] Document change in Pi's README

---

## 🔮 Future Enhancements

### Electricity Dashboard Widget
- [ ] Mount handler in `puma_server.rb`
- [ ] Create `ElectricityWidget.tsx` component
- [ ] Design: Daily bar chart + monthly projection
- [ ] Show peak price hours (red highlights)
- [ ] Display savings vs fixed price

### Database Migration
- [ ] Create `ElectricityConsumption` table (timestamp, kwh, cost)
- [ ] Create `ElectricityPrice` table (timestamp, price_per_kwh)
- [ ] Migrate historical JSON data to database
- [ ] Update scrapers to write to database
- [ ] Update handlers to read from database

### Handbook Integration
- [ ] Cost tracking page (monthly electricity trends)
- [ ] Cost split calculator (per-tenant usage if available)
- [ ] Historical cost analysis (year-over-year comparison)
- [ ] Energy efficiency tracking (kWh per degree day)

---

## 📞 Questions for User

1. **Do you want to display electricity stats on the dashboard?**
   - If yes → Migrate cron to Dell + mount handler
   - If no → Can keep on Pi or migrate for future-proofing

2. **How important is electricity data for the handbook?**
   - If high priority → Definitely migrate to Dell
   - If low priority → Can defer

3. **Do you trust Ferrum browser automation on Dell?**
   - Vattenfall scraper uses headless Chrome via Ferrum
   - Needs to work reliably for unattended cron execution

4. **Preference: JSON files or database?**
   - JSON is simpler but less scalable
   - Database is more professional but more work

---

## 🎯 User's Current Position

> "I think DDClient, Pycalima fan control script, Node-RED and Mosquitto could maybe keep working on the Pi."
>
> "But then I could maybe migrate the stuff that's slightly more relevant to the dashboard and rent/electricity/heating stuff that displays on the dashboard or that could be useful for the online handbook."

**Analysis:** User wants to migrate dashboard-relevant data (electricity) to Dell, keep infrastructure services (Node-RED, MQTT, DNS, fan) on Pi.

**Recommendation:** ✅ **Option B (Migrate Cron to Dell)** aligns perfectly with user's intent.

# Electricity Price Data Analysis
**Created:** October 9, 2025
**Purpose:** Verify Tibber API accuracy vs verified elprisetjustnu.se data

---

## 🚨 CRITICAL DISCOVERY: Tibber Cron Job Stopped Working

**Pi's `tibber.rb` has NOT updated since May 2, 2025** (5 months ago!)

```bash
# File check on Pi:
-rw-r--r-- 1 pi pi 26K May  2 00:00 /home/pi/kimonokittens/tibber_price_data.json
```

**Data range in file:** April 1, 2025 → May 1, 2025 (last entry: `2025-05-01T23:00:00`)

**Cron schedule:** Every 2 hours (`0 0,2,4,6,8,10,12,14,16,18,20,22 * * * bundle exec ruby tibber.rb`)

**Implications:**
- ⚠️ **Heatpump schedule potentially running on 5-month-old price data** (if Node-RED still uses tibber.rb output)
- ⚠️ **Potentially wasted money** - schedule optimizes for April 2025 prices in October 2025
- ⚠️ **Cron job silently failing** - no alerting, script may be broken

---

## 📊 Data Source Comparison

### Current State (October 9, 2025)

| Source | API | Last Update | Data Range | Status |
|--------|-----|-------------|------------|--------|
| **Pi `tibber.rb`** | Tibber GraphQL | May 2, 2025 | Apr 1 - May 1, 2025 | ❌ **STALE** |
| **Dell `electricity_price_handler.rb`** | elprisetjustnu.se | Oct 9, 2025 13:06 | Today + tomorrow | ✅ **WORKING** |
| **Pi `vattenfall.rb`** | Vattenfall portal | Oct 9, 2025 | Sep 6, 2024 - Nov 1, 2025 | ✅ **WORKING** |

---

## 🔍 Price Data Accuracy Analysis

### Cannot Compare Directly (No Overlapping Data)

**Problem:** Tibber data stops at May 1, 2025. New handler fetches October 9, 2025 data. **Zero overlap.**

**To verify Tibber accuracy historically**, we would need:
1. Archive of elprisetjustnu.se data from April-May 2025
2. OR wait until Pi's tibber.rb starts working again and compare real-time

---

## 📝 Tibber API Warning from Documentation

**User reported:** Tibber API homepage/docs say "don't trust the data to be accurate"

**Actual status unknown** - need to:
- [ ] Locate specific Tibber API documentation warning
- [ ] Understand context (is it about forecasts vs real prices?)
- [ ] Determine if this affected April-May 2025 heatpump schedules

---

## 🏠 Current Heatpump Schedule Data Source

**UNKNOWN - Needs Investigation:**

Possible scenarios:
1. **Node-RED uses Tibber data** → Stale 5-month-old prices → **BAD**
2. **Node-RED uses elprisetjustnu.se** → Fresh prices → **GOOD** (but when did migration happen?)
3. **Node-RED hardcoded schedule** → No price optimization → **NEUTRAL**

**Investigation needed:**
- SSH to Pi, examine `/home/pi/.node-red/flows.json`
- Check which data source Node-RED heatpump schedule flow uses
- Verify if sparkline implementation affected schedule generation

---

## 🎯 Recommendations

### Immediate Actions

1. **Verify Node-RED schedule data source**
   ```bash
   ssh pi
   grep -i "tibber\|elpriset" /home/pi/.node-red/flows.json
   ```

2. **Fix or migrate tibber.rb**
   - Option A: Debug why Pi cron stopped working
   - Option B: Migrate to Dell immediately (use working elprisetjustnu.se handler)

3. **Add monitoring/alerting for stale data**
   - Dashboard should warn if price data > 48 hours old
   - Cron job should log failures (not silent)

### Long-Term Strategy

**Consolidate to single verified source: elprisetjustnu.se**

**Why:**
- ✅ **Working NOW** on Dell (proven via sparkline)
- ✅ **Hourly updates** via DataBroadcaster (3600s interval)
- ✅ **Aggregates 15-min intervals** → hourly averages (cleaner than Tibber's hourly data)
- ✅ **No Tibber API warnings** about accuracy
- ✅ **Already integrated** into dashboard (SparklineComponent uses it)

**Migration path:**
1. Update Node-RED to fetch from Dell's `/data/electricity_prices` endpoint
2. Remove dependency on Pi's tibber.rb
3. Deprecate Tibber GraphQL API entirely
4. Monitor for 1 week to verify schedule optimization working

---

## 🧮 Potential Money Wasted (Rough Estimate)

**Assumptions:**
- Stale data since May 2, 2025 (5 months)
- Heatpump schedule runs 6-10 hours/day
- Average hourly difference between April prices and October prices: ~20%
- Average electricity cost: 2000 kr/month

**Rough calculation:**
```
5 months × 2000 kr/month × 20% error = 2000 kr potentially wasted
```

**Reality:** Likely less because:
- Node-RED may have switched to another data source
- Schedule might use fallback logic
- Some months have similar price patterns

**Need to confirm:** Check actual schedule behavior before estimating waste.

---

## 📚 Related Documentation

- `docs/PI_MIGRATION_MAP.md` - Cron job details
- `docs/PI_VS_DELL_ELECTRICITY_ANALYSIS.md` - Architecture comparison
- `handlers/electricity_price_handler.rb` - New working implementation
- `dashboard/src/components/TemperatureWidget.tsx:5-77` - SparklineComponent using new data

---

## ⏭️ Next Steps

1. **Investigate Node-RED flows** - Determine actual schedule data source
2. **Fix tibber.rb OR migrate** - Get current price data flowing
3. **Add staleness detection** - Prevent silent failures
4. **Document Tibber API warnings** - Find specific docs about accuracy
5. **Consolidate to elprisetjustnu.se** - Single source of truth

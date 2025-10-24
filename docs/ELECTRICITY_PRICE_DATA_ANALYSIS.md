# Electricity Price Data Analysis
**Created:** October 9, 2025
**Purpose:** Verify Tibber API accuracy vs verified elprisetjustnu.se data

---

## 🚨 CRITICAL DISCOVERY: Tibber API Key Invalid + Demo Data Concerns

### Root Cause Identified ✅

**Pi's `tibber.rb` stopped working because the API key became invalid!**

```bash
# API Key in Pi .env:
TIBBER_API_KEY='5K4MVS-OjfWhK_4yrjOlFe1F6kJXPVf7eQYggo8ebAE'

# Test result:
{"errors":[{"message":"invalid token","extensions":{"code":"UNAUTHENTICATED"}}]}
```

**Error in cron logs:**
```
/home/pi/kimonokittens/tibber.rb:65:in `fetch_tibber_data': undefined method `[]' for nil:NilClass
```

**Timeline:**
- Last successful update: May 2, 2025 (5 months ago)
- API key became invalid sometime after May 2
- Cron job running but failing silently (NoMethodError when parsing nil response)
- Data frozen at April 1 - May 1, 2025

### Tibber Demo API Analysis

**Demo API key tested:** `3A77EECF61BD445F47241A5A36202185C35AF3AF58609E19B53F3A8872AD7BE1-1`

**Result: Demo API gives MASSIVELY INFLATED prices (~96.5% higher than real!)**

**October 9, 2025 Comparison:**
- **Tibber demo daily total:** 21.844 SEK
- **Real prices (elprisetjustnu.se):** 11.116 SEK
- **Difference:** +10.728 SEK (**+96.5%** inflation!)
- **Average error:** +118.7% per hour

**Detailed breakdown:**
- Night hours (0-5): **150-173% inflated** (🚨 >2x real prices)
- Morning peak (7-8): **60-90% inflated** (⚠️ 50%+ higher)
- Daytime (9-19): **70-95% inflated** (⚠️ 50%+ higher)
- Evening (20-23): **125-250% inflated** (🚨 >2x real prices)

**Good news:** Pattern preserved - cheap/expensive hours align 7/8 times
**Bad news:** Absolute prices completely unrealistic

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

## ✅ SE3 Region Verification (October 9, 2025)

**Question:** Is SE3 the correct region for Stockholm area electricity pricing?

**Answer:** ✅ **YES - SE3 is definitively correct**

### Regional Price Comparison (October 9, 2025)

| Region | Area | Avg Price | Range | Morning Peak (08:00) |
|--------|------|-----------|-------|---------------------|
| SE1 | Northern Sweden (Luleå) | 0.07 SEK/kWh | 0.01 - 0.16 | 0.16 SEK/kWh |
| SE2 | Central Sweden (Sundsvall) | 0.02 SEK/kWh | 0.00 - 0.04 | 0.02 SEK/kWh |
| **SE3** | **Southern Sweden (Stockholm)** | **0.66 SEK/kWh** | **0.20 - 1.63** | **1.63 SEK/kWh** |
| SE4 | Southernmost Sweden (Malmö) | 0.75 SEK/kWh | 0.24 - 1.82 | 1.82 SEK/kWh |

### Why SE3 is Correct

1. **Geographic match**: Stockholm is in southern Sweden (SE3 zone)
2. **Price pattern match**: SE3 average (0.66 SEK/kWh) matches verified dashboard data
3. **Economic logic**: Southern regions are expensive due to:
   - Higher population density and demand
   - Less hydroelectric power (northern advantage)
   - More imports from European grid

4. **Consistency check**: Our sparkline shows prices ranging 0.33-1.15 SEK/kWh, which fits perfectly within SE3's 0.20-1.63 range

**Conclusion:** SE3 region setting in `electricity_price_handler.rb` is **100% correct** for Stockholm area.

---

## ⏭️ Next Steps

1. **Investigate Node-RED flows** - Determine actual schedule data source
2. **Fix tibber.rb OR migrate** - Get current price data flowing
3. **Add staleness detection** - Prevent silent failures
4. **Document Tibber API warnings** - Find specific docs about accuracy
5. **Consolidate to elprisetjustnu.se** - Single source of truth

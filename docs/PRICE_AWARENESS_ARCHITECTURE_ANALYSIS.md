# Price Awareness System Architecture Analysis

**Created:** 2025-11-20
**Context:** Deciding whether to keep `maxPrice` field in `HeatpumpConfig` for auto-calculated price thresholds

---

## The Question

Should we keep the `maxPrice` field in `HeatpumpConfig` table and repurpose it as an auto-calculated price alert threshold?

## Arguments FOR Keeping It

### 1. Infrastructure Already Exists
- Database field defined in schema (`maxPrice Float @default(2.2)`)
- Model property (`HeatpumpConfig.max_price`)
- Repository CRUD operations already implemented
- API endpoints (GET/PUT) already handle it
- **Effort saved:** Zero code changes needed to database layer

### 2. Easy Persistence
- Value stored in database, survives restarts
- Can display "current threshold: 3.2 kr" in dashboard
- Historical record of threshold changes over time

### 3. Gradual Migration Path
- Keep field, change how it's populated (manual → auto)
- Backward compatible with existing code
- Low-risk transition

## Arguments AGAINST Keeping It

### 1. Semantic Mismatch (CRITICAL)
**HeatpumpConfig is about HEATPUMP OPERATION:**
- `hours_on` - How many hours to run per day
- `emergency_temp_offset` - When to override schedule (safety)
- `min_hotwater` - Hot water temperature minimum (safety)
- `output_value_for_on/off` - EVU signal format

**Price awareness is about COST OPTIMIZATION:**
- Applies to ALL household appliances (washing machine, dryer, dishwasher)
- Not specific to heatpump operation
- Different concern entirely (cost vs heating)

**Analogy:** Storing grocery budget in thermostat settings. Wrong layer.

### 2. Architectural Coupling
Ties price awareness system to heatpump configuration when they're conceptually separate:
- What if we want dishwasher price alerts? Put threshold in HeatpumpConfig?
- What if we need MULTIPLE thresholds (warning=90th, urgent=95th percentile)?
- Violates Single Responsibility Principle

### 3. Unnecessary Persistence
**User's insight: "Manual override will NOT be needed"**

If value is 100% auto-calculated from statistics:
- Why store it in database at all?
- Can calculate on-demand (cheap: rolling average + std dev)
- Cache in memory like electricity anomaly data

**Current precedent:** Electricity anomaly regression model
- Cached until midnight in `DataBroadcaster`
- Recalculated daily, not stored in DB
- Works perfectly for same use case

### 4. Limits Future Expansion
Single float field can't support:
- Multiple threshold levels (info, warning, urgent)
- Per-appliance thresholds (dishwasher vs dryer)
- Seasonal variation tracking
- Confidence intervals

### 5. Database Pollution
Keeping unused/repurposed fields creates confusion:
- Future developers: "Why is price threshold in heatpump config?"
- Code archaeology: "Is this still used? What does it control?"
- API surface: GET/PUT endpoints imply user can set it (but shouldn't)

## Alternative Architectures

### Option A: Calculate On-Demand (RECOMMENDED)

**Implementation:**
```ruby
class PriceAwarenessService
  def current_threshold(method: :percentile_90, window: 90.days)
    prices = fetch_price_history(window)
    case method
    when :percentile_90
      prices.percentile(90)
    when :std_dev
      prices.mean + (2 * prices.std_dev)
    end
  end
end
```

**Caching:**
```ruby
# In DataBroadcaster (already has electricity stats caching)
@price_threshold_cache ||= {
  value: PriceAwarenessService.current_threshold,
  expires_at: Date.tomorrow.beginning_of_day
}
```

**Pros:**
- No database storage needed
- Separates concerns properly
- Easy to add multiple threshold types
- Follows existing pattern (electricity anomaly caching)

**Cons:**
- Recalculates on server restart (negligible cost)
- No historical record (but do we need it?)

### Option B: Separate Configuration Table

**If** we decide persistence is valuable:

```prisma
model PriceAwarenessConfig {
  id                String   @id @default(cuid())
  warningThreshold  Float    // 90th percentile
  urgentThreshold   Float    // 95th percentile
  calculationMethod String   @default("percentile")
  lastUpdated       DateTime
  createdAt         DateTime @default(now())
  updatedAt         DateTime @updatedAt
}
```

**Pros:**
- Proper semantic location
- Supports multiple thresholds
- Can track calculation method
- Expandable for future needs

**Cons:**
- New database table (migration required)
- More infrastructure (model, repository)
- Still unclear if persistence is needed

### Option C: Part of Electricity Stats System

**Integrate with existing anomaly detection:**

```ruby
# Already exists: electricity_stats_handler.rb
# Add price threshold calculation alongside consumption anomaly
{
  anomaly_summary: [...],  # Existing consumption anomalies
  price_threshold: {       # NEW: Add price awareness
    current: 3.2,
    method: "percentile_90",
    baseline_mean: 2.1,
    baseline_std_dev: 0.4
  }
}
```

**Pros:**
- Leverages existing infrastructure
- Both use statistical baselines
- Natural fit (electricity costs = consumption × price)
- No new database tables

**Cons:**
- Couples price awareness to electricity stats endpoint
- Might make that endpoint too large

## Honest Recommendation

**Remove `maxPrice` from `HeatpumpConfig` entirely.**

**Why:**
1. **Semantic clarity:** Heatpump config should control heatpump, not cost awareness
2. **No persistence needed:** Auto-calculated value doesn't need DB storage
3. **Future flexibility:** Can easily add multiple thresholds, per-appliance alerts
4. **Follows precedent:** Electricity anomaly uses in-memory caching, works great

**Implementation Plan:**

**Phase 1: Remove from HeatpumpConfig (now)**
- Database migration: Drop `maxPrice` column
- Remove from model, repository, handler
- Clean slate for proper architecture

**Phase 2: Build Price Awareness Service (future - TODO.md #9)**
- New service: `lib/services/price_awareness_service.rb`
- Calculate threshold on-demand (percentile or std dev method)
- Cache in DataBroadcaster (expires midnight)
- Return via electricity stats endpoint (natural fit)

**Phase 3: Dashboard Integration (future - TODO.md #9)**
- Enhance sparkline with price threshold line
- Visual alerts when forecast > threshold
- Predictive SMS day(s) before expensive periods

## Decision Matrix

| Criterion | Keep in HeatpumpConfig | Remove & Calculate On-Demand |
|-----------|------------------------|------------------------------|
| Semantic correctness | ❌ Wrong location | ✅ Proper separation |
| Code changes required | ✅ None | ⚠️ Migration + removal |
| Future expandability | ❌ Single value limit | ✅ Unlimited flexibility |
| Persistence needed | ❌ No (auto-calculated) | ✅ No DB storage |
| Architectural clarity | ❌ Confusing | ✅ Clear intent |
| Implementation effort | ✅ Zero | ⚠️ Moderate |
| Follows existing patterns | ❌ No | ✅ Yes (anomaly caching) |

## What Other Systems Do

**Home Assistant:** Price sensors separate from device configs
**OpenHAB:** Rules engine separate from thing definitions
**Node-RED:** Context storage separate from node configs

**Industry pattern:** Separate operational config from analytics thresholds

## Conclusion

**Bias check:** I initially suggested keeping it because "infrastructure exists" and "easy migration."

**Honest take:** That's **lazy architecture**. Just because the field exists doesn't mean we should repurpose it for something semantically unrelated.

**User's instinct is correct:** Be dubious about keeping `maxPrice` in `HeatpumpConfig`.

**Recommendation:** Remove it cleanly. Build price awareness properly as separate service. Future you will thank present you for the clarity.

**Cost of removal:**
- 1 database migration (drop column)
- Remove from 3 files (model, repository, handler)
- 15 minutes of work

**Benefit of removal:**
- Clean architecture
- Proper separation of concerns
- Foundation for extensible price awareness system
- No confusion in 6 months: "Why is this here?"

---

**Final Answer:** Remove `maxPrice` from `HeatpumpConfig`. Don't repurpose it. Build price awareness properly when we implement TODO.md #9.

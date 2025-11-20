# Electricity Price Awareness System - Architecture Proposal

**Created:** 2025-11-20
**Status:** Planning - See TODO.md #9
**Related:** Existing electricity usage anomaly detection (90-day regression model)

---

## Vision

**Goal:** Help household optimize electricity costs by providing awareness and warnings about abnormally high price periods, enabling smarter timing of deferrable appliances (washing machine, tumble dryer, dishwasher).

**Key principle:** Auto-detect abnormal prices via statistical analysis. Users shouldn't manually track what's "expensive" - the system learns normal patterns and alerts on deviations.

---

## Proposed Features

### 1. Statistical Price Baseline

**Concept:** Establish rolling baseline for "normal" electricity prices accounting for seasonal variation.

**Method options:**
- **Percentile-based:** 90th percentile of last 90 days = threshold
- **Standard deviation:** Mean + (2 × std_dev) = threshold
- **Seasonal-aware:** Separate baselines per month (Dec baseline higher than July)

**Example calculation:**
```ruby
# 90-day rolling window
prices = fetch_spot_prices(window: 90.days)
threshold = prices.percentile(90)  # Top 10% trigger alerts

# OR with seasonal adjustment
winter_baseline = winter_prices.mean + (2 * winter_prices.std_dev)
summer_baseline = summer_prices.mean + (2 * summer_prices.std_dev)
```

**Update frequency:** Daily recalculation (cached until next midnight)

### 2. Predictive Warnings

**Day-ahead SMS alerts:**
```
"Dyrt imorgon: 3.8 kr/kWh 07-09"
"Vänta med tvätt till kväll"
```

**Multi-day forecast:**
```
"Fredag dyrast: 4.2 kr/kWh"
"Tvätta redan onsdag"
```

**Timing:** Send evening before expensive day (allows planning)

**Threshold:** Only alert when price exceeds statistical baseline (not every day)

### 3. Dashboard Integration

#### 3a. Enhanced Price Sparkline

**Current state:** Heatpump schedule bar shows price curve overlay

**Proposed enhancement:**
- Visual threshold line (dotted, labeled with kr/kWh value)
- Color-coded regions:
  - Normal prices: neutral gray
  - Elevated (>baseline, <urgent): orange glow
  - Urgent (>95th percentile): red glow
- Tooltip shows: "3.2 kr (normal: 2.1 kr, +52% above avg)"

**Example visualization:**
```
Price (kr/kWh)
4.0 ┤     ╱╲  ← Red glow (urgent)
3.0 ┤    ╱  ╲ ← Orange (elevated)
2.5 ┼ ─ ─ ─ ─ ─  ← Threshold line (auto-calculated)
2.0 ┤  ╱      ╲ ← Gray (normal)
1.0 ┤╱          ╲
    └────────────
    00  06  12  18
```

#### 3b. Current Status Indicator

**Dashboard widget showing:**
```
Elpris just nu: 2.8 kr/kWh
Status: Normal (vardagspris)
```

**Or during high prices:**
```
Elpris just nu: 3.9 kr/kWh
⚠️ Dyrt! Undvik tunga maskiner
```

**Or during peak periods:**
```
Elpris just nu: 4.3 kr/kWh
🔴 Mycket dyrt! Vänta till kväll
```

### 4. Historical Cost Awareness

**Monthly summary (SMS or email):**
```
Nov elförbrukning:
• Normal pris: 847 kr
• Dyra timmar: 156 kr extra (+18%)
• Mest sparbar: Onsdagar 08-10
```

**Insights:**
- Show which appliances ran during expensive hours
- Suggest better timing patterns
- Quantify cost of convenience choices

---

## Integration with Existing Systems

### Leverages Current Infrastructure

**Electricity Usage Anomaly Detection** (already exists):
- Backend: `handlers/electricity_stats_handler.rb` (90-day linear regression)
- Frontend: `dashboard/src/components/RentWidget.tsx` (anomaly sparkline)
- Method: Temperature-based consumption baseline, ±20% deviation threshold
- Caching: DataBroadcaster, expires midnight

**Price Awareness System** (proposed):
- Similar statistical approach (rolling baseline for prices instead of consumption)
- Same caching strategy (DataBroadcaster, daily recalculation)
- Complementary visualization (price anomalies vs consumption anomalies)

**Key difference:**
- **Consumption anomalies:** "You used more than expected" (backward-looking, post-mortem)
- **Price anomalies:** "Prices are higher than normal" (forward-looking, actionable)

**Synergy opportunity:**
- Overlay BOTH on same sparkline: consumption spikes + price spikes
- Identify expensive days: high consumption × high price = worst case
- Show savings potential: "If you'd waited 6 hours: -47 kr"

### Backend Architecture

**Proposed service:**
```ruby
# lib/services/price_awareness_service.rb
class PriceAwarenessService
  def self.current_threshold(method: :percentile_90)
    prices = ElectricityProjector.spot_prices(window: 90.days)

    case method
    when :percentile_90
      prices.percentile(90)
    when :std_dev
      prices.mean + (2 * prices.std_dev)
    when :seasonal
      seasonal_baseline(Date.today.month) + (2 * seasonal_std_dev)
    end
  end

  def self.forecast_warnings(days_ahead: 2)
    forecast = fetch_price_forecast(days_ahead)
    threshold = current_threshold

    forecast.select { |hour| hour.price > threshold }
      .group_by(&:date)
      .map { |date, hours| format_warning(date, hours, threshold) }
  end

  def self.current_status
    current_price = ElectricityProjector.current_spot_price
    threshold = current_threshold

    {
      price: current_price,
      threshold: threshold,
      deviation_pct: ((current_price - threshold) / threshold * 100).round,
      status: categorize(current_price, threshold)
    }
  end
end
```

**Caching in DataBroadcaster:**
```ruby
# Similar to electricity anomaly caching
def fetch_price_awareness_data
  @price_awareness_cache ||= {
    threshold: PriceAwarenessService.current_threshold,
    status: PriceAwarenessService.current_status,
    warnings: PriceAwarenessService.forecast_warnings,
    expires_at: Date.tomorrow.beginning_of_day
  }
end
```

**API endpoint:**
```ruby
# handlers/electricity_stats_handler.rb (extend existing)
{
  anomaly_summary: [...],          # Existing consumption anomalies
  price_awareness: {               # NEW: Price threshold data
    current_price: 2.8,
    threshold: 2.5,
    threshold_method: "percentile_90",
    status: "normal",              # normal | elevated | urgent
    deviation_pct: 12,
    forecast_warnings: [
      { date: "2025-11-21", hours: "07-09", peak_price: 3.9 }
    ]
  }
}
```

### Frontend Visualization

**Data consumption:**
```typescript
// dashboard/src/context/DataContext.tsx
interface ElectricityDailyCostsData {
  anomaly_summary: AnomalySummary;      // Existing
  price_awareness?: PriceAwarenessData; // NEW
}

interface PriceAwarenessData {
  current_price: number;
  threshold: number;
  threshold_method: string;
  status: 'normal' | 'elevated' | 'urgent';
  deviation_pct: number;
  forecast_warnings: ForecastWarning[];
}
```

**Sparkline enhancement:**
```typescript
// dashboard/src/components/RentWidget.tsx
// Overlay price threshold line on existing heatpump schedule bar
<line
  y1={scaleY(data.price_awareness.threshold)}
  y2={scaleY(data.price_awareness.threshold)}
  stroke="orange"
  strokeDasharray="2,2"
/>

// Color price curve segments based on threshold
{priceData.map((hour, i) => {
  const color = hour.price > threshold.urgent ? 'red'
              : hour.price > threshold.elevated ? 'orange'
              : 'gray';
  return <rect fill={color} opacity={0.3} ... />;
})}
```

---

## Architectural Decision: maxPrice Field

### Context

Existing `HeatpumpConfig` table has `maxPrice` field (2.2 kr default) that was removed from schedule generation algorithm (Nov 20, 2025). Question: Should we repurpose it for auto-calculated price threshold?

### Decision: Remove Entirely

**Rationale:**

1. **Semantic mismatch:** HeatpumpConfig is for heatpump operation settings (hours_on, emergency_temp_offset, min_hotwater). Price awareness is about cost optimization across ALL appliances (washing machine, dryer, dishwasher).

2. **Architectural coupling:** Ties price awareness to heatpump when they're separate concerns. Violates Single Responsibility Principle.

3. **No persistence needed:** Auto-calculated threshold doesn't require database storage. Calculate on-demand (cheap), cache in memory (follows existing pattern).

4. **Manual override not needed:** If 100% auto-calculated from statistics, no reason for user configuration or database persistence.

5. **Limits future expansion:** Single float field can't support multiple threshold levels (warning vs urgent), per-appliance thresholds, seasonal tracking.

**Implementation plan:**
1. ~~Remove from schedule generation~~ ✅ Done (Nov 20, 2025)
2. Database migration: Drop `maxPrice` column (future cleanup)
3. Remove from model, repository, handler (~15 min work)
4. Build PriceAwarenessService when implementing TODO.md #9

**Alternative considered:** Keep in database, auto-populate daily

**Why rejected:** Creates confusion ("Why is price threshold in heatpump config?"), limits expansion (can't have multiple thresholds), violates separation of concerns (heatpump ≠ cost awareness).

---

## Implementation Phases

### Phase 1: Foundation (Backend Service)

**Tasks:**
- Create `PriceAwarenessService` with threshold calculation
- Add caching to DataBroadcaster (expires midnight)
- Extend electricity stats endpoint with price awareness data
- Unit tests for statistical methods

**Effort:** ~4 hours
**Deliverable:** API returns current threshold + status

### Phase 2: Dashboard Visualization

**Tasks:**
- Enhance existing sparkline with threshold line
- Color-code price regions (normal/elevated/urgent)
- Add current status widget
- Tooltips showing deviation from baseline

**Effort:** ~3 hours
**Deliverable:** Visual price awareness in dashboard

### Phase 3: Predictive Warnings

**Tasks:**
- Fetch price forecasts (existing Elprisetjustnu.se API)
- Identify expensive periods vs threshold
- Daily cron job to send warnings
- SMS alerts for day-ahead high prices

**Effort:** ~2 hours
**Deliverable:** Proactive cost optimization alerts

### Phase 4: Historical Insights

**Tasks:**
- Track appliance usage during expensive hours
- Monthly cost summary reports
- Savings opportunity identification
- Behavioral insights

**Effort:** ~4 hours
**Deliverable:** Learning system for continuous improvement

---

## Success Metrics

**Quantitative:**
- Reduction in electricity cost (target: 10-15% monthly savings)
- % of expensive hours with deferrable loads reduced
- User engagement with warnings (SMS open rate, dashboard views)

**Qualitative:**
- User reports better awareness of price patterns
- Behavior change (washing machine usage shifts to cheaper hours)
- Reduced anxiety about electricity costs (transparency)

---

## Open Questions

1. **Threshold calculation method:** Percentile vs std dev vs seasonal? Test with historical data.

2. **Warning frequency:** Daily SMS sufficient or real-time push notifications?

3. **Appliance integration:** Track individual appliance usage during expensive periods? (Requires additional telemetry)

4. **Household learning:** Personalized thresholds based on household tolerance for cost vs convenience trade-offs?

5. **Grid integration:** Consider not just price but carbon intensity? (Sustainability angle)

---

## References

**Existing systems:**
- Electricity usage anomaly detection: `handlers/electricity_stats_handler.rb:243-328`
- ElectricityProjector (peak/off-peak pricing): `lib/electricity_projector.rb`
- Dashboard sparkline: `dashboard/src/components/RentWidget.tsx:156-596`
- DataBroadcaster caching: `lib/data_broadcaster.rb`

**External data sources:**
- Spot prices: Elprisetjustnu.se API (SE3 Stockholm zone)
- Price forecasts: Same API (provides day-ahead EPEX Spot data)
- Grid fees: Known constants (peak 53.6 öre, off-peak 21.4 öre)

**Related documentation:**
- TODO.md #9 - Electricity Price Awareness System feature spec
- HEATPUMP_EMERGENCY_FIXES_TODO.md - Context from emergency session

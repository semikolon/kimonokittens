# Anomaly Sparkline Bar Implementation Plan

## Current State (as of Oct 26, 2025)

**Text-based anomaly summary:**
```
Elförbrukning Jul 28 - Aug 23: oväntat hög (ca +30%), 2-18 Aug: oväntat låg (ca -26%),
Sep 8: oväntat hög (ca +39%), Sep 13: oväntat låg (ca -23%), 8-16 Oct: oväntat låg (ca -24%).
Förmodligen pga varierande antal personer i huset
```

**Problems:**
- Not visually intuitive
- Requires reading/parsing text
- Doesn't show temporal context (how much of 90-day period was anomalous)
- No cost impact visualization

## Desired State

**Visual sparkline bar showing anomaly clusters:**
- Single horizontal bar representing full 90-day regression window
- Anomaly clusters shown as chunks (like old DailyElectricityCostBar)
- Each chunk displays:
  - Line 1: Date range (e.g., "Jul 28 - Aug 23")
  - Line 2: Anomaly % (e.g., "+30%")
  - Line 3: Cost impact (e.g., "+200kr")
- Color coding: positive anomalies (high usage) vs negative (low usage)
- Non-anomalous periods shown as neutral/background chunks

## Data Available

### Backend (`electricity_stats_handler.rb:285-288`)
```ruby
anomaly_summary: {
  total_anomalies: all_anomalies.length,
  anomalous_days: [
    {
      date: "Jul 28",
      consumption: 27.3,  # kWh
      expected: 19.4,     # kWh
      temp_c: 20.7,       # °C
      excess_pct: 41.0    # Can be positive or negative
    },
    # ... more anomalies (7 in current dataset)
  ]
}
```

### Frontend TypeScript Interface (RentWidget.tsx:6-15)
```typescript
anomalySummary?: {
  total_anomalies: number
  anomalous_days: Array<{
    date: string
    consumption: number
    expected: number
    temp_c: number
    excess_pct: number  // Positive = high, Negative = low
  }>
}
```

### Clustering Algorithm (RentWidget.tsx:46-70)
- 14-day temporal clustering window
- Separates high (+) and low (-) anomalies
- Results in 2-5 clusters for current dataset
- Example clusters:
  1. Jul 28 - Aug 23: +30% avg (high cluster)
  2. 2-18 Aug: -26% avg (low cluster)
  3. Sep 8: +39% (standalone high)
  4. Sep 13: -23% (standalone low)
  5. 8-16 Oct: -24% avg (low cluster)

## Historical Bar Component Analysis

### Old `DailyElectricityCostBar` (commit b310230)

**Key features we can reuse:**
1. Flex container for chunks (`dashboard/src/components/RentWidget.tsx:113-117`)
2. Individual chunk styling with rounded corners
3. Text rendering with shadows for readability
4. Background opacity for visual hierarchy
5. Anomaly glow effect (proportional to excess_pct)

**Code structure:**
```tsx
<div className="relative h-16 rounded-lg overflow-visible">
  {/* Sparkline SVG overlays (if needed) */}
  <svg className="absolute inset-0 w-full h-full" ...>
    <path d={sparklinen} ... />
  </svg>

  {/* Day/Cluster chunks */}
  <div className="absolute inset-0 flex">
    {chunks.map((chunk, index) => (
      <div
        key={index}
        className="flex-1 relative h-full"
        style={{ flex: chunk.durationWeight }} // Width proportional to time span
      >
        {/* Background */}
        <div className="absolute inset-0 bg-white opacity-5" />

        {/* Anomaly glow (if anomalous) */}
        {chunk.isAnomalous && (
          <div className="absolute inset-0" style={{
            backgroundColor: chunk.isHigh ? '#ff6600' : '#6699ff',
            opacity: Math.abs(chunk.avgPct) / 100 * 0.6
          }} />
        )}

        {/* Text content */}
        <div className="relative z-10 flex flex-col items-center">
          <div className="text-xs">{chunk.dateRange}</div>
          <div className="text-sm font-bold">{chunk.anomalyPct}</div>
          <div className="text-xs">{chunk.costImpact}</div>
        </div>
      </div>
    ))}
  </div>
</div>
```

## Implementation Plan

### Phase 1: Data Preparation & Chunk Generation

**File:** `dashboard/src/components/RentWidget.tsx`

**Function:** `prepareAnomalyChunks(anomalySummary, fullPeriodDays = 90)`

**Input:**
- `anomalySummary` from backend
- `fullPeriodDays` - total regression window (default 90)

**Output:** Array of chunk objects:
```typescript
interface AnomalyChunk {
  type: 'anomalous' | 'normal'
  startDate: string       // "Jul 28" or null for normal periods
  endDate: string         // "Aug 23" or null
  dateRange: string       // "Jul 28 - Aug 23" or "normal periods"
  durationDays: number    // Number of days in this chunk
  isHigh: boolean         // true = high usage, false = low usage
  avgExcessPct: number    // Average excess % for cluster
  costImpactKr: number    // Calculated cost impact in kr
}
```

**Algorithm:**
1. Sort all anomalous days chronologically
2. Apply 14-day clustering (reuse existing `clusterAnomalies` function)
3. Create anomaly chunks from clusters
4. Fill gaps between anomaly chunks with "normal" chunks
5. Calculate chunk widths proportional to duration vs 90-day total

**Challenges:**
- Need to infer normal periods between anomalies
- Calculate start/end dates for full 90-day window (need backend to provide)
- Cost calculation requires spot prices for anomalous dates

### Phase 2: Cost Impact Calculation

**Challenge:** Backend doesn't currently send individual date prices with anomalies.

**Options:**

**Option A: Backend enhancement (RECOMMENDED)**
```ruby
# In electricity_stats_handler.rb, enhance anomaly data:
all_anomalies << {
  date: day[:date],
  consumption: actual_consumption.round(1),
  expected: expected_consumption.round(1),
  temp_c: day[:avg_temp_c],
  excess_pct: excess_pct,
  # NEW FIELDS:
  price_per_kwh: price_per_kwh,  # From tibber_prices lookup
  cost_impact: ((actual_consumption - expected_consumption) * price_per_kwh).round(1)
}
```

**Option B: Frontend estimation (FALLBACK)**
- Use average electricity price from current month
- Estimate: `costImpact = (consumption - expected) * avgPricePerKwh`
- Less accurate but doesn't require backend changes

**Recommended:** Option A for accuracy

### Phase 3: Component Implementation

**New component:** `AnomalySparklineBar`

**Location:** `dashboard/src/components/RentWidget.tsx` (inline component)

**Props:**
```typescript
interface AnomalySparklineBarProps {
  anomalySummary: {
    total_anomalies: number
    anomalous_days: Array<{
      date: string
      consumption: number
      expected: number
      temp_c: number
      excess_pct: number
      price_per_kwh?: number      // If backend provides
      cost_impact?: number        // If backend provides
    }>
  }
}
```

**Visual design:**
```
┌─────────────────────────────────────────────────────────────────────┐
│  [normal]  [HIGH GLOW]      [LOW GLOW]  [normal]  [HIGH]  [LOW]    │
│            Jul 28-Aug 23    2-18 Aug             Sep 8    Sep 13    │
│            +30%             -26%                 +39%      -23%      │
│            +450kr           -320kr               +89kr     -55kr     │
└─────────────────────────────────────────────────────────────────────┘
    ← Full width represents 90-day regression window →
```

**Color scheme:**
- **High anomalies:** Orange/red glow (`#ff6600`)
- **Low anomalies:** Blue glow (`#6699ff`)
- **Normal periods:** Subtle white overlay (5% opacity)

**Intensity mapping:**
- Glow opacity: `Math.abs(excess_pct) / 100 * 0.6` (max 60% opacity at 100% excess)
- Box shadow intensity scales with excess_pct

### Phase 4: Integration & Testing

**Steps:**
1. Replace text-based `AnomalySummaryText` component
2. Add `AnomalySparklineBar` before rent message
3. Test with current dataset (7 anomalies)
4. Verify chunk widths are proportional
5. Verify cost calculations are accurate
6. Test edge cases:
   - 0 anomalies (show message "Ingen avvikande förbrukning")
   - 1 anomaly
   - Many anomalies (>10)

## Regression Window Research (Oct 26, 2025)

**Question:** Should we extend regression window from 90 days to 180+ days?

**Available data:** 401 days of historical electricity usage (Sept 26, 2024 → Nov 1, 2025)

**GPT-5 Analysis:**

**Key finding:** Don't simply extend to 180-365 days with current uniform weighting - will dilute anomaly detection by mixing heating/non-heating seasonal regimes.

**Recommendations:**
1. **Keep 90-120 days** for simple linear model with uniform weights (current implementation)
2. **To extend to 180+ days**, need model enhancements:
   - Time-decay weighting (45-60 day half-life), OR
   - Regime-based fitting (heating vs non-heating seasons, split at ~12°C), OR
   - Switch to Heating Degree Days (HDD) instead of raw temperature

**Rationale:**
- Swedish climate has distinct heating/non-heating regimes with different consumption-temperature slopes
- Single linear fit over 180+ days mixes both regimes, flattening slopes and reducing anomaly sensitivity
- Want responsive detection for recent occupancy changes (last 14 days)
- Longer uniform windows bias toward older behavior patterns

**Decision:** Keep 90 days for now. Window extension is separate enhancement requiring model changes.

**Future work:** Consider implementing time-decay weighting OR HDD-based model for more stable 180-day window.

---

## Open Questions & Decisions Needed

### Q1: How to determine 90-day window boundaries?

**User decision:** Add backend metadata for regression window dates.

**Implementation:** Backend sends `{ start_date: "Jul 18", end_date: "Oct 16", total_days: 90 }` in anomaly_summary.

### Q2: Should we show a sparkline overlay?

**User decision:** Yes - sparkline should represent regression excess percentages.

**Implementation:** Single sparkline showing excess_pct values (+30%, -23%, etc.) as peaks and troughs, NOT price data or temperature data. The sparkline visualizes the deviation from expected consumption.

### Q3: Chunk text sizing

**User decision:** Aim for 6-7 chunks maximum. Text sizing shouldn't be an issue, cross that bridge if needed.

**Implementation:** Use clustering algorithm that produces 6-7 chunks. If text becomes cramped during testing, adjust font sizes or abbreviate then.

### Q4: Cost calculation accuracy

**User decision:** Backend enhancement - go ahead!

**Implementation:** Calculate exact cost impact in backend anomaly detection loop using hourly price data already available in `tibber_prices` hash.

Add to each anomaly:
- `price_per_kwh`: Daily average of hourly spot prices
- `cost_impact`: `(actual_consumption - expected_consumption) * price_per_kwh` in SEK

## Implementation Estimate

**Time:** 2-4 hours

**Breakdown:**
- Phase 1 (Data prep): 30 min
- Phase 2 (Backend cost calc): 30 min
- Phase 3 (Component): 60-90 min
- Phase 4 (Integration/testing): 30-60 min

**Dependencies:**
- Backend changes (if Option A for cost calc)
- Decision on open questions

## References

- Old bar component: commit `b310230`
- Anomaly detection: `electricity_stats_handler.rb:218-277`
- Current clustering: `RentWidget.tsx:46-70`
- TypeScript interfaces: `DataContext.tsx:115-133`

---

**Status:** Ready for implementation pending user decisions on open questions.

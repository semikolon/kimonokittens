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

**Status:** ✅ **IMPLEMENTED** (Oct 26, 2025)

## Implementation Complete

**Backend Enhancement (commit 46a1f7d):**
- ✅ Added `price_per_kwh` and `cost_impact` calculation to each anomaly
- ✅ Daily average price lookup using hourly Tibber data
- ✅ Cost impact formula: `(actual_consumption - expected_consumption) * price_per_kwh`
- ✅ Price includes spot price + transfer fee (0.09) + energy tax (0.392) + VAT (25%)

**Frontend Component (commits 1952568, current):**
- ✅ AnomalySparklineBar replaces text-based summary
- ✅ Visual chunks show date range, excess %, cost impact
- ✅ SVG sparkline overlay shows excess_pct peaks/troughs with 0% baseline
- ✅ 14-day temporal clustering produces 5 chunks
- ✅ Chunk widths proportional to time duration
- ✅ Console logging for cost verification
- ✅ Positioned at bottom of widget with top margin
- ✅ Text padding (1em left/right) for readability
- ✅ No background coloring (removed orange/blue glows per user request)

**Current Visualization:**
- High Cluster 1: Jul 28 - Aug 23 (6 days)
- Low Cluster 1: 2-18 Aug (5 days)
- High Cluster 2: Sep 8 (1 day)
- Low Cluster 2: Sep 13 (1 day)
- Low Cluster 3: 8-16 Oct (2 days)

**Cost Calculation Verification:**
Example (Jul 28):
- Actual: 27.3 kWh, Expected: 19.4 kWh, Difference: +7.9 kWh
- Price: 0.985 kr/kWh (spot ~0.35 + transfer 0.09 + tax 0.392, all × 1.25 VAT)
- Cost Impact: 7.9 × 0.985 = 7.8 kr (single day)
- Clusters aggregate multiple days: Jul 28 + Jul 29 + Aug 10 + Aug 11 + Aug 14 + Aug 23

**Console Debugging:**
Open browser console to verify:
- Individual day cost_impact values
- Cluster aggregation totals
- All assumptions (price, consumption diff, clustering logic)

---

## Sparkline Architecture Clarification (Oct 26, 2025)

**User requirement**: Sparkline should show continuous curve of excess_pct across FULL 90-day window, completely uncoupled from anomaly chunks.

**Current limitation**: Backend only sends 15 anomalous days (those exceeding ±20% threshold). Cannot draw continuous 90-day sparkline from this sparse data.

**Required backend change:**
```ruby
# In electricity_stats_handler.rb, add new field alongside anomaly_summary:
regression_data: historical_with_temp.map do |day|
  {
    date: day[:date],
    excess_pct: ((day[:consumption] / (slope * day[:avg_temp_c] + intercept) - 1) * 100).round(1)
  }
end
```

**Frontend will then:**
- Draw continuous sparkline from all 90 days of regression_data
- Overlay anomaly chunks as highlights (unchanged)
- Sparkline and chunks are visually independent

**Alternative (simpler)**: Start sparkline at first anomaly date, end at last anomaly date, interpolate between anomaly points. Less accurate but requires no backend changes.

---

## Sparkline Scaling Fix (Oct 26, 2025)

**Problem**: Sparkline appeared completely flat in browser.

**Root causes**:
1. **X-coordinate calculation**: Used `(index / totalDays) * width`, which never reached 100 at the end. For 90 days, last point was at x=98.89.
2. **Y-axis scaling too conservative**: Used fixed `/2` divisor, making ±40% variations only move ±20 pixels in 100px viewBox.
3. **No dynamic scaling**: Didn't adapt to actual min/max values in dataset.

**Solution** (commit `47bd5a5`):
```typescript
// Fix x-coordinate to reach 100 at end
const x = totalDays > 1 ? (index / (totalDays - 1)) * width : 0

// Dynamic y-axis scaling with padding
const minExcess = Math.min(...excessValues)
const maxExcess = Math.max(...excessValues)
const padding = 10  // 10% padding top/bottom
const usableHeight = 100 - (2 * padding)
const normalizedY = (day.excess_pct - minExcess) / range
const y = padding + (1 - normalizedY) * usableHeight
```

**Debugging support**: Added comprehensive console logging to verify:
- Regression data length and sample values
- Min/max/range of excess_pct values
- Generated SVG point coordinates

**Dev logs limitation discovered**: `npm run dev:logs` fails in Claude Code because it calls `overmind connect`, which requires interactive terminal (TTY). Alternative: Browser DevTools console (F12) for client-side logs.

**Files modified**:
- `dashboard/src/components/RentWidget.tsx` (lines 335-381)

**Status**: ✅ Committed and pushed. Awaiting browser verification.

---

## Chunk Alignment & Visual Refinements (Oct 26, 2025) - LATEST WORK

### Problem: Chunks didn't align with sparkline peaks/troughs

**Root cause discovered:** Two separate issues:
1. **Overlapping date ranges** - Clustering high/low separately created ranges like "Aug 15-18" inside "Aug 10-23"
2. **Flex layout drift** - Proportional flex widths accumulated positioning errors vs sparkline's calendar positioning

### Solution 1: Unified Clustering with Type Splits (commit 9c17d51)

**Algorithm change:**
```typescript
// OLD: Separate clustering caused overlaps
const highClusters = clusterAnomalies(highAnomalies, 10)
const lowClusters = clusterAnomalies(lowAnomalies, 10)

// NEW: Unified clustering, then split on type changes
const initialClusters = clusterAllAnomalies(sortedDays, 10)
const finalClusters = initialClusters.flatMap(splitOnTypeChanges)
```

**Result:** No more overlapping date ranges. "Aug 10-23" becomes:
- [Aug 10-14 high] [Aug 15-18 low] [Aug 18-23 high]

### Solution 2: Absolute Positioning (commits d8ebb52, dcca0c1)

**Replaced flex layout with calendar-based absolute positioning:**
```typescript
// Calculate exact position in 89-day window
const startIndex = daysBetween(windowStart, chunk.startDate)
const leftPercent = (startIndex / (totalDays - 1)) * 100
const widthPercent = (chunk.durationDays / (totalDays - 1)) * 100

// Render with absolute positioning
<div style={{ left: `${leftPercent}%`, width: `${widthPercent}%` }}>
```

**Key insight:** Use same formula as sparkline: `(index / 88) * 100` for 89 days

### Solution 3: Minimum Width + Radial Glow (commits 1934e77, current)

**Problem:** Short chunks (1-2 days) caused text wrapping

**Solution:**
- 8% minimum width for anomaly chunks (gaps stay proportional)
- Radial gradient glow instead of uniform background (reduces overlap clash)
- Orange glow for high anomalies, turquoise for low

```typescript
const minWidthPercent = chunk.type === 'gap' ? calculatedWidth : 8
const widthPercent = Math.max(calculatedWidth, minWidthPercent)

// Radial glow centered in chunk
background: chunk.type === 'high'
  ? 'radial-gradient(circle at center, rgba(255, 136, 68, 0.06), transparent)'
  : 'radial-gradient(circle at center, rgba(68, 204, 204, 0.06), transparent)'
```

### Current Status (Oct 26, 2025)

**Architecture:**
- Unified clustering algorithm (10-day window)
- Absolute calendar positioning
- 8% minimum width with radial gradient glow
- Orange/turquoise color coding for high/low anomalies

**Configuration values:**
- Clustering window: 10 days
- Sparkline tension: 0.2 (balance smoothness vs daily responsiveness)
- Bar opacity: 0.018 (subtle background)
- Gradient: orange→dark purple→turquoise (50% dark stop at 0.25 opacity)
- Chunk glow: 0.06 opacity (doubled from background for visibility)
- Min width: 8% (~96px at 1200px viewport)

**Positioning formula:** Matches sparkline exactly - `(index / 88) * 100` for 89-day window

### Cost Impact Calculation Verification (Oct 26, 2025)

**Formula (backend: `handlers/electricity_stats_handler.rb:256-260`):**
```ruby
consumption_diff = actual_consumption - expected_consumption  # kWh
cost_impact = (consumption_diff * price_per_kwh).round(1)    # SEK
```

**Price components:**
- Spot price: Variable hourly rate from Tibber API (~0.50-1.50 kr/kWh)
- Transfer price: `(0.09 + 0.392) × 1.25 = 0.6025 kr/kWh` (Vattenfall network + energy tax + VAT)
- Total: ~1.10-2.10 kr/kWh depending on spot price

**Per-day calculation then summed in frontend:**
```typescript
const totalCostImpact = cluster.reduce((sum, d) => sum + d.cost_impact, 0)
```

**Critical insight: Date ranges are misleading!**
- Chunk label "Jul 28 - Aug 23" spans 27 days
- But only anomalous days (>20% from expected) contribute to cost_impact
- Normal days within that span are excluded from the sum
- Example: "Jul 28 - Aug 23, +30%, +46 kr" might be:
  - Jul 28-29 (2 days) + Aug 10-14 (5 days) + Aug 23 (1 day) = 8 anomalous days
  - At ~6 kr/day excess → 48 kr ≈ 46 kr shown ✓

**Math verification (single-day example from screenshot):**
- "Sep 8" → +39%, +12 kr
- If expected: 20 kWh, actual: 27.8 kWh (39% excess)
- Excess: 7.8 kWh × 1.54 kr/kWh = 12 kr ✓

**Why values seem low:**
1. Only anomalous days count (not full date span)
2. Many clusters have gaps with normal days between anomalies
3. Typical excess: 5-8 kWh/day × 1-2 kr/kWh = 5-15 kr/day

**Display considerations:**
- Percentage (+30%) shows magnitude but not actionable cost
- Cost impact (+46 kr) is more meaningful but date range misleading
- Could add day count ("8 days") to clarify non-continuous span
- Could remove percentage to reduce visual clutter

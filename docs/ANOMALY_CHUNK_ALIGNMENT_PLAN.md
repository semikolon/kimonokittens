# Anomaly Chunk vs Peak/Trough Alignment Analysis & Fix Plan

**Date**: October 26, 2025
**Status**: Investigation & Planning
**Context**: 4% remaining - fast documentation needed

## Problem Statement

Anomaly chunks (text labels with date ranges and cost impacts) don't align perfectly with the visual peaks/troughs in the regression sparkline.

**Observable Issue**: Sep 8 chunk center doesn't align with Sep 8 sparkline peak position.

---

## Root Cause Analysis

### Current Implementation (as of commit 42df188)

**Chunk Positioning Logic** (`RentWidget.tsx:375-413`):
1. Find peak day within chunk (highest absolute `excess_pct`)
2. Calculate peak day's index in regression window
3. Position chunk CENTER at peak position: `peakPercent - (widthPercent / 2)`
4. Apply bounds checking to prevent cutoff

**Sparkline Generation** (`RentWidget.tsx:423-495`):
- Maps each regression data point to SVG coordinates
- Uses Catmull-Rom to Bezier smoothing with `tension = 0.3`
- X-coordinate: `(index / (totalDays - 1)) * 100`
- Y-coordinate: Dynamic scaling based on excess_pct range

### Why Misalignment Still Occurs

**Theory 1: Bezier Control Points Shift Visual Peak**
- Peak day has highest data value at exact position X
- Bezier smoothing creates control points based on neighboring points
- Visual peak appears shifted from data point due to curve interpolation
- **Evidence**: Tension adjustments (0.05 → 0.2 → 0.3) didn't fix alignment

**Theory 2: Peak Detection vs Visual Peak Divergence**
- Chunk centers on day with MAX excess_pct value
- Sparkline visual peak may occur between data points due to interpolation
- Multi-day chunks complicate this: which day is THE peak?

**Theory 3: Width-Based Offset Accumulation**
- Chunks have minimum 10% width for text visibility
- Centering formula may not account for width distortion
- Bounds clamping (preventing cutoff) shifts chunks from ideal position

**Theory 4: Regression Window vs Chunk Date Calculation**
- Regression window: 89-90 days from `regressionData[0].date`
- Chunk dates parsed separately from `anomalySummary.anomalous_days`
- Potential off-by-one or timezone issues in date calculations

---

## Investigation Steps (Priority Order)

### 1. Verify Data Point Alignment (Console Debugging)
**Add logging**:
```typescript
console.log('Peak alignment check:', {
  chunkDateRange: chunk.dateRange,
  peakDate: peakDay?.date,
  peakIndex: peakIndex,
  peakPercent: peakPercent.toFixed(2),
  actualSparklineX: ((peakIndex / (totalDays - 1)) * 100).toFixed(2)
})
```

**Check**: Does `peakPercent` match the expected sparkline X position for that day?

### 2. Visualize Peak Day Markers
**Add vertical lines at peak positions**:
```typescript
<line
  x1={peakPercent} y1="0"
  x2={peakPercent} y2="100"
  stroke="red"
  strokeWidth="0.5"
  opacity="0.5"
/>
```

**Outcome**: Visual confirmation of whether chunks center on correct X positions.

### 3. Compare Mathematical Peak vs Visual Peak
**Calculate Bezier curve maximum**:
- For each chunk, sample the Bezier curve at fine intervals
- Find Y-coordinate maximum within chunk's X range
- Compare to data point peak position

**Hypothesis**: If visual peak differs from data peak by >2%, Bezier is the culprit.

### 4. Test Linear Interpolation (No Smoothing)
**Temporary change**:
```typescript
// Replace Bezier with straight lines
path += ` L ${p2.x},${p2.y}`
```

**If alignment improves**: Smoothing is the issue → need different approach.
**If alignment stays poor**: Issue is in positioning logic, not smoothing.

---

## Potential Solutions

### Solution A: Calculate Visual Peak from Bezier Curve
**Complexity**: High
**Accuracy**: Best

1. For each chunk, extract Bezier segments within chunk's date range
2. Sample curve at fine intervals (100 points per segment)
3. Find Y-coordinate maximum → this is the VISUAL peak X position
4. Center chunk on visual peak instead of data peak

**Pros**: Perfectly aligns chunk with what user sees
**Cons**: Computationally expensive, complex math

### Solution B: Reduce Tension to Near-Zero
**Complexity**: Low
**Accuracy**: Medium

Set `tension = 0.05` or lower to minimize curve deviation from data points.

**Pros**: Simple one-line change
**Cons**: Sparkline looks less smooth, already tested with no success at 0.05

### Solution C: Offset Correction Factor
**Complexity**: Medium
**Accuracy**: Medium

Empirically measure average offset between data peaks and visual peaks for tension=0.3. Apply correction:
```typescript
const offsetCorrection = 1.5 // Adjust based on tension
const leftPercent = peakPercent - (widthPercent / 2) + offsetCorrection
```

**Pros**: Quick fix without major refactoring
**Cons**: Brittle, may not work for all peak shapes

### Solution D: Align to Chunk Midpoint (Abandon Peak Alignment)
**Complexity**: Low
**Accuracy**: Predictable

Position chunk based on its date range midpoint, ignore peak day:
```typescript
const midDate = new Date((chunk.startDate.getTime() + chunk.endDate.getTime()) / 2)
const midIndex = Math.round((midDate.getTime() - windowStart.getTime()) / (1000 * 60 * 60 * 24))
const leftPercent = ((midIndex / (totalDays - 1)) * 100) - (widthPercent / 2)
```

**Pros**: Simple, predictable, avoids Bezier complexity
**Cons**: May not align with visual peaks at all

---

## Recommended Approach

**Phase 1: Diagnose** (1-2 hours)
- Add debug logging (Step 1)
- Add visual peak markers (Step 2)
- Confirm whether Bezier is causing offset

**Phase 2: Quick Fix** (if Bezier confirmed as issue)
- Implement Solution C (offset correction factor)
- Test with multiple anomaly patterns
- Document empirical offset value

**Phase 3: Proper Fix** (if time permits)
- Implement Solution A (calculate visual peak from Bezier)
- Fallback to Solution D if too complex

---

## Open Questions

1. **Do we want perfect alignment** or is "close enough" acceptable?
2. **Multi-day chunks**: Should we align to peak day or midpoint?
3. **Bounds clamping**: Does preventing cutoff introduce more misalignment than it fixes?
4. **Alternative visualization**: Should chunks be full-height bars instead of centered labels?

---

## Files Involved

- `dashboard/src/components/RentWidget.tsx` (lines 156-545)
  - `AnomalySparklineBar` component
  - Chunk positioning: lines 375-413
  - Sparkline generation: lines 423-495

---

**Next Session TODO**: Run Phase 1 diagnostics, measure actual offset, decide on solution.

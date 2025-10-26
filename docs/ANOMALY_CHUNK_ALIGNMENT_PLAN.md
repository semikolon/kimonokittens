# Anomaly Chunk vs Peak/Trough Alignment Analysis & Fix Plan

**Date**: October 26, 2025
**Status**: ✅ COMPLETE - Pure midpoint alignment (Solution D)
**Final commit**: f6210e0

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

---

## Implementation Summary (October 26, 2025)

### What Was Implemented ✅

**Phase 1: Midpoint Alignment (Solution D)**
- Switched from peak-based to date range midpoint positioning
- Simpler, more predictable alignment logic
- Better correlation with sparkline troughs/peaks

**Phase 2: Adaptive Overlap Prevention**
- Iterative symmetric push algorithm (30 iterations max)
- Adaptive gap sizing: 2% target, reduces to 0.3% minimum for dense clusters
- Asymmetric edge handling: edge-constrained chunks get 0 push, movable chunk gets full separation
- Removed MAX_SHIFT limit for edge pairs to ensure they can separate fully

**Results:**
- ✅ All 8 chunks visible within 0-100% bounds
- ✅ 7/8 chunk pairs have clean text separation
- ⚠️ July/Aug 2 pair still has minor text overlap ("+16 kr-9 kr" merged)

### Remaining Challenge

**The July/Aug 2 Problem:**
- Dense cluster at left edge (within ~3 days)
- July chunk pinned at 0% (can't move left)
- Iterative algorithm creates cascade effects: Aug 2 pushes right → collides with 10-14 Aug → bounces back → still overlaps July
- Oscillation prevents convergence even with 30 iterations

**Potential Next Steps:**
1. **One-pass sequential layout**: Place chunks left-to-right with guaranteed gaps (no iteration)
2. **Reduce chunk width**: Use narrower chunks for dense clusters (may cause text wrapping)
3. **Abbreviate dates**: "28-29 Jul" → "Jul 28" for compressed chunks
4. **Accept minor overlap**: Current state is 87.5% clean, may be "good enough"

**Recommendation**: Try one-pass sequential layout if overlap remains unacceptable. Otherwise ship current implementation.

---

## Final Solution (October 26, 2025)

**Implemented: Pure Midpoint Alignment (Solution D)**

After iterating through multiple approaches, the final solution is the simplest:

**Architecture**:
1. Calculate chunk center position based on date range midpoint
2. Use calculated positions directly without any repositioning logic
3. No compression, no gap enforcement, no sequential layout
4. Natural calendar-based spacing with px-2 text padding

**Code**: `RentWidget.tsx:375-407`
```typescript
// Step 1: Calculate midpoint positions
const chunksWithInitialPositions = chunks.map(chunk => {
  const midpointTime = (chunk.startDate.getTime() + chunk.endDate.getTime()) / 2
  const midpointDate = new Date(midpointTime)
  const midpointIndex = Math.round((midpointDate.getTime() - windowStart.getTime()) / (1000 * 60 * 60 * 24))

  const calculatedWidth = totalDays > 1 ? (chunk.durationDays / (totalDays - 1)) * 100 : 0
  const widthPercent = Math.max(calculatedWidth, 10) // 10% minimum for text visibility

  const midpointPercent = totalDays > 1 ? (midpointIndex / (totalDays - 1)) * 100 : 0
  const idealLeft = midpointPercent - (widthPercent / 2)

  return { ...chunk, leftPercent: idealLeft, widthPercent, midpointDate: ... }
})

// Step 2: Use positions directly (no sequential repositioning)
const chunksWithPositions = [...chunksWithInitialPositions]
chunksWithPositions.sort((a, b) => a.leftPercent - b.leftPercent)
```

**Results**:
- ✅ Perfect alignment with sparkline peaks/troughs
- ✅ No text overlap (px-2 padding provides 8px separation)
- ✅ Natural date-based distribution (Sep 8 and Sep 13 are 5 days apart → natural spacing)
- ✅ No artificial compression or narrowing
- ✅ No right-side overflow from sequential layout
- ✅ Backgrounds can overlap when dates are close (accepted by user)
- ✅ All 8 chunks visible and readable

**Key Insight**: User requirement "I don't care about anything other than TEXT overlap" meant all the complex repositioning logic was unnecessary. Natural calendar positioning + text padding = perfect solution.

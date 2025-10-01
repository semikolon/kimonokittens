# ViewTransition Strategy: Side-by-Side Logic Comparison
## How ViewTransition Naturally Solves Our Animation Problems

**Date**: October 1, 2025
**Status**: Strategic Analysis
**Related**: `VIEWTRANSITION_LOGIC_PRESERVATION_AUDIT.md`, `REACT_VIEWTRANSITION_IMPLEMENTATION_PLAN.md`

---

## Executive Summary

**Question**: Can ViewTransition actually replace our existing logic, or just the animation wrappers?

**Finding**: ViewTransition can naturally solve MOST of our animation problems through its declarative approach. Many manual state machines become unnecessary.

**Key Insight**: Our current code is IMPERATIVE (we tell it when/how to animate). ViewTransition is DECLARATIVE (we describe what should exist, React figures out animations).

---

## Side-by-Side Comparison

### 1. **List Change Detection** (5-Minute Time Window)

#### Current Approach (Imperative)
```typescript
// Manual tracking of what was previously shown
const [prevFeasibleTrains, setPrevFeasibleTrains] = useState<TrainDeparture[]>([])

// Manual comparison
const currentIds = new Set(currentFeasibleTrains.map(generateTrainId))
const prevIds = new Set(prevFeasibleTrains.map(generateTrainId))
const potentiallyAdded = [...currentIds].filter(id => !prevIds.has(id))

// Filter out false positives (time updates vs genuinely new)
const genuinelyAdded = potentiallyAdded.filter(newTrainId => {
  const newTrain = currentFeasibleTrains.find(...)
  const isTimeUpdate = prevFeasibleTrains.some(prevTrain =>
    prevTrain.line_number === newTrain.line_number &&
    prevTrain.destination === newTrain.destination &&
    Math.abs(prevTrain.departure_timestamp - newTrain.departure_timestamp) <= 300
  )
  return !isTimeUpdate
})
```

**Lines of code**: ~35 (in `useTrainListChanges` hook)

**What we're manually tracking**:
- Previous list state
- Current list state
- Set operations (added, removed)
- Time-based filtering (5-min window)

---

#### ViewTransition Approach (Declarative)

```typescript
// Just generate stable IDs - ViewTransition handles the rest
const generateTrainId = (train: TrainDeparture): string =>
  `${train.departure_time}-${train.line_number}-${train.destination}`

// Render with stable keys
{feasibleTrains.map(train => (
  <ViewTransition key={generateTrainId(train)}>
    <TrainDepartureLine departure={train} />
  </ViewTransition>
))}
```

**Lines of code**: ~2 (just ID generation)

**What ViewTransition automatically does**:
- Tracks elements by `key` prop
- Detects when keys appear (enter animation)
- Detects when keys disappear (exit animation)
- Detects when keys move position (update animation)

---

#### The Magic: How 5-Minute Window Still Works

**The Problem**:
```
API updates every 30s:
T=0:   Train "20:42-41-Uppsala" (timestamp: 1759265720)
T=30s: Train "20:42-41-Uppsala" (timestamp: 1759265750)  ← +30s
```

**Current solution**: Compare timestamps, if within 5 min → same train

**ViewTransition solution**: Use stable ID that ignores timestamp updates!

```typescript
// CRITICAL: Use ORIGINAL departure time, not timestamp
const generateTrainId = (train: TrainDeparture): string =>
  `${train.departure_time}-${train.line_number}-${train.destination}`
  // "20:42-41-Uppsala" stays the same even when backend updates
```

**Why this works**:
- Backend sends `departure_time: "20:42"` (string, stable)
- Backend also sends `departure_timestamp: 1759265720` (int, changes)
- We use the STABLE string for identity
- ViewTransition sees same key → no animation (correct!)

**Example with delay announcement**:
```
T=0:   Train { departure_time: "20:42", summary_deviation_note: "" }
       ID: "20:42-41-Uppsala"

T=30s: Train { departure_time: "20:42", summary_deviation_note: "försenad 4 min" }
       ID: "20:42-41-Uppsala"  ← SAME KEY
       ViewTransition: No animation (just data update) ✅
```

---

#### Conclusion: Can ViewTransition Replace This?

**✅ YES!** The 5-minute window logic is ALREADY SOLVED by our ID generation strategy.

**What to KEEP**:
```typescript
const generateTrainId = (train: TrainDeparture): string =>
  `${train.departure_time}-${train.line_number}-${train.destination}`
```

**What to REMOVE**:
- `useTrainListChanges` hook (~35 lines)
- `useBusListChanges` hook (~35 lines)
- `prevFeasibleTrains` state
- `introducingItems` state
- Manual set operations and comparisons

**Savings**: ~70 lines of complex state management → 2 lines of ID generation

---

### 2. **Introduction Animations** (New Trains Sliding In)

#### Current Approach (Imperative)

```typescript
// Track what's being introduced
const [introducingItems, setIntroducingItems] = useState<Set<string>>(new Set())

// When new trains appear
useEffect(() => {
  if (added.length > 0) {
    setIntroducingItems(new Set(added))

    // Clean up after 5 seconds
    const timer = setTimeout(() => {
      setIntroducingItems(new Set())
    }, 5000)

    return () => clearTimeout(timer)
  }
}, [added])

// Apply CSS class manually
const isIntroducing = introducingItems.has(trainId)
<div className={isIntroducing ? 'introducing' : 'introduced'}>
```

**Lines of code**: ~20 (state + useEffect + cleanup)

**What we're manually managing**:
- State for which items are introducing
- Timer to remove state after animation
- CSS class application
- Cleanup of timers

---

#### ViewTransition Approach (Declarative)

```typescript
// Just render with ViewTransition wrapper
{feasibleTrains.map(train => (
  <ViewTransition key={generateTrainId(train)}>
    <TrainDepartureLine departure={train} />
  </ViewTransition>
))}
```

**CSS** (one-time definition):
```css
/* Automatically applied when new elements appear */
::view-transition-new(train-item) {
  animation: slideInFromBottom 0.5s cubic-bezier(0.25, 0.46, 0.45, 0.94);
}

@keyframes slideInFromBottom {
  from {
    opacity: 0;
    transform: translateY(20px);
  }
  to {
    opacity: 1;
    transform: translateY(0);
  }
}
```

**Lines of code**: 0 in component (just CSS once)

**What ViewTransition automatically does**:
- Detects new keys appearing
- Creates `::view-transition-new` pseudo-element
- Applies animation from CSS
- Cleans up when complete
- No manual timers needed

---

#### Conclusion: Can ViewTransition Replace This?

**✅ YES!** Completely. This is exactly what ViewTransition was designed for.

**What to REMOVE**:
- `introducingItems` state
- `useEffect` with timer
- Manual CSS class management
- All cleanup logic

**Savings**: ~20 lines → 0 lines (plus cleaner CSS)

---

### 3. **Departure Animations** (Trains Sliding Out)

#### Current Approach (Imperative)

```typescript
// Track what's departing
const [animatingItems, setAnimatingItems] = useState<Set<string>>(new Set())

// When trains disappear
useEffect(() => {
  if (removed.length > 0) {
    setAnimatingItems(new Set(removed))

    const timer = setTimeout(() => {
      setAnimatingItems(new Set())
    }, 400)

    return () => clearTimeout(timer)
  }
}, [removed])

// Keep item in DOM while animating
const isDeparting = animatingItems.has(trainId)
if (!isDeparting && trainNotInList) {
  return null  // Only remove after animation
}
```

**Lines of code**: ~25 (state + useEffect + conditional rendering)

**What we're manually managing**:
- State for which items are departing
- Keeping items in DOM during animation
- Timer to remove after animation
- Synchronization between list data and UI

**The Problem**: We have to render items that AREN'T in the data anymore!

---

#### ViewTransition Approach (Declarative)

```typescript
// Just stop rendering it - ViewTransition handles the exit
{feasibleTrains.map(train => (
  <ViewTransition key={generateTrainId(train)}>
    <TrainDepartureLine departure={train} />
  </ViewTransition>
))}
```

**CSS**:
```css
/* Automatically applied when elements disappear */
::view-transition-old(train-item) {
  animation: slideOutToTop 0.4s ease-in;
}

@keyframes slideOutToTop {
  from {
    opacity: 1;
    transform: translateY(0);
  }
  to {
    opacity: 0;
    transform: translateY(-20px);
  }
}
```

**What ViewTransition automatically does**:
- Captures snapshot of element before removal
- Keeps snapshot in DOM during animation
- Animates the snapshot
- Removes snapshot when complete
- **Magic**: Original element already gone from data!

---

#### Conclusion: Can ViewTransition Replace This?

**✅ YES!** This is the killer feature - exit animations without manual DOM management.

**What to REMOVE**:
- `animatingItems` state
- `useEffect` for departure tracking
- Conditional rendering logic
- Manual synchronization

**Savings**: ~25 lines → 0 lines

**Clarity gain**: We render ONLY what's in the data. No "ghost items" for animation.

---

### 4. **Departure Sequence State Machine** (Warning → Critical → Departing)

#### Current Approach (Imperative)

```typescript
type DepartureState = 'feasible' | 'warning' | 'critical' | 'departing' | 'departed'

const [trainStates, setTrainStates] = useState<Map<string, DepartureState>>(new Map())
const [warningTrains, setWarningTrains] = useState<Set<string>>(new Set())
const [criticalTrains, setCriticalTrains] = useState<Set<string>>(new Set())
const [departingTrains, setDepartingTrains] = useState<Set<string>>(new Set())

useEffect(() => {
  trains.forEach(train => {
    const minutesUntil = calculateAdjustedDeparture(train).adjustedMinutesUntil

    if (minutesUntil < 6) {
      // Phase 1: Warning (orange glow) - 4 seconds
      setTrainStates(prev => new Map(prev).set(trainId, 'warning'))
      setWarningTrains(prev => new Set([...prev, trainId]))

      setTimeout(() => {
        // Phase 2: Critical (red glow) - 3 seconds
        setTrainStates(prev => new Map(prev).set(trainId, 'critical'))
        setWarningTrains(prev => { newSet.delete(trainId); return newSet })
        setCriticalTrains(prev => new Set([...prev, trainId]))

        setTimeout(() => {
          // Phase 3: Departing (fade out) - 2 seconds
          setDepartingTrains(prev => new Set([...prev, trainId]))

          setTimeout(() => {
            // Cleanup
          }, 2000)
        }, 3000)
      }, 4000)
    }
  })
}, [trains])
```

**Lines of code**: ~85 (complex state machine with nested timeouts)

**What we're manually managing**:
- 4 separate state variables
- Nested setTimeout chains
- Manual cleanup
- State transitions
- Preventing re-triggering

**The complexity**: This is a 9-second choreographed sequence.

---

#### ViewTransition Approach (Declarative)

**Key Insight**: This is TWO separate concerns!

**Concern 1: Glow Effects** (warning, critical)
- These are **NOT animations** - they're pulsing visual effects
- Triggered by TIME, not list changes
- ViewTransition doesn't help here

**Concern 2: Exit Animation** (departing → departed)
- This IS an animation (fade out)
- ViewTransition handles this automatically

**Split the logic**:

```typescript
// KEEP: Glow effect state machine
type GlowState = 'none' | 'warning' | 'critical'
const [glowStates, setGlowStates] = useState<Map<string, GlowState>>(new Map())

useEffect(() => {
  trains.forEach(train => {
    const minutesUntil = calculateAdjustedDeparture(train).adjustedMinutesUntil

    if (minutesUntil < 6 && minutesUntil >= 0) {
      // Start warning glow (4s)
      setGlowStates(prev => new Map(prev).set(trainId, 'warning'))

      setTimeout(() => {
        // Transition to critical glow (3s)
        setGlowStates(prev => new Map(prev).set(trainId, 'critical'))

        setTimeout(() => {
          // Stop glow - train becomes infeasible
          // ViewTransition will handle exit animation automatically!
          setGlowStates(prev => {
            const newMap = new Map(prev)
            newMap.delete(trainId)
            return newMap
          })
        }, 3000)
      }, 4000)
    }
  })
}, [trains])

// REMOVE: `departing` state - ViewTransition handles this!
```

**Feasibility filter** (determines when train exits list):
```typescript
// Before: Include warning, critical, AND departing
const feasibleTrains = trains.filter(train => {
  const adjusted = calculateAdjustedDeparture(train)
  const glowState = glowStates.get(generateTrainId(train))

  return adjusted.adjustedMinutesUntil >= 0 && (
    isFeasibleTrainDeparture(adjusted.adjustedMinutesUntil) ||  // 5+ min
    glowState === 'warning' ||  // Orange glow
    glowState === 'critical'    // Red glow
    // REMOVED: glowState === 'departing' - ViewTransition handles exit!
  )
})

// After 7 seconds (4s warning + 3s critical), train removed from list
// → ViewTransition automatically applies exit animation
```

---

#### Comparison

**Before** (Imperative):
- 4 state variables
- Manual "departing" phase with timeout
- Keep train in list during exit animation
- 9-second total sequence (4s + 3s + 2s)

**After** (Declarative):
- 1 state variable (`glowStates`)
- ViewTransition handles exit automatically
- Remove train from list after 7s (4s + 3s)
- ViewTransition adds ~300-500ms exit animation
- 7.5-second total sequence (simpler!)

**Lines of code**: ~85 → ~45 lines

---

#### Conclusion: Can ViewTransition Replace This?

**⚠️ PARTIALLY**

**What to KEEP**:
- Warning/critical glow state machine (these are CSS effects, not animations)
- Timeout chains for glow transitions
- Glow state in feasibility filter

**What to REMOVE**:
- `departing` state
- `departingTrains` set
- Third timeout (2s departing phase)
- Manual exit animation logic

**Savings**: ~40 lines

**Simplification**: 4 states → 1 state, clearer separation of concerns

---

### 5. **Staggered Entry** (Items Appear Sequentially)

#### Current Approach (Imperative)

```typescript
// Add index as CSS variable
<div
  className="train-departure-item introducing"
  style={{ '--item-index': index } as React.CSSProperties}
>
```

**CSS**:
```css
.introducing {
  animation: slideInFromBottom 5s ease-out;
  animation-delay: calc(var(--item-index) * 0.1s);  /* Stagger by 100ms */
}
```

**Lines of code**: ~2 (style prop)

---

#### ViewTransition Approach (Declarative)

**Same approach!** This works perfectly with ViewTransition:

```typescript
// Still add index as CSS variable
<ViewTransition
  key={trainId}
  style={{ '--item-index': index } as React.CSSProperties}
>
  <TrainDepartureLine departure={train} />
</ViewTransition>
```

**CSS** (ViewTransition version):
```css
::view-transition-new(train-item) {
  animation: slideInFromBottom 0.5s cubic-bezier(0.25, 0.46, 0.45, 0.94);
  animation-delay: calc(var(--item-index) * 0.1s);  /* Same stagger! */
}
```

---

#### Conclusion: Can ViewTransition Replace This?

**✅ YES!** No changes needed - `--item-index` works with ViewTransition.

**What to KEEP**: Everything (just move to ViewTransition CSS)

**Savings**: 0 lines (pattern stays the same)

---

### 6. **Feasibility Filtering** (When to Show Trains)

#### Current Approach

```typescript
// Frontend threshold: 6 minutes
const RUN_TIME_FRONTEND = 6  // More conservative than backend

const isFeasibleTrainDeparture = (minutesUntil: number): boolean => {
  return minutesUntil >= RUN_TIME_FRONTEND
}

// Include trains in grace period (warning/critical/departing states)
const feasibleTrains = trains.filter(train => {
  const adjusted = calculateAdjustedDeparture(train)
  const departureState = trainStates.get(trainId)

  return adjusted.adjustedMinutesUntil >= 0 && (
    isFeasibleTrainDeparture(adjusted.adjustedMinutesUntil) ||
    ['warning', 'critical', 'departing'].includes(departureState)
  )
})
```

**Issue identified**: Frontend uses 6 min, backend uses 5 min (RUN_TIME)

**User's correction**: "Backend is more correct - you CAN catch a train in 5 min by biking"

---

#### ViewTransition Approach (With Fix)

```typescript
// FIXED: Match backend's more realistic threshold
const RUN_TIME = 5  // Can bike/run to station in 5 min

const isFeasibleTrainDeparture = (minutesUntil: number): boolean => {
  return minutesUntil >= RUN_TIME  // Changed from 6 to 5
}

// Simplified: Remove `departing` state (ViewTransition handles)
const feasibleTrains = trains.filter(train => {
  const adjusted = calculateAdjustedDeparture(train)
  const glowState = glowStates.get(trainId)  // Changed from trainStates

  return adjusted.adjustedMinutesUntil >= 0 && (
    isFeasibleTrainDeparture(adjusted.adjustedMinutesUntil) ||  // 5+ min
    glowState === 'warning' ||   // Orange glow (4s)
    glowState === 'critical'     // Red glow (3s)
    // REMOVED: departing state - ViewTransition handles exit
  )
})
```

**Timeline**:
```
10 min: Feasible (shown normally)
6 min:  Feasible (shown normally)
5 min:  Still feasible (bike/run) ← CHANGED from 6
4:59:   Enter warning state → orange glow starts (4s)
4:55:   Still warning
...
0:59:   Enter critical state → red glow starts (3s)
0:56:   Still critical
...
0:53:   Glow ends, train becomes infeasible
        → Removed from list
        → ViewTransition exit animation (~300-500ms)
0:52:   Fully gone from UI
```

---

#### Conclusion: Can ViewTransition Replace This?

**✅ YES!** Plus we can simplify it.

**What to CHANGE**:
- Threshold: 6 min → 5 min (match backend's RUN_TIME)
- Remove `departing` from filter (ViewTransition handles)
- Use `glowStates` instead of `trainStates`

**What to KEEP**:
- Grace period concept (warning/critical in filter)
- Adjusted time calculation
- Business logic for when to show

**Savings**: ~5 lines (simpler logic)

---

### 7. **Urgent/Critical Flashing** (Buses)

#### Current Approach

```typescript
const [urgentFlashingBuses, setUrgentFlashingBuses] = useState<Set<string>>(new Set())
const [criticalFlashingBuses, setCriticalFlashingBuses] = useState<Set<string>>(new Set())

useEffect(() => {
  buses.forEach(bus => {
    if (bus.minutes_until === 2 && !alreadyFlashed.has(busId + '-urgent')) {
      setUrgentFlashingBuses(prev => new Set([...prev, busId]))
      setTimeout(() => setUrgentFlashingBuses(prev => {
        const newSet = new Set(prev)
        newSet.delete(busId)
        return newSet
      }), 10000)  // Flash for 10s
    }

    if (bus.minutes_until === 1 && !alreadyFlashed.has(busId + '-critical')) {
      setCriticalFlashingBuses(prev => new Set([...prev, busId]))
      setTimeout(() => setCriticalFlashingBuses(prev => {
        const newSet = new Set(prev)
        newSet.delete(busId)
        return newSet
      }), 4000)  // Flash for 4s
    }
  })
}, [buses])
```

**What this does**: Pulsing glow when bus is 2 min or 1 min away

---

#### ViewTransition Approach

**Key Insight**: This is **NOT an animation** - it's a time-triggered CSS effect!

**ViewTransition has ZERO impact on this logic.**

**Reasoning**:
- Triggered by time threshold (2 min, 1 min)
- Not triggered by list changes
- Pulsing glow effect (keyframe animation on the element)
- Independent of entry/exit animations

---

#### Conclusion: Can ViewTransition Replace This?

**❌ NO.** This is orthogonal to ViewTransition.

**What to KEEP**: Everything unchanged

**Savings**: 0 lines (no change)

---

## Summary Table: What ViewTransition Replaces

| Feature | Current Lines | ViewT Lines | Can Replace? | Savings |
|---------|--------------|-------------|--------------|---------|
| **List change detection** | ~35 | ~2 | ✅ YES | 33 lines |
| **Introduction animations** | ~20 | 0 | ✅ YES | 20 lines |
| **Departure animations** | ~25 | 0 | ✅ YES | 25 lines |
| **Departure sequence** | ~85 | ~45 | ⚠️ PARTIAL | 40 lines |
| **Staggered entry** | ~2 | ~2 | ✅ YES | 0 lines |
| **Feasibility filtering** | ~15 | ~10 | ⚠️ SIMPLIFY | 5 lines |
| **Urgent/critical flashing** | ~40 | ~40 | ❌ NO | 0 lines |
| **Delay calculation** | ~100 | ~100 | ❌ NO | 0 lines |
| **Identity generation** | ~2 | ~2 | ❌ NO (needed!) | 0 lines |
| **Display formatting** | ~50 | ~50 | ❌ NO | 0 lines |

**Total**: ~374 lines → ~251 lines = **-123 lines (-33%)**

**Revised estimate**: More savings than initial 5% estimate, but not the 83% from naive estimate.

---

## Key Insights: Imperative vs Declarative

### The Old Way (Imperative)
```typescript
// We tell React WHEN and HOW to animate
"When this train appears, add it to introducingItems set,
 wait 5 seconds, then remove it from the set"

"When this train disappears, add it to animatingItems set,
 keep rendering it even though it's not in data,
 wait 400ms, then stop rendering it"

"Track previous list, compare with current list,
 figure out what changed, trigger animations manually"
```

**Result**:
- Lots of state management
- Manual synchronization
- Timeout management
- Edge case handling

---

### The New Way (Declarative)
```typescript
// We tell React WHAT should exist
"Here are the trains that should be shown right now.
 Figure out the animations yourself."

feasibleTrains.map(train => (
  <ViewTransition key={generateTrainId(train)}>
    <TrainDepartureLine departure={train} />
  </ViewTransition>
))
```

**Result**:
- React compares keys
- Detects additions/removals/moves
- Applies CSS animations
- Cleans up automatically

---

## The Critical Realization

**What ViewTransition CAN'T replace**: Business logic

**Examples**:
- Delay calculation (time arithmetic)
- Feasibility rules (5-min threshold)
- Glow triggers (warning at 5:59, critical at 0:59)
- Identity generation (stable keys)
- Data normalization (merge deviations)

**What ViewTransition CAN replace**: Animation coordination

**Examples**:
- Tracking which items are introducing
- Keeping items in DOM during exit
- Manual setTimeout chains for animations
- List comparison for change detection

---

## Feasibility Threshold Fix

### Current (Incorrect)

```typescript
// Frontend
const isFeasibleTrainDeparture = (minutesUntil: number): boolean => {
  return minutesUntil >= 6  // Need at least 6 minutes
}

// Backend
RUN_TIME = 5  # Minutes to cycle or run to the station
departures.select { |d| d[:minutes_until_departure] > RUN_TIME }
```

**Problem**:
- Backend allows 5 min (realistic - can bike)
- Frontend requires 6 min (too conservative)
- Result: Trains sent by backend aren't shown by frontend

---

### Fixed (Aligned)

```typescript
// Frontend - MATCH backend
const RUN_TIME = 5  // Can bike/run to station in 5 min

const isFeasibleTrainDeparture = (minutesUntil: number): boolean => {
  return minutesUntil >= RUN_TIME  // Changed from 6 to 5
}

// Backend - unchanged
RUN_TIME = 5  # Consistent!
```

**Result**: Frontend and backend now agree on what's feasible

**New timeline**:
```
Before:
6:00 → Feasible (shown)
5:59 → Infeasible (hidden) ← Too early!

After:
5:00 → Feasible (shown)
4:59 → Enter warning state (orange glow)
0:59 → Enter critical state (red glow)
0:53 → Removed (ViewTransition exit)
```

---

## Proposed Refactor Strategy (Revised)

### Phase 1: Fix Threshold + Prove ViewTransition Works

**Changes**:
1. Fix feasibility threshold (6 → 5 min)
2. Install React experimental
3. Add `useDeferredValue(trainData)`
4. Wrap items in `<ViewTransition>`
5. **KEEP** old animations (both systems)

**Goal**: Prove ViewTransition handles all cases

---

### Phase 2: Remove Animation State

**Remove**:
- `useTrainListChanges` / `useBusListChanges` hooks
- `introducingItems` state
- `animatingItems` state
- `departingTrains` state

**Simplify**:
- `useDepartureSequence` → `useGlowEffects`
  - Remove `departing` state
  - Keep `warning` / `critical` states

---

### Phase 3: Clean Up CSS

**Remove**:
```css
.introducing { ... }
.departing { ... }
@keyframes slideInFromBottom { ... }
@keyframes slideOutToTop { ... }
```

**Add**:
```css
::view-transition-new(train-item) { ... }
::view-transition-old(train-item) { ... }
```

**Keep**:
```css
.warning-glow { ... }
.critical-glow { ... }
```

---

## Final Recommendation

**✅ Proceed with ViewTransition migration**

**Key changes from original plan**:
1. **Bigger savings**: ~33% code reduction (not 5%, not 83%)
2. **Feasibility fix**: Change threshold from 6 → 5 min
3. **Clearer separation**: Glows (time-based) vs Animations (list-based)
4. **Simpler state**: 1 state map instead of 4

**What stays the same**:
- Delay calculation (just fixed Sep 30!)
- Identity generation (critical for ViewTransition!)
- Urgent/critical flashing (orthogonal to ViewTransition)
- All business logic

**Risk level**: ✅ LOW (ViewTransition is a natural fit)

---

**Last Updated**: October 1, 2025
**Status**: Ready for Implementation

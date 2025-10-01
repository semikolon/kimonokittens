# ViewTransition Refactor: Critical Logic Preservation Audit
## Ensuring No Valuable Code is Lost

**Date**: October 1, 2025
**Status**: Pre-Implementation Analysis
**Related**: `REACT_VIEWTRANSITION_IMPLEMENTATION_PLAN.md`, `TrainWidget.tsx`

---

## Executive Summary

**Purpose**: Audit ALL logic in current `TrainWidget.tsx` before React ViewTransition migration to ensure no functionality is lost.

**Approach**: Two-phase analysis
1. **Identify ALL logic components** - what each piece does
2. **Classify by fate** - keep, transform, or safely remove

**Key Finding**: ViewTransition replacement is **ONLY** safe for animation wrappers. Much critical logic must be preserved!

---

## Current Code Inventory (873 lines)

### 1. **Type Definitions** (Lines 5-36)
**What it does**: TypeScript interfaces for all data structures

```typescript
interface TrainDeparture { ... }
interface BusDeparture { ... }
interface Deviation { ... }
interface StructuredTransportData { ... }
interface DelayInfo { ... }
interface AdjustedDeparture { ... }
```

**Reason for existence**: Type safety, IDE autocomplete, catches bugs at compile time

**Fate**: ✅ **KEEP UNCHANGED** - ViewTransition doesn't affect types

---

### 2. **Delay Parsing Logic** (Lines 53-149)

#### A. `parseDelayInfo()` - Lines 53-85
**What it does**: Extracts delay information from Swedish text

```typescript
parseDelayInfo("försenad 4 min")
// → { isDelayed: true, delayMinutes: 4, originalNote: "försenad 4 min" }
```

**Critical features**:
- Defensive null/undefined handling
- Regex extraction of minutes: `/försenad (\d+) min/`
- Handles both "försenad X min" AND just "försenad"
- Falls back gracefully when no delay found

**Reason for existence**:
- **Bug fix from Sep 30**: Backend sends "Försenad 4 min", we need to extract "4"
- **User experience**: Shows delay inline with departure time

**Fate**: ✅ **KEEP UNCHANGED** - Core business logic, not related to animations

---

#### B. `mergeDelayInfoIntoTrains()` - Lines 88-115
**What it does**: Merges delay data from separate `deviations` array into train objects

```typescript
// Backend sends:
trains: [{ departure_time: "20:42", summary_deviation_note: "" }]
deviations: [{ time: "20:42", reason: "försenad 4 min" }]

// After merge:
trains: [{ departure_time: "20:42", summary_deviation_note: "försenad 4 min" }]
```

**Reason for existence**:
- Backend sometimes puts delay info in `deviations` instead of train object
- **Data normalization** - ensures delay info is always in the same place

**Fate**: ✅ **KEEP UNCHANGED** - Data transformation, not animation

---

#### C. `calculateAdjustedDeparture()` - Lines 117-149
**What it does**: Calculates **actual** departure time accounting for delays

```typescript
// Original: 20:42 + 4 min delay = Actual: 20:46
// "om 8m" becomes "om 12m" when delayed
```

**Critical features**:
- Time parsing and arithmetic
- Handles non-delayed trains (passthrough)
- Returns both original and adjusted times
- Recalculates `minutes_until` based on current time

**Reason for existence**:
- **User experience**: Show accurate "om X minuter" when train is delayed
- **Cost optimization**: Prevents rushing for a train that's actually later

**Fate**: ✅ **KEEP UNCHANGED** - Core business logic for delay handling

---

#### D. `formatDelayAwareTimeDisplay()` - Lines 151-167
**What it does**: Formats time string with delay info inline

```typescript
// Non-delayed: "20:42 - om 8m"
// Delayed:     "20:46 - om 12m (4m sen)"  ← NEW from Sep 30 fix
// Urgent:      "20:42 - spring!"
```

**Reason for existence**:
- **Sep 30 bug fix**: Never show "(0m sen)" without valid delay
- **User experience**: Single glance shows both actual time and delay

**Fate**: ✅ **KEEP UNCHANGED** - Critical display logic, just fixed!

---

### 3. **Identity Tracking** (Lines 170-174)

```typescript
const generateTrainId = (train: TrainDeparture): string =>
  `${train.departure_time}-${train.line_number}-${train.destination}`

const generateBusId = (bus: BusDeparture): string =>
  `${bus.departure_time}-${bus.line_number}-${bus.destination}`
```

**What it does**: Creates stable, unique IDs for React keys and animation tracking

**Critical design decision**:
- Uses **original** departure time (not adjusted-if-late time)
- **Why**: Delayed trains maintain identity across updates
- **Result**: No unnecessary animations when delay info updates

**Example**:
```
Train at 20:42 to Uppsala
→ Delay announced: still same train, don't animate
→ Uses original time "20:42" for identity, not adjusted "20:46"
```

**Fate**: ✅ **KEEP UNCHANGED**
- **CRITICAL for ViewTransition**: These become React `key` props
- ViewTransition relies on stable keys to track element movement

---

### 4. **List Change Detection Hooks** (Lines 176-247)

#### A. `useTrainListChanges()` - Lines 178-211
**What it does**: Detects when trains **genuinely** enter/leave the feasible list

**Complex logic**:
```typescript
// NOT just: currentIds !== prevIds
// Because every 30s the API updates timestamps → false "new" trains

// Solution: 5-minute time window
const isTimeUpdate = prevFeasibleTrains.some(prevTrain =>
  prevTrain.line_number === newTrain.line_number &&
  prevTrain.destination === newTrain.destination &&
  Math.abs(prevTrain.departure_timestamp - newTrain.departure_timestamp) <= 300
)
```

**Why this is critical**:
- **Problem**: API updates every 30s with new timestamps
- **Naive approach**: Every update triggers "new train" animation
- **Solution**: 5-min window distinguishes updates from genuinely new trains

**Example timeline**:
```
22:00 - Train at 22:15 appears → ANIMATE (genuinely new)
22:30 - Same train, API updates timestamp 22:15:30 → NO ANIMATE (time update)
22:45 - Train at 23:00 appears → ANIMATE (genuinely new)
```

**Reason for existence**:
- **User experience**: Animations only for meaningful changes
- **Performance**: Avoid 30-second animation spam

**Fate**: 🔄 **TRANSFORM**
- **Logic must be preserved** - 5-minute window is critical
- **Method changes** - ViewTransition doesn't need `introducing`/`departing` state
- **Keep**: Time window logic, genuine change detection
- **Remove**: State management for animation classes

---

#### B. `useBusListChanges()` - Lines 215-247
**What it does**: Same as trains but for buses

**Fate**: 🔄 **TRANSFORM** - Same reasoning as trains

---

### 5. **Urgent Departure Detection** (Lines 250-402)

#### A. Train Urgency - Lines 250-261
**What it does**: Determines when to flash orange/red warnings

```typescript
const isUrgentDeparture = (train: TrainDeparture): boolean => {
  // Flash when 9-10 minutes left (2 minutes before "spring eller cykla")
  return train.minutes_until >= 9 && train.minutes_until <= 10 && train.can_walk
}

const isCriticalDeparture = (train: TrainDeparture): boolean => {
  // Flash when train shows "spring eller cykla" (too late to walk)
  return !train.can_walk && train.suffix.includes('spring')
}
```

**Reason for existence**:
- **User experience**: Visual alert before it's too late
- **Cost optimization**: 9-10min = last window to comfortably walk
- **UX research**: Two-tier warning (orange → red-orange)

**Fate**: ✅ **KEEP UNCHANGED** - Business logic, not animation timing

---

#### B. `useDepartureSequence()` - Lines 263-347
**What it does**: Multi-phase departure animation with glow effects

**Complex state machine**:
```
feasible (6+ min)
    ↓ (< 6 min)
warning (orange glow, 4s)
    ↓
critical (red-orange glow, 3s)
    ↓
departing (fade out, 2s)
    ↓
departed (removed)
```

**Critical features**:
- **Timing orchestration**: 4s → 3s → 2s sequence
- **State tracking**: Map<trainId, DepartureState>
- **Cleanup**: Removes states for departed trains
- **Deduplication**: `processedTransitions` prevents re-triggering

**Reason for existence**:
- **User experience**: Smooth, multi-phase warning before train becomes infeasible
- **Prevents abrupt removal**: 9-second graceful exit sequence

**Fate**: 🔄 **PARTIALLY TRANSFORM**
- **KEEP**:
  - State machine logic (feasible → warning → critical → departing)
  - Timing constants (4s, 3s, 2s)
  - Glow effect triggers
- **CHANGE**:
  - Remove manual `departing` state (ViewTransition handles exit)
  - Keep `warning` and `critical` glows (these are CSS effects, not animations)

**CRITICAL**: This is **NOT** just animation - it's a **warning system** with visual feedback!

---

#### C. `useUrgentBusFlashing()` - Lines 360-402
**What it does**: Urgent/critical flashing for buses (simpler than trains)

```typescript
// Urgent: 2 minutes left → flash orange for 10s
// Critical: 1 minute left → flash red-orange for 4s
```

**Fate**: ✅ **KEEP UNCHANGED** - Visual alert system, not list animations

---

### 6. **Visual Styling Helpers** (Lines 405-428)

#### A. `getTimeOpacity()` - Lines 405-413
**What it does**: Fades far-future trains progressively

```typescript
0-20m   → opacity 1.0 (fully visible)
20-50m  → smooth gradient fade
50m+    → opacity 0.15 (very faded)
```

**Reason for existence**:
- **Visual hierarchy**: Focus on imminent departures
- **UX research**: Smooth fade is less jarring than hard cutoffs

**Fate**: ✅ **KEEP UNCHANGED** - Display logic, not animation

---

#### B. `isFeasibleTrainDeparture()` / `isFeasibleBusDeparture()` - Lines 415-428
**What it does**: Business rules for when to show/hide departures

```typescript
// Trains: Need 6+ minutes (walk time + margin)
// Buses: Show until departure (bus stop is 1min away)
```

**Reason for existence**:
- **Cost optimization**: Don't show impossible-to-catch trains
- **User experience**: Different thresholds reflect physical distance

**Fate**: ✅ **KEEP UNCHANGED** - Core business logic

---

### 7. **Animation Wrapper Components** (Lines 431-574)

#### A. `AnimatedTrainList` - Lines 431-507
**What it does**:
- Wraps train list to detect additions/removals
- Manages `introducing` and `departing` CSS classes
- Adds `--item-index` CSS var for stagger

**Current features**:
```typescript
- Introduction animation: 5s slide-in
- Departure animation: 400ms slide-out
- Staggered entry: --item-index for delay
- Glow effects: warning/critical classes
```

**Fate**: ❌ **REMOVE & REPLACE**
- **Remove**: Introduction/departure state management
- **Replace**: ViewTransition wraps each item
- **Keep elsewhere**: Glow effects (move to parent or item component)

---

#### B. `AnimatedBusList` - Lines 510-574
**What it does**: Same as trains but for buses

**Fate**: ❌ **REMOVE & REPLACE** - Same reasoning

---

### 8. **Display Formatting** (Lines 577-646)

#### A. `formatTimeDisplay()` - Lines 577-587
**What it does**: Basic time formatting (without delay handling)

```typescript
// 0 min: "20:42 - spring!"
// 1-59 min: "20:42 - om 8m"
// 60+ min: "20:42"
```

**Fate**: ✅ **KEEP UNCHANGED** - Used by buses (which don't have delays)

---

#### B. `TrainDepartureLine` - Lines 590-619
**What it does**: Renders single train line with all visual logic

**Critical features**:
- Delay-aware time display (uses `formatDelayAwareTimeDisplay`)
- Opacity fading (uses `getTimeOpacity`)
- Glow effects (urgent/critical flashing)
- Filters out delay note from suffix (prevents duplication)

**Fate**: ✅ **KEEP UNCHANGED** - Just needs ViewTransition wrapper

---

#### C. `BusDepartureLine` - Lines 622-646
**What it does**: Renders single bus line

**Fate**: ✅ **KEEP UNCHANGED** - Just needs ViewTransition wrapper

---

### 9. **Deviation Filtering** (Lines 649-693)

#### A. `filterNonDelayDeviations()` - Lines 649-663
**What it does**: Prevents showing delays twice (inline + störningar box)

**Logic**:
```typescript
// If delay is shown inline (e.g., "20:46 - om 12m (4m sen)")
// → Don't also show in "Störningar" box
// → Keeps UI clean, avoids redundancy
```

**Reason for existence**:
- **UX polish**: After Sep 30 fix, delays are inline
- **Prevents**: "20:46 (4m sen)" PLUS "20:42: försenad 4 min" redundancy

**Fate**: ✅ **KEEP UNCHANGED** - Data transformation logic

---

#### B. `DeviationAlerts` - Lines 666-693
**What it does**: Renders yellow alert box for non-delay deviations

**Features**:
- Groups by reason (cleaner display)
- Removes "läs mer" footer text
- Yellow background styling

**Fate**: ✅ **KEEP UNCHANGED** - Separate component, no animation

---

### 10. **Main Component** (Lines 695-873)

#### A. Hook Ordering & Rules of Hooks - Lines 708-736
**What it does**: Ensures all hooks called in same order every render

**Critical pattern**:
```typescript
// IMPORTANT: All hooks must be called before any conditional returns
const trainsForHooks = structuredData ? ... : []
const feasibleTrainsForHooks = trainsForHooks.filter(...)

// Call all hooks with safe data (React Hooks Rules)
const { trainStates, ... } = useDepartureSequence(feasibleTrainsForHooks)
const { urgentFlashingBuses, ... } = useUrgentBusFlashing(feasibleBusesForHooks)

// Now we can do conditional returns after all hooks are called
if (!trainData || !isStructuredData) { return ... }
```

**Reason for existence**:
- **React requirement**: Hooks must be called unconditionally
- **Bug prevention**: Conditional hooks cause "Rendered more/fewer hooks" errors

**Fate**: ✅ **KEEP PATTERN** - React Hooks rules don't change with ViewTransition

---

#### B. Feasibility Filtering - Lines 716-732
**What it does**: Complex filtering for which trains to show

```typescript
// Include trains that are:
// 1. Feasible (6+ min) OR
// 2. In departure sequence (warning/critical/departing states)
//
// Exclude: Fully departed trains
```

**Reason for existence**:
- **9-second grace period**: Trains in departure sequence stay visible
- **Smooth UX**: No abrupt removal at 6-minute mark

**Fate**: ✅ **KEEP UNCHANGED** - Business logic for what to render

---

#### C. Debug Logging - Lines 757-763
**What it does**: Console logs for bus data debugging

**Fate**: ⚠️ **OPTIONAL REMOVE** - Development aid, not production logic

---

#### D. Deviation Feasibility - Lines 766-791
**What it does**: Filters deviations to only show feasible ones (accounting for delays)

**Complex logic**:
```typescript
// For delayed trains:
// - Parse original time: "20:42"
// - Add delay: 4 min → "20:46"
// - Calculate minutes until ADJUSTED time
// - Only show if adjusted time is still feasible (6+ min)
```

**Reason for existence**:
- **Prevents**: Showing alerts for trains that are feasible only because of delay
- **Example**: Train at 20:42 delayed 10 min → Actually 20:52 → Still show if currently 20:43

**Fate**: ✅ **KEEP UNCHANGED** - Critical business logic

---

#### E. Render Logic - Lines 793-873
**What it does**: Two-column layout (trains | buses)

**Structure**:
```typescript
<DeviationAlerts />
<AnimatedTrainList>
  {trains.map(train =>
    <TrainDepartureLine />
  )}
</AnimatedTrainList>
```

**Fate**: 🔄 **TRANSFORM**
- **Remove**: AnimatedTrainList/AnimatedBusList wrappers
- **Add**: ViewTransition wrapper per item
- **Keep**: Everything else (layout, DeviationAlerts, empty states)

---

### 11. **Helper Function** (Lines 861-872)

```typescript
function getMinutesUntilFromTime(timeStr: string): number {
  // Handles tomorrow wrapping: if "01:00" and current time is "23:00" → tomorrow
}
```

**Fate**: ✅ **KEEP UNCHANGED** - Used by deviation filtering

---

## Refactor Strategy: What to Keep vs Remove

### ✅ KEEP UNCHANGED (80% of code - ~700 lines)

**Types & Interfaces**:
- All TypeScript interfaces (lines 5-36)

**Delay Handling** (CRITICAL - just fixed Sep 30):
- `parseDelayInfo()` - regex extraction of delay minutes
- `mergeDelayInfoIntoTrains()` - data normalization
- `calculateAdjustedDeparture()` - time arithmetic for delays
- `formatDelayAwareTimeDisplay()` - never show "(0m sen)" without valid delay

**Identity Tracking** (CRITICAL for ViewTransition):
- `generateTrainId()` / `generateBusId()` - stable IDs using original times

**Urgency Detection**:
- `isUrgentDeparture()` / `isCriticalDeparture()` - when to flash warnings
- `isUrgentBusDeparture()` / `isCriticalBusDeparture()` - bus warnings
- `useUrgentBusFlashing()` - bus flash timing

**Visual Logic**:
- `getTimeOpacity()` - progressive fading
- `isFeasibleTrainDeparture()` / `isFeasibleBusDeparture()` - business rules

**Display Components**:
- `formatTimeDisplay()` - basic formatting
- `TrainDepartureLine` - individual train rendering
- `BusDepartureLine` - individual bus rendering
- `filterNonDelayDeviations()` - prevent duplication
- `DeviationAlerts` - störningar box

**Business Logic**:
- Feasibility filtering (lines 716-732)
- Deviation feasibility with delay accounting (lines 766-791)
- Hook ordering pattern (lines 708-736)
- `getMinutesUntilFromTime()` - tomorrow wrapping

---

### 🔄 TRANSFORM (15% of code - ~130 lines)

**List Change Detection**:
- `useTrainListChanges()` - **KEEP 5-minute window logic**
  - Remove: `introducing`/`departing` state management
  - Keep: Genuine change detection vs time updates

- `useBusListChanges()` - Same transformation

**Departure Sequence**:
- `useDepartureSequence()` - **KEEP state machine & glow effects**
  - Keep: `feasible → warning → critical` states for glow
  - Keep: Timing (4s, 3s)
  - Remove: `departing` state (ViewTransition handles exit)

**Render Logic**:
- Main component (lines 793-873) - **KEEP layout & structure**
  - Remove: `AnimatedTrainList`/`AnimatedBusList` wrappers
  - Add: `<ViewTransition key={id}>` per item
  - Keep: Two-column grid, headers, empty states

---

### ❌ REMOVE (5% of code - ~40 lines)

**Animation Wrappers**:
- `AnimatedTrainList` component (lines 431-507)
- `AnimatedBusList` component (lines 510-574)

**Animation State**:
- `introducingItems` state in wrappers
- `animatingItems` state in wrappers
- Introduction/departure timeouts (ViewTransition handles)

**Optional**:
- Debug logging (lines 757-763) - development aid

---

## Critical Logic That MUST Be Preserved

### 1. **5-Minute Time Window** (Lines 193-196, 230-233)
**Why it exists**: API updates every 30s with new timestamps

**What happens if removed**:
❌ Every 30-second update triggers "new train" animation
❌ Constant visual noise
❌ Users can't focus on actual new trains

**ViewTransition impact**:
- ViewTransition still needs to know when to animate
- Must preserve this logic in filter/comparison

---

### 2. **Delay Calculation Chain** (Lines 53-167)
**Why it exists**: Sep 30 bug fix for "(0m sen)" issue

**Chain of dependencies**:
```
parseDelayInfo() → used by →
calculateAdjustedDeparture() → used by →
formatDelayAwareTimeDisplay() → used by →
TrainDepartureLine (display)

ALSO: calculateAdjustedDeparture() → used by →
useDepartureSequence() (for glow triggers)
```

**What happens if removed**:
❌ Delays show as "(0m sen)" again (bug regression)
❌ Trains depart based on wrong times
❌ Users rush for trains that are actually later

---

### 3. **Departure Sequence State Machine** (Lines 263-347)
**Why it exists**: 9-second graceful exit vs abrupt removal

**States & timing**:
```
feasible (6+ min)
  ↓ at 5:59
warning (orange glow, 4s)  ← User sees: "I should go soon"
  ↓ after 4s
critical (red glow, 3s)    ← User sees: "Too late to walk!"
  ↓ after 3s
departing (fade, 2s)       ← ViewTransition can handle this
  ↓ after 2s
departed (removed)
```

**What happens if removed**:
❌ No warning before infeasibility
❌ Trains disappear instantly at 6-minute mark
❌ Users miss trains because no visual alert

**ViewTransition impact**:
- ViewTransition can handle `departing → departed` (exit animation)
- But we MUST keep `warning` and `critical` states for glow effects
- Glow is NOT an animation - it's a pulsing CSS effect

---

### 4. **Original Time Identity** (Lines 170-174)
**Why it exists**: Delayed trains must maintain stable identity

**Example**:
```
T=0:  Train "20:42 to Uppsala"
T=30s: API updates → "Delay: 4 min" → Now shows "20:46"

Without original time ID:
  Old ID: "20:42-41-Uppsala"
  New ID: "20:46-41-Uppsala"  ← React thinks it's a new train!
  Result: Unnecessary animation

With original time ID:
  ID: "20:42-41-Uppsala" (unchanged)
  Result: No animation (correct - just data update)
```

**What happens if removed**:
❌ Delay announcements trigger departure + introduction animations
❌ Visual chaos every time delays update

**ViewTransition impact**:
- **CRITICAL**: ViewTransition uses `key` prop to track elements
- These IDs become the keys
- Stability is ESSENTIAL

---

### 5. **Feasibility Filtering with Departure States** (Lines 716-732)
**Why it exists**: Smooth 9-second exit sequence

**Logic**:
```typescript
// Include if:
// - Feasible (6+ min) OR
// - In warning/critical/departing states (grace period)
```

**Example timeline**:
```
6:00 - Feasible (6 min) → Show
5:59 - Enter warning state → Still show (orange glow)
5:55 - Enter critical state → Still show (red glow)
5:52 - Enter departing state → Still show (fading)
5:50 - Departed → Remove
```

**What happens if removed**:
❌ Trains disappear exactly at 6:00 (no warning)
❌ Users don't have time to react

---

### 6. **Deviation Delay Feasibility** (Lines 766-791)
**Why it exists**: Alerts for delayed trains need adjusted time check

**Complex logic**:
```typescript
// Original time: 20:42
// Delay: 10 min
// Actual time: 20:52
// Current time: 20:43
//
// Naive: 20:42 was 1 min ago → Don't show
// Correct: 20:52 is 9 min away → Show (feasible)
```

**What happens if removed**:
❌ Missing alerts for trains that ARE still catchable
❌ Users miss feasible delayed trains

---

## Proposed Refactor Plan (Informed by Audit)

### Phase 1: Keep Everything, Add ViewTransition Alongside

**Goal**: Prove ViewTransition works WITHOUT breaking existing logic

**Changes**:
1. Install React experimental
2. Add `useDeferredValue(trainData)`
3. Wrap EACH item in `<ViewTransition key={id}>...</ViewTransition>`
4. **KEEP** existing animation wrappers (both systems running)

**Result**:
- Both old animations AND ViewTransition active
- Compare side-by-side
- Verify ViewTransition handles all cases

---

### Phase 2: Remove Animation State, Keep Detection Logic

**After Phase 1 proves ViewTransition works:**

**Remove**:
- `AnimatedTrainList` / `AnimatedBusList` components
- `introducingItems` state
- `animatingItems` state (for departures)
- Introduction/departure timeouts

**Transform**:
- `useTrainListChanges()` - remove state management, KEEP 5-min window
- `useBusListChanges()` - same
- `useDepartureSequence()` - remove `departing` state, KEEP warning/critical

**Keep ALL**:
- 5-minute time window logic
- Delay calculation chain
- Warning/critical glow states
- Original time identity
- Feasibility filtering
- Deviation delay logic

---

### Phase 3: Simplify CSS

**After Phase 2 is stable:**

**Remove CSS**:
```css
/* Can remove: */
.introducing { ... }
.departing { ... }
@keyframes slideInFromBottom { ... }
@keyframes slideOutToTop { ... }
```

**Add CSS**:
```css
/* ViewTransition animations */
::view-transition-new(train-item) { ... }
::view-transition-old(train-item) { ... }
```

**Keep CSS**:
```css
/* Glow effects (NOT animations) */
.warning-glow { ... }
.critical-glow { ... }
.urgent-text-glow { ... }
.critical-text-glow { ... }
```

---

## Risk Assessment

### ⚠️ HIGH RISK - Do NOT Remove

**1. Delay calculation chain**
- **Impact**: Breaks recently-fixed "(0m sen)" bug
- **Mitigation**: Comprehensive tests before/after

**2. 5-minute time window**
- **Impact**: Animation spam every 30 seconds
- **Mitigation**: Keep logic, just change what it triggers

**3. Departure sequence states**
- **Impact**: No warnings before infeasibility
- **Mitigation**: Transform (remove `departing`, keep `warning`/`critical`)

---

### ✅ LOW RISK - Safe to Remove

**1. Animation wrapper components**
- **Reason**: ViewTransition replaces this functionality
- **Caveat**: Only after Phase 1 proves it works

**2. Introduction/departure state management**
- **Reason**: ViewTransition handles entry/exit
- **Caveat**: Keep detection logic, just remove state

---

## Testing Checklist Before ANY Removal

**Delay Handling**:
- [ ] Train delayed by 4 min shows "(4m sen)" not "(0m sen)"
- [ ] Adjusted time calculated correctly (20:42 + 4min = 20:46)
- [ ] "om X minuter" uses adjusted time, not original

**Animation Triggers**:
- [ ] New train appearing → animates in
- [ ] Same train, API timestamp update → NO animation
- [ ] Train departing → animates out
- [ ] Train delayed → NO animation (just data update)

**Warning System**:
- [ ] Train at 10 min → no glow
- [ ] Train at 6 min → orange warning glow (4s)
- [ ] Train at 2 min → red critical glow (3s)
- [ ] Train at 0 min → fades out (2s)

**Feasibility**:
- [ ] Trains with 6+ min → shown
- [ ] Trains with < 6 min → only if in warning/critical/departing
- [ ] Buses shown until departure (0 min threshold)

**Deviations**:
- [ ] Delays shown inline → NOT in störningar box
- [ ] Non-delay issues → shown in störningar box
- [ ] Delayed train feasibility uses adjusted time

---

## Server-Side Logic Dependencies

### Critical Backend Processing (handlers/train_departure_handler.rb)

The frontend relies heavily on server-side string transformations. **Any ViewTransition refactor must preserve these dependencies!**

#### 1. **Delay Extraction** (Lines 106-115)
**Server-side logic**:
```ruby
# Backend extracts delay from SL Transport API's Swedish text
if deviation_note.include?('Försenad') || deviation_note.include?('delayed')
  if match = deviation_note.match(/(\d+)\s*min/)
    summary_deviation_note = "försenad #{match[1]} min"  # ← Normalized format
  else
    summary_deviation_note = ''  # ← Avoid "0m sen" bug
  end
end
```

**Frontend dependency**:
```typescript
// Frontend expects EXACTLY this format from backend
parseDelayInfo("försenad 4 min")  // ← Backend's normalized format
// → { isDelayed: true, delayMinutes: 4, ... }
```

**Why this matters for ViewTransition**:
- Backend already does the heavy lifting (regex extraction from Swedish text)
- Frontend just parses the clean format
- **CRITICAL**: If we refactor frontend delay parsing, it must still handle backend's format

**Testing requirement**:
```json
// Backend sends:
{
  "deviation_note": "Försenad cirka 4 min. Läs mer på trafikläget.",
  "summary_deviation_note": "försenad 4 min"  ← Normalized by backend
}

// Frontend must parse this correctly
```

---

#### 2. **Action Suffix Generation** (Lines 152-161)
**Server-side logic**:
```ruby
# Backend calculates which action user should take
late = minutes_until_departure < WALK_TIME  # 8 minutes
suffix = if late
  "spring eller cykla!"  # Can't walk, need to rush
elsif minutes_until_departure > (WALK_TIME + MARGIN_TIME + 5)  # > 18 min
  alarm_time = departure_time - (WALK_TIME + MARGIN_TIME)*60
  "var redo #{alarm_time.strftime('%H:%M')}"  # Set alarm for this time
else
  "du hinner gå"  # Just walk normally
end
```

**Constants** (Lines 28-33):
```ruby
WALK_TIME = 8    # Minutes to walk to station
RUN_TIME = 5     # Minutes to cycle/run to station
MARGIN_TIME = 5  # Minutes for alarm margin
```

**Frontend dependency**:
```typescript
// Frontend displays suffix verbatim
<div>{departure.suffix}</div>  // "spring eller cykla!" or "var redo 22:15" etc.
```

**Why this matters for ViewTransition**:
- Backend encodes **business logic** (walking time, urgency) into strings
- Frontend treats as opaque display strings
- **No frontend duplication** - backend is source of truth
- **KEEP**: Frontend suffix display logic (lines 616 in TrainWidget.tsx)

---

#### 3. **Feasibility Filtering** (Lines 143-146)
**Server-side logic**:
```ruby
# Backend pre-filters out:
# 1. Cancelled trains
# 2. Trains too soon to catch (< 5 min)
departures = departures.select do |d|
  d[:summary_deviation_note] != ' (inställd)' &&
  d[:minutes_until_departure] > RUN_TIME  # > 5 min
end
```

**Frontend dependency**:
```typescript
// Frontend ALSO filters (lines 716-732)
const feasibleTrainsForHooks = trainsForHooks.filter(train => {
  const adjusted = calculateAdjustedDeparture(train)
  return adjusted.adjustedMinutesUntil >= 0 && (
    isFeasibleTrainDeparture(adjusted.adjustedMinutesUntil) ||  // 6+ min
    ['warning', 'critical', 'departing'].includes(departureState)  // Grace period
  )
})
```

**Why both filter?**:
- **Backend**: Removes impossible trains (< 5 min) to reduce bandwidth
- **Frontend**: Applies stricter threshold (6 min) + grace period for UX

**Why this matters for ViewTransition**:
- Frontend filtering is MORE COMPLEX than backend
- Backend sends trains 5-6 min away that frontend might not show
- **KEEP**: Frontend's grace period logic (warning/critical states)

---

#### 4. **Timestamp Precision** (Lines 150, 164-165)
**Server-side logic**:
```ruby
departure_timestamp = departure_time.to_i  # Unix timestamp (seconds)
'departure_time' => departure_time.strftime('%H:%M')  # Display string
'departure_timestamp' => departure_timestamp  # Sortable integer
```

**Frontend dependency**:
```typescript
// Frontend uses timestamps for:
// 1. Identity generation (lines 170-174)
const generateTrainId = (train: TrainDeparture): string =>
  `${train.departure_time}-${train.line_number}-${train.destination}`
  // ↑ Uses string, not timestamp (stable across updates)

// 2. Time window comparison (lines 193-196)
Math.abs(prevTrain.departure_timestamp - newTrain.departure_timestamp) <= 300
  // ↑ Uses timestamp for 5-minute window

// 3. Sorting (future feature - not implemented yet)
```

**Why this matters for ViewTransition**:
- Frontend needs BOTH formats (string for ID, int for comparison)
- **CRITICAL**: Identity uses `departure_time` string, not timestamp
- **Reason**: String is stable (doesn't change when backend updates)

---

#### 5. **Deviation Separate Array** (Lines 131-140)
**Server-side logic**:
```ruby
# Backend creates SEPARATE deviations array from train data
deviations = departures.map do |d|
  unless d[:deviation_note].empty?
    {
      'time' => d[:departure_time].strftime('%H:%M'),
      'destination' => d[:destination],
      'reason' => d[:deviation_note].downcase  ← Lowercased!
    }
  end
end.compact
```

**Frontend dependency**:
```typescript
// Frontend merges deviations back into trains (lines 88-115)
const mergeDelayInfoIntoTrains = (trains, deviations) => {
  // If train.summary_deviation_note is empty,
  // look for matching deviation by time
}

// Then filters deviations for störningar box (lines 649-663)
const filterNonDelayDeviations = (deviations, trains) => {
  // Don't show delays twice (inline + box)
}
```

**Why this structure?**:
- Backend sends delays in TWO places (train object + deviations array)
- **Reason**: Some delays apply to multiple trains, deviations allow grouping
- **Frontend responsibility**: Merge them, then filter to prevent duplication

**Why this matters for ViewTransition**:
- **KEEP**: `mergeDelayInfoIntoTrains()` - data normalization
- **KEEP**: `filterNonDelayDeviations()` - prevents UI redundancy
- **NO CHANGE**: ViewTransition doesn't affect data transformation

---

### Backend Constants Driving Frontend Behavior

**From lines 28-34**:
```ruby
WALK_TIME = 8     # Frontend: isFeasibleTrainDeparture() uses 6 (2 min buffer)
RUN_TIME = 5      # Frontend: No equivalent (backend-only filtering)
MARGIN_TIME = 5   # Frontend: No equivalent (backend uses for alarm time)
```

**Important asymmetry**:
- Backend filters at 5 min (RUN_TIME)
- Frontend filters at 6 min (WALK_TIME - 2)
- **Result**: Some trains sent by backend aren't shown by frontend
- **Reason**: Frontend is MORE conservative (better UX)

**Why this matters for ViewTransition**:
- Don't assume "all data from backend is shown"
- Frontend's 6-min threshold is INDEPENDENT business logic
- **KEEP**: `isFeasibleTrainDeparture()` unchanged

---

### Server-Side Transformation Summary

**What backend sends (JSON)**:
```json
{
  "trains": [
    {
      "departure_time": "20:42",           ← Display string (HH:MM)
      "departure_timestamp": 1759265720,   ← Unix timestamp
      "minutes_until": 8,                  ← Calculated by backend
      "can_walk": true,                    ← Based on WALK_TIME constant
      "line_number": "41",
      "destination": "Märsta",
      "deviation_note": "Försenad cirka 4 min. Läs mer...",  ← Raw Swedish
      "summary_deviation_note": "försenad 4 min",  ← Normalized format
      "suffix": "du hinner gå"             ← Action based on backend logic
    }
  ],
  "deviations": [
    {
      "time": "20:42",
      "destination": "Märsta",
      "reason": "försenad cirka 4 min. läs mer..."  ← Lowercased
    }
  ]
}
```

**Frontend transformations**:
1. **Merge** deviations into trains (if `summary_deviation_note` empty)
2. **Parse** delay from normalized format (`parseDelayInfo`)
3. **Calculate** adjusted time (`calculateAdjustedDeparture`)
4. **Filter** by stricter feasibility (6 min + grace period)
5. **Detect** genuine changes (5-min time window)
6. **Format** display strings (inline delay, opacity, etc.)

**ViewTransition impact**:
- ✅ ViewTransition only affects HOW animations happen
- ✅ All data transformations stay the same
- ✅ Server contract unchanged
- ✅ Business logic untouched

---

## Conclusion

**ViewTransition replacement is ONLY safe for:**
- `AnimatedTrainList` / `AnimatedBusList` wrapper components
- `introducing` / `animating` state management
- CSS animations for entry/exit

**EVERYTHING ELSE must be preserved:**
- ✅ Delay calculation chain (just fixed Sep 30!)
- ✅ 5-minute time window (prevents animation spam)
- ✅ Warning/critical glow states (user alerts)
- ✅ Original time identity (stable keys)
- ✅ Departure sequence state machine (graceful exits)
- ✅ All business logic (feasibility, opacity, formatting)

**Estimated code reduction**:
- Current: 873 lines
- After refactor: ~830 lines (only -40 lines, ~5%)
- **NOT** the ~300 → ~50 lines initially estimated

**Why smaller than expected?**
- Initial estimate assumed animations were just wrappers
- Reality: Most code is critical business logic
- Animations are < 10% of total code

**Recommendation**:
✅ Proceed with ViewTransition migration
⚠️ Use 3-phase approach (add alongside → remove old → simplify CSS)
✅ Test thoroughly at each phase
✅ Never remove logic that has a clear business purpose

---

**Last Updated**: October 1, 2025
**Reviewed By**: Claude Code + Fredrik Bränström
**Status**: Ready for Phase 1 Implementation

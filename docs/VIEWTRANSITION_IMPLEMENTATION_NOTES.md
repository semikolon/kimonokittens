# ViewTransition Implementation Notes

**Status**: In Progress - Native Browser API Approach
**Date**: October 1, 2025
**Decision**: Use native `document.startViewTransition()` + `flushSync()`
**Last Updated**: October 1, 2025 - After critical performance analysis

## Strategic Decision: Native Browser API with Abstraction ✅

After extensive research and critical performance analysis (GPT-5 + web research), we're using native `document.startViewTransition()` with `flushSync()`, wrapped in an abstraction layer.

**Why Native API (Despite React's Component Being "Better"):**

1. **React's Component Not Available**: Despite January 2025 PR merge and April 2025 docs, `unstable_ViewTransition` isn't exported in any public build (behind `enableViewTransition` feature flag, Facebook-internal only)
2. **Unknown Timeline**: Could be weeks or months before public availability
3. **Acceptable Performance Tradeoff**: flushSync penalty is **localized and infrequent**
4. **Real-World Validation**: Pattern widely used, Jake Archibald (Chrome team) recommended it

**Performance Analysis:**

**flushSync Penalty:**
- **4-25ms typical** block on modern hardware (30-50ms on slow devices)
- **Only when list changes structurally** (trains appear/disappear)
- **1-3 transitions per minute** (WebSocket updates every 30s, not all trigger transitions)
- Kiosk context = low interactivity = minimal UX impact

**View Transitions Overhead:**
- **~70ms added to LCP** (separate from flushSync, happens with any View Transition approach)
- Correlates with CPU speed (Chrome kiosk = fast CPU = lower end)

**React's Warning Context:**
- "Significantly hurts performance" targets *frequent* use in *interactive* flows
- Bad use cases: scroll handlers, drag, typing input
- Good use case: infrequent list transitions (our scenario)

**Why This Still Wins:**
- Eliminates **123 lines** of manual animation state management
- No race conditions, no animation interruption edge cases
- Browser handles all transition coordination
- Clean abstraction enables migration when React component ships

**Migration Strategy:**
```typescript
// Today: Native API wrapper with performance instrumentation
export const startListTransition = (setState, newState, isStructural) => {
  if (isStructural && document.startViewTransition) {
    performance.mark('transition-start');
    document.startViewTransition(() => {
      flushSync(() => setState(newState));
    });
    performance.mark('transition-end');
  } else {
    setState(newState); // Normal update
  }
};

// Future: Drop-in React component when publicly available
import { unstable_ViewTransition as ViewTransition } from 'react';
// Simple find-replace migration
```

---

## Current State

### Backend Changes COMPLETED ✅
- **Train filter removed** (handlers/train_departure_handler.rb:145)
  - Was filtering at `> RUN_TIME` (5 min)
  - Now sends ALL non-cancelled trains
  - Frontend handles feasibility filtering

- **Bus filter removed** (handlers/train_departure_handler.rb:281-285)
  - Was filtering at `bus_time > now`
  - Now sends ALL buses
  - Frontend handles feasibility filtering

### Frontend Changes COMPLETED ✅
- **Feasibility threshold fixed** (TrainWidget.tsx:416)
  - Changed from 6 min → 5 min (matches backend RUN_TIME)
  - More realistic for biking/running to station

- **Departure sequence trigger updated** (TrainWidget.tsx:279)
  - Changed from `< 6` → `< 5` to match new threshold

---

## Implementation Approach: Native Browser API

### Key Insights from Analysis

**Code Reduction**: ~33% (123 lines removed)
- **Replaces**: List change detection, animation wrappers, introducingItems/departingTrains state
- **Keeps**: Business logic, delay calculations, glow effects, identity generation

**Critical Discovery**: Stable ID generation already perfect for View Transitions
- Uses `${train.departure_time}-${train.line_number}-${train.destination}`
- Original time string (not timestamp) = stable across API updates
- Becomes `view-transition-name` CSS property

### What Native ViewTransition Replaces:

**1. List Change Detection** (~70 lines - both trains/buses)
```typescript
// REMOVE: useTrainListChanges, useBusListChanges
// Browser automatically detects DOM changes when wrapped in startViewTransition

// KEEP: generateTrainId, generateBusId (becomes view-transition-name)
```

**2. Introduction/Departure State** (~80 lines - both wrappers)
```typescript
// REMOVE: AnimatedTrainList, AnimatedBusList components
// REMOVE: introducingItems, animatingItems state management

// ADD: Wrap setState in startViewTransition + flushSync
startListTransition(setFeasibleTrains, newTrains, hasStructuralChange);
```

**3. Departure Sequence Simplification** (~40 lines)
```typescript
// KEEP: warning/critical states (time-triggered glows)
// REMOVE: departing state (View Transitions handle exit)
// Trains removed after 7s (4s warning + 3s critical)
// → Browser animates exit automatically
```

### What ViewTransition CANNOT Replace

**1. Glow Effects** (~40 lines) - TIME-TRIGGERED, not list-triggered
```typescript
// These are based on minutes_until, not list membership
const useUrgentBusFlashing = (buses) => {
  // Glow when 2-1 min remaining
}
```

**2. Delay Calculation Chain** (~100 lines) - BUSINESS LOGIC
```typescript
const parseDelayInfo = (note: string): DelayInfo => {
  // Parse "försenad 4 min" → { isDelayed: true, delayMinutes: 4 }
}
```

**3. Identity Generation** (5 lines) - CRITICAL for View Transitions!
```typescript
const generateTrainId = (train: TrainDeparture): string =>
  `${train.departure_time}-${train.line_number}-${train.destination}`
// Becomes view-transition-name CSS property
```

**4. Feasibility Filtering** (~10 lines) - BUSINESS LOGIC
```typescript
const isFeasibleTrainDeparture = (minutesUntil: number): boolean => {
  return minutesUntil >= 5
}
```

---

## Implementation Plan (7 Phases)

### Phase 1: Setup Native API Infrastructure (5 tasks)
1. Revert to React 19.1.0 stable (remove experimental)
2. Update ViewTransition wrapper for native browser API
3. Add structural change detection helper (only transition on add/remove)
4. Add performance instrumentation (marks + long task observer)
5. Verify dev server works with stable React

### Phase 2: Integrate ViewTransition - Dual System (5 tasks)
1. Integrate native ViewTransition in TrainWidget
2. Add `view-transition-name` CSS property to train items (using generateTrainId)
3. Add `view-transition-name` CSS property to bus items (using generateBusId)
4. Wrap list updates with `startListTransition` helper
5. Test both animation systems work simultaneously

### Phase 3: Add ViewTransition CSS (3 tasks)
1. Add `::view-transition-new()` CSS for entry animations (5s slide-in)
2. Add `::view-transition-old()` CSS for exit animations (400ms fade-out)
3. Verify animations match old system timing

### Phase 4: Remove Old Animation System (6 tasks)
After Phase 2/3 proven stable:
1. Remove `useTrainListChanges` hook (~35 lines)
2. Remove `useBusListChanges` hook (~35 lines)
3. Remove `AnimatedTrainList` component (~75 lines)
4. Remove `AnimatedBusList` component (~65 lines)
5. Simplify `useDepartureSequence` (remove departing state)
6. Update feasibility filter (remove departing condition)

### Phase 5: Clean Up CSS (3 tasks)
1. Remove `.introducing` and `.departing` CSS classes
2. Remove `@keyframes fadeInSlide`
3. Keep warning/critical glow CSS (time-triggered, not animation-related)

### Phase 6: Testing & Monitoring (5 tasks)
1. Test train intro/departure animations
2. Test bus intro/departure animations
3. Test warning/critical glows still trigger correctly
4. Test delay display (no "0m sen" regression)
5. Monitor performance marks for >50ms blocks (auto-disable if persistent)

### Phase 7: Documentation (1 task)
1. Update all documentation with final implementation details

---

## Performance Instrumentation Strategy

**Goal:** Detect and respond to performance issues automatically

```typescript
// Detect long flushSync blocks
const observer = new PerformanceObserver((list) => {
  for (const entry of list.getEntries()) {
    if (entry.duration > 50) {
      console.warn(`Long transition block: ${entry.duration}ms`);
      // Auto-disable transitions after 3 occurrences
    }
  }
});
observer.observe({ entryTypes: ['longtask'] });

// Measure each transition
performance.mark('transition-start');
document.startViewTransition(() => {
  flushSync(() => setState(newState));
});
performance.measure('transition-duration', 'transition-start');
```

**Thresholds:**
- **< 25ms**: Excellent (typical for modest lists)
- **25-50ms**: Acceptable (still smooth)
- **> 50ms**: Warning logged (investigate)
- **> 80ms (3 times)**: Auto-disable transitions for session

---

## Critical Files

- **TrainWidget.tsx** (873 lines total)
  - Lines 170-174: generateTrainId (KEEP - becomes view-transition-name)
  - Lines 176-259: useTrainListChanges (REMOVE in Phase 4)
  - Lines 263-347: useDepartureSequence (SIMPLIFY in Phase 4)
  - Lines 349-407: useUrgentBusFlashing (KEEP - time-triggered glows)
  - Lines 415-417: isFeasibleTrainDeparture (KEEP - business logic)

- **src/components/ViewTransition.tsx** (NEW)
  - Native API wrapper with abstraction layer
  - Performance instrumentation
  - Feature flag for easy rollback

---

## Testing Checklist

Before removing old code:
- [ ] Train introduction animations work (slide in from left, 5s)
- [ ] Train departure animations work (fade out, 400ms)
- [ ] Bus introduction animations work
- [ ] Bus departure animations work
- [ ] Warning glow (orange) triggers at 5 min
- [ ] Critical glow (red-orange) triggers at <1 min
- [ ] Delayed trains show adjusted time correctly
- [ ] "0m sen" bug stays fixed (no delay shown without minutes)
- [ ] Identity generation prevents false animations
- [ ] Performance marks show <50ms blocks consistently
- [ ] No long task warnings in console

---

## Known Issues Fixed This Session

1. **Backend filtered trains at 5 min** → Fixed: Now sends all trains
2. **Backend filtered buses at 0 min** → Fixed: Now sends all buses
3. **Frontend threshold too conservative (6 min)** → Fixed: Changed to 5 min
4. **Departure sequence trigger mismatch** → Fixed: Changed to 5 min
5. **Overmind doesn't work with Claude Code background** → Fixed: TTY detection + daemon mode
6. **React ViewTransition not exported** → Discovered: Behind internal feature flag, using native API instead

---

## Research Citations

**React ViewTransition Status:**
- PR #31975 merged January 8, 2025
- Feature behind `enableViewTransition` flag (PR #32306)
- Flag set to "dynamic for www" (Facebook-internal only)
- Unknown public availability timeline

**Performance Data:**
- flushSync: 4-25ms typical, 30-50ms on slow devices (GPT-5 analysis)
- View Transitions: ~70ms LCP overhead (corewebvitals.io research)
- Pattern recommended by Jake Archibald (Chrome team)

**Sources:**
- github.com/facebook/react (PR #31975, #32306)
- react.dev/reference/react-dom/flushSync
- malcolmkee.com/blog/view-transition-api-in-react-app
- corewebvitals.io/pagespeed/view-transition-web-performance

---

## Documentation Cross-References

- `VIEWTRANSITION_LOGIC_PRESERVATION_AUDIT.md` - Complete line-by-line analysis (1,160 lines)
- `VIEWTRANSITION_STRATEGY_COMPARISON.md` - Imperative vs declarative comparison
- This file - Implementation strategy and performance analysis

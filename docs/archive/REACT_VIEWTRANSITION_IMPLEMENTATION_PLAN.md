# React ViewTransition Implementation Plan
## Train & Bus List Animations

**Date**: September 30, 2025
**Author**: Claude Code
**Status**: Planning Phase
**Target**: Kimonokittens Dashboard - TrainWidget Component

---

## Executive Summary

This document provides a comprehensive implementation plan for migrating the train/bus departure list animations from custom CSS/React hooks to React's experimental `<ViewTransition>` component. The new system will provide browser-native, GPU-accelerated animations for list item entry, exit, and reordering with significantly less code complexity.

**Key Benefits:**
- ✅ **Automatic position tracking** - Browser handles all position calculations
- ✅ **Smooth reordering** - Items automatically animate to new positions
- ✅ **Zero manual bookkeeping** - No need to track previous/current states
- ✅ **GPU-accelerated** - Native browser optimizations
- ✅ **Reduced code complexity** - ~300 lines → ~50 lines
- ✅ **Better animation quality** - Shared element transitions with FLIP technique

**Key Challenges:**
- ⚠️ **Experimental API** - Requires React experimental/canary version
- ⚠️ **Browser support** - Limited to modern browsers
- ⚠️ **API stability** - May change before React 20 stable

---

## Current System Analysis

### Current Animation Implementation

**Files:**
- `dashboard/src/components/TrainWidget.tsx` (859 lines)
- `dashboard/src/index.css` (animation keyframes)

**Current Approach:**
```typescript
// Manual list change tracking
const useTrainListChanges = (currentFeasibleTrains: TrainDeparture[]) => {
  const [prevFeasibleTrains, setPrevFeasibleTrains] = useState<TrainDeparture[]>([])

  // Compare IDs, filter time updates, detect genuinely added/removed items
  const genuinelyAdded = potentiallyAdded.filter(newTrainId => {
    // 5-minute window to distinguish updates from new arrivals
    const isTimeUpdate = prevFeasibleTrains.some(prevTrain =>
      prevTrain.line_number === newTrain.line_number &&
      Math.abs(prevTrain.departure_timestamp - newTrain.departure_timestamp) <= 300
    )
    return !isTimeUpdate
  })

  return { hasStructuralChange, added: genuinelyAdded, removed }
}
```

**Current Animation Classes:**
- `.introducing` - Items appearing at bottom (5s fade-in + slide-up)
- `.departing` - Items exiting from top (400ms fade-out + slide-up)
- `.warning-glow` - Orange glow (4s) when approaching infeasibility
- `.critical-glow` - Red-orange glow (3s) when critically close

**Problems Identified:**
1. ❌ **Middle-of-list insertion bug** - Items appearing mid-list still get "introducing" animation
2. ❌ **No gap-filling animation** - When top item exits, remaining items don't smoothly slide up
3. ❌ **Complex state management** - 300+ lines of hooks tracking previous states
4. ❌ **Position-unaware** - Only tracks IDs, not actual positions in rendered list

---

## Data Flow Architecture

### Backend → Frontend Flow

```
SL Transport API (REST)
  ↓ (HTTParty GET every 30s)
TrainDepartureHandler.rb
  ↓ (transforms to structured JSON)
{
  "trains": [...],      // TrainDeparture[]
  "buses": [...],       // BusDeparture[]
  "deviations": [...],  // Deviation[]
  "generated_at": "ISO8601"
}
  ↓ (WebSocket broadcast)
DataBroadcaster.rb
  ↓ (publishes via PubSub)
DataContext.tsx (useWebSocket)
  ↓ (useReducer dispatch)
TrainWidget.tsx (useData hook)
  ↓ (filtering, sorting, rendering)
AnimatedTrainList / AnimatedBusList
```

### Data Structures

**TrainDeparture** (from backend):
```typescript
interface TrainDeparture {
  departure_time: string           // "15:30"
  departure_timestamp: number      // Unix timestamp
  minutes_until: number            // Minutes until departure
  can_walk: boolean                // Walking feasibility
  line_number: string              // "41"
  destination: string              // "Stockholm Central"
  deviation_note: string           // Full deviation text
  summary_deviation_note: string   // "försenad 3 min"
  suffix: string                   // "spring eller cykla!"
}
```

**BusDeparture** (from backend):
```typescript
interface BusDeparture {
  departure_time: string           // "15:30"
  departure_timestamp: number      // Unix timestamp
  minutes_until: number            // Minutes until departure
  line_number: string              // "865"
  destination: string              // "Handens station"
}
```

### Current Filtering Logic

**Train Feasibility:**
```typescript
const isFeasibleTrainDeparture = (minutesUntil: number): boolean => {
  return minutesUntil >= 6 // Need at least 6 minutes to reach train station
}
```

**Bus Feasibility:**
```typescript
const isFeasibleBusDeparture = (minutesUntil: number): boolean => {
  return minutesUntil >= 0 // Bus stop is right outside (1min walk)
}
```

---

## React ViewTransition Technology Overview

### What is ViewTransition?

React's `<ViewTransition>` component wraps the browser's native [View Transition API](https://developer.mozilla.org/en-US/docs/Web/API/View_Transition_API), providing declarative animations for DOM updates.

**Key Concept:** The browser automatically:
1. Takes a "before" snapshot of wrapped elements
2. Applies DOM changes
3. Takes an "after" snapshot
4. Creates pseudo-elements and animates between states using FLIP technique

### Browser View Transition Pseudo-elements

When a view transition runs, the browser creates this pseudo-element tree:

```
::view-transition (root overlay)
└─ ::view-transition-group(name)
   └─ ::view-transition-image-pair(name)
      ├─ ::view-transition-old(name)  // "before" snapshot
      └─ ::view-transition-new(name)  // "after" live content
```

### React ViewTransition API

**Import:**
```typescript
import { unstable_ViewTransition as ViewTransition } from 'react'
```

**Props:**
- `enter`: CSS class for entering animations
- `exit`: CSS class for exiting animations
- `update`: CSS class for update animations
- `share`: CSS class for shared element transitions
- `name`: Unique identifier for shared element transitions
- `types`: Array of transition type strings for conditional animations

**Activation Triggers:**

ViewTransitions only activate when wrapped in a React Transition:

1. **`startTransition`** - Imperative API
```typescript
import { startTransition } from 'react'

startTransition(() => {
  setData(newData)
})
```

2. **`useDeferredValue`** - Declarative hook
```typescript
const deferredData = useDeferredValue(transportData)
```

3. **`Suspense`** - When fallback switches to content

### Example: List Reordering

```typescript
function TrainList({ trains }) {
  const [searchText, setSearchText] = useState("")
  const deferredSearchText = useDeferredValue(searchText)
  const filteredTrains = filterTrains(trains, deferredSearchText)

  return (
    <div className="train-list">
      {filteredTrains.map((train) => (
        <ViewTransition key={generateTrainId(train)}>
          <TrainDepartureLine departure={train} />
        </ViewTransition>
      ))}
    </div>
  )
}
```

**What happens automatically:**
- ✅ Items appearing at bottom: fade in + slide up (enter animation)
- ✅ Items disappearing from top: fade out + slide up (exit animation)
- ✅ Items moving position: smoothly animate to new position (update animation)
- ✅ No manual position tracking required

---

## Implementation Strategy

### Phase 1: Upgrade to React Experimental ✅

**Current Version:** React 19.1.0 (stable)
**Required Version:** React experimental/canary (contains ViewTransition)

**Installation:**
```bash
cd dashboard
npm install react@experimental react-dom@experimental
npm install --save-dev @types/react@experimental @types/react-dom@experimental
```

**Verification:**
```typescript
// Add to TrainWidget.tsx temporarily
import { unstable_ViewTransition as ViewTransition } from 'react'
console.log('ViewTransition available:', typeof ViewTransition !== 'undefined')
```

### Phase 2: Integrate useDeferredValue Trigger ✅

The key to ViewTransition activation is wrapping state updates in a React Transition. We'll use `useDeferredValue` because:
- ✅ More declarative than `startTransition`
- ✅ Plays well with WebSocket data updates
- ✅ Automatic batching of rapid updates

**Implementation:**
```typescript
// In TrainWidget.tsx
import { useDeferredValue } from 'react'

export function TrainWidget() {
  const { state } = useData()
  const { trainData } = state

  // Defer the data to trigger ViewTransitions on updates
  const deferredTrainData = useDeferredValue(trainData)

  // Use deferredTrainData instead of trainData for rendering
  const structuredData = deferredTrainData as StructuredTransportData
  // ...
}
```

### Phase 3: Replace Animation Wrappers ✅

**Remove:**
- `AnimatedTrainList` component (~100 lines)
- `AnimatedBusList` component (~100 lines)
- `useTrainListChanges` hook (~35 lines)
- `useBusListChanges` hook (~35 lines)
- State management for `introducing`, `departing` animations

**Replace with:**
```typescript
<div className="train-list-container">
  {feasibleTrains.map((train, index) => {
    const trainId = generateTrainId(train)
    const isUrgentFlashing = urgentFlashingTrains.has(trainId)
    const isCriticalFlashing = criticalFlashingTrains.has(trainId)

    return (
      <ViewTransition
        key={trainId}
        enter="train-enter"
        exit="train-exit"
        update="train-update"
      >
        <TrainDepartureLine
          departure={train}
          isUrgentFlashing={isUrgentFlashing}
          isCriticalFlashing={isCriticalFlashing}
        />
      </ViewTransition>
    )
  })}
</div>
```

### Phase 4: Define CSS Animations ✅

**Add to `index.css`:**
```css
/* ViewTransition classes for trains/buses */

/* Entry animation - items appearing at bottom */
.train-enter {
  view-transition-name: var(--vt-name, auto);
}

/* Exit animation - items disappearing from top */
.train-exit {
  view-transition-name: var(--vt-name, auto);
}

/* Update animation - items moving to new positions */
.train-update {
  view-transition-name: var(--vt-name, auto);
}

/* Customize the actual animations using pseudo-elements */

/* Entering items: fade in + slide up from bottom */
::view-transition-new(.train-enter) {
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

/* Exiting items: fade out + slide up and out */
::view-transition-old(.train-exit) {
  animation: slideOutToTop 0.4s cubic-bezier(0.25, 0.46, 0.45, 0.94);
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

/* Moving items: smooth position transition (browser handles automatically) */
::view-transition-group(.train-update) {
  animation-duration: 0.5s;
  animation-timing-function: cubic-bezier(0.25, 0.46, 0.45, 0.94);
}

/* Respect user preferences */
@media (prefers-reduced-motion: reduce) {
  ::view-transition-new(.train-enter),
  ::view-transition-old(.train-exit),
  ::view-transition-group(.train-update) {
    animation: none !important;
  }
}
```

### Phase 5: Preserve Warning/Critical Glow System ✅

The warning and critical glow animations should remain unchanged:
- `useDepartureSequence` hook - Keep as-is
- `useUrgentBusFlashing` hook - Keep as-is
- `.warning-glow` / `.critical-glow` CSS - Keep as-is

These are **orthogonal** to list entry/exit animations and work on a different timescale.

### Phase 6: Testing & Validation ✅

**Test Scenarios:**

1. **Entry Animation** (Bottom Insertion)
   - Wait for a new train/bus to become feasible
   - Should: Fade in + slide up from bottom
   - Should NOT: Appear instantly or glitch

2. **Exit Animation** (Top Departure)
   - Wait for top train/bus to become infeasible
   - Should: Fade out + slide up and out
   - Should: Remaining items slide up smoothly to fill gap

3. **Reordering Animation** (Middle Position Changes)
   - Observe trains/buses changing relative order (due to time updates or delays)
   - Should: Smoothly animate to new positions
   - Should NOT: Jump or flash

4. **Multiple Simultaneous Changes**
   - Add delays to cause multiple trains to update at once
   - Should: All animations run smoothly in parallel
   - Should NOT: Stagger awkwardly or conflict

5. **Glow Compatibility**
   - Verify warning/critical glows still work
   - Should: Glow animations overlay on top of position animations
   - Should NOT: Interfere with each other

6. **Performance**
   - Monitor frame rate during animations
   - Should: Maintain 60fps
   - Should NOT: Cause jank or layout thrashing

---

## Detailed Implementation Steps

### Step 1: Backup Current Implementation

```bash
# Create a backup branch
git checkout -b backup/pre-viewtransition
git commit -am "Backup before ViewTransition migration"
git push origin backup/pre-viewtransition

# Create feature branch
git checkout master
git pull
git checkout -b feature/react-viewtransition-animations
```

### Step 2: Upgrade React Dependencies

```bash
cd dashboard

# Install experimental React
npm install react@experimental react-dom@experimental

# Install experimental type definitions
npm install --save-dev @types/react@experimental @types/react-dom@experimental

# Verify installation
npm list react react-dom
```

**Expected Output:**
```
dashboard@0.0.0
├─ react@19.0.0-experimental-<hash>
└─ react-dom@19.0.0-experimental-<hash>
```

### Step 3: Add ViewTransition Import

**Edit:** `dashboard/src/components/TrainWidget.tsx`

```typescript
// At the top of the file
import React, { useState, useEffect, useMemo, useDeferredValue } from 'react'
import { unstable_ViewTransition as ViewTransition } from 'react'
import { useData } from '../context/DataContext'

// ... rest of imports
```

### Step 4: Wrap Data with useDeferredValue

**Edit:** `dashboard/src/components/TrainWidget.tsx` - Line ~696

```typescript
export function TrainWidget() {
  const { state } = useData()
  const { trainData, connectionStatus } = state

  // NEW: Defer trainData to trigger ViewTransitions
  const deferredTrainData = useDeferredValue(trainData)

  // Calculate state flags
  const loading = connectionStatus === 'connecting' && !deferredTrainData
  const error = connectionStatus === 'closed' ? 'WebSocket-anslutning avbruten' : null
  const hasNoData = !deferredTrainData

  // Handle both old HTML format and new structured format
  const isStructuredData = deferredTrainData?.trains !== undefined
  const structuredData = isStructuredData ? deferredTrainData as StructuredTransportData : null

  // ... rest of component logic using deferredTrainData
}
```

### Step 5: Simplify Train List Rendering

**Replace Lines ~806-826** with:

```typescript
<div className="mb-3">
  <div className="leading-relaxed train-list-container">
    {feasibleTrains.length > 0 ? (
      feasibleTrains.map((train) => {
        const trainId = generateTrainId(train)
        const isUrgentFlashing = urgentFlashingTrains.has(trainId)
        const isCriticalFlashing = criticalFlashingTrains.has(trainId)

        return (
          <ViewTransition
            key={trainId}
            enter="train-enter"
            exit="train-exit"
            update="train-update"
          >
            <TrainDepartureLine
              departure={train}
              isUrgentFlashing={isUrgentFlashing}
              isCriticalFlashing={isCriticalFlashing}
            />
          </ViewTransition>
        )
      })
    ) : (
      <div style={{ opacity: 0.6 }}>Inga pendeltåg inom en timme</div>
    )}
  </div>
</div>
```

### Step 6: Simplify Bus List Rendering

**Replace Lines ~834-853** with:

```typescript
<div className="mb-3">
  <div className="leading-relaxed bus-list-container">
    {feasibleBuses.length > 0 ? (
      feasibleBuses.map((bus) => {
        const busId = generateBusId(bus)
        const isUrgentFlashing = urgentFlashingBuses.has(busId)
        const isCriticalFlashing = criticalFlashingBuses.has(busId)

        return (
          <ViewTransition
            key={busId}
            enter="bus-enter"
            exit="bus-exit"
            update="bus-update"
          >
            <BusDepartureLine
              departure={bus}
              isUrgentFlashing={isUrgentFlashing}
              isCriticalFlashing={isCriticalFlashing}
            />
          </ViewTransition>
        )
      })
    ) : (
      <div style={{ opacity: 0.6 }}>Inga bussar tillgängliga</div>
    )}
  </div>
</div>
```

### Step 7: Remove Obsolete Code

**Delete the following from `TrainWidget.tsx`:**

1. **Lines ~177-211** - `useTrainListChanges` hook (entire function)
2. **Lines ~213-247** - `useBusListChanges` hook (entire function)
3. **Lines ~430-507** - `AnimatedTrainList` component (entire component)
4. **Lines ~509-574** - `AnimatedBusList` component (entire component)

**Total removal:** ~250 lines of code

**Keep unchanged:**
- `useDepartureSequence` hook (warning/critical glow management)
- `useUrgentBusFlashing` hook (bus glow management)
- `TrainDepartureLine` component
- `BusDepartureLine` component
- All data transformation and filtering logic

### Step 8: Add ViewTransition CSS

**Edit:** `dashboard/src/index.css` - Add after line ~300

```css
/* ============================================
   VIEWTRANSITION ANIMATIONS
   ============================================ */

/* Train & Bus Entry Animations (appearing at bottom) */
.train-enter,
.bus-enter {
  view-transition-name: var(--vt-name, auto);
}

::view-transition-new(.train-enter),
::view-transition-new(.bus-enter) {
  animation: viewTransitionSlideInFromBottom 0.5s cubic-bezier(0.25, 0.46, 0.45, 0.94);
}

@keyframes viewTransitionSlideInFromBottom {
  from {
    opacity: 0;
    transform: translateY(30px);
  }
  to {
    opacity: 1;
    transform: translateY(0);
  }
}

/* Train & Bus Exit Animations (disappearing from top) */
.train-exit,
.bus-exit {
  view-transition-name: var(--vt-name, auto);
}

::view-transition-old(.train-exit),
::view-transition-old(.bus-exit) {
  animation: viewTransitionSlideOutToTop 0.4s cubic-bezier(0.25, 0.46, 0.45, 0.94);
}

@keyframes viewTransitionSlideOutToTop {
  from {
    opacity: 1;
    transform: translateY(0);
  }
  to {
    opacity: 0;
    transform: translateY(-30px);
  }
}

/* Train & Bus Reordering Animations (moving to new positions) */
.train-update,
.bus-update {
  view-transition-name: var(--vt-name, auto);
}

::view-transition-group(.train-update),
::view-transition-group(.bus-update) {
  animation-duration: 0.6s;
  animation-timing-function: cubic-bezier(0.25, 0.46, 0.45, 0.94);
}

/* Ensure smooth interpolation for position changes */
::view-transition-old(.train-update),
::view-transition-new(.train-update),
::view-transition-old(.bus-update),
::view-transition-new(.bus-update) {
  /* Browser handles FLIP animation automatically */
  animation: none;
}

/* Respect user motion preferences */
@media (prefers-reduced-motion: reduce) {
  ::view-transition-new(.train-enter),
  ::view-transition-new(.bus-enter),
  ::view-transition-old(.train-exit),
  ::view-transition-old(.bus-exit),
  ::view-transition-group(.train-update),
  ::view-transition-group(.bus-update) {
    animation: none !important;
  }
}

/* ============================================
   LEGACY ANIMATIONS (can be removed after migration)
   ============================================ */

/* OLD: Manual slide-in animation (replaced by ViewTransition) */
.train-departure-item.introducing {
  /* DEPRECATED - ViewTransition handles this now */
  animation: fadeInSlide 5s cubic-bezier(0.25, 0.46, 0.45, 0.94) forwards;
}

/* OLD: Manual slide-out animation (replaced by ViewTransition) */
.train-departure-item.departing {
  /* DEPRECATED - ViewTransition handles this now */
  transform: translateY(-20px);
  opacity: 0;
  transition: transform 0.3s ease-out, opacity 0.3s ease-out;
}

/* NOTE: These can be removed in a future cleanup commit after verification */
```

### Step 9: Update CLAUDE.md Documentation

**Edit:** `CLAUDE.md` - Add new section

```markdown
## Train/Bus Animation System 🚂 **MIGRATED TO VIEWTRANSITION ✅** (September 30, 2025)

### React ViewTransition Migration
**Location**: `dashboard/src/components/TrainWidget.tsx`

The animation system has been migrated from custom CSS/hooks to React's experimental `<ViewTransition>` component:

**Benefits:**
- ✅ **Automatic position tracking** - No manual state management
- ✅ **Browser-native FLIP animations** - GPU-accelerated
- ✅ **Reduced code complexity** - 250 lines removed

**Key Implementation:**
```typescript
// Defer data to trigger ViewTransitions
const deferredTrainData = useDeferredValue(trainData)

// Wrap each list item with ViewTransition
<ViewTransition key={trainId} enter="train-enter" exit="train-exit" update="train-update">
  <TrainDepartureLine departure={train} />
</ViewTransition>
```

**Animation Behaviors:**
- **Entry** (bottom): New trains/buses fade in + slide up (0.5s)
- **Exit** (top): Departing trains/buses fade out + slide up and out (0.4s)
- **Reorder** (middle): Items smoothly animate to new positions (0.6s)
- **Glow** (overlay): Warning/critical glows work independently on separate layer

**Dependencies:**
- Requires React experimental: `react@experimental`, `react-dom@experimental`
- Browser View Transition API support (Chrome 111+, Edge 111+, Safari 18+)
- Graceful degradation: Falls back to instant updates in unsupported browsers

**CSS Classes:**
- `.train-enter` / `.bus-enter` - Entry animations
- `.train-exit` / `.bus-exit` - Exit animations
- `.train-update` / `.bus-update` - Reordering animations
- Pseudo-elements: `::view-transition-new()`, `::view-transition-old()`, `::view-transition-group()`

**Legacy Code (can be removed):**
- `useTrainListChanges` hook - Replaced by ViewTransition
- `useBusListChanges` hook - Replaced by ViewTransition
- `AnimatedTrainList` component - Replaced by direct ViewTransition wrapping
- `AnimatedBusList` component - Replaced by direct ViewTransition wrapping
- `.introducing` / `.departing` CSS classes - Replaced by ViewTransition pseudo-elements
```

### Step 10: Build and Test

```bash
# Ensure backend is running
npm run dev:restart

# In another terminal, start frontend with experimental React
cd dashboard
npm run dev

# Open browser
open http://localhost:5175
```

**Verification Checklist:**

- [ ] Page loads without errors
- [ ] Console shows no ViewTransition-related warnings
- [ ] New trains appear with fade-in + slide-up animation
- [ ] Departing trains fade out + slide up
- [ ] Trains changing position smoothly animate
- [ ] Warning/critical glows still work
- [ ] Bus animations work identically
- [ ] No animation on `prefers-reduced-motion` devices
- [ ] Performance: 60fps during animations (check DevTools Performance tab)

---

## Testing Strategy

### Manual Testing Checklist

**Pre-deployment Testing:**

1. **Visual Regression Testing**
   - [ ] Compare side-by-side with current production
   - [ ] Verify timing feels natural (not too fast/slow)
   - [ ] Check for flicker or jank during animations

2. **Edge Case Testing**
   - [ ] WebSocket reconnection during animation
   - [ ] Rapid data updates (< 30s interval)
   - [ ] All trains simultaneously becoming infeasible
   - [ ] Browser tab backgrounded/foregrounded
   - [ ] Window resize during animation

3. **Browser Compatibility Testing**
   - [ ] Chrome 111+ (full support)
   - [ ] Edge 111+ (full support)
   - [ ] Safari 18+ (full support - check macOS Sequoia)
   - [ ] Firefox (check current support status)
   - [ ] iOS Safari (check iOS 18+)

4. **Accessibility Testing**
   - [ ] Enable "Reduce Motion" in system preferences
   - [ ] Verify animations are disabled
   - [ ] Screen reader announces updates correctly

### Automated Testing (Future)

**Playwright E2E Tests:**

```typescript
// tests/train-animations.spec.ts
import { test, expect } from '@playwright/test'

test.describe('Train ViewTransition Animations', () => {
  test('new train appears with slide-in animation', async ({ page }) => {
    await page.goto('http://localhost:5175')

    // Mock WebSocket message with new train
    await page.evaluate(() => {
      window.mockTrainData({
        trains: [
          { departure_time: '15:30', minutes_until: 15, line_number: '41', ... }
        ]
      })
    })

    // Check for ViewTransition animation
    const trainElement = page.locator('[data-train-id="15:30-41-Stockholm Central"]')
    await expect(trainElement).toBeVisible()

    // Verify animation occurred (check computed style or wait for animation end)
    await page.waitForTimeout(500) // Animation duration
  })
})
```

---

## Rollback Plan

### If ViewTransition Causes Issues

**Option 1: Feature Flag** (Recommended)

```typescript
// Add to TrainWidget.tsx
const USE_VIEW_TRANSITION = import.meta.env.VITE_USE_VIEW_TRANSITION !== 'false'

export function TrainWidget() {
  // ...

  if (USE_VIEW_TRANSITION) {
    return <ViewTransitionList trains={feasibleTrains} />
  } else {
    return <LegacyAnimatedList trains={feasibleTrains} />
  }
}
```

**Option 2: Git Revert**

```bash
# If major issues arise, revert the entire feature
git revert <commit-hash>
git push origin master

# Reinstall stable React
cd dashboard
npm install react@19.1.0 react-dom@19.1.0
npm install --save-dev @types/react@19.1.8 @types/react-dom@19.1.6
```

**Option 3: Hybrid Approach**

Keep current implementation but add ViewTransition alongside:
- Old hooks remain functional
- ViewTransition adds enhancement layer
- If ViewTransition fails, old system takes over

---

## Performance Considerations

### ViewTransition Performance Characteristics

**Pros:**
- ✅ **GPU-accelerated** - Browser optimizes via composite layers
- ✅ **FLIP technique** - First, Last, Invert, Play (no layout thrashing)
- ✅ **Requestanimationframe** - Automatically synced with display refresh
- ✅ **Batched updates** - Multiple changes in one transition

**Cons:**
- ⚠️ **Memory overhead** - Browser stores snapshots of old/new states
- ⚠️ **Complexity limits** - Too many concurrent transitions can cause jank
- ⚠️ **Initial cost** - First transition may be slower (JIT compilation)

### Optimization Strategies

1. **Limit Concurrent Animations**
   - Max 10-15 items animating simultaneously
   - Current list sizes: ~8 trains, ~4 buses (well within limits)

2. **CSS Containment**
   ```css
   .train-list-container {
     contain: layout style paint;
   }
   ```

3. **Will-change Hints**
   ```css
   .train-departure-item {
     will-change: transform, opacity;
   }
   ```

4. **Reduce Motion Preference**
   - Already handled via `@media (prefers-reduced-motion)`

### Performance Monitoring

**Metrics to Track:**
- Frame rate during animations (target: 60fps)
- JavaScript heap size (should not increase significantly)
- Layout shift (CLS should remain near zero)
- Time to interactive (should not regress)

**Tools:**
- Chrome DevTools Performance tab
- Lighthouse CI
- Real User Monitoring (RUM) if available

---

## Browser Support

### View Transition API Support

| Browser | Version | Status |
|---------|---------|--------|
| Chrome | 111+ | ✅ Full support |
| Edge | 111+ | ✅ Full support |
| Safari | 18.0+ | ✅ Full support (macOS Sequoia, iOS 18) |
| Firefox | Not yet | ⚠️ No support (as of Sept 2025) |
| Opera | 97+ | ✅ Full support |

**Current Coverage:** ~85% of global users (Chrome + Edge + Safari)

### Graceful Degradation

**Fallback Behavior:**
- If ViewTransition API not supported:
  - Items still appear/disappear correctly
  - No animation, instant updates
  - No errors or broken layout

**Detection:**
```typescript
if (typeof document.startViewTransition === 'undefined') {
  console.log('View Transitions not supported, using instant updates')
}
```

React handles this automatically - `<ViewTransition>` becomes a no-op wrapper if unsupported.

---

## Future Enhancements

### Phase 2: Advanced Animations (Post-MVP)

1. **Stagger Effect**
   - Animate items with slight delay cascade
   - Use `animation-delay: calc(var(--index) * 50ms)`

2. **Shared Element Transitions**
   - Use `name` prop for smooth cross-list animations
   - E.g., train moving from "upcoming" to "departing" section

3. **Custom Transition Types**
   - Use `types` prop for context-aware animations
   - Different animations for normal vs urgent departures

4. **Physics-based Animations**
   - Use Web Animations API for spring physics
   - More natural, less robotic motion

### Phase 3: Performance Optimizations

1. **Virtual Scrolling**
   - If list grows beyond 20 items
   - Integrate with `react-window` or `@tanstack/react-virtual`

2. **Intersection Observer**
   - Only animate items in viewport
   - Pause animations when tab backgrounded

3. **Dynamic Animation Quality**
   - Reduce animation complexity on low-end devices
   - Use `navigator.deviceMemory` or frame rate detection

---

## Appendix: Code Diffs

### Before (Current Implementation)

**TrainWidget.tsx** - AnimatedTrainList component:
```typescript
const AnimatedTrainList: React.FC<{
  trains: TrainDeparture[];
  renderItem: (train: TrainDeparture, index: number, isUrgentFlashing: boolean, isCriticalFlashing: boolean) => React.ReactNode;
  urgentFlashingTrains?: Set<string>;
  criticalFlashingTrains?: Set<string>;
  departingTrains?: Set<string>;
  trainStates?: Map<string, DepartureState>;
}> = ({
  trains,
  renderItem,
  urgentFlashingTrains = new Set(),
  criticalFlashingTrains = new Set(),
  departingTrains = new Set(),
  trainStates = new Map()
}) => {
  const { hasStructuralChange, added, removed } = useTrainListChanges(trains)
  const [animatingItems, setAnimatingItems] = useState<Set<string>>(new Set())
  const [introducingItems, setIntroducingItems] = useState<Set<string>>(new Set())

  // Handle train departure animation
  useEffect(() => {
    if (removed.length > 0) {
      setAnimatingItems(new Set(removed))

      const timer = setTimeout(() => {
        setAnimatingItems(new Set())
      }, 400)

      return () => clearTimeout(timer)
    }
  }, [removed])

  // Handle train introduction animation
  useEffect(() => {
    if (added.length > 0) {
      setIntroducingItems(new Set(added))

      const timer = setTimeout(() => {
        setIntroducingItems(new Set())
      }, 5000)

      return () => clearTimeout(timer)
    }
  }, [added])

  return (
    <div className="train-list-container">
      {trains.map((train, index) => {
        const trainId = generateTrainId(train)
        const departureState = trainStates.get(trainId) || 'feasible'
        const isUrgentFlashing = urgentFlashingTrains.has(trainId)
        const isCriticalFlashing = criticalFlashingTrains.has(trainId)
        const isDeparting = departingTrains.has(trainId) || animatingItems.has(trainId)
        const isIntroducing = introducingItems.has(trainId)

        // Build CSS classes based on departure state and animations
        const cssClasses = ['train-departure-item']
        if (departureState === 'warning') cssClasses.push('warning-glow')
        if (departureState === 'critical') cssClasses.push('critical-glow')
        if (departureState === 'departing' || isDeparting) cssClasses.push('departing')
        if (isIntroducing) cssClasses.push('introducing')
        else if (!isDeparting) cssClasses.push('introduced')

        return (
          <div
            key={trainId}
            className={cssClasses.join(' ')}
            style={{ '--item-index': index } as React.CSSProperties}
          >
            {renderItem(train, index, isUrgentFlashing, isCriticalFlashing)}
          </div>
        )
      })}
    </div>
  )
}
```

**Total lines: ~100**

### After (ViewTransition Implementation)

**TrainWidget.tsx** - Simplified rendering:
```typescript
<div className="train-list-container">
  {feasibleTrains.map((train, index) => {
    const trainId = generateTrainId(train)
    const isUrgentFlashing = urgentFlashingTrains.has(trainId)
    const isCriticalFlashing = criticalFlashingTrains.has(trainId)

    return (
      <ViewTransition
        key={trainId}
        enter="train-enter"
        exit="train-exit"
        update="train-update"
      >
        <TrainDepartureLine
          departure={train}
          isUrgentFlashing={isUrgentFlashing}
          isCriticalFlashing={isCriticalFlashing}
        />
      </ViewTransition>
    )
  })}
</div>
```

**Total lines: ~18**

**Code reduction: ~82 lines (82% reduction)**

---

## Summary & Next Steps

### Summary

This implementation plan provides a comprehensive roadmap for migrating train/bus list animations from custom CSS/React hooks to React's experimental ViewTransition component. The migration will:

- ✅ Reduce code complexity by ~250 lines
- ✅ Fix middle-of-list insertion bug
- ✅ Add smooth gap-filling animations
- ✅ Improve animation quality with browser-native FLIP technique
- ✅ Maintain backward compatibility with warning/critical glow system
- ✅ Gracefully degrade in unsupported browsers

### Immediate Next Steps

1. **Review & Approval** - User reviews this plan and approves approach
2. **Create Feature Branch** - `feature/react-viewtransition-animations`
3. **Install React Experimental** - Upgrade dependencies
4. **Implement Changes** - Follow steps 3-8 above
5. **Test Thoroughly** - Manual testing checklist
6. **Documentation** - Update CLAUDE.md
7. **Commit & Push** - Prepare for production deployment

### Timeline Estimate

- **Research & Planning**: ✅ Complete (3 hours)
- **Implementation**: 2-3 hours
- **Testing**: 1-2 hours
- **Documentation**: 30 minutes
- **Total**: ~4-6 hours

### Risk Assessment

**Low Risk:**
- Experimental API is stable (tested in production by Meta)
- Easy rollback via Git revert
- Browser support covers 85% of users
- Graceful degradation for unsupported browsers

**Medium Risk:**
- API may change before React 20 stable (mitigated by feature flag)
- Performance on low-end devices (mitigated by `prefers-reduced-motion`)

---

**Document Status:** ✅ Ready for Implementation
**Last Updated:** September 30, 2025
**Review Required:** Yes - User approval before proceeding

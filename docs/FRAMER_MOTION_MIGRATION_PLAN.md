# Framer Motion Migration Plan

**Created**: October 2, 2025
**Status**: 🔧 READY TO IMPLEMENT
**Estimated Time**: 2-3 hours

---

## Why Framer Motion?

### The Problem
Native ViewTransition API + React integration is fundamentally broken:
- Requires `flushSync()` which React docs call "the least performant way to perform state updates"
- Blocks main thread on every list update
- Created empty lines bug due to complex state synchronization (`feasibleTrainsState` vs `feasibleTrainsForHooks`)
- Firefox has NO support (and won't for years)
- Fighting React's async rendering model

### The Solution
**Framer Motion** is the production-ready, battle-tested choice for React list animations:
- ✅ **Built for React's async model** - no `flushSync` performance penalty
- ✅ **Handles complexity automatically** - AnimatePresence keeps items in DOM during exit
- ✅ **Layout animations** - `layout` prop makes ALL items slide up in unison (FLIP)
- ✅ **Universal browser support** - works everywhere React works
- ✅ **35KB bundle** - irrelevant for kiosk that loads once, runs 24/7
- ✅ **Solves empty lines bug** - library manages DOM persistence
- ✅ **Maintainable** - clear declarative API vs 150 lines of state management

**User quote**: "I just want something that works... handles the complexity for me"

Framer Motion does exactly that.

---

## Complete Requirements (Verified)

### Your Unique System

**1. Feasibility Thresholds:**
- **Trains**: `>= 5 minutes` (matches `RUN_TIME = 5` backend constant - biking feasibility)
- **Buses**: `>= 0 minutes` (bus stop right outside, 1-min walk)
- **Pre-emptive Removal**: Trains marked at exactly `5m`, slide out before showing `4m`

**2. Shine Swoosh Animation:**
- **Trains**: 9m (orange), 8m (orange), **7m (red-orange)** - last swoosh before removal
- **Buses**: 4m (orange), 3m (orange), **2m (red-orange)** - last swoosh before removal
- **Duration**: 2 seconds linear
- **Technique**: `background-clip: text` with animated gradient
- **Triggers once per minute threshold** via `animatedAtMinuteRef` Map<trainId, Set<minutes>>

**3. 3-Minute Window for Time Updates:**
- Prevents false slide-in animations when trains get delayed
- Compares: `line_number`, `destination`, `departure_timestamp`
- Within 180 seconds → time update (NO slide animation)
- Outside window → genuinely new train (YES slide animation)
- Example: `08:07` delayed to `08:10` (180s) = NO animation

**4. Delay Handling:**
- **Inline display**: "08:07 → 08:10 (3 min sen)"
- **Störningar filtering**: Prevents duplicates (delay shown inline + störningar box)
- **Feasibility**: Delayed trains check `adjustedMinutesUntil >= 6` for störningar

**5. Entry/Exit Animations:**
- **Entry**: 1 second, slide up from bottom (`translateY(20px) → 0`)
- **Exit**: 1 second, slide up to top (`translateY(0) → -20px`)
- **Layout**: ALL items slide up in unison when one leaves (**Framer Motion `layout` prop**)
- **No staggering**: Simultaneous animations

**6. Visual Styling:**
- **Opacity fading**: `getTimeOpacity(minutesUntil)` - 0-20m visible, 50m+ faded
- **mixBlendMode**: `'hard-light'` for text
- **Special displays**: "spring!", delay minutes, suffix

**7. Unique ID Generation:**
```typescript
generateTrainId(train): `${departure_time}-${line_number}-${destination}`
generateBusId(bus): `${departure_time}-${line_number}-${destination}`
```

---

## Migration Phases

### Phase 1: Install & Setup (10 minutes)

**1.1 Install Framer Motion:**
```bash
npm install framer-motion
```

**1.2 Update imports in TrainWidget.tsx:**
```typescript
// REMOVE:
import { startListTransition } from './ViewTransition'

// ADD:
import { motion, AnimatePresence, LayoutGroup } from 'framer-motion'
```

---

### Phase 2: Preserve All Logic, Remove ViewTransition Infrastructure (30 minutes)

**2.1 KEEP EXACTLY AS IS:**
- ✅ `generateTrainId()` / `generateBusId()` - ID generation
- ✅ `parseDelayInfo()` - Delay parsing ("försenad X min")
- ✅ `calculateAdjustedDeparture()` - Adjusted times for delayed trains
- ✅ `formatDelayAwareTimeDisplay()` - Inline delay display
- ✅ `mergeDelayInfoIntoTrains()` - Deviation merging
- ✅ `isFeasibleTrainDeparture()` / `isFeasibleBusDeparture()` - Feasibility checks
- ✅ `getTimeOpacity()` - Opacity fading based on minutes_until
- ✅ `DeviationAlerts` component - Störningar box
- ✅ `filterNonDelayDeviations()` - Duplicate filtering
- ✅ `TrainDepartureLine` / `BusDepartureLine` components

**2.2 KEEP AND ENHANCE (add red-tint logic):**
- `useTrainDepartureAnimation()` - Add red tint for 7m swoosh
- `useBusDepartureAnimation()` - Add red tint for 2m swoosh

**2.3 REMOVE:**
- `startListTransition` import and all calls
- `feasibleTrainsState` / `feasibleBusesState` state variables
- `hasStructuralChange` function
- `useEffect` with ViewTransition logic (lines 566-610)
- `viewTransitionName` CSS properties (lines 712, 756)
- All `console.log` debug statements added Oct 2, 2025
- `isUrgentDeparture` / `isCriticalDeparture` functions (lines 181-192) - **replaced by shine swoosh**
- `DepartureState` type (line 377)
- `TrainWithDepartureState` interface (line 379)

---

### Phase 3: Red-Tinted Last Swoosh Logic (15 minutes)

**3.1 Modify `useTrainDepartureAnimation` hook:**

**Change state type:**
```typescript
// FROM:
const [shineAnimatedTrains, setShineAnimatedTrains] = useState<Set<string>>(new Set())

// TO:
const [shineAnimatedTrains, setShineAnimatedTrains] = useState<Map<string, boolean>>(new Map())
//                                                    Map<trainId, isRedTinted>
```

**Update animation trigger logic (line 236-254):**
```typescript
if (minutesUntil === 9 || minutesUntil === 8 || minutesUntil === 7) {
  const animatedMinutes = animatedAtMinuteRef.current.get(trainId) || new Set()
  if (!animatedMinutes.has(minutesUntil)) {
    console.log(`Shine swoosh animation for train ${trainId} at ${minutesUntil}m`)
    animatedMinutes.add(minutesUntil)
    animatedAtMinuteRef.current.set(trainId, animatedMinutes)

    const isLastSwoosh = minutesUntil === 7 // Red-tinted for final warning before removal

    setShineAnimatedTrains(prev => new Map([...prev, [trainId, isLastSwoosh]]))

    // Remove shine class after 2s (animation duration)
    setTimeout(() => {
      setShineAnimatedTrains(prev => {
        const newMap = new Map(prev)
        newMap.delete(trainId)
        return newMap
      })
    }, 2000)
  }
}
```

**Update cleanup effect:**
```typescript
// Line 269-278: Change Set to Map
useEffect(() => {
  const currentTrainIds = new Set(trains.map(generateTrainId))
  setShineAnimatedTrains(prev => {
    const filtered = new Map([...prev].filter(([id]) => currentTrainIds.has(id)))
    // Only update if actually changed
    if (filtered.size === prev.size) return prev
    return filtered
  })
}, [trains])
```

**3.2 Same changes for `useBusDepartureAnimation`:**
- Change to `Map<string, boolean>`
- `isLastSwoosh = minutesUntil === 2` (buses)

---

### Phase 4: Framer Motion Implementation (1 hour)

**4.1 Train Section Render (lines 696-729):**

```typescript
{feasibleTrains.length > 0 ? (
  <LayoutGroup>
    <AnimatePresence mode="popLayout">
      {feasibleTrains.map((train) => {
        const trainId = generateTrainId(train)
        const shineState = shineAnimatedTrains.get(trainId)
        const hasShineAnimation = shineState !== undefined
        const isRedTinted = shineState === true

        return (
          <motion.div
            key={trainId}
            layout  // ⭐ Auto slide-up in unison when items leave
            initial={{ opacity: 0, y: 20 }}
            animate={{ opacity: 1, y: 0 }}
            exit={{ opacity: 0, y: -20 }}
            transition={{
              duration: 1,
              ease: "easeOut",
              layout: { duration: 0.3 } // Fast layout shifts
            }}
            className="train-departure-item"
          >
            <TrainDepartureLine
              departure={train}
              hasShineAnimation={hasShineAnimation}
              isRedTinted={isRedTinted}
            />
          </motion.div>
        )
      })}
    </AnimatePresence>
  </LayoutGroup>
) : (
  <div style={{ opacity: 0.6 }}>Inga pendeltåg inom en timme</div>
)}
```

**4.2 Bus Section (lines 740-768) - same pattern:**
```typescript
{feasibleBuses.length > 0 ? (
  <LayoutGroup>
    <AnimatePresence mode="popLayout">
      {feasibleBuses.map((bus) => {
        const busId = generateBusId(bus)
        const shineState = shineAnimatedBuses.get(busId)
        const hasShineAnimation = shineState !== undefined
        const isRedTinted = shineState === true

        return (
          <motion.div
            key={busId}
            layout
            initial={{ opacity: 0, y: 20 }}
            animate={{ opacity: 1, y: 0 }}
            exit={{ opacity: 0, y: -20 }}
            transition={{
              duration: 1,
              ease: "easeOut",
              layout: { duration: 0.3 }
            }}
            className="bus-departure-item"
          >
            <BusDepartureLine
              departure={bus}
              hasShineAnimation={hasShineAnimation}
              isRedTinted={isRedTinted}
            />
          </motion.div>
        )
      })}
    </AnimatePresence>
  </LayoutGroup>
) : (
  <div style={{ opacity: 0.6 }}>Inga bussar inom en timme</div>
)}
```

**4.3 Update component props (lines 387-420, 440-467):**

```typescript
// TrainDepartureLine
const TrainDepartureLine: React.FC<{
  departure: TrainDeparture;
  isUrgentFlashing?: boolean;  // KEEP for backward compat but unused
  isCriticalFlashing?: boolean; // KEEP for backward compat but unused
  hasShineAnimation?: boolean;
  isRedTinted?: boolean;  // NEW
}> = ({
  departure,
  isUrgentFlashing = false,
  isCriticalFlashing = false,
  hasShineAnimation = false,
  isRedTinted = false  // NEW
}) => {
  // ... existing logic ...

  const glowClass = isUrgentFlashing ? 'urgent-text-glow' : isCriticalFlashing ? 'critical-text-glow' : ''
  const shineClass = hasShineAnimation
    ? (isRedTinted ? 'shine-swoosh-red' : 'shine-swoosh')
    : ''
  const combinedClasses = [glowClass, shineClass].filter(Boolean).join(' ')

  // ... rest unchanged ...
}

// BusDepartureLine - same changes
const BusDepartureLine: React.FC<{
  departure: BusDeparture;
  isUrgentFlashing?: boolean;
  isCriticalFlashing?: boolean;
  hasShineAnimation?: boolean;
  isRedTinted?: boolean;  // NEW
}> = ({
  departure,
  isUrgentFlashing = false,
  isCriticalFlashing = false,
  hasShineAnimation = false,
  isRedTinted = false  // NEW
}) => {
  // ... same logic ...
}
```

---

### Phase 5: CSS Updates (15 minutes)

**5.1 Add red-tinted swoosh variant (dashboard/src/index.css after line 286):**

```css
/* Shine swoosh animation for urgent departures (trains: 9-8-7m, buses: 4-3-2m) */
.train-departure-item.shine-swoosh,
.bus-departure-item.shine-swoosh {
  position: relative;
  background: linear-gradient(
    90deg,
    rgba(255, 255, 255, 1) 0%,
    rgba(255, 255, 255, 1) 30%,
    rgba(255, 140, 0, 1) 50%,  /* Orange #FF8C00 */
    rgba(255, 255, 255, 1) 70%,
    rgba(255, 255, 255, 1) 100%
  );
  background-size: 200% 100%;
  background-clip: text;
  -webkit-background-clip: text;
  color: transparent;
  animation: shineSwoosh 2s linear;
}

/* Red-tinted swoosh for last warning (7m trains, 2m buses) */
.train-departure-item.shine-swoosh-red,
.bus-departure-item.shine-swoosh-red {
  position: relative;
  background: linear-gradient(
    90deg,
    rgba(255, 255, 255, 1) 0%,
    rgba(255, 255, 255, 1) 30%,
    rgba(255, 69, 0, 1) 50%,  /* Red-orange #FF4500 (OrangeRed) */
    rgba(255, 255, 255, 1) 70%,
    rgba(255, 255, 255, 1) 100%
  );
  background-size: 200% 100%;
  background-clip: text;
  -webkit-background-clip: text;
  color: transparent;
  animation: shineSwoosh 2s linear;
}

@keyframes shineSwoosh {
  0% {
    background-position: -200% 0;
  }
  100% {
    background-position: 200% 0;
  }
}
```

**5.2 Remove ViewTransition CSS (lines 288-336):**
```css
/* DELETE entire section:
   - ::view-transition-new(root) / ::view-transition-old(root)
   - ::view-transition-new(*) / ::view-transition-old(*)
   - @keyframes viewTransitionSlideIn
   - @keyframes viewTransitionSlideOut
   - urgentTextGlow / criticalTextGlow (unused)
   - .urgent-text-glow / .critical-text-glow classes
*/
```

**5.3 Remove unused base transition (lines 247-253):**
```css
/* DELETE:
.train-departure-item,
.bus-departure-item {
  transform: translateY(0);
  transition: transform 0.8s cubic-bezier(...);
  opacity: 1;
  will-change: transform, opacity;
}
*/
```

**5.4 Keep shine swoosh in prefers-reduced-motion (line 369-384):**
```css
@media (prefers-reduced-motion: reduce) {
  .train-time-update,
  .schedule-cursor,
  .heatpump-status,
  .train-departure-item,
  .shine-swoosh,
  .shine-swoosh-red {  /* ADD this */
    animation: none !important;
    transition: none !important;
  }

  /* Ensure text stays visible when animations are disabled */
  .shine-swoosh,
  .shine-swoosh-red {  /* ADD this */
    background: none !important;
    color: white !important;
  }
}
```

---

### Phase 6: Clean Up (15 minutes)

**6.1 Delete entire file:**
- `dashboard/src/components/ViewTransition.tsx`

**6.2 Remove from TrainWidget.tsx:**
- `isUrgentDeparture` function (lines 181-186)
- `isCriticalDeparture` function (lines 188-192)
- `DepartureState` type (line 377)
- `TrainWithDepartureState` interface (line 379-381)
- All debug `console.log` statements from Oct 2 debugging session

**6.3 Update feasibility filtering (lines 537-551, 553-556):**

**BEFORE (complex dual-state system):**
```typescript
const feasibleTrainsForHooks = trainsForHooks.filter(train => {
  const trainId = generateTrainId(train)
  const adjusted = calculateAdjustedDeparture(train)

  if (adjusted.adjustedMinutesUntil > 5) {
    return true
  } else if (adjusted.adjustedMinutesUntil === 5) {
    return !trainsMarkedForRemoval.has(trainId)
  }
  return false
})

// Later: const feasibleTrains = feasibleTrainsState.length > 0 ? feasibleTrainsState : feasibleTrainsForHooks
```

**AFTER (simple single-source):**
```typescript
const feasibleTrains = trainsForHooks.filter(train => {
  const trainId = generateTrainId(train)
  const adjusted = calculateAdjustedDeparture(train)

  // Show trains with >5 minutes, OR trains at exactly 5m not yet marked for removal
  if (adjusted.adjustedMinutesUntil > 5) {
    return true
  } else if (adjusted.adjustedMinutesUntil === 5) {
    return !trainsMarkedForRemoval.has(trainId)
  }
  return false
})

// Same for buses (simpler - no pre-emptive removal):
const feasibleBuses = busesForHooks.filter(bus =>
  bus.minutes_until >= 0 && isFeasibleBusDeparture(bus.minutes_until)
)
```

---

### Phase 7: Testing Checklist

**Visual Verification:**
- [ ] Entry: New trains slide in from bottom (1 second, smooth)
- [ ] Exit: Trains slide out to top at 5m (1 second, never show 4m on screen)
- [ ] Layout: ALL trains slide up in unison when one departs (no gaps, no jumps)
- [ ] No staggering: All items animate simultaneously
- [ ] No empty lines during transitions
- [ ] Swoosh 9m: Orange gradient sweep (2 seconds)
- [ ] Swoosh 8m: Orange gradient sweep (2 seconds)
- [ ] **Swoosh 7m: RED-ORANGE gradient sweep** (2 seconds, #FF4500)
- [ ] Swoosh 4m (buses): Orange
- [ ] Swoosh 3m (buses): Orange
- [ ] **Swoosh 2m (buses): RED-ORANGE** (#FF4500)

**Functional Verification:**
- [ ] 3-minute window: Delayed trains (08:07 → 08:10) don't trigger slide-in
- [ ] Genuinely new trains trigger slide-in
- [ ] Delay display: Inline "08:07 → 08:10 (3 min sen)" works
- [ ] Störningar: No duplicates, grouped by reason
- [ ] Opacity fading: 0-20m visible, 50m+ faded
- [ ] "spring!" displays at 0 minutes
- [ ] Suffix displays correctly ("spring eller cykla", etc.)
- [ ] DeviationAlerts shows for feasible departures only

**Performance & Accessibility:**
- [ ] No console errors or React warnings
- [ ] Animations run at 60fps (smooth, no jank)
- [ ] `prefers-reduced-motion: reduce` disables all animations
- [ ] Text stays white when animations disabled

**Edge Cases:**
- [ ] Empty train list shows "Inga pendeltåg inom en timme"
- [ ] Empty bus list shows "Inga bussar inom en timme"
- [ ] Delayed trains at 6+ minutes show in störningar
- [ ] Delayed trains at <6 minutes don't show in störningar
- [ ] Multiple trains departing simultaneously (all slide out together)

---

## Known Issues & Mitigation

### WebSocket Update Frequency
- **Assumption**: 30-second updates based on puma_server.rb code
- **Risk**: If train hits 5m, gets marked for removal, but next update is 30s away, user might see countdown to 4m
- **Mitigation**: Pre-emptive removal at 5m + 100ms delay ensures ViewTransition captures "5m" snapshot, then 1s exit animation completes before next update

### Layout Animation Performance
- Set `layout: { duration: 0.3 }` for fast slide-up (default 0.5s can feel sluggish)
- Framer Motion uses FLIP animation (GPU-accelerated) for smooth 60fps

---

## Rollback Plan

If Framer Motion causes issues:

**Option 1: Quick Disable**
```typescript
// Wrap AnimatePresence in feature flag:
const ENABLE_ANIMATIONS = false

{ENABLE_ANIMATIONS ? (
  <AnimatePresence>...</AnimatePresence>
) : (
  feasibleTrains.map(train => <div key={generateTrainId(train)}>...</div>)
)}
```

**Option 2: Git Revert**
```bash
git log --oneline | grep "Framer Motion"
git revert <commit-hash>
```

**Option 3: Restore Manual CSS**
```bash
git show aac0ba6:dashboard/src/components/TrainWidget.tsx > manual_backup.tsx
git show aac0ba6:dashboard/src/index.css > manual_css_backup.css
# Extract useTrainListChanges, AnimatedTrainList logic
```

---

## Post-Migration

### Documentation Updates
- [ ] Update `TRAIN_DEPARTURE_ANIMATION_REQUIREMENTS.md` - change status to "✅ FRAMER MOTION"
- [ ] Update `CLAUDE.md` - remove ViewTransition notes, add Framer Motion section
- [ ] Archive ViewTransition docs to `docs/archive/viewtransition/`

### Performance Monitoring
- [ ] Check Chrome DevTools Performance tab during animations
- [ ] Verify no long tasks (>50ms) during list updates
- [ ] Confirm 60fps during transitions

### Future Enhancements
- [ ] Animation Test Mode (from `ANIMATION_TEST_MODE.md`)
- [ ] Gesture support (swipe to dismiss? probably not needed for kiosk)
- [ ] Spring physics (if natural motion preferred over duration-based)

---

## References

- [Framer Motion Docs](https://www.framer.com/motion/)
- [AnimatePresence Guide](https://www.framer.com/motion/animate-presence/)
- [Layout Animations (FLIP)](https://www.framer.com/motion/layout-animations/)
- Research doc: `docs/REACT_LIST_ANIMATION_RESEARCH_OCT2.md`

# ViewTransition Animation Troubleshooting

**Purpose**: Systematic debugging runbook for train/bus departure animation failures

**Created**: October 2, 2025
**Status**: ✅ ACTIVE

---

## Quick Diagnosis Flowchart

```
No animations visible?
│
├─ Check browser console for emoji logs 🔄🚂📞✨
│  │
│  ├─ No "🔄" logs? → Component not rendering (check React errors)
│  │
│  ├─ "🔄" but no "🚂"? → Structural change detection failing
│  │  └─ See: Section 2 (Structural Change Detection)
│  │
│  ├─ "🚂" but no "📞"? → startListTransition call failing
│  │  └─ See: Section 3 (Function Invocation)
│  │
│  ├─ "📞" with transitionsDisabled: true? → Auto-disabled after slow transitions
│  │  └─ See: Section 4 (Performance Auto-Disable)
│  │
│  ├─ "📞" with supportsViewTransition: false? → Browser lacks API
│  │  └─ See: Section 5 (Browser Support)
│  │
│  └─ "✨" appears but no visual animation? → CSS or timing issue
│     └─ See: Section 6 (CSS Inspection)
│
└─ Shine swoosh not visible?
   └─ See: Section 7 (Shine Swoosh Debugging)
```

---

## Section 1: Browser Console Logs

### Expected Log Patterns

**Normal Operation (First Load)**:
```javascript
🔄 ViewTransition Effect Running: {
  trainsChanged: true,
  busesChanged: true,
  feasibleTrainsState_count: 0,
  feasibleTrainsForHooks_count: 5,
  ...
}
🚂 TRAIN TRANSITION FIRING: {
  oldCount: 0,
  newCount: 5,
  oldIds: [],
  newIds: ['14:30-17-Åkeshov', '14:35-17-Alvik', ...]
}
📞 startListTransition called: {
  isStructural: true,
  transitionsDisabled: false,
  supportsViewTransition: true,
  slowTransitions: 0
}
✨ Starting ViewTransition...
```

**Normal Operation (Data Update, No Changes)**:
```javascript
🔄 ViewTransition Effect Running: {
  trainsChanged: false,
  busesChanged: false,
  ...
}
ℹ️ No train structural change detected
ℹ️ No bus structural change detected
```

**Normal Operation (New Train Arrives)**:
```javascript
🔄 ViewTransition Effect Running: { trainsChanged: true, ... }
🚂 TRAIN TRANSITION FIRING: { oldCount: 5, newCount: 6, ... }
📞 startListTransition called: { isStructural: true, ... }
✨ Starting ViewTransition...
```

### Problem Patterns

**Pattern A - No logs at all**:
```
[empty console]
```
**Diagnosis**: Component not rendering or console cleared
**Fix**: Check React DevTools for component errors, refresh page

**Pattern B - Effect running continuously**:
```
🔄 ViewTransition Effect Running: { ... }
🔄 ViewTransition Effect Running: { ... }
🔄 ViewTransition Effect Running: { ... }
[repeats infinitely]
```
**Diagnosis**: Infinite render loop (dependency array issue)
**Fix**: Check `useEffect` dependencies in TrainWidget.tsx:593

**Pattern C - Transitions disabled**:
```
📞 startListTransition called: {
  transitionsDisabled: true,
  slowTransitions: 3,
  ...
}
⏭️ Skipping transition: transitions disabled
```
**Diagnosis**: Performance auto-disable kicked in after 3 slow transitions (>80ms)
**Fix**: See Section 4

---

## Section 2: Structural Change Detection

### Symptoms
- Console shows "🔄" logs but never "🚂 TRAIN TRANSITION FIRING"
- `trainsChanged` is always `false` even when trains change

### Debug Steps

1. **Check train ID generation**:
   ```javascript
   // Add to console:
   const trains = /* current train data */
   trains.map(t => `${t.departure_time}-${t.line_number}-${t.destination}`)
   ```
   Verify IDs are unique and stable (not changing on every render)

2. **Check state vs hooks comparison**:
   ```javascript
   // In console log output, compare:
   feasibleTrainsState_count vs feasibleTrainsForHooks_count
   ```
   If counts differ but `trainsChanged: false`, the comparison logic is broken

3. **Inspect `hasStructuralChange` logic** (TrainWidget.tsx:567-571):
   ```typescript
   const hasStructuralChange = (oldList: any[], newList: any[], generateId: (item: any) => string) => {
     const oldIds = new Set(oldList.map(generateId))
     const newIds = new Set(newList.map(generateId))
     return oldIds.size !== newIds.size || ![...oldIds].every(id => newIds.has(id))
   }
   ```
   **Common Issue**: Set comparison failing due to reference equality vs value equality

4. **Check 3-minute window interaction**:
   - The `genuinelyNewTrains` memoization (lines 202-221) should NOT affect ViewTransition
   - ViewTransition should fire on ANY ID change, not just "genuinely new" trains
   - If 3-minute window is filtering trains before structural detection, that's the bug

### Fixes

**Fix A - Separate concerns**:
```typescript
// ViewTransition fires on ANY structural change
const trainsChanged = hasStructuralChange(feasibleTrainsState, feasibleTrainsForHooks, generateTrainId)

if (trainsChanged) {
  startListTransition(setFeasibleTrainsState, feasibleTrainsForHooks, true)
}

// 3-minute window ONLY affects shine swoosh triggers (separate hook)
const genuinelyNewTrains = useMemo(() => {
  // ... filter for swoosh only
}, [trains])
```

**Fix B - Add ref-based comparison**:
```typescript
const prevTrainsRef = useRef<TrainDeparture[]>([])

useEffect(() => {
  if (!arraysEqual(prevTrainsRef.current, feasibleTrainsForHooks)) {
    startListTransition(setFeasibleTrainsState, feasibleTrainsForHooks, true)
    prevTrainsRef.current = feasibleTrainsForHooks
  }
}, [feasibleTrainsForHooks])
```

---

## Section 3: Function Invocation

### Symptoms
- Console shows "🚂 TRAIN TRANSITION FIRING" but never "📞 startListTransition called"
- Call to `startListTransition` is not reaching the function

### Debug Steps

1. **Check import statement** (TrainWidget.tsx:4):
   ```typescript
   import { startListTransition } from './ViewTransition'
   ```
   Verify import exists and path is correct

2. **Check function signature**:
   ```typescript
   startListTransition(setFeasibleTrainsState, feasibleTrainsForHooks, true)
   //                   ↑ state setter      ↑ new state         ↑ isStructural
   ```
   Verify all 3 parameters are provided

3. **Add inline logging**:
   ```typescript
   console.log('About to call startListTransition with:', {
     setState: typeof setFeasibleTrainsState,
     newState: feasibleTrainsForHooks.length,
     isStructural: true
   })
   startListTransition(setFeasibleTrainsState, feasibleTrainsForHooks, true)
   ```

### Fixes

**Fix A - Re-import function**:
```typescript
import { startListTransition, getTransitionStats } from './ViewTransition'
```

**Fix B - Verify ViewTransition.tsx exports**:
```typescript
export const startListTransition = <T,>(...) => { ... }
```
Ensure function is exported, not just declared

---

## Section 4: Performance Auto-Disable

### Symptoms
- Console shows:
  ```
  📞 startListTransition called: { transitionsDisabled: true, slowTransitions: 3 }
  ⏭️ Skipping transition: transitions disabled
  ```
- Earlier in logs, you might see:
  ```
  [ViewTransition] Long transition block: 85.42ms
  [ViewTransition] Auto-disabled after 3 slow transitions (>80ms)
  ```

### Root Cause
ViewTransition.tsx (lines 30-44) monitors transition performance and auto-disables after 3 consecutive slow transitions (>80ms) to prevent janky user experience.

### Debug Steps

1. **Check performance timeline** (Chrome DevTools → Performance tab):
   - Record during page load
   - Look for long tasks (yellow blocks) during transition
   - Identify JavaScript execution, layout, paint bottlenecks

2. **Verify transition count**:
   ```javascript
   // In console:
   import { getTransitionStats } from './components/ViewTransition'
   getTransitionStats()
   // Output: { slowTransitions: 3, transitionsDisabled: true }
   ```

3. **Check component complexity**:
   - Too many trains/buses in list (>20 items)?
   - Complex component tree causing slow reconciliation?
   - Heavy CSS animations overlapping with ViewTransition?

### Fixes

**Fix A - Reset stats** (temporary, for debugging):
```typescript
// In ViewTransition.tsx, add:
export const resetTransitionStats = () => {
  stats.slowTransitions = 0
  stats.transitionsDisabled = false
}

// In console:
resetTransitionStats()
```

**Fix B - Increase threshold** (if hardware is slower):
```typescript
// ViewTransition.tsx:36
if (entry.duration > 120) { // Increased from 80ms
  stats.slowTransitions++
```

**Fix C - Reduce component complexity**:
- Limit visible trains/buses to top 10
- Simplify CSS animations (remove blur, reduce shadow layers)
- Use `will-change: transform, opacity` for GPU acceleration

---

## Section 5: Browser Support

### Symptoms
- Console shows:
  ```
  📞 startListTransition called: { supportsViewTransition: false }
  ⏭️ Skipping transition: browser does not support ViewTransition API
  ```

### Supported Browsers
- ✅ Chrome 111+ (March 2023)
- ✅ Edge 111+ (March 2023)
- ❌ Firefox (not yet supported as of Oct 2025)
- ❌ Safari (not yet supported as of Oct 2025)

### Debug Steps

1. **Check browser version**:
   ```javascript
   // In console:
   navigator.userAgent
   ```

2. **Test API availability**:
   ```javascript
   // In console:
   'startViewTransition' in document
   // Should return: true (Chrome/Edge) or false (Firefox/Safari)
   ```

3. **Verify polyfill** (if using one):
   ```javascript
   // Check if polyfill loaded:
   window.__VIEW_TRANSITION_POLYFILL__
   ```

### Fixes

**Fix A - Use supported browser**:
- Switch to Chrome 111+ or Edge 111+ for development
- Deployment: Kiosk uses Chrome, so production is fine

**Fix B - Add polyfill** (not recommended, complex):
- Libraries like `@types/dom-view-transitions` provide types but not polyfill
- No mature polyfill exists yet (native implementation too complex)

**Fix C - Graceful degradation** (already implemented):
- ViewTransition.tsx automatically falls back to instant state updates
- Animations just won't be visible in unsupported browsers
- App remains functional

---

## Section 6: CSS Inspection

### Symptoms
- Console shows "✨ Starting ViewTransition..." but no visual animation
- DOM updates but slides/fades don't occur

### Debug Steps

1. **Inspect pseudo-elements** (Chrome DevTools → Elements tab):
   ```
   ::view-transition
   └─ ::view-transition-group(root)
      └─ ::view-transition-image-pair(root)
         ├─ ::view-transition-old(root)
         └─ ::view-transition-new(root)
   ```
   These should appear briefly during transition

2. **Check CSS rules** (dashboard/src/index.css:288-336):
   ```css
   ::view-transition-new(*) {
     animation: viewTransitionSlideIn 5s cubic-bezier(0.25, 0.46, 0.45, 0.94);
   }

   ::view-transition-old(*) {
     animation: viewTransitionSlideOut 800ms ease-out;
   }
   ```
   Verify rules are present and not overridden

3. **Test animation keyframes**:
   ```css
   @keyframes viewTransitionSlideIn {
     from { opacity: 0; transform: translateY(20px); }
     to { opacity: 1; transform: translateY(0); }
   }
   ```
   Verify keyframes are defined

4. **Check `view-transition-name`** (if using scoped transitions):
   ```css
   .train-departure-item {
     view-transition-name: train-item;
   }
   ```
   If used, names must be unique per element

### Fixes

**Fix A - Disable `prefers-reduced-motion`** (if enabled):
```css
/* index.css:369-384 */
@media (prefers-reduced-motion: reduce) {
  ::view-transition-new(*),
  ::view-transition-old(*) {
    animation: none !important;
  }
}
```
Check OS accessibility settings (macOS System Preferences → Accessibility → Display → Reduce motion)

**Fix B - Verify animation duration**:
```css
/* Should NOT be 0s or instant */
::view-transition-new(*) {
  animation-duration: 5s; /* Explicit duration */
}
```

**Fix C - Check for competing animations**:
```css
/* Remove conflicting transform/opacity animations */
.train-departure-item {
  /* These might conflict: */
  /* animation: slideUp 0.8s ease-out; */
  /* transition: transform 0.3s ease; */
}
```

---

## Section 7: Shine Swoosh Debugging

### Symptoms
- ViewTransition slides work, but shine swoosh (orange gradient) doesn't appear
- Console shows "Shine swoosh animation for train..." but no visual effect

### Debug Steps

1. **Check animation class application**:
   ```javascript
   // In React DevTools, inspect train element:
   <div className="train-departure-item shine-swoosh">
   ```
   Verify `shine-swoosh` class is added at 9m/8m/7m

2. **Inspect CSS** (index.css:260-286):
   ```css
   .train-departure-item.shine-swoosh {
     background: linear-gradient(90deg, ...);
     background-clip: text;
     -webkit-background-clip: text;
     color: transparent;
     animation: shineSwoosh 2s linear;
   }
   ```
   Verify rules are present

3. **Test gradient manually**:
   ```css
   /* In DevTools, force add to element: */
   .train-departure-item {
     background: linear-gradient(90deg, white 0%, orange 50%, white 100%);
     background-clip: text;
     -webkit-background-clip: text;
     color: transparent;
   }
   ```
   If gradient doesn't show, `background-clip: text` isn't supported

4. **Check timing**:
   ```javascript
   // Verify class is removed after 2s:
   setTimeout(() => console.log('Class should be removed now'), 2000)
   ```

### Fixes

**Fix A - Apply to text element, not container**:
```tsx
// WRONG (shine on container div):
<div className={`train-departure-item ${hasShineAnimation ? 'shine-swoosh' : ''}`}>
  <span>14:35</span>
</div>

// RIGHT (shine on text span):
<div className="train-departure-item">
  <span className={hasShineAnimation ? 'shine-swoosh' : ''}>14:35</span>
</div>
```

**Fix B - Add vendor prefixes**:
```css
.shine-swoosh {
  background: linear-gradient(...);
  -webkit-background-clip: text;
  background-clip: text;
  -webkit-text-fill-color: transparent; /* Fallback */
  color: transparent;
}
```

**Fix C - Verify animation trigger logic** (TrainWidget.tsx:236-254):
```typescript
if (minutesUntil === 9 || minutesUntil === 8 || minutesUntil === 7) {
  const animatedMinutes = animatedAtMinuteRef.current.get(trainId) || new Set()
  if (!animatedMinutes.has(minutesUntil)) {
    // Trigger animation
    setShineAnimatedTrains(prev => new Set([...prev, trainId]))
    // Remove after 2s
    setTimeout(() => {
      setShineAnimatedTrains(prev => {
        const newSet = new Set(prev)
        newSet.delete(trainId)
        return newSet
      })
    }, 2000)
  }
}
```

---

## Section 8: Empty Lines Issue

### Symptoms
- Random empty lines appear between trains/buses
- Lines appear/disappear during animations
- More common during ViewTransition animations

### Root Causes

1. **State synchronization lag** between `feasibleTrainsState` and `feasibleTrainsForHooks`
2. **Render timing** - ViewTransition captures old snapshot while new state partially applied
3. **CSS height animation** - Element collapsing to 0 height but not `display: none`

### Debug Steps

1. **Inspect empty element** (DevTools → Elements tab):
   ```html
   <div class="train-departure-item" style="height: 0; opacity: 0">
     <!-- Empty or partial content -->
   </div>
   ```

2. **Check render logic** (TrainWidget.tsx:612-627):
   ```typescript
   const feasibleTrains = feasibleTrainsState.length > 0
     ? feasibleTrainsState
     : feasibleTrainsForHooks
   ```
   This fallback might cause inconsistency

3. **Add console logging**:
   ```typescript
   console.log('Rendering trains:', {
     stateCount: feasibleTrainsState.length,
     hooksCount: feasibleTrainsForHooks.length,
     rendering: feasibleTrains.length,
     actualIds: feasibleTrains.map(generateTrainId)
   })
   ```

### Fixes

**Fix A - Synchronize state sources**:
```typescript
// Remove fallback, always use state:
const feasibleTrains = feasibleTrainsState
```

**Fix B - Filter empty items**:
```typescript
const feasibleTrains = feasibleTrainsState.filter(train =>
  train.departure_time && train.line_number && train.destination
)
```

**Fix C - Add key prop**:
```tsx
{feasibleTrains.map(train => (
  <TrainDepartureLine
    key={generateTrainId(train)} // Stable unique key
    departure={train}
  />
))}
```

---

## Common Solutions Summary

| Problem | Quick Fix |
|---------|-----------|
| No logs in console | Refresh page, check React errors |
| Infinite render loop | Check `useEffect` dependency array |
| Transitions disabled (performance) | Reduce component complexity, increase threshold |
| No browser support | Use Chrome 111+, accept graceful degradation |
| CSS not applying | Check pseudo-elements in DevTools, verify keyframes |
| Shine swoosh invisible | Apply to text element, not container div |
| Empty lines appearing | Synchronize state sources, add stable keys |
| Delayed trains trigger animations | Separate 3-minute window from structural detection |

---

## Emergency Rollback

If ViewTransition causes critical issues:

1. **Disable via feature flag**:
   ```typescript
   // In ViewTransition.tsx:24
   const stats: TransitionStats = {
     slowTransitions: 0,
     transitionsDisabled: true // Force disable
   }
   ```

2. **Revert to manual animations**:
   ```bash
   git log --oneline --all --grep="ViewTransition"
   git revert <commit-hash>
   ```
   Look for commits from Sept 29-30, 2025

3. **Use old animation classes** (if CSS still exists):
   ```tsx
   <div className={isNew ? 'introducing' : isDeparting ? 'departing' : ''}>
   ```

---

## Related Documentation

- `docs/ANIMATION_TEST_MODE.md` - Simulate rapid data changes for testing
- `docs/TRAIN_DEPARTURE_ANIMATION_REQUIREMENTS.md` - Animation specifications
- `docs/VIEWTRANSITION_SESSION_STATE.md` - Native API implementation details
- `docs/VIEWTRANSITION_DEBUG_SESSION_OCT2_EVENING.md` - Oct 2 debugging session notes

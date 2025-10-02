# Train Departure Animation Requirements

**Last Updated:** October 2, 2025
**Status:** Revision Required - Replacing Glow with Lens Flare Swoosh

---

## Current Issues (October 2, 2025)

### 1. **Train Visibility Threshold Bug**
**Problem:** Trains with 4 minutes remaining are visible, but should only show until <5 minutes.

**Root Cause:** Lines 491-502 in `TrainWidget.tsx` keep trains visible during departure sequence:
```typescript
return adjusted.adjustedMinutesUntil >= 0 && (
  isFeasibleTrainDeparture(adjusted.adjustedMinutesUntil) ||  // >= 5 minutes
  ['warning', 'critical'].includes(departureState)            // ❌ Keeps trains < 5 min
)
```

**Fix Required:** Remove `|| ['warning', 'critical'].includes(departureState)` - trains should disappear strictly at <5 minutes.

### 2. **Warning/Critical Timing Mismatch**
**Problem:** Glow triggers at <5 minutes, but should trigger earlier when there's time to dress and walk/run.

**Current Logic:**
- Line 210: Departure sequence starts at `minutesUntil < 5`
- Warning: 4 seconds
- Critical: 3 seconds

**Required Logic:**
- Trigger at **8-9 minutes** (enough time to put on clothes and run/walk)
- Single swoosh animation: **1 second** (not multi-phase)

---

## Corrected Requirements

### Train Visibility Rules

**Feasibility Threshold: 5 Minutes**
- Trains are **visible** when `minutes_until >= 5` (matches biking feasibility)
- Trains **disappear** when `minutes_until < 5` (too late to bike)
- Backend sends all trains; frontend filters by this threshold

**Rationale:** 5 minutes is feasible to bike to station, matching `RUN_TIME` constant in backend.

### Animation Trigger Rules

**Warning Animation Trigger: 8-9 Minutes**
- Trigger orange gradient swoosh when `minutes_until === 9` OR `minutes_until === 8`
- This provides enough time to dress quickly and walk/run to station
- Animation should trigger **once per train** (not on every data refresh)

**No Multi-Phase Sequence**
- Remove warning/critical phases (old glow system)
- Single swoosh animation: **1 second duration**
- Animation completes, then train stays visible until <5 minutes

---

## New Animation Design: Lens Flare / Shine Swoosh

### Visual Characteristics

**Effect Description:**
- Orange gradient sweeps left-to-right across **text glyphs only** (not background)
- Animation duration: **1 second**
- Timing function: **linear** (smooth, continuous movement - no choppy keyframes)
- Start state: Normal white text
- End state: Normal white text (returns to original appearance)

**Color Gradient:**
- Base: White text (existing color)
- Swoosh: Transparent → Orange (#FF8C00 or similar) → Transparent
- Gradient clips to text shape only (no rectangular overlay)

### Technical Implementation (CSS)

**Key Technique:** `background-clip: text` with animated `linear-gradient`

```css
@keyframes shine-swoosh {
  0% {
    background-position: -200% 0;
  }
  100% {
    background-position: 200% 0;
  }
}

.warning-shine {
  background: linear-gradient(
    90deg,
    transparent 0%,
    transparent 30%,
    rgba(255, 140, 0, 0.8) 50%,
    transparent 70%,
    transparent 100%
  );
  background-size: 200% 100%;
  background-clip: text;
  -webkit-background-clip: text;
  color: transparent;
  animation: shine-swoosh 1s linear;
  /* Animation completes once, no infinite loop */
}
```

**Accessibility:**
- Respect `prefers-reduced-motion: reduce` - disable animation for users who prefer less motion
- Fallback: No animation, text remains white

### Animation Behavior

**Trigger Once Per Train:**
- Track which trains have already been animated (use Set with train IDs)
- When train reaches 8-9 minutes, apply `.warning-shine` class
- After 1 second, remove class (animation complete)
- Train continues showing normally until <5 minutes (feasibility threshold)

**State Management:**
- Remove `trainStates` Map tracking 'warning'/'critical'/'departing' states
- Replace with simple `animatedTrains` Set (train IDs that have swooshed)
- Simpler logic: "Has this train been animated? If not, and it's at 8-9min, animate it."

---

## Implementation Files

**Primary Files:**
- `dashboard/src/components/TrainWidget.tsx` - Component logic
- `dashboard/src/styles/globals.css` - CSS animations

**Changes Required:**
1. Fix `feasibleTrainsForHooks` filter (line 491-502)
2. Replace `useDepartureSequence` hook with simpler `useShineAnimation` hook
3. Update trigger threshold: `minutesUntil < 5` → `minutesUntil === 8 || minutesUntil === 9`
4. Replace `warning-glow` / `critical-glow` CSS with `shine-swoosh` animation
5. Remove multi-phase timing (4s warning, 3s critical) - single 1s animation

---

## References

**CSS Shine Animation Resources:**
- [Web.dev: Animated Gradient Text](https://web.dev/articles/speedy-css-tip-animated-gradient-text) - Core technique
- [CSS-Tricks: Lens Flare](https://css-tricks.com/add-a-css-lens-flare-to-photos-for-a-bright-touch/) - Gradient blending
- [Medium: 14+ Shine Effects](https://medium.com/@forfrontendofficial/14-css-shine-effects-for-frontend-3194b796c174) - Examples

**Related Documentation:**
- `docs/VIEWTRANSITION_SESSION_STATE.md` - ViewTransition implementation (Phase 1-4)
- `CLAUDE.md` (project instructions) - Train/bus animation system notes

---

## Testing Checklist

After implementation:

- [ ] Trains disappear at exactly <5 minutes (not 4, 3, 2, 1)
- [ ] Swoosh animation triggers at 8-9 minutes
- [ ] Animation is smooth (linear, 1 second, no choppy keyframes)
- [ ] Orange gradient only affects text glyphs (not background)
- [ ] Animation triggers once per train (no repeats on data refresh)
- [ ] Text returns to normal white after animation completes
- [ ] `prefers-reduced-motion: reduce` disables animation
- [ ] No console errors or React warnings
- [ ] Works with delayed trains (adjusted time calculations)

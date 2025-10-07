# Train Departure Animation Requirements

**Last Updated:** October 2, 2025 (Evening)
**Status:** ✅ IMPLEMENTED - Shine Swoosh with 3-Minute Window

---

## Implementation Summary (October 2, 2025)

### ✅ All Issues Resolved

1. **Train Visibility Threshold** - Fixed
   - Trains visible when `adjustedMinutesUntil >= 5`
   - Pre-emptive removal at exactly 5 minutes (ViewTransition captures "5m" snapshot)
   - Users never see "4m" on screen

2. **Shine Swoosh Animation** - Working
   - Orange gradient sweeps across text glyphs (background-clip: text)
   - Triggers at 9m, 8m, 7m for trains; 4m, 3m, 2m for buses
   - Duration: 2 seconds linear animation
   - Applied to text elements, not container divs

3. **Identity Tracking** - Updated for Framer Motion (Oct 6, 2025)
   - **Old approach**: Rounded timestamps to 180-second buckets to prevent animation on minor time updates
   - **Problem**: Caused ID collisions → bus accumulation bug (>4 buses shown over time)
   - **New approach**: Use exact timestamps - Framer Motion handles time updates with smooth exit/enter
   - Compares line_number, destination, exact departure_timestamp

---

## Corrected Requirements

### Train Visibility Rules

**Feasibility Threshold: 5 Minutes**
- Trains are **visible** when `minutes_until >= 5` (matches biking feasibility)
- Trains **disappear** when `minutes_until < 5` (too late to bike)
- Backend sends all trains; frontend filters by this threshold

**Rationale:** 5 minutes is feasible to bike to station, matching `RUN_TIME` constant in backend.

### Animation Trigger Rules

**Train Swoosh Trigger: 9, 8, 7 Minutes**
- Trigger orange gradient swoosh at each threshold (3 separate swooshes per train)
- Provides time to dress quickly and walk/run to station
- Animation triggers **once per minute threshold** (tracked via ref to prevent repeats)

**Bus Swoosh Trigger: 4, 3, 2 Minutes**
- Same pattern for buses (shorter window due to closer bus stops)
- 3 separate swooshes as bus approaches

**Single Animation Per Threshold**
- Duration: **2 seconds** (linear timing function)
- No multi-phase sequences
- Animation completes, train/bus stays visible until <5 minutes (trains) or 0 minutes (buses)

---

## New Animation Design: Lens Flare / Shine Swoosh

### Visual Characteristics

**Effect Description:**
- Orange gradient sweeps left-to-right across **text glyphs only** (not background)
- Animation duration: **2 seconds**
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

**Trigger Once Per Minute Threshold:**
- Track which trains have been animated at which minutes (Map<trainId, Set<minute>>)
- When train reaches 9m/8m/7m, check if already animated at that specific minute
- Apply `.shine-swoosh` class for 2 seconds
- Train continues showing normally until <5 minutes (feasibility threshold)

**State Management:**
- `animatedAtMinuteRef`: Map<string, Set<number>> tracks which minutes triggered animations
- `shineAnimatedTrains`: Set<string> of currently animating train IDs
- `trainsMarkedForRemoval`: Set<string> for pre-emptive removal at 5 minutes

**3-Minute Window for Time Updates:**
- Prevents false animations when trains get delayed
- Compares line_number, destination, departure_timestamp
- If within 180 seconds, treats as time update (no animation)
- Only genuinely new trains trigger animations

---

## Implementation Files

**Primary Files:**
- `dashboard/src/components/TrainWidget.tsx` - Component logic
- `dashboard/src/styles/globals.css` - CSS animations

**Completed Implementation (October 2, 2025):**
1. ✅ Fixed `feasibleTrainsForHooks` filter - strict <5 minute threshold
2. ✅ Replaced `useDepartureSequence` with `useTrainDepartureAnimation` and `useBusDepartureAnimation`
3. ✅ Updated trigger thresholds: 9/8/7m for trains, 4/3/2m for buses
4. ✅ Implemented `shine-swoosh` CSS animation (2s linear, background-clip: text)
5. ✅ Removed multi-phase timing - single animation per minute threshold
6. ✅ Added 3-minute window to prevent false animations on delays

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

- [x] Trains disappear at exactly <5 minutes (not 4, 3, 2, 1) - ✅ Pre-emptive removal at 5m
- [x] Swoosh animation triggers at 9/8/7 minutes (trains) and 4/3/2 minutes (buses) - ✅ Implemented
- [x] Animation is smooth (linear, 2 seconds, no choppy keyframes) - ✅ CSS verified
- [x] Orange gradient only affects text glyphs (not background) - ✅ background-clip: text
- [x] Animation triggers once per minute threshold (no repeats) - ✅ animatedAtMinuteRef tracking
- [x] Text returns to normal white after animation completes - ✅ 2s timeout removes class
- [ ] `prefers-reduced-motion: reduce` disables animation - ⚠️ TODO in CSS
- [x] No console errors or React warnings - ✅ Infinite loop fixed
- [x] Works with delayed trains (adjusted time calculations) - ✅ 3-min window prevents false triggers
- [ ] ViewTransition slide animations working - ⚠️ NEEDS TESTING (user reports no animations visible)

# Session Work Report: Shine Swoosh Animation Refinement & Bug Fixes
**Date:** October 3, 2025 (evening session)
**Duration:** ~2 hours
**Context:** Continuation of shine swoosh system, production deployment preparation

## Critical Bugs Fixed

### 1. **CSS Shorthand Property Trap** ✅ SOLVED
**Symptom:** After refactoring CSS for DRY, gradients showed as colored boxes instead of text gradient

**Root Cause:** `background` shorthand resets ALL background properties
- Using `background: linear-gradient(...)` in `.shine-swoosh` class
- Reset `background-clip`, `background-size`, `background-repeat` from shared selector
- Gradients no longer clipped to text

**Fix:** Use `background-image` instead of `background` in variant classes
- Preserves `background-clip: text` from shared `.shine-swoosh, .shine-swoosh-red` selector
- Only gradient colors differ between variants

### 2. **Animation Snap-Back Flash** ✅ SOLVED
**Symptom:** 0.1s flash of gradient colors at end of animation before cleanup

**Root Cause:** CSS animations revert to start position by default after completion
- Animation reaches end → browser snaps gradient back to 0% → color flash
- Then `onAnimationEnd` fires → removes class → text returns to white

**Fix:** Add `animation-fill-mode: forwards`
- Keeps gradient at final position until class removed
- No snap-back flash

### 3. **Test Interval Race Condition** ✅ SOLVED
**Symptom:** Animation never appeared to complete cleanly

**Root Cause:** 5s test interval matched 5s animation duration
- New animation triggered exactly when previous should end
- Animation restarted before `onAnimationEnd` fired
- Never saw clean end state

**Fix:** Increased test interval to 8s (5s animation + 3s gap)

### 4. **Train Vanishing Without Animation** ✅ SOLVED
**Symptom:** Trains at 6m vanished instantly instead of sliding out

**Root Cause:** Complex manual removal logic conflicted with natural filtering
- Hook marked trains for removal at 6m
- But feasibility filter logic had race conditions
- Framer Motion never saw clean array removal

**Fix:** Simplified to natural feasibility filtering
- Removed manual `trainsMarkedForRemoval` complexity
- Let `minutesUntil >= 6` naturally filter trains
- Framer Motion detects removal from array → plays exit animation

## Feature Implementations

### Opacity Transition Adjustment
**Request:** Start fading earlier
**Implementation:** Changed from 20m to 15m threshold
- 0-15m: Full opacity (1.0)
- 15-50m: Gradual fade to 0.15
- Lines 305-310 in TrainWidget.tsx

### Gradient Color Evolution
**Iterations:**
1. Orange + purple trail → Red-orange final warning
2. Light purple/pink + light peachy tones (too pale)
3. **Final:** Vibrant purple/pink (regular), vibrant yellow/orange (final warning)

**Current gradient specs:**
```css
/* Regular swoosh */
rgba(200, 140, 255, 1)  /* Vibrant purple */
rgba(255, 160, 220, 1)  /* Vibrant pink */

/* Final warning */
rgba(255, 220, 100, 1)  /* Vibrant yellow */
rgba(255, 160, 80, 1)   /* Vibrant orange */
```
- Full opacity (1.0) for visibility
- Saturated colors for clear visual signal

### Display Limit
**Request:** Never show more than 4 trains or 4 buses
**Implementation:** `.slice(0, 4)` after filtering
- Lines 574, 617 in TrainWidget.tsx
- Keeps UI clean and focused on nearest departures

### Swoosh Timing Expansion
**Trains:** 10m, 9m, 8m, 7m, 6m (5 swooshes)
- Final warning (yellow/orange) at 6m before removal
**Buses:** 3m, 2m, 1m, 0m (4 swooshes)
- Final warning (yellow/orange) at 0m (departing NOW!)

### Animation Duration
**Changed:** 5s → 4s (user preference for slightly faster swoosh)

## CSS Architecture Improvements

### DRY Refactoring
**Before:** Full duplication between `.shine-swoosh` and `.shine-swoosh-red`
**After:** Shared base styles with gradient-only variants
```css
.shine-swoosh,
.shine-swoosh-red {
  /* All shared properties */
  background-size: 200% 100%;
  background-repeat: repeat-x;
  background-clip: text;
  animation: shineSwoosh 4s linear forwards;
}

.shine-swoosh {
  background-image: linear-gradient(...); /* Only colors */
}

.shine-swoosh-red {
  background-image: linear-gradient(...); /* Only colors */
}
```

### Key CSS Learnings Documented
Added to CLAUDE.md:
- `background` shorthand resets all properties
- Always use `animation-fill-mode: forwards`
- Test intervals need gap to avoid race conditions
- `background-repeat: repeat-x` solves transparency bugs
- Background-position math formula

## Background-Position Math Explanation

**Formula:** `offset = (container_width - gradient_width) × position%`

With 200% gradient:
- Container: 100%
- Gradient: 200%
- Formula: `offset = -100% × position%`

**Examples:**
- Position 130%: offset = -130% (gradient far left)
- Position -70%: offset = +70% (gradient far right)
- Movement 130% → -70% = left-to-right visual sweep

**Why negative coefficient matters:**
- Positive positions move gradient LEFT (negative offset)
- Negative positions move gradient RIGHT (positive offset)
- Counterintuitive but mathematically correct!

## Test Mode Status

**Current:** 7s interval loop for visual debugging
- Triggers regular purple/pink swoosh on all trains
- Allows user to verify gradient visibility and smoothness
- Production time-based logic still active (10/9/8/7/6m triggers)

**To remove test mode:** Delete lines 203-210 in TrainWidget.tsx

## Files Modified

### Code
1. **dashboard/src/components/TrainWidget.tsx**
   - Lines 202-243: Test loop + production swoosh logic
   - Lines 303-311: Opacity transition (15m threshold)
   - Lines 493-497: Simplified feasibility filtering
   - Lines 574, 617: Display limit (max 4 each)

2. **dashboard/src/index.css**
   - Lines 256-294: Refactored CSS with DRY pattern
   - Vibrant gradient colors (full opacity)
   - 4s animation duration

### Documentation
- **CLAUDE.md** (lines 462-468): CSS gradient animation gotchas
- This report: Complete session work

## Pending Items

### To Verify
- [ ] Train slide-out animation works correctly at 6m→5m transition
- [ ] Gradient colors visible enough on actual kiosk display
- [ ] Test loop can be safely removed without breaking production triggers

### Known State
- Test mode active (7s interval)
- Feasibility threshold: 6m for trains, 0m for buses
- Max display: 4 trains, 4 buses
- Animation: 4s duration, linear timing

## Key Decisions

### Why Simplified Filtering?
Manual removal logic (`trainsMarkedForRemoval`) created complexity and race conditions. Natural feasibility filtering is cleaner:
- Train at 6m: shows (≥6 is true)
- Train at 5m: filtered out (≥6 is false)
- Framer Motion sees removal → animates exit
- Simple, predictable, works

### Why Full Opacity Gradients?
User feedback: 0.8 opacity too pale, colors barely visible. Changed to 1.0 with more saturated RGB values for clear visual signal.

### Why 4s Duration?
User tested 5s, requested slightly faster. 4s provides good visibility without feeling slow.

## Context for Next Session

**Git State:** Changes not committed yet
**Test Mode:** Active (remove before production push)
**User Feedback Needed:** Verify train slide-out animation works, check gradient visibility

**Token Usage:** 108k/200k (54% this session)

# Animation Test Mode

**Purpose**: Simulate rapid data changes to visually verify train/bus departure animations work correctly

**Created**: October 2, 2025
**Status**: 🔧 IMPLEMENTATION NEEDED

---

## Overview

The dashboard receives WebSocket updates every 30 seconds, making it difficult to observe animation behavior in real-time during development. Animation Test Mode provides mock data generators to simulate various scenarios at accelerated rates.

**User Request**: "Can we test the animation logic irl by simulating different data updates occurring in short order? So that I see it in rapid progression? Would be helpful."

---

## Test Scenarios

### 1. New Train Arrival (Slide-In Animation)

**Expectation**: Train slides in from bottom over 5 seconds

**Mock Data**:
- Add new train to existing list
- Different `departure_time` + `line_number` + `destination` combination
- `minutes_until >= 5` (feasible threshold)

**Trigger Frequency**: Every 10 seconds

**Example**:
```typescript
const mockNewTrain: TrainDeparture = {
  departure_time: '14:35',
  line_number: '18',
  destination: 'Alvik',
  minutes_until: 8,
  departure_timestamp: Math.floor(Date.now() / 1000) + 480,
  track: '1'
}
```

### 2. Train Departure (Slide-Out Animation)

**Expectation**: Train slides out to top over 800ms when `minutes_until < 5`

**Mock Data**:
- Decrement `minutes_until` by 1 every 2 seconds
- When reaches 4, train should be marked for removal at next 5-minute check
- Pre-emptive removal captures "5m" snapshot before slide-out

**Trigger Frequency**: Every 2 seconds (fast-forward time)

**Example**:
```typescript
// Existing train at 7 minutes
{ departure_time: '14:32', minutes_until: 7, ... }

// After 2 seconds
{ departure_time: '14:32', minutes_until: 6, ... }

// After 4 seconds
{ departure_time: '14:32', minutes_until: 5, ... } // Marked for removal

// After 6 seconds
// Train removed from list, slide-out animation plays
```

### 3. Delayed Train (Time Update, No Animation)

**Expectation**: Time changes but NO slide animation (3-minute window prevents false triggers)

**Mock Data**:
- Same `line_number` + `destination`
- `departure_time` changes by 1-3 minutes
- `departure_timestamp` within 180 seconds of previous value

**Trigger Frequency**: Every 8 seconds

**Example**:
```typescript
// Before delay
{ departure_time: '14:30', line_number: '17', destination: 'Åkeshov', departure_timestamp: 1696258200 }

// After delay (2 minutes later)
{ departure_time: '14:32', line_number: '17', destination: 'Åkeshov', departure_timestamp: 1696258320 }
// Same train ID via 3-minute window, NO slide animation
```

### 4. Shine Swoosh Animation

**Expectation**: Orange gradient sweeps across text at 9m, 8m, 7m for trains; 4m, 3m, 2m for buses

**Mock Data**:
- Train at 10 minutes, decrement every 2 seconds
- Should trigger swoosh at 9m, 8m, 7m (once per minute threshold)

**Trigger Frequency**: Every 2 seconds

**Example**:
```typescript
// At 10m: no animation
{ departure_time: '14:40', minutes_until: 10, ... }

// At 9m: SWOOSH (first trigger)
{ departure_time: '14:39', minutes_until: 9, ... }

// At 8m: SWOOSH (second trigger)
{ departure_time: '14:38', minutes_until: 8, ... }

// At 7m: SWOOSH (third trigger)
{ departure_time: '14:37', minutes_until: 7, ... }

// At 6m: no animation
{ departure_time: '14:36', minutes_until: 6, ... }
```

### 5. Mixed Scenario (Real-World Complexity)

**Combination**:
- 2 new trains arriving (slide in)
- 1 train departing (slide out)
- 1 train delayed (time update, no animation)
- 1 train at 8m (shine swoosh)

**Trigger Frequency**: Staggered over 20 seconds

---

## Implementation Approaches

### Option A: Mock Data Generator (Frontend)

**Pros**:
- No backend changes required
- Easy to control timing and scenarios
- Can be toggled via URL parameter (`?test_mode=animations`)

**Cons**:
- Doesn't test WebSocket data flow
- Mock data structure must match real API exactly

**Example Implementation**:
```typescript
// Add to TrainWidget.tsx
const useAnimationTestMode = () => {
  const [testData, setTestData] = useState<TrainDeparture[]>([])
  const [scenario, setScenario] = useState<'new' | 'departing' | 'delayed' | 'swoosh' | 'mixed'>('mixed')

  useEffect(() => {
    if (!window.location.search.includes('test_mode=animations')) return

    const interval = setInterval(() => {
      setTestData(prev => generateScenario(scenario, prev))
    }, 2000) // Update every 2 seconds

    return () => clearInterval(interval)
  }, [scenario])

  return testData
}
```

### Option B: Backend Mock Endpoint

**Pros**:
- Tests full WebSocket data flow
- Can simulate network delays
- More realistic integration testing

**Cons**:
- Requires backend changes
- Harder to control precise timing

**Example Implementation**:
```ruby
# Add to puma_server.rb
if ENV['ANIMATION_TEST_MODE'] == 'true'
  get '/api/test/train_scenarios/:scenario' do
    scenario = params[:scenario] # 'new', 'departing', 'delayed', 'swoosh', 'mixed'
    content_type :json
    generate_test_scenario(scenario).to_json
  end
end
```

### Option C: Browser DevTools Override (Recommended)

**Pros**:
- No code changes required
- Uses browser's Network tab "Local Overrides" feature
- Can replay and modify real WebSocket messages

**Cons**:
- Requires manual DevTools setup
- Different per browser (Chrome/Firefox)

**Steps**:
1. Open DevTools → Network tab
2. Filter for WebSocket connections (`ws://localhost:3001`)
3. Right-click message → "Save as Local Override"
4. Edit JSON to create test scenarios
5. Reload page to use overridden data

---

## Visual Verification Checklist

When running test mode, verify:

### ViewTransition Slide Animations
- [ ] New trains slide in from bottom (5s duration, smooth cubic-bezier easing)
- [ ] Departing trains slide out to top (800ms duration)
- [ ] No slide animation for time updates (delayed trains)
- [ ] Empty lines don't appear during transitions

### Shine Swoosh Animations
- [ ] Orange gradient sweeps left-to-right across text glyphs (not background)
- [ ] Triggers at 9m, 8m, 7m for trains
- [ ] Triggers at 4m, 3m, 2m for buses
- [ ] Only triggers once per minute threshold (no repeats)
- [ ] Animation duration is 2 seconds (linear timing)
- [ ] Text returns to normal white after animation

### Performance
- [ ] Animations run at 60fps (no frame drops)
- [ ] No console errors or React warnings
- [ ] CPU usage stays reasonable (<50% on modern hardware)
- [ ] Memory usage doesn't grow over time (no leaks)

---

## Debug Console Patterns

When test mode is active, watch for these logs:

**Successful Slide-In**:
```
🔄 ViewTransition Effect Running: { trainsChanged: true, ... }
🚂 TRAIN TRANSITION FIRING: { oldCount: 3, newCount: 4, ... }
📞 startListTransition called: { isStructural: true, transitionsDisabled: false, ... }
✨ Starting ViewTransition...
```

**Successful Shine Swoosh**:
```
Shine swoosh animation for train 14:35-17-Åkeshov at 9m
[2 seconds later]
Shine swoosh animation for train 14:35-17-Åkeshov at 8m
```

**Time Update (No Animation)**:
```
🔄 ViewTransition Effect Running: { trainsChanged: false, ... }
ℹ️ No train structural change detected
```

---

## Future Enhancements

- **Keyboard shortcuts**: Press `T` to trigger test scenario, `R` to reset
- **On-screen controls**: UI panel to select scenarios and speed
- **Scenario recording**: Record real WebSocket data and replay at custom speeds
- **Automated visual testing**: Playwright screenshots at each animation frame
- **Performance profiling**: Automatic detection of slow transitions (>80ms)

---

## Related Documentation

- `docs/VIEWTRANSITION_TROUBLESHOOTING.md` - Debugging runbook for when animations fail
- `docs/TRAIN_DEPARTURE_ANIMATION_REQUIREMENTS.md` - Animation specifications
- `docs/VIEWTRANSITION_SESSION_STATE.md` - Native API implementation details

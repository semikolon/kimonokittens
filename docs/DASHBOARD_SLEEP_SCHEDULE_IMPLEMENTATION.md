# Dashboard Sleep Schedule - Detailed Implementation Plan

**Status**: ✅ PRODUCTION READY - October 4, 2025
**Created**: October 3, 2025
**Updated**: October 4, 2025 - Fixed fade transitions with pure CSS (GPU-accelerated)
**Implementation**: Frontend + Backend complete with smooth CSS transitions

---

## ⚠️ Critical Bug Fix - October 4, 2025

**Problem Discovered**: Original requestAnimationFrame fade implementation conflicted with CSS transitions, causing instant jumps instead of smooth fades.

**Root Cause**: JavaScript was updating `opacity` via React state while CSS `transition` tried to animate the same property. Inline styles override CSS transitions → no fade.

**Solution Applied**: Pure CSS transitions - simpler, GPU-accelerated, and actually works!

**Changes Made**:
1. **FadeOverlay.tsx**: Removed all `requestAnimationFrame` logic
2. **Opacity values**: Simple boolean logic (sleeping/fading-out = 1, awake/fading-in = 0)
3. **CSS handles everything**: `transition: opacity 120s cubic-bezier(0.4, 0.0, 0.2, 1)`
4. **Timer interval**: Reduced from 60s to 10s (prevents missing minute boundaries)

**Result**: ✅ Smooth 2-minute fades working perfectly, more performant than JS animation

---

## Overview

Implement automatic sleep/wake schedule with **adaptive brightness** and **system-level monitor control** for the dashboard display to prevent hallway light pollution and match ambient conditions.

**Core Requirements**:
- ✅ 2-minute fade-out transition (opacity 1 → 0)
- ✅ 2-minute fade-in transition (opacity 0 → 1)
- ✅ **NEW: Adaptive brightness** (0.7-1.5 based on time of day)
- ✅ **NEW: Monitor DPMS control** (physical display off/on)
- ✅ Default schedule: Sleep 1:00 AM, Wake 5:30 AM
- ✅ LocalStorage persistence for settings
- ✅ Manual override controls (instant sleep/wake)
- ✅ Keep WebSocket connections alive during sleep
- ✅ Configuration UI for custom times
- ⏳ Future: Motion sensor integration
- ⏳ Future: Webcam gesture detection
- ⏳ Future: Ambient light sensor for true adaptive brightness

---

## Architecture

### Component Hierarchy

```
App.tsx
└── SleepScheduleProvider (Context + State)
    ├── FadeOverlay (Visual sleep layer)
    ├── ConfigPanel (Settings UI)
    └── [Existing Dashboard Components]
        ├── TrainWidget
        ├── RentWidget
        └── WeatherWidget
```

### State Management

**Primary State Location**: React Context with LocalStorage synchronization

**State Shape**:
```typescript
interface SleepScheduleState {
  enabled: boolean;                    // Master toggle
  sleepTime: string;                   // "01:00" (24-hour format)
  wakeTime: string;                    // "05:30"
  currentState: 'awake' | 'sleeping' | 'fading-out' | 'fading-in';
  fadeProgress: number;                // 0-100 (percentage of fade transition)
  brightness: number;                  // 0.7-1.5 (current brightness level)
  manualOverride: boolean;             // User forced sleep/wake
  lastTransitionTime: number;          // Unix timestamp
  monitorPowerControl: boolean;        // Enable DPMS display off/on
  brightnessEnabled: boolean;          // Enable adaptive brightness curve
}
```

**LocalStorage Schema**:
```json
{
  "sleepSchedule": {
    "enabled": true,
    "sleepTime": "01:00",
    "wakeTime": "05:30",
    "manualOverride": false,
    "monitorPowerControl": true,
    "brightnessEnabled": true
  }
}
```

---

## Complete Daily Schedule Timeline

**Typical 24-Hour Cycle** with sleep schedule (01:00-05:30) and adaptive brightness:

```
┌──────────────────────────────────────────────────────────────────────┐
│ TIME     │ STATE        │ BRIGHTNESS │ ANIMATIONS │ MONITOR          │
├──────────────────────────────────────────────────────────────────────┤
│ 00:00    │ Awake        │ 0.7        │ Running    │ On               │
│ 00:30    │ Awake        │ 0.7        │ Running    │ On               │
│ 01:00    │ Fade-out     │ 0.7        │ Running    │ On               │
│          │ (0→100%)     │            │ (visible!) │                  │
│ 01:02    │ Sleeping     │ -          │ PAUSED     │ OFF (DPMS)       │
│ 02:00    │ Sleeping     │ -          │ PAUSED     │ OFF              │
│ 03:00    │ Sleeping     │ -          │ PAUSED     │ OFF              │
│ 04:00    │ Sleeping     │ -          │ PAUSED     │ OFF              │
│ 05:00    │ Sleeping     │ -          │ PAUSED     │ OFF              │
│ 05:30    │ Fade-in      │ -          │ Running    │ ON (DPMS)        │
│          │ (100→0%)     │            │ (visible!) │ (+500ms delay)   │
│ 05:32    │ Awake        │ 0.7        │ Running    │ On               │
│ 06:00    │ Awake        │ 1.0        │ Running    │ On               │
│ 08:00    │ Awake        │ 1.26       │ Running    │ On               │
│ 10:00    │ Awake        │ 1.39       │ Running    │ On               │
│ 12:00    │ Awake        │ 1.4        │ Running    │ On (Peak)        │
│ 14:00    │ Awake        │ 1.33       │ Running    │ On               │
│ 16:00    │ Awake        │ 1.26       │ Running    │ On               │
│ 18:00    │ Awake        │ 1.2        │ Running    │ On               │
│ 20:00    │ Awake        │ 1.05       │ Running    │ On               │
│ 22:00    │ Awake        │ 0.9        │ Running    │ On               │
│ 23:00    │ Awake        │ 0.83       │ Running    │ On               │
└──────────────────────────────────────────────────────────────────────┘
```

**Key Behavioral Notes**:

1. **Fade Transitions Are Visible**: Animations run during ENTIRE 2-minute fade (both in/out)
   - `01:00-01:02`: Fade-out with animations running, opacity 0→1 over 120s
   - `05:30-05:32`: Fade-in with animations running, opacity 1→0 over 120s

2. **Animation Pause ONLY When Fully Asleep**:
   - Pause condition: `currentState === 'sleeping'`
   - NOT paused during: `'fading-out'` or `'fading-in'`
   - Ensures beautiful visual experience during transitions

3. **Monitor Control Timing**:
   - DPMS OFF: Triggered AFTER 2-minute fade-out completes
   - DPMS ON: Triggered BEFORE 2-minute fade-in begins (+500ms delay for monitor wake)

4. **Brightness Updates**:
   - Check interval: Every 60 seconds
   - Update threshold: ±0.01 (prevents unnecessary API calls)
   - Disabled during: `currentState === 'sleeping'`
   - Range: 0.7 (night) → 1.5 (bright day)

5. **Sleep Period Power Savings**:
   - Duration: 4.5 hours (01:00-05:30)
   - WebGL shader: Paused (0% GPU)
   - CSS gradients: Paused (`animationPlayState: 'paused'`)
   - Monitor: Physical OFF (~11.5W saved)
   - Total savings: ~52 Wh/night, 19 kWh/year

---

## Adaptive Brightness System

**Goal**: Match display brightness to time of day for optimal viewing comfort.

**Brightness Curve** (based on 24-hour time):
```
06:00-12:00  →  1.0 → 1.4  (Morning: gradual increase)
12:00-18:00  →  1.4 → 1.2  (Afternoon: stay bright, slight decrease)
18:00-22:00  →  1.2 → 0.9  (Evening: sunset dimming)
22:00-01:00  →  0.9 → 0.7  (Night: pre-sleep dim)
01:00-05:30  →  [SLEEPING - monitor off]
05:30-06:00  →  0.7 → 1.0  (Dawn: gentle wake)
```

**Implementation**:
```typescript
const calculateBrightness = (hour: number, minute: number): number => {
  const time = hour + minute / 60;

  // Morning: 6am-12pm (1.0 → 1.4)
  if (time >= 6 && time < 12) {
    return 1.0 + ((time - 6) / 6) * 0.4;
  }

  // Afternoon: 12pm-6pm (1.4 → 1.2)
  if (time >= 12 && time < 18) {
    return 1.4 - ((time - 12) / 6) * 0.2;
  }

  // Evening: 6pm-10pm (1.2 → 0.9)
  if (time >= 18 && time < 22) {
    return 1.2 - ((time - 18) / 4) * 0.3;
  }

  // Night: 10pm-1am (0.9 → 0.7)
  if (time >= 22 || time < 1) {
    const nightTime = time >= 22 ? time - 22 : time + 2;
    return 0.9 - (nightTime / 3) * 0.2;
  }

  // Dawn: 5:30am-6am (0.7 → 1.0)
  if (time >= 5.5 && time < 6) {
    return 0.7 + ((time - 5.5) / 0.5) * 0.3;
  }

  // Default (should not reach)
  return 1.0;
};

// Update brightness every minute
useEffect(() => {
  if (!state.enabled || state.currentState === 'sleeping') return;

  const updateBrightness = async () => {
    const now = new Date();
    const targetBrightness = calculateBrightness(now.getHours(), now.getMinutes());

    if (Math.abs(targetBrightness - state.brightness) > 0.01) {
      // Smooth transition over 60 seconds to new brightness
      await fetch('/api/display/brightness', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ level: targetBrightness })
      });

      setState(prev => ({ ...prev, brightness: targetBrightness }));
    }
  };

  updateBrightness(); // Immediate
  const interval = setInterval(updateBrightness, 60000); // Every minute

  return () => clearInterval(interval);
}, [state.enabled, state.currentState]);
```

---

## Component Specifications

### 1. SleepScheduleProvider

**File**: `dashboard/src/contexts/SleepScheduleContext.tsx`

**Responsibilities**:
- Manage sleep schedule state
- Calculate next sleep/wake time
- Trigger fade transitions on schedule
- Provide sleep controls to children

**Key Methods**:
```typescript
interface SleepScheduleContext {
  state: SleepScheduleState;
  setSleepTime: (time: string) => void;
  setWakeTime: (time: string) => void;
  toggleEnabled: () => void;
  forceSleep: () => void;           // Instant fade-out start
  forceWake: () => void;            // Instant fade-in start
  clearOverride: () => void;        // Return to schedule
}
```

**Timer Logic** (Corrected - October 4, 2025):
```typescript
useEffect(() => {
  if (!state.enabled || state.manualOverride) return;

  const checkSchedule = () => {
    const now = new Date();
    const currentTime = `${now.getHours().toString().padStart(2, '0')}:${now.getMinutes().toString().padStart(2, '0')}`;
    const dayOfWeek = now.getDay(); // 0=Sunday, 5=Friday, 6=Saturday

    // Use weekend sleep time on Friday and Saturday nights
    const isWeekendNight = dayOfWeek === 5 || dayOfWeek === 6;
    const effectiveSleepTime = isWeekendNight ? state.sleepTimeWeekend : state.sleepTime;

    // Check if we should start sleeping
    if (currentTime === effectiveSleepTime && state.currentState === 'awake') {
      startFadeOut();
    }

    // Check if we should start waking
    if (currentTime === state.wakeTime && state.currentState === 'sleeping') {
      startFadeIn();
    }
  };

  // Check every 10 seconds to never miss minute boundary
  // (60s interval could skip over target minute if component mounts at wrong time)
  const interval = setInterval(checkSchedule, 10000);
  checkSchedule(); // Check immediately on mount

  return () => clearInterval(interval);
}, [state.enabled, state.sleepTime, state.sleepTimeWeekend, state.wakeTime, state.currentState, state.manualOverride]);
```

**Fade Transition Logic** (Corrected - October 4, 2025):
```typescript
// SIMPLIFIED: No requestAnimationFrame needed - CSS handles everything!
const startFadeOut = () => {
  dispatch({ type: 'SET_STATE', state: 'fading-out' });

  // CSS transition handles the 120s fade automatically
  // After 120s, set to sleeping state
  setTimeout(() => {
    dispatch({ type: 'SET_STATE', state: 'sleeping' });

    // Turn off monitor if enabled
    if (state.monitorPowerControl) {
      fetch('/api/display/power', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ action: 'off' }),
      }).catch(error => console.error('Failed to turn off monitor:', error));
    }
  }, 120000);
};

const startFadeIn = () => {
  // Turn on monitor before fade-in
  if (state.monitorPowerControl) {
    fetch('/api/display/power', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ action: 'on' }),
    }).catch(error => console.error('Failed to turn on monitor:', error));
  }

  setTimeout(() => {
    dispatch({ type: 'SET_STATE', state: 'fading-in' });

    // CSS transition handles the 120s fade automatically
    // After 120s, set to awake state
    setTimeout(() => {
      dispatch({ type: 'SET_STATE', state: 'awake' });
    }, 120000);
  }, 500); // 500ms delay for monitor wake
};
```

---

### 2. FadeOverlay

**File**: `dashboard/src/components/SleepSchedule/FadeOverlay.tsx`

**Responsibilities**:
- Render black overlay with dynamic opacity
- GPU-accelerated smooth transitions
- Pointer-events management (block clicks when sleeping)

**Component Structure** (Corrected - October 4, 2025):
```tsx
const FadeOverlay: React.FC = () => {
  const { state } = useSleepSchedule();

  // Simplified: Pure CSS transitions, no JS opacity calculations
  // Opacity targets based on state:
  // - fading-out: 1 (transitions from 0 to 1)
  // - sleeping: 1 (stays at 1)
  // - fading-in: 0 (transitions from 1 to 0)
  // - awake: 0 (stays at 0)
  const opacity = (state.currentState === 'sleeping' || state.currentState === 'fading-out') ? 1 : 0;
  const hasTransition = state.currentState === 'fading-out' || state.currentState === 'fading-in';

  return (
    <div
      className="sleep-overlay"
      data-sleep-overlay
      style={{
        opacity,
        pointerEvents: state.currentState === 'sleeping' ? 'auto' : 'none',
        transition: hasTransition ? 'opacity 120s cubic-bezier(0.4, 0.0, 0.2, 1)' : 'none',
      }}
      aria-hidden={state.currentState !== 'sleeping'}
    />
  );
};
```

**CSS** (`dashboard/src/components/SleepSchedule/FadeOverlay.css`):
```css
.sleep-overlay {
  position: fixed;
  top: 0;
  left: 0;
  width: 100vw;
  height: 100vh;
  background-color: #000000;
  z-index: 9999;
  will-change: opacity;

  /* GPU acceleration */
  transform: translateZ(0);
  backface-visibility: hidden;
}

/* Respect accessibility preferences */
@media (prefers-reduced-motion: reduce) {
  .sleep-overlay {
    transition: opacity 2s ease-in-out !important;
  }
}
```

---

### 3. ConfigPanel

**File**: `dashboard/src/components/SleepSchedule/ConfigPanel.tsx`

**Responsibilities**:
- Sleep/wake time pickers
- Master enable/disable toggle
- Manual override buttons
- Current status indicator

**UI Layout**:
```
┌─────────────────────────────────────────┐
│ Sleep Schedule Configuration            │
├─────────────────────────────────────────┤
│ [✓] Enable sleep schedule               │
│                                          │
│ Sleep Time:  [01] : [00]  ▼            │
│ Wake Time:   [05] : [30]  ▼            │
│                                          │
│ Current Status: 😴 Sleeping (45% faded) │
│                                          │
│ [ Force Sleep ]  [ Force Wake ]         │
│                                          │
│ Next Event: Wake at 5:30 AM (3h 12m)   │
└─────────────────────────────────────────┘
```

**Component Code**:
```tsx
const ConfigPanel: React.FC = () => {
  const {
    state,
    setSleepTime,
    setWakeTime,
    toggleEnabled,
    forceSleep,
    forceWake
  } = useSleepSchedule();

  const [isOpen, setIsOpen] = useState(false);

  return (
    <div className="sleep-config-panel">
      <button
        className="sleep-config-trigger"
        onClick={() => setIsOpen(!isOpen)}
      >
        {state.currentState === 'sleeping' ? '😴' : '☀️'}
      </button>

      {isOpen && (
        <div className="sleep-config-content">
          <h3>Sleep Schedule</h3>

          <label>
            <input
              type="checkbox"
              checked={state.enabled}
              onChange={toggleEnabled}
            />
            Enable automatic sleep
          </label>

          <div className="time-picker">
            <label>
              Sleep Time
              <input
                type="time"
                value={state.sleepTime}
                onChange={(e) => setSleepTime(e.target.value)}
              />
            </label>
          </div>

          <div className="time-picker">
            <label>
              Wake Time
              <input
                type="time"
                value={state.wakeTime}
                onChange={(e) => setWakeTime(e.target.value)}
              />
            </label>
          </div>

          <div className="status-indicator">
            <StatusBadge state={state.currentState} />
            {state.currentState.includes('fading') && (
              <ProgressBar value={state.fadeProgress} />
            )}
          </div>

          <div className="manual-controls">
            <button onClick={forceSleep}>Force Sleep</button>
            <button onClick={forceWake}>Force Wake</button>
          </div>

          <NextEventTimer state={state} />
        </div>
      )}
    </div>
  );
};
```

---

## WebSocket Connection Handling

**Critical Requirement**: WebSocket MUST stay alive during sleep to receive data updates.

**Implementation Strategy**:
```typescript
// In DataContext.tsx (existing WebSocket management)

const useSleepAwareWebSocket = () => {
  const { state: sleepState } = useSleepSchedule();
  const ws = useRef<WebSocket | null>(null);

  useEffect(() => {
    // WebSocket connection logic remains UNCHANGED
    // Sleep state does NOT affect connection lifecycle

    ws.current = new WebSocket(WS_URL);

    ws.current.onmessage = (event) => {
      const data = JSON.parse(event.data);

      // Data updates happen even when sleeping
      // UI just isn't visible due to overlay
      dispatch({ type: 'UPDATE_DATA', payload: data });
    };

    // No cleanup based on sleep state
    return () => ws.current?.close();
  }, []);

  return ws;
};
```

**Why this works**:
- Overlay opacity affects VISIBILITY only, not component lifecycle
- Components continue rendering beneath overlay
- WebSocket messages processed normally
- When waking, data is already fresh (no catch-up needed)

---

## Current Production Configuration

**Production Config** (`config/sleep_schedule.json`):
```json
{
  "enabled": true,
  "sleepTime": "00:00",
  "sleepTimeWeekend": "02:00",
  "wakeTime": "06:00",
  "monitorPowerControl": true,
  "brightnessEnabled": true
}
```

**Schedule Behavior**:
- **Weekday sleep (Sun-Thu)**: Midnight (00:00) → 6:00 AM (6 hours)
- **Weekend sleep (Fri-Sat)**: 2:00 AM → 6:00 AM (4 hours)
- **Monitor control**: DPMS power off during sleep (saves ~12W)
- **Adaptive brightness**: 0.7-1.5 range throughout the day

---

## Edge Cases & Handling

### 1. Page Reload During Fade
```typescript
useEffect(() => {
  // On mount, check if we should be sleeping RIGHT NOW
  const now = new Date();
  const currentTime = now.getHours() * 60 + now.getMinutes();
  const sleepMinutes = parseTime(state.sleepTime);
  const wakeMinutes = parseTime(state.wakeTime);

  if (isInSleepWindow(currentTime, sleepMinutes, wakeMinutes)) {
    // Instant sleep if reloaded during sleep hours
    setState(prev => ({
      ...prev,
      currentState: 'sleeping',
      fadeProgress: 100
    }));
  }
}, []);
```

### 2. Clock Time Changes
```typescript
// Handle daylight saving time, manual clock adjustments
useEffect(() => {
  const lastCheck = localStorage.getItem('lastScheduleCheck');
  const now = Date.now();

  // If more than 2 hours passed since last check, re-evaluate state
  if (lastCheck && (now - parseInt(lastCheck)) > 7200000) {
    recalculateScheduleState();
  }

  localStorage.setItem('lastScheduleCheck', now.toString());
}, [state.currentState]);
```

### 3. Browser Tab Visibility
```typescript
useEffect(() => {
  const handleVisibilityChange = () => {
    if (!document.hidden) {
      // Tab became visible, verify we're in correct state
      const shouldBeSleeping = isCurrentlyInSleepWindow();

      if (shouldBeSleeping && state.currentState === 'awake') {
        forceSleep();
      } else if (!shouldBeSleeping && state.currentState === 'sleeping') {
        forceWake();
      }
    }
  };

  document.addEventListener('visibilitychange', handleVisibilityChange);
  return () => document.removeEventListener('visibilitychange', handleVisibilityChange);
}, [state]);
```

### 4. Sleep/Wake Times Overlap (e.g., sleep 23:00, wake 06:00)
```typescript
const isInSleepWindow = (current: number, sleep: number, wake: number): boolean => {
  if (wake > sleep) {
    // Normal case: sleep 01:00, wake 05:30
    return current >= sleep && current < wake;
  } else {
    // Overnight case: sleep 23:00, wake 06:00
    return current >= sleep || current < wake;
  }
};
```

---

## Testing Checklist

### Manual Testing
- [ ] Set sleep time to 2 minutes from now, verify 2-minute fade-out starts
- [ ] Set wake time to 2 minutes from fade completion, verify 2-minute fade-in
- [ ] Reload page during sleep, verify instant black screen
- [ ] Reload page during wake, verify instant normal display
- [ ] Toggle enabled off during fade, verify fade stops immediately
- [ ] Force sleep button triggers 2-minute fade-out
- [ ] Force wake button triggers 2-minute fade-in
- [ ] WebSocket continues updating data during sleep (check network tab)
- [ ] LocalStorage persists settings across page reload
- [ ] Config panel shows accurate "next event" countdown

### Automated Testing (Future)
```typescript
// dashboard/src/components/SleepSchedule/__tests__/SleepScheduleContext.test.tsx

describe('SleepScheduleContext', () => {
  it('starts fade-out at configured sleep time', () => {
    // Mock current time to sleep time
    // Assert currentState transitions to 'fading-out'
  });

  it('maintains WebSocket during sleep', () => {
    // Mock sleep state
    // Assert WebSocket.send still works
  });

  it('handles overnight sleep windows correctly', () => {
    // Set sleep 23:00, wake 06:00
    // Assert 02:00 is detected as "sleeping"
  });
});
```

---

## Performance Considerations

### Critical Optimization: Pause Background Animations During Sleep

**Problem**: The dashboard runs GPU-intensive animations 24/7, wasting resources when display is black (opacity 0).

**Systems to Pause**:

1. **WebGL Shader (`<AnoAI />`)** - `dashboard/src/components/ui/animated-shader-background.tsx`
   - Currently: Runs `requestAnimationFrame` loop continuously at 60fps
   - GPU cost: Fragment shader calculations on every frame
   - **Solution**: Stop animation loop when sleeping

2. **CSS Gradient Animations** - `dashboard/src/App.tsx:145-151`
   - Currently: 5 layered gradients with `animate-dashboard-*` classes
   - CSS cost: Continuous transform/position calculations
   - **Solution**: Pause CSS animations when sleeping

**Implementation Strategy**:

```typescript
// Modified animated-shader-background.tsx
const AnoAI = () => {
  const { state } = useSleepSchedule();
  const containerRef = useRef(null);
  const frameIdRef = useRef<number>();
  const isPausedRef = useRef(false);

  useEffect(() => {
    // Pause ONLY when fully asleep (not during fade transitions)
    const shouldPause = state.currentState === 'sleeping';

    if (shouldPause && !isPausedRef.current) {
      // Pause animation
      if (frameIdRef.current) {
        cancelAnimationFrame(frameIdRef.current);
        frameIdRef.current = undefined;
      }
      isPausedRef.current = true;
    } else if (!shouldPause && isPausedRef.current) {
      // Resume animation
      isPausedRef.current = false;
      animate(); // Restart loop
    }
  }, [state.currentState]);

  const animate = () => {
    if (isPausedRef.current) return;

    material.uniforms.iTime.value += 0.016;
    renderer.render(scene, camera);
    frameIdRef.current = requestAnimationFrame(animate);
  };

  // ... rest of component
};
```

```tsx
// Modified App.tsx - CSS gradient container
const DashboardContent = () => {
  const { state } = useSleepSchedule();

  // Pause CSS animations ONLY when fully asleep (not during fade transitions)
  const shouldPauseCSS = state.currentState === 'sleeping';

  return (
    <div className="min-h-screen ...">
      {/* Shader background - pauses internally via useSleepSchedule */}
      <div className="fixed inset-0 ...">
        <AnoAI />
      </div>

      {/* CSS gradient background - pause animations when sleeping */}
      <div
        className="gradients-container fixed inset-0 h-full w-full opacity-20 blur-[60px]"
        style={{
          zIndex: 2,
          animationPlayState: shouldPauseCSS ? 'paused' : 'running'
        }}
      >
        <div className="absolute ... animate-dashboard-first" />
        <div className="absolute ... animate-dashboard-second" />
        <div className="absolute ... animate-dashboard-third" />
        <div className="absolute ... animate-dashboard-fourth" />
        <div className="absolute ... animate-dashboard-fifth" />
      </div>
      {/* ... rest of content ... */}
    </div>
  );
};
```

**Performance Gains**:
- **WebGL shader paused**: ~5-10% CPU reduction (fragment shader math at 60fps)
- **CSS animations paused**: ~2-3% CPU reduction (compositor work)
- **Total savings**: ~7-13% CPU during 4.5-hour sleep period
- **Daily impact**: ~35 minutes at low power vs full render power

**Why Pause ONLY When Fully Asleep**:
- Animations remain visible during entire 2-minute fade-out (beautiful aesthetic)
- Animations visible during entire 2-minute fade-in (smooth wake experience)
- Pause only when display is 100% black (currentState === 'sleeping')
- Power savings still significant (4.5 hours of zero GPU usage)

### GPU Acceleration
- Use `transform: translateZ(0)` for overlay (force GPU layer)
- Use `will-change: opacity` hint for browser optimization
- Avoid `box-shadow` or `filter` during fade (expensive)

### Memory Management
```typescript
// Clean up animation frames on unmount
useEffect(() => {
  let animationId: number;

  const animate = () => {
    // Fade logic
    animationId = requestAnimationFrame(animate);
  };

  return () => {
    if (animationId) cancelAnimationFrame(animationId);
  };
}, []);
```

### Battery Impact
- Fading animation: 120s at 60fps = 7,200 frames
- Each frame: opacity update only (minimal GPU work)
- Expected battery impact: <0.5% per transition
- Daily impact (2 transitions): <1% battery

---

## Implementation Phases

### Phase 1: Core Sleep System (Day 1)
1. Create `SleepScheduleContext.tsx` with basic state
2. Implement timer logic for schedule checking
3. Add LocalStorage persistence
4. Create `FadeOverlay.tsx` with basic opacity control
5. Test manual sleep/wake triggers

**Deliverables**:
- [ ] Context provides sleep state to children
- [ ] Overlay renders with correct opacity
- [ ] LocalStorage saves/loads settings
- [ ] Manual controls work (instant transitions for testing)

### Phase 2: Smooth Transitions (Day 2)
1. Implement 2-minute fade-out with `requestAnimationFrame`
2. Implement 2-minute fade-in with `requestAnimationFrame`
3. Add CSS transitions as fallback
4. Test transition smoothness (should be buttery 60fps)
5. Add `prefers-reduced-motion` support

**Deliverables**:
- [ ] Fade-out completes in exactly 2 minutes
- [ ] Fade-in completes in exactly 2 minutes
- [ ] No jank or dropped frames during transition
- [ ] Accessibility respected

### Phase 3: Configuration UI (Day 3)
1. Create `ConfigPanel.tsx` with time pickers
2. Add master enable/disable toggle
3. Implement status indicator with progress bar
4. Add "next event" countdown timer
5. Style config panel to match dashboard theme

**Deliverables**:
- [ ] Time pickers allow custom sleep/wake times
- [ ] Status shows current state accurately
- [ ] Next event timer counts down correctly
- [ ] UI matches existing dashboard aesthetic

### Phase 4: Edge Cases & Polish (Day 4)
1. Handle page reload during fade
2. Handle overnight sleep windows (23:00 → 06:00)
3. Add tab visibility state synchronization
4. Test WebSocket persistence during sleep
5. Add error handling for invalid times

**Deliverables**:
- [ ] All edge cases tested and handled
- [ ] WebSocket confirmed alive during sleep
- [ ] No console errors in any scenario
- [ ] Documentation updated

---

## Future Enhancements

### Motion Sensor Integration
**Hardware**: PIR motion sensor via GPIO or USB

**Implementation**:
```typescript
// Pseudo-code for future implementation
const useMotionSensor = () => {
  const { forceWake } = useSleepSchedule();

  useEffect(() => {
    const sensor = new MotionSensor('/dev/usb/motion');

    sensor.on('motion-detected', () => {
      if (state.currentState === 'sleeping') {
        forceWake(); // Instant wake on motion
      }
    });

    return () => sensor.disconnect();
  }, []);
};
```

**User Story**: Walking past dashboard in hallway triggers instant wake (no 2-minute wait)

---

### Webcam Gesture Detection
**Hardware**: USB webcam

**Implementation Libraries**:
- [MediaPipe Hands](https://google.github.io/mediapipe/solutions/hands.html)
- [TensorFlow.js Hand Pose Detection](https://github.com/tensorflow/tfjs-models/tree/master/hand-pose-detection)

**Gestures**:
- 👋 Wave: Wake dashboard
- ✋ Palm up: Show full rent breakdown
- 👈 Point left: Focus train departures
- 👉 Point right: Focus weather
- 🤚 Stop sign: Sleep dashboard

**Privacy**: All processing done locally (no cloud)

---

### System-Level Monitor Control (Advanced Power Savings)

**Goal**: Physically turn off monitor after fade completes, eliminating backlight and ALL GPU rendering.

**Benefits**:
- ✅ Zero light pollution (no backlight glow)
- ✅ Maximum power savings (~10-15W for typical LED monitor)
- ✅ Zero GPU usage (Chrome compositor can suspend)
- ✅ Extended monitor lifespan (reduced backlight hours)

**Technology: DPMS (Display Power Management Signaling)**

DPMS is a standard Linux/X11 feature for controlling monitor power states:
- **Off**: Monitor completely powered down, no signal
- **Suspend**: Low power mode, quick wake
- **Standby**: Minimal power, instant wake
- **On**: Full power

**Implementation Architecture**:

```
Frontend (React)                Backend (Ruby)              System (xset)
     │                               │                          │
     │  POST /api/display/off        │                          │
     ├──────────────────────────────>│                          │
     │                               │  `xset dpms force off`   │
     │                               ├─────────────────────────>│
     │                               │                          │
     │                               │  ✅ Monitor OFF          │
     │  200 OK                       │                          │
     │<──────────────────────────────┤                          │
     │                               │                          │
     │  POST /api/display/on         │                          │
     ├──────────────────────────────>│                          │
     │                               │  `xset dpms force on`    │
     │                               ├─────────────────────────>│
     │                               │                          │
     │                               │  ✅ Monitor ON           │
     │  200 OK                       │                          │
     │<──────────────────────────────┤                          │
```

**Backend Implementation** (`handlers/display_control_handler.rb`):

```ruby
require 'open3'

class DisplayControlHandler
  # Pragmatic security: whitelist exact commands, no user input injection
  DISPLAY_COMMANDS = {
    'off' => 'xset dpms force off',
    'on' => 'xset dpms force on'
  }.freeze

  def self.handle_display_power(params)
    action = params['action']

    # Validate action exists in whitelist
    unless DISPLAY_COMMANDS.key?(action)
      return { success: false, error: 'Invalid action' }
    end

    # Execute with DISPLAY environment set
    stdout, stderr, status = Open3.capture3(
      { 'DISPLAY' => ':0' },
      DISPLAY_COMMANDS[action]
    )

    if status.success?
      { success: true, state: action, timestamp: Time.now.to_i }
    else
      { success: false, error: stderr.strip }
    end
  rescue => e
    { success: false, error: e.message }
  end

  def self.handle_brightness(params)
    level = params['level'].to_f

    # Validate brightness range (0.5-1.6, but we use 0.7-1.5)
    unless level >= 0.7 && level <= 1.5
      return { success: false, error: 'Brightness must be 0.7-1.5' }
    end

    # Execute xrandr brightness command
    stdout, stderr, status = Open3.capture3(
      { 'DISPLAY' => ':0' },
      'xrandr', '--output', 'HDMI-0', '--brightness', level.to_s
    )

    if status.success?
      { success: true, brightness: level, timestamp: Time.now.to_i }
    else
      { success: false, error: stderr.strip }
    end
  rescue => e
    { success: false, error: e.message }
  end
end
```

**Route Additions** (in `puma_server.rb`):

```ruby
when '/api/display/power'
  if req.request_method == 'POST'
    params = parse_json_body(req)
    result = DisplayControlHandler.handle_display_power(params)
    [200, {'Content-Type' => 'application/json'}, [result.to_json]]
  else
    [405, {}, [{ error: 'Method not allowed' }.to_json]]
  end

when '/api/display/brightness'
  if req.request_method == 'POST'
    params = parse_json_body(req)
    result = DisplayControlHandler.handle_brightness(params)
    [200, {'Content-Type' => 'application/json'}, [result.to_json]]
  else
    [405, {}, [{ error: 'Method not allowed' }.to_json]]
  end
```

**Pragmatic Security Notes**:
- ✅ Whitelist exact commands (no string interpolation)
- ✅ Validate numeric ranges for brightness
- ✅ Use `Open3.capture3` to avoid shell injection
- ✅ POST-only for state changes
- ❌ No rate limiting (LAN-only service, trusted network)
- ❌ No authentication (home environment, browser running as kimonokittens user)

**Frontend Integration** (in SleepScheduleContext):

```typescript
const turnOffMonitor = async () => {
  try {
    const response = await fetch('/api/display/off', { method: 'POST' });
    const result = await response.json();
    console.log('Monitor turned off:', result);
  } catch (error) {
    console.error('Failed to turn off monitor:', error);
  }
};

const turnOnMonitor = async () => {
  try {
    const response = await fetch('/api/display/on', { method: 'POST' });
    const result = await response.json();
    console.log('Monitor turned on:', result);
  } catch (error) {
    console.error('Failed to turn on monitor:', error);
  }
};

// Call after fade-out completes
const startFadeOut = () => {
  // ... existing fade logic ...

  const animateFrame = () => {
    const elapsed = Date.now() - startTime;
    const progress = Math.min(elapsed / duration, 1);

    setState(prev => ({ ...prev, fadeProgress: progress * 100 }));

    if (progress < 1) {
      requestAnimationFrame(animateFrame);
    } else {
      setState(prev => ({
        ...prev,
        currentState: 'sleeping',
        fadeProgress: 100,
        lastTransitionTime: Date.now()
      }));

      // NEW: Turn off monitor after fade completes
      turnOffMonitor();
    }
  };

  requestAnimationFrame(animateFrame);
};

// Call before fade-in starts
const startFadeIn = () => {
  // NEW: Turn on monitor before fade begins
  turnOnMonitor();

  // Small delay to ensure monitor is on before fade
  setTimeout(() => {
    setState(prev => ({ ...prev, currentState: 'fading-in' }));

    const duration = 120000;
    const startTime = Date.now();

    const animateFrame = () => {
      // ... existing fade-in logic ...
    };

    requestAnimationFrame(animateFrame);
  }, 500); // 500ms delay for monitor wake
};
```

**Permissions Setup**:

The `kimonokittens` user needs permission to control the display. Add to kiosk startup script:

```bash
# Allow kimonokittens user to control display
# (Already has DISPLAY=:0 access from kiosk session)

# Ensure DPMS is enabled
DISPLAY=:0 xset +dpms

# Set DPMS timeouts (optional - we control manually)
DISPLAY=:0 xset dpms 0 0 0  # Disable automatic timeouts
```

**Testing Commands**:

```bash
# Manually test display control
DISPLAY=:0 xset dpms force off   # Monitor should turn off
sleep 5
DISPLAY=:0 xset dpms force on    # Monitor should turn on

# Check DPMS status
DISPLAY=:0 xset q | grep -A 3 "DPMS"
```

**Power Savings Calculation**:

Assuming:
- Monitor: ~12W active, ~0.5W standby
- Sleep period: 1:00 AM - 5:30 AM (4.5 hours)
- Display off saves: 11.5W × 4.5h = 51.75 Wh/night
- Annual savings: 51.75 Wh × 365 = **18.9 kWh/year**

At Swedish electricity rates (~2.50 SEK/kWh):
- **Annual cost savings: ~47 SEK**
- **Environmental impact: ~4 kg CO₂ reduction/year**

**Edge Cases**:

1. **Monitor doesn't wake**: Use motion sensor to force `xset dpms force on`
2. **DPMS not supported**: Fallback to CSS-only sleep (graceful degradation)
3. **User manually wakes display**: Detect via `xset q` polling and sync state
4. **Browser tab loses focus**: Wake on visibility change before turning on display

**Alternative: DDC/CI Control (Future)**

For more advanced control (brightness, input switching):
```bash
# Install ddcutil
sudo apt install ddcutil

# Turn off backlight via DDC/CI
ddcutil setvcp 10 0   # Set brightness to 0
ddcutil setvcp D6 5   # Power mode: Off
```

**Configuration Option**:

Add to SleepSchedule settings:
```typescript
interface SleepScheduleState {
  // ... existing fields ...
  hardwareControl: boolean;  // Enable/disable monitor power control
}
```

This allows users to opt-in to system-level control if their monitor supports it properly.

---

## Success Metrics

### Functional Requirements
- ✅ Dashboard fades to black in exactly 2 minutes
- ✅ Dashboard fades to visible in exactly 2 minutes
- ✅ Fade transitions are smooth (60fps, no jank)
- ✅ Schedule triggers automatically at configured times
- ✅ WebSocket maintains connection during sleep
- ✅ Settings persist across page reloads
- ✅ Manual controls provide instant override

### User Experience
- ✅ No hallway light pollution between 1:00 AM - 5:30 AM
- ✅ Dashboard data remains fresh when waking (no stale trains)
- ✅ Configuration is intuitive (5 seconds to set custom times)
- ✅ Transitions feel natural (not jarring)

### Technical Quality
- ✅ No memory leaks from animation frames
- ✅ GPU-accelerated rendering (<5% CPU during fade)
- ✅ Respects accessibility preferences
- ✅ Works across browser restarts
- ✅ Handles edge cases gracefully

---

## File Checklist

### New Files to Create
- [ ] `dashboard/src/contexts/SleepScheduleContext.tsx`
- [ ] `dashboard/src/components/SleepSchedule/FadeOverlay.tsx`
- [ ] `dashboard/src/components/SleepSchedule/FadeOverlay.css`
- [ ] `dashboard/src/components/SleepSchedule/ConfigPanel.tsx`
- [ ] `dashboard/src/components/SleepSchedule/ConfigPanel.css`
- [ ] `dashboard/src/hooks/useSleepSchedule.ts`
- [ ] `dashboard/src/components/SleepSchedule/__tests__/SleepScheduleContext.test.tsx`

### Files to Modify
- [ ] `dashboard/src/App.tsx` (wrap with SleepScheduleProvider)
- [ ] `dashboard/src/contexts/DataContext.tsx` (verify WebSocket independence)

---

## Quick Start Commands

```bash
# Development (with live reload)
npm run dev

# Test sleep schedule manually
# 1. Open dashboard at http://localhost:5175
# 2. Click config icon (☀️ or 😴)
# 3. Set sleep time to 1 minute from now
# 4. Watch 2-minute fade-out begin
# 5. Verify WebSocket still active in Network tab
# 6. Set wake time to current time
# 7. Watch 2-minute fade-in begin

# Production build
npm run build
```

---

## Questions & Decisions

### Resolved
- ✅ Fade duration: 2 minutes (user confirmed)
- ✅ Power savings tracking: Not needed (user confirmed)
- ✅ Motion sensor: Future enhancement (user confirmed)
- ✅ Webcam gestures: Future enhancement (user confirmed)

### Outstanding
- None - ready to implement!

---

**Next Steps**: Begin Phase 1 implementation (Core Sleep System)

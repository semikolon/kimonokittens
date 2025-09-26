# Dashboard Animation Implementation Plans

## Overview
This document outlines planned CSS/shader animations for enhanced dashboard UX, designed to provide smooth visual feedback and improved information hierarchy.

## 1. Train/Bus Data Transition Animations

### Current State
- Static text updates when WebSocket data arrives
- Abrupt changes in departure times and route information

### Planned Animations

#### A. Fade-In/Out Transitions
```css
.train-time-update {
  transition: opacity 0.3s ease-in-out, transform 0.2s ease-out;
}

.train-time-update.updating {
  opacity: 0;
  transform: translateY(-4px);
}

.train-time-update.updated {
  opacity: 1;
  transform: translateY(0);
}
```

#### B. Sliding Updates for Time Changes
```css
.departure-time {
  position: relative;
  overflow: hidden;
}

.departure-time.slide-update {
  animation: slideTimeUpdate 0.4s ease-in-out;
}

@keyframes slideTimeUpdate {
  0% { transform: translateX(0); }
  50% { transform: translateX(-100%); opacity: 0; }
  51% { transform: translateX(100%); }
  100% { transform: translateX(0); opacity: 1; }
}
```

#### C. Pulse Animation for Urgent Departures
```css
.departure-urgent {
  animation: urgentPulse 2s ease-in-out infinite;
}

@keyframes urgentPulse {
  0%, 100% {
    box-shadow: 0 0 5px rgba(255, 120, 0, 0.3);
    color: #ff7800;
  }
  50% {
    box-shadow: 0 0 15px rgba(255, 120, 0, 0.6);
    color: #ffaa44;
  }
}
```

#### D. Implementation Strategy
1. **Data Change Detection**: Use `useEffect` to detect train data updates
2. **Stagger Animations**: Delay animations by 50ms per item for cascade effect
3. **Conditional Triggers**: Only animate significant changes (>1 min time difference)

## 2. Schedule Bar State Transition Animations

### Current State
- Instant state changes between heating modes
- Static glow effects and opacity changes

### Planned Animations

#### A. Smooth Glow Transitions
```css
.schedule-chunk {
  transition: box-shadow 0.6s ease-in-out, background-color 0.4s ease-out;
}

.schedule-chunk.heating-active {
  animation: heatingGlow 3s ease-in-out infinite alternate;
}

@keyframes heatingGlow {
  0% {
    box-shadow: 0 0 24px rgba(255, 120, 0, 0.8);
  }
  100% {
    box-shadow: 0 0 36px rgba(255, 120, 0, 1.2),
                0 0 60px rgba(255, 120, 0, 0.6);
  }
}
```

#### B. Status Text Morphing
```css
.heatpump-status {
  transition: color 0.5s ease-in-out, text-shadow 0.3s ease-out;
  position: relative;
}

.heatpump-status.changing {
  animation: statusMorph 0.8s ease-in-out;
}

@keyframes statusMorph {
  0% { opacity: 1; transform: scale(1); }
  50% { opacity: 0; transform: scale(0.9); }
  100% { opacity: 1; transform: scale(1); }
}
```

#### C. Cursor Movement Animation
```css
.time-cursor {
  transition: left 1s cubic-bezier(0.25, 0.46, 0.45, 0.94);
  /* Real-time smooth movement as minutes progress */
}

.time-cursor.minute-tick {
  animation: cursorPulse 0.2s ease-out;
}

@keyframes cursorPulse {
  0% { transform: translateX(-50%) scale(1); }
  50% { transform: translateX(-50%) scale(1.1); }
  100% { transform: translateX(-50%) scale(1); }
}
```

#### D. Schedule Chunk Opacity Transitions
```css
.schedule-bar {
  --transition-duration: 0.8s;
}

.schedule-chunk {
  transition:
    opacity var(--transition-duration) ease-in-out,
    background-color var(--transition-duration) ease-in-out;
}

.schedule-chunk.state-change {
  animation: chunkStateChange 1.2s ease-in-out;
}

@keyframes chunkStateChange {
  0% { transform: scaleY(1); }
  20% { transform: scaleY(0.8); }
  80% { transform: scaleY(1.05); }
  100% { transform: scaleY(1); }
}
```

## 3. Implementation Priority & Technical Notes

### Phase 1: Basic Transitions (High Impact, Low Complexity)
1. Train data fade-in/out transitions
2. Schedule bar glow intensity transitions
3. Status text color transitions

### Phase 2: Advanced Animations (Medium Impact, Medium Complexity)
1. Sliding time updates for train departures
2. Cursor movement smoothing
3. Schedule chunk state change animations

### Phase 3: Premium Effects (High Polish, High Complexity)
1. Urgent departure pulse animations
2. Complex shader effects for background interactions
3. Particle effects for heating state changes

### Technical Considerations
- **Performance**: Use `transform` and `opacity` for GPU acceleration
- **Accessibility**: Respect `prefers-reduced-motion` media query
- **Battery**: Limit concurrent animations to 3-4 elements max
- **React Integration**: Use CSS classes toggled by state changes, not JS animations

### Code Locations
- **Train Animations**: `dashboard/src/components/TrainWidget.tsx`
- **Schedule Animations**: `dashboard/src/components/TemperatureWidget.tsx` (HeatpumpScheduleBar)
- **Global CSS**: `dashboard/src/index.css` for keyframes and transitions

---

*Implementation Priority: After core functionality is stable*
*Estimated Development Time: 6-8 hours for Phase 1, 12-16 hours total*
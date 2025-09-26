# Train List Sliding Animations - Implementation Plan

## Overview
Implement smooth sliding animations that trigger only when trains are added/removed from the list, not when countdown numbers change. When a train departs, remaining trains should slide upward smoothly to fill the gap.

## Technical Requirements

### 1. Smart List Change Detection
- Track trains by unique identifier (departure_time + line_number + destination)
- Detect structural changes (additions/removals) vs. data updates (countdown changes)
- Only animate on list composition changes, ignore time updates

### 2. Animation System Architecture

#### A. Train Identity Tracking
```typescript
interface TrainIdentity {
  id: string; // `${departure_time}-${line_number}-${destination}`
  departure_time: string;
  line_number: string;
  destination: string;
}

const generateTrainId = (train: TrainDeparture): string =>
  `${train.departure_time}-${train.line_number}-${train.destination}`
```

#### B. List Diff Detection
```typescript
const useTrainListChanges = (currentTrains: TrainDeparture[]) => {
  const [prevTrainIds, setPrevTrainIds] = useState<Set<string>>(new Set())

  return useMemo(() => {
    const currentIds = new Set(currentTrains.map(generateTrainId))
    const added = [...currentIds].filter(id => !prevTrainIds.has(id))
    const removed = [...prevTrainIds].filter(id => !currentIds.has(id))

    const hasStructuralChange = added.length > 0 || removed.length > 0

    useEffect(() => {
      setPrevTrainIds(currentIds)
    }, [currentIds])

    return { hasStructuralChange, added, removed }
  }, [currentTrains, prevTrainIds])
}
```

### 3. CSS Animation Implementation

#### A. Base Transition Classes
```css
.train-list-container {
  position: relative;
}

.train-departure-item {
  transform: translateY(0);
  transition: transform 0.4s cubic-bezier(0.25, 0.46, 0.45, 0.94);
  opacity: 1;
  will-change: transform, opacity;
}

/* Slide up animation for trains moving up */
.train-departure-item.slide-up {
  transform: translateY(-100%);
}

/* Fade out animation for departing trains */
.train-departure-item.departing {
  transform: translateY(-20px);
  opacity: 0;
  transition: transform 0.3s ease-out, opacity 0.3s ease-out;
}

/* Slide in animation for new trains */
.train-departure-item.arriving {
  transform: translateY(20px);
  opacity: 0;
}

.train-departure-item.arrived {
  transform: translateY(0);
  opacity: 1;
}
```

#### B. Staggered Animation Support
```css
.train-departure-item {
  transition-delay: calc(var(--item-index) * 0.05s);
}
```

### 4. React Animation Component

#### A. Animated Train List Wrapper
```tsx
const AnimatedTrainList: React.FC<{
  trains: TrainDeparture[];
  renderItem: (train: TrainDeparture, index: number) => React.ReactNode;
}> = ({ trains, renderItem }) => {
  const { hasStructuralChange, removed } = useTrainListChanges(trains)
  const [animatingItems, setAnimatingItems] = useState<Set<string>>(new Set())

  // Handle train removal animation
  useEffect(() => {
    if (removed.length > 0) {
      setAnimatingItems(new Set(removed))

      // Clear animation state after animation completes
      const timer = setTimeout(() => {
        setAnimatingItems(new Set())
      }, 400) // Match CSS transition duration

      return () => clearTimeout(timer)
    }
  }, [removed])

  return (
    <div className="train-list-container">
      {trains.map((train, index) => {
        const trainId = generateTrainId(train)
        const isAnimating = animatingItems.has(trainId)

        return (
          <div
            key={trainId}
            className={`train-departure-item ${isAnimating ? 'departing' : ''}`}
            style={{ '--item-index': index } as React.CSSProperties}
          >
            {renderItem(train, index)}
          </div>
        )
      })}
    </div>
  )
}
```

### 5. Integration with Existing TrainWidget

#### A. Replace Current Mapping
```tsx
// OLD (current):
{feasibleTrains.map((train, index) => (
  <TrainDepartureLine key={index} departure={train} />
))}

// NEW (with animations):
<AnimatedTrainList
  trains={feasibleTrains}
  renderItem={(train, index) => (
    <TrainDepartureLine departure={train} />
  )}
/>
```

#### B. Bus List Integration
Apply same pattern to bus departures for consistency.

### 6. Animation Timing & Performance

#### A. Performance Optimizations
- Use `transform` and `opacity` for GPU acceleration
- Limit concurrent animations with `will-change` management
- Debounce rapid list changes to prevent animation conflicts

#### B. Timing Coordination
- Departure animation: 300ms fade + slide out
- List reflow: 400ms slide up
- Arrival animation: 300ms fade + slide in
- Total cycle: ~700ms maximum

### 7. Edge Cases & Considerations

#### A. Rapid Data Changes
- If multiple trains depart within animation duration, queue animations
- Prevent animation spam with debouncing (minimum 500ms between animations)

#### B. List Reordering
- Handle cases where train order changes due to timing updates
- Maintain stable keys for React reconciliation

#### C. Empty List States
- Smooth transition to/from "no trains" message
- Handle first train arrival gracefully

#### D. Accessibility
- Respect `prefers-reduced-motion` setting
- Provide fallback for users with motion sensitivity

### 8. Implementation Steps

1. **Create animation utilities** (TrainIdentity, useTrainListChanges)
2. **Add CSS transition classes** to index.css
3. **Build AnimatedTrainList component**
4. **Integrate with TrainWidget**
5. **Test with real data changes**
6. **Polish timing and easing**
7. **Add accessibility support**

### 9. Testing Strategy

#### A. Manual Testing Scenarios
- Single train departure (most common)
- Multiple simultaneous departures
- New train arrival during departures
- Rapid consecutive changes
- Empty → populated → empty transitions

#### B. Animation Validation
- Verify no visual glitches during transitions
- Confirm smooth 60fps animation performance
- Test on slower devices

---

**Estimated Implementation Time**: 3-4 hours
**Priority**: High (significant UX improvement)
**Dependencies**: None (self-contained)
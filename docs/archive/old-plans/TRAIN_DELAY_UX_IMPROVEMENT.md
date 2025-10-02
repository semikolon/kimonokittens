# Train Delay UX Improvement - Implementation Plan

## Problem Analysis

### Current Issues
1. **Confusing delay display**: Shows original time + "försenad X min" but user must calculate actual departure time
2. **Redundant information**: Delay info appears both in departure lines AND in "Störningar" section
3. **Mental math required**: User sees "09:57 försenad 7 min" and must calculate "10:04" themselves

### Desired UX
```
Current:  09:57 - om 12m (försenad) - du hinner gå
Improved: 10:04 - om 12m (7m sen) - du hinner gå
```

## Technical Implementation

### 1. Data Structure Analysis

Current `TrainDeparture` interface:
```typescript
interface TrainDeparture {
  departure_time: string      // "09:57" (original time)
  departure_timestamp: number // Original timestamp
  minutes_until: number       // Minutes until ORIGINAL time (wrong for delays)
  summary_deviation_note: string // "försenad 6 min"
  // ... other fields
}
```

### 2. Delay Parsing Logic

**Function: `parseDelayInfo(summary_deviation_note: string)`**
```typescript
interface DelayInfo {
  isDelayed: boolean
  delayMinutes: number
  originalNote: string
}

const parseDelayInfo = (note: string): DelayInfo => {
  const delayMatch = note.match(/försenad (\d+) min/)
  if (delayMatch) {
    return {
      isDelayed: true,
      delayMinutes: parseInt(delayMatch[1]),
      originalNote: note
    }
  }
  return { isDelayed: false, delayMinutes: 0, originalNote: note }
}
```

### 3. Adjusted Time Calculation

**Function: `calculateAdjustedDeparture(departure: TrainDeparture)`**
```typescript
interface AdjustedDeparture {
  originalTime: string        // "09:57"
  adjustedTime: string        // "10:04"
  adjustedMinutesUntil: number // Minutes until NEW time
  delayMinutes: number        // How many minutes late
  isDelayed: boolean
}

const calculateAdjustedDeparture = (departure: TrainDeparture): AdjustedDeparture => {
  const delayInfo = parseDelayInfo(departure.summary_deviation_note)

  if (!delayInfo.isDelayed) {
    return {
      originalTime: departure.departure_time,
      adjustedTime: departure.departure_time,
      adjustedMinutesUntil: departure.minutes_until,
      delayMinutes: 0,
      isDelayed: false
    }
  }

  // Parse original time
  const [hours, minutes] = departure.departure_time.split(':').map(Number)
  const originalTime = new Date()
  originalTime.setHours(hours, minutes, 0, 0)

  // Add delay
  const adjustedTime = new Date(originalTime.getTime() + (delayInfo.delayMinutes * 60 * 1000))

  // Calculate new minutes until
  const now = new Date()
  const adjustedMinutesUntil = Math.max(0, Math.round((adjustedTime.getTime() - now.getTime()) / (1000 * 60)))

  return {
    originalTime: departure.departure_time,
    adjustedTime: `${adjustedTime.getHours().toString().padStart(2, '0')}:${adjustedTime.getMinutes().toString().padStart(2, '0')}`,
    adjustedMinutesUntil,
    delayMinutes: delayInfo.delayMinutes,
    isDelayed: true
  }
}
```

### 4. Updated Display Logic

**Function: `formatDelayAwareTimeDisplay(departure: TrainDeparture)`**
```typescript
const formatDelayAwareTimeDisplay = (departure: TrainDeparture): string => {
  const adjusted = calculateAdjustedDeparture(departure)

  if (adjusted.adjustedMinutesUntil === 0) {
    return `${adjusted.adjustedTime} - spring!`
  }

  if (adjusted.adjustedMinutesUntil > 59) {
    return adjusted.adjustedTime
  }

  if (adjusted.isDelayed) {
    return `${adjusted.adjustedTime} - om ${adjusted.adjustedMinutesUntil}m (${adjusted.delayMinutes}m sen)`
  } else {
    return `${adjusted.adjustedTime} - om ${adjusted.adjustedMinutesUntil}m`
  }
}
```

### 5. Enhanced Train Departure Component

**Updated: `TrainDepartureLine`**
```typescript
const TrainDepartureLine: React.FC<{ departure: TrainDeparture }> = ({ departure }) => {
  const adjusted = calculateAdjustedDeparture(departure)
  const opacity = adjusted.adjustedMinutesUntil === 0 ? 1.0 : getTimeOpacity(adjusted.adjustedMinutesUntil)
  const timeDisplay = formatDelayAwareTimeDisplay(departure)

  // Filter out delay info from summary_deviation_note since it's now inline
  const nonDelayNote = adjusted.isDelayed ? '' : departure.summary_deviation_note

  return (
    <div style={{ opacity, mixBlendMode: 'hard-light', marginBottom: '2px' }}>
      <strong>{timeDisplay}</strong>
      {nonDelayNote && `\u00A0${nonDelayNote}`}
      {departure.suffix && `\u00A0- ${departure.suffix}`}
    </div>
  )
}
```

### 6. Smart Störningar Filtering

**Function: `filterNonDelayDeviations(deviations: Deviation[], trains: TrainDeparture[])`**
```typescript
const filterNonDelayDeviations = (deviations: Deviation[], trains: TrainDeparture[]): Deviation[] => {
  // Get all delay times that are now shown inline
  const inlineDelayTimes = trains
    .filter(train => parseDelayInfo(train.summary_deviation_note).isDelayed)
    .map(train => train.departure_time)

  // Filter out deviations that are just delay notices for times we show inline
  return deviations.filter(deviation => {
    const isDelayNotice = /försenad \d+ min/.test(deviation.reason)
    const timeMatchesInlineDelay = inlineDelayTimes.includes(deviation.time)

    // Keep if it's not a delay notice, or if it's a delay notice for a time not shown inline
    return !isDelayNotice || !timeMatchesInlineDelay
  })
}
```

### 7. Updated DeviationAlerts Component

```typescript
const DeviationAlerts: React.FC<{
  deviations: Deviation[]
  trains: TrainDeparture[]
}> = ({ deviations, trains }) => {
  const filteredDeviations = filterNonDelayDeviations(deviations, trains)

  if (!filteredDeviations.length) return null

  // ... rest of component unchanged
}
```

## Implementation Steps

### Phase 1: Core Logic (30-45 minutes)
1. **Add delay parsing functions** to TrainWidget.tsx
   - `parseDelayInfo()`
   - `calculateAdjustedDeparture()`
   - `formatDelayAwareTimeDisplay()`

### Phase 2: Component Updates (15-20 minutes)
2. **Update TrainDepartureLine component**
   - Use new time display logic
   - Filter out delay info from summary_deviation_note

3. **Update DeviationAlerts component**
   - Add trains prop
   - Implement smart filtering
   - Hide component if no non-delay deviations

### Phase 3: Integration & Testing (15-20 minutes)
4. **Update TrainWidget main component**
   - Pass trains to DeviationAlerts
   - Test with various delay scenarios

5. **Edge case handling**
   - Delays that span midnight
   - Multiple delay notices
   - Non-Swedish delay formats

## Expected Results

### Before
```
09:57: försenad 6 min
09:57 - om 12m (försenad) - du hinner gå

Störningar:
09:57: Försenad 6 min
```

### After
```
10:03: försenad 6 min
10:03 - om 6m (6m sen) - du hinner gå

[No Störningar section if only delay notices]
```

## Benefits

1. **Intuitive UX**: Users see actual departure time immediately
2. **Reduced cognitive load**: No mental math required
3. **Cleaner interface**: No duplicate delay information
4. **Better accuracy**: Minutes until shown for actual departure time
5. **Contextual information**: Clear indication of delay amount

## Technical Considerations

- **Time zone handling**: Account for Swedish time zones
- **Data validation**: Handle malformed delay strings gracefully
- **Performance**: Minimal impact (just string parsing + date math)
- **Backward compatibility**: Graceful fallback for non-delay trains
- **Testing**: Need test data with various delay scenarios

## Files to Modify

1. `/dashboard/src/components/TrainWidget.tsx` - Main implementation
2. Test with real SL API data to validate delay format assumptions

---

**Estimated Implementation Time**: 1-1.5 hours
**Complexity**: Medium (date manipulation + string parsing)
**User Impact**: High (significantly improved UX for delayed trains)
# Deployment Countdown Feature

## Overview
Real-time deployment awareness indicator showing when the dashboard is about to reload due to a webhook deployment.

## Visual Design

**Position**: Fixed lower-right corner, inset matching widget spacing (16px from edge)
**Size**: 30px diameter
**Style**:
- Thick white stroke (4px) on transparent background
- Circular progress pie chart
- Smooth countdown animation
- Minimal, non-intrusive

## Technical Implementation

### 1. Hook: `useDeploymentStatus`
```tsx
// hooks/useDeploymentStatus.ts
import { useState, useEffect } from 'react'

interface DeploymentStatus {
  pending: boolean
  time_remaining?: number
  commit_sha?: string
}

export const useDeploymentStatus = () => {
  const [status, setStatus] = useState<DeploymentStatus | null>(null)

  useEffect(() => {
    const pollStatus = async () => {
      try {
        const res = await fetch('http://localhost:9001/status')
        const data = await res.json()
        setStatus(data.deployment)
      } catch (error) {
        console.error('Failed to fetch deployment status:', error)
        setStatus(null)
      }
    }

    // Poll every 5 seconds
    pollStatus()
    const interval = setInterval(pollStatus, 5000)

    return () => clearInterval(interval)
  }, [])

  return status
}
```

### 2. Component: `DeploymentCountdown`
```tsx
// components/DeploymentCountdown.tsx
import { useDeploymentStatus } from '../hooks/useDeploymentStatus'

const DeploymentCountdown = () => {
  const status = useDeploymentStatus()

  // Don't render if no deployment pending
  if (!status?.pending || !status.time_remaining) {
    return null
  }

  const totalTime = 120 // 2-minute debounce
  const percentage = (status.time_remaining / totalTime) * 100
  const radius = 12
  const circumference = 2 * Math.PI * radius
  const offset = circumference * (1 - percentage / 100)

  return (
    <div
      className="fixed bottom-4 right-4 z-50"
      style={{ width: '30px', height: '30px' }}
      title={`Deployment in ${status.time_remaining}s (${status.commit_sha})`}
    >
      <svg viewBox="0 0 30 30" className="transform -rotate-90">
        <circle
          cx="15"
          cy="15"
          r={radius}
          fill="transparent"
          stroke="white"
          strokeWidth="4"
          strokeDasharray={circumference}
          strokeDashoffset={offset}
          style={{
            transition: 'stroke-dashoffset 1s linear',
            opacity: 0.8
          }}
        />
      </svg>
    </div>
  )
}

export default DeploymentCountdown
```

### 3. Integration in `App.tsx`
```tsx
import DeploymentCountdown from './components/DeploymentCountdown'

function App() {
  return (
    <DataProvider>
      <AnoAI />
      {/* ... existing widgets ... */}

      {/* Deployment countdown indicator */}
      <DeploymentCountdown />
    </DataProvider>
  )
}
```

## Behavior

1. **Polling**: Frontend polls webhook `/status` endpoint every 5 seconds
2. **Detection**: When `deployment.pending === true`, countdown appears
3. **Animation**: Circular progress animates smoothly over countdown duration
4. **Disappearance**:
   - Auto-disappears when `time_remaining` reaches 0
   - Kiosk restarts → page reloads → countdown gone
5. **Tooltip**: Hovering shows time remaining and commit SHA

## Benefits

- ✅ **User awareness**: No surprise reloads
- ✅ **Elegant design**: Respects design system (white on dark)
- ✅ **Self-healing**: Disappears automatically on reload
- ✅ **Minimal footprint**: Small, non-intrusive indicator
- ✅ **Real-time**: Updates every 5 seconds
- ✅ **Informative**: Tooltip shows commit SHA

## Edge Cases

- **No webhook running**: Fetch fails silently, no countdown shown
- **Multiple rapid pushes**: Countdown resets as debounce timer resets
- **Network issues**: Graceful degradation, no error shown to user
- **Deployment cancelled**: Countdown disappears when `pending: false`

## Future Enhancements

- Fade-in/out animations
- Configurable polling interval
- Error state indicator (if webhook unreachable)
- Click to view deployment details
- Integration with error boundary for failed deployments

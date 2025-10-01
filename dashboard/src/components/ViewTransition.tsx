import { flushSync } from 'react-dom'

/**
 * Native Browser ViewTransition API wrapper with performance instrumentation
 *
 * This wrapper provides:
 * 1. Abstraction layer for future React component migration
 * 2. Performance monitoring with auto-disable on slow devices
 * 3. Structural change detection (only transition on add/remove)
 * 4. Feature detection and graceful degradation
 *
 * Performance thresholds:
 * - < 25ms: Excellent (typical)
 * - 25-50ms: Acceptable
 * - > 50ms: Warning logged
 * - > 80ms (3 times): Auto-disable for session
 */

interface TransitionStats {
  slowTransitions: number
  transitionsDisabled: boolean
}

const stats: TransitionStats = {
  slowTransitions: 0,
  transitionsDisabled: false
}

// Performance observer for long tasks
if (typeof window !== 'undefined' && 'PerformanceObserver' in window) {
  const observer = new PerformanceObserver((list) => {
    for (const entry of list.getEntries()) {
      if (entry.duration > 50) {
        console.warn(`[ViewTransition] Long transition block: ${entry.duration.toFixed(2)}ms`)

        if (entry.duration > 80) {
          stats.slowTransitions++

          if (stats.slowTransitions >= 3) {
            stats.transitionsDisabled = true
            console.error('[ViewTransition] Auto-disabled after 3 slow transitions (>80ms)')
            observer.disconnect()
          }
        }
      }
    }
  })

  try {
    observer.observe({ entryTypes: ['longtask'] })
  } catch (e) {
    // longtask not supported in all browsers
    console.debug('[ViewTransition] Long task monitoring not available')
  }
}

/**
 * Start a View Transition for list updates
 *
 * @param setState - React state setter function
 * @param newState - New state value to set
 * @param isStructural - Whether this is a structural change (add/remove items)
 *
 * Only triggers transitions for structural changes to avoid performance
 * penalty on every field update (e.g., time changes, delay info).
 */
export const startListTransition = <T,>(
  setState: (state: T) => void,
  newState: T,
  isStructural: boolean
): void => {
  // Skip if transitions disabled or not a structural change
  if (stats.transitionsDisabled || !isStructural) {
    setState(newState)
    return
  }

  // Feature detection
  if (!document.startViewTransition) {
    setState(newState)
    return
  }

  // Performance instrumentation
  performance.mark('view-transition-start')

  document.startViewTransition(() => {
    flushSync(() => {
      setState(newState)
    })
  })

  performance.mark('view-transition-end')

  try {
    const measure = performance.measure(
      'view-transition-duration',
      'view-transition-start',
      'view-transition-end'
    )

    if (measure.duration > 50) {
      console.warn(`[ViewTransition] Transition took ${measure.duration.toFixed(2)}ms`)
    }
  } catch (e) {
    // Performance API not available or marks cleared
  }
}

/**
 * Get current transition stats (for debugging)
 */
export const getTransitionStats = (): TransitionStats => {
  return { ...stats }
}

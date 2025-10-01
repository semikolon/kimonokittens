import React, { useState, useEffect, useMemo } from 'react'
import { useData } from '../context/DataContext'
import { startListTransition } from './ViewTransition'

// Types for structured transport data
interface TrainDeparture {
  departure_time: string
  departure_timestamp: number
  minutes_until: number
  can_walk: boolean
  line_number: string
  destination: string
  deviation_note: string
  summary_deviation_note: string
  suffix: string
}

interface BusDeparture {
  departure_time: string
  departure_timestamp: number
  minutes_until: number
  line_number: string
  destination: string
}

interface Deviation {
  time: string
  destination: string
  reason: string
}

interface StructuredTransportData {
  trains: TrainDeparture[]
  buses: BusDeparture[]
  deviations: Deviation[]
  generated_at: string
}

// Delay parsing types and functions
interface DelayInfo {
  isDelayed: boolean
  delayMinutes: number
  originalNote: string
}

interface AdjustedDeparture {
  originalTime: string
  adjustedTime: string
  adjustedMinutesUntil: number
  delayMinutes: number
  isDelayed: boolean
}

const parseDelayInfo = (note: string): DelayInfo => {
  // Defensive: ensure note is a string and not null/undefined
  if (!note || typeof note !== 'string') {
    return { isDelayed: false, delayMinutes: 0, originalNote: '' }
  }

  // Defensive: trim whitespace and ensure it's not empty
  const trimmedNote = note.trim()
  if (!trimmedNote) {
    return { isDelayed: false, delayMinutes: 0, originalNote: note }
  }

  // Handle both "försenad X min" and just "försenad"
  const delayWithMinutes = trimmedNote.match(/försenad (\d+) min/)
  if (delayWithMinutes) {
    return {
      isDelayed: true,
      delayMinutes: parseInt(delayWithMinutes[1]),
      originalNote: note
    }
  }

  // Check for just "försenad" without specific minutes
  if (trimmedNote.includes('försenad')) {
    return {
      isDelayed: true,
      delayMinutes: 0, // We'll estimate from time difference
      originalNote: note
    }
  }

  return { isDelayed: false, delayMinutes: 0, originalNote: note }
}

// Merge delay information from deviations array into train objects
const mergeDelayInfoIntoTrains = (trains: TrainDeparture[], deviations: Deviation[]): TrainDeparture[] => {
  return trains.map(train => {
    // Defensive: ensure summary_deviation_note exists and is a string
    const existingNote = train.summary_deviation_note
    if (existingNote && typeof existingNote === 'string' && existingNote.trim()) {
      return train
    }

    // Look for delay info in deviations array
    const matchingDeviation = deviations.find(deviation =>
      deviation.time === train.departure_time &&
      /försenad \d+ min/.test(deviation.reason)
    )

    if (matchingDeviation) {
      // Extract delay minutes from deviation reason
      const delayMatch = matchingDeviation.reason.match(/försenad (\d+) min/)
      if (delayMatch) {
        return {
          ...train,
          summary_deviation_note: `försenad ${delayMatch[1]} min`
        }
      }
    }

    return train
  })
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

const formatDelayAwareTimeDisplay = (departure: TrainDeparture): string => {
  const adjusted = calculateAdjustedDeparture(departure)

  if (adjusted.adjustedMinutesUntil === 0) {
    return `${adjusted.adjustedTime} - spring!`
  }

  if (adjusted.adjustedMinutesUntil > 59) {
    return adjusted.adjustedTime
  }

  if (adjusted.isDelayed && adjusted.delayMinutes > 0) {
    return `${adjusted.adjustedTime} - om ${adjusted.adjustedMinutesUntil}m (${adjusted.delayMinutes}m sen)`
  } else {
    return `${adjusted.adjustedTime} - om ${adjusted.adjustedMinutesUntil}m`
  }
}

// Train identity tracking for animations
const generateTrainId = (train: TrainDeparture): string =>
  `${train.departure_time}-${train.line_number}-${train.destination}`

const generateBusId = (bus: BusDeparture): string =>
  `${bus.departure_time}-${bus.line_number}-${bus.destination}`

// NOTE: useTrainListChanges and useBusListChanges removed in Phase 4
// ViewTransition API handles structural change detection via useEffect in TrainWidget

// Urgent departure detection and flashing
const isUrgentDeparture = (train: TrainDeparture): boolean => {
  // Flash when 9-10 minutes left (2 minutes before "spring eller cykla")
  return train.minutes_until >= 9 &&
         train.minutes_until <= 10 &&
         train.can_walk
}

const isCriticalDeparture = (train: TrainDeparture): boolean => {
  // Flash when train shows "spring eller cykla" (too late to walk)
  return !train.can_walk &&
         train.suffix.includes('spring')
}

// Simplified departure sequence - only warning/critical glows (ViewTransitions handle departing)
const useDepartureSequence = (trains: TrainDeparture[]) => {
  const [trainStates, setTrainStates] = useState<Map<string, DepartureState>>(new Map())
  const [warningTrains, setWarningTrains] = useState<Set<string>>(new Set())
  const [criticalTrains, setCriticalTrains] = useState<Set<string>>(new Set())
  const [processedTransitions, setProcessedTransitions] = useState<Set<string>>(new Set())

  useEffect(() => {
    trains.forEach(train => {
      const trainId = generateTrainId(train)
      const adjusted = calculateAdjustedDeparture(train)
      const minutesUntil = adjusted.adjustedMinutesUntil
      const currentState = trainStates.get(trainId) || 'feasible'
      const transitionKey = `${trainId}-${currentState}`

      // Trigger departure sequence when train becomes infeasible (< 5 minutes)
      if (currentState === 'feasible' && minutesUntil < 5 && minutesUntil >= 0 && !processedTransitions.has(transitionKey)) {
        console.log(`Starting departure sequence for train ${trainId} (${minutesUntil}m remaining)`)
        setProcessedTransitions(prev => new Set([...prev, transitionKey]))

        // Phase 1: Warning (orange glow) - 4 seconds
        setTrainStates(prev => new Map(prev).set(trainId, 'warning'))
        setWarningTrains(prev => new Set([...prev, trainId]))

        setTimeout(() => {
          // Phase 2: Critical (orange-red glow) - 3 seconds
          setTrainStates(prev => new Map(prev).set(trainId, 'critical'))
          setWarningTrains(prev => {
            const newSet = new Set(prev)
            newSet.delete(trainId)
            return newSet
          })
          setCriticalTrains(prev => new Set([...prev, trainId]))

          setTimeout(() => {
            // Phase 3: Cleanup (ViewTransition API handles exit animation)
            setCriticalTrains(prev => {
              const newSet = new Set(prev)
              newSet.delete(trainId)
              return newSet
            })
          }, 3000)
        }, 4000)
      }
    })
  }, [trains, trainStates, processedTransitions])

  // Clean up states for trains that are no longer in the list
  useEffect(() => {
    const currentTrainIds = new Set(trains.map(generateTrainId))
    setTrainStates(prev => {
      const newMap = new Map(prev)
      for (const trainId of prev.keys()) {
        if (!currentTrainIds.has(trainId)) {
          newMap.delete(trainId)
        }
      }
      return newMap
    })

    // Clean up flash sets
    setWarningTrains(prev => new Set([...prev].filter(id => currentTrainIds.has(id))))
    setCriticalTrains(prev => new Set([...prev].filter(id => currentTrainIds.has(id))))
  }, [trains])

  return {
    trainStates,
    urgentFlashingTrains: warningTrains, // Keep same interface for compatibility
    criticalFlashingTrains: criticalTrains
  }
}

// Bus urgent departure detection and flashing
const isUrgentBusDeparture = (bus: BusDeparture): boolean => {
  // Flash when 2 minutes left (orange warning) - allows buses to settle before glowing
  return bus.minutes_until === 2
}

const isCriticalBusDeparture = (bus: BusDeparture): boolean => {
  // Flash when 1 minute left (red-orange critical)
  return bus.minutes_until === 1
}

const useUrgentBusFlashing = (buses: BusDeparture[]) => {
  const [urgentFlashingBuses, setUrgentFlashingBuses] = useState<Set<string>>(new Set())
  const [criticalFlashingBuses, setCriticalFlashingBuses] = useState<Set<string>>(new Set())
  const [alreadyFlashed, setAlreadyFlashed] = useState<Set<string>>(new Set())

  useEffect(() => {
    buses.forEach(bus => {
      const busId = generateBusId(bus)

      // Check for urgent departures (4 minutes)
      if (isUrgentBusDeparture(bus) && !alreadyFlashed.has(busId + '-urgent')) {
        setAlreadyFlashed(prev => new Set([...prev, busId + '-urgent']))
        setUrgentFlashingBuses(prev => new Set([...prev, busId]))

        // Stop flashing after 4 flashes × 2.5s = 10s
        setTimeout(() => {
          setUrgentFlashingBuses(prev => {
            const newSet = new Set(prev)
            newSet.delete(busId)
            return newSet
          })
        }, 10000)
      }

      // Check for critical departures (3 minutes)
      if (isCriticalBusDeparture(bus) && !alreadyFlashed.has(busId + '-critical')) {
        setAlreadyFlashed(prev => new Set([...prev, busId + '-critical']))
        setCriticalFlashingBuses(prev => new Set([...prev, busId]))

        // Stop flashing after 2 flashes × 2s = 4s
        setTimeout(() => {
          setCriticalFlashingBuses(prev => {
            const newSet = new Set(prev)
            newSet.delete(busId)
            return newSet
          })
        }, 4000)
      }
    })
  }, [buses, alreadyFlashed])

  return { urgentFlashingBuses, criticalFlashingBuses }
}

// Helper functions for time-based styling
const getTimeOpacity = (minutesUntil: number): number => {
  if (minutesUntil < 0) return 0.3 // Past times very faded
  if (minutesUntil <= 20) return 1.0 // Next 20m fully visible
  if (minutesUntil >= 50) return 0.15 // 50m+ very faded

  // Smooth gradual fade from 20m (1.0) to 50m (0.15)
  const progress = (minutesUntil - 20) / (50 - 20)
  return 1.0 - (progress * 0.85)
}

const isFeasibleTrainDeparture = (minutesUntil: number): boolean => {
  return minutesUntil >= 5 // Can bike/run to station in 5 minutes (matches backend RUN_TIME)
}

// Enhanced departure sequence states
type DepartureState = 'feasible' | 'warning' | 'critical' | 'departing' | 'departed'

interface TrainWithDepartureState extends TrainDeparture {
  departureState?: DepartureState
}

const isFeasibleBusDeparture = (minutesUntil: number): boolean => {
  return minutesUntil >= 0 // Bus stop is right outside (1min walk), show until departure
}

// NOTE: AnimatedTrainList and AnimatedBusList removed in Phase 4
// ViewTransition API handles all entry/exit animations via CSS pseudo-elements
// Glow effects (warning-glow, critical-glow) still applied via trainStates/useDepartureSequence

// Format time display with action suffix
const formatTimeDisplay = (departure: TrainDeparture | BusDeparture): string => {
  const { departure_time, minutes_until } = departure

  if (minutes_until === 0) {
    return `${departure_time} - spring!`
  } else if (minutes_until > 59) {
    return departure_time
  } else {
    return `${departure_time} - om ${minutes_until}m`
  }
}

// Render train departure line
const TrainDepartureLine: React.FC<{
  departure: TrainDeparture;
  isUrgentFlashing?: boolean;
  isCriticalFlashing?: boolean;
}> = ({ departure, isUrgentFlashing = false, isCriticalFlashing = false }) => {
  const adjusted = calculateAdjustedDeparture(departure)
  const opacity = adjusted.adjustedMinutesUntil === 0 ? 1.0 : getTimeOpacity(adjusted.adjustedMinutesUntil)
  const timeDisplay = formatDelayAwareTimeDisplay(departure)

  // Filter out delay info from summary_deviation_note since it's now inline
  const nonDelayNote = adjusted.isDelayed ? '' : departure.summary_deviation_note

  const glowClass = isUrgentFlashing ? 'urgent-text-glow' : isCriticalFlashing ? 'critical-text-glow' : ''

  return (
    <div
      className={glowClass}
      style={{
        opacity,
        mixBlendMode: 'hard-light' as const,
        display: 'flex',
        alignItems: 'flex-start'
      }}
    >
      <strong>{timeDisplay}</strong>
      {nonDelayNote && `\u00A0${nonDelayNote}`}
      {departure.suffix && `\u00A0- ${departure.suffix}`}
    </div>
  )
}

// Render bus departure line
const BusDepartureLine: React.FC<{
  departure: BusDeparture;
  isUrgentFlashing?: boolean;
  isCriticalFlashing?: boolean;
}> = ({ departure, isUrgentFlashing = false, isCriticalFlashing = false }) => {
  const { line_number, destination, minutes_until } = departure
  const opacity = minutes_until === 0 ? 1.0 : getTimeOpacity(minutes_until)
  const timeDisplay = formatTimeDisplay(departure)

  const glowClass = isUrgentFlashing ? 'urgent-text-glow' : isCriticalFlashing ? 'critical-text-glow' : ''

  return (
    <div
      className={glowClass}
      style={{
        opacity,
        mixBlendMode: 'hard-light' as const,
        display: 'flex',
        alignItems: 'flex-start'
      }}
    >
      {line_number} till {destination}:{'\u00A0'}<strong>{timeDisplay}</strong>
    </div>
  )
}

// Smart filtering for DeviationAlerts to avoid duplicate delay info
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

// Render deviation alerts
const DeviationAlerts: React.FC<{
  deviations: Deviation[]
  trains: TrainDeparture[]
}> = ({ deviations, trains }) => {
  const filteredDeviations = filterNonDelayDeviations(deviations, trains)
  if (!filteredDeviations.length) return null

  // Group deviations by reason for cleaner display
  const grouped = filteredDeviations.reduce((acc, deviation) => {
    const key = deviation.reason.trim()
    if (!acc[key]) acc[key] = []
    acc[key].push(deviation)
    return acc
  }, {} as Record<string, Deviation[]>)

  return (
    <div className="text-yellow-400 bg-yellow-400/10 p-2 rounded inline-block max-w-full mb-3 -ml-2">
      <div className="space-y-1">
        {Object.entries(grouped).map(([reason, items], index) => (
          <div key={index} className="leading-tight">
            <strong>{items.map(item => item.time).join(', ')}:</strong>{' '}
            {reason.replace(/\.\s*läs mer på trafikläget\.?/gi, '.')}
          </div>
        ))}
      </div>
    </div>
  )
}

export function TrainWidget() {
  const { state } = useData()
  const { trainData, connectionStatus } = state

  // Calculate state flags
  const loading = connectionStatus === 'connecting' && !trainData
  const error = connectionStatus === 'closed' ? 'WebSocket-anslutning avbruten' : null
  const hasNoData = !trainData

  // Handle both old HTML format (backwards compatibility) and new structured format
  const isStructuredData = trainData?.trains !== undefined
  const structuredData = isStructuredData ? trainData as StructuredTransportData : null

  // IMPORTANT: All hooks must be called before any conditional returns
  // Prepare data for hooks (use empty arrays if no structured data)
  const trainsForHooks = structuredData ?
    mergeDelayInfoIntoTrains(structuredData.trains, structuredData.deviations) : []

  // Include trains in departure sequence (warning, critical states) - ViewTransitions handle exit animations
  const { trainStates, urgentFlashingTrains, criticalFlashingTrains } = useDepartureSequence(trainsForHooks)

  const feasibleTrainsForHooks = trainsForHooks.filter(train => {
    const trainId = generateTrainId(train)
    const adjusted = calculateAdjustedDeparture(train)
    const departureState = trainStates.get(trainId) || 'feasible'

    // Include trains that are feasible OR in departure sequence (warning, critical)
    // Trains are removed from list naturally when no longer feasible; ViewTransitions handle exit animation
    return adjusted.adjustedMinutesUntil >= 0 && (
      isFeasibleTrainDeparture(adjusted.adjustedMinutesUntil) ||
      ['warning', 'critical'].includes(departureState)
    )
  })

  const busesForHooks = structuredData?.buses || []
  const feasibleBusesForHooks = busesForHooks.filter(bus =>
    bus.minutes_until >= 0 && isFeasibleBusDeparture(bus.minutes_until)
  )

  // Call all hooks with safe data (React Hooks Rules - must be called in same order every render)
  // Note: departure sequence for trains is already handled above
  const { urgentFlashingBuses, criticalFlashingBuses } = useUrgentBusFlashing(feasibleBusesForHooks)

  // ViewTransition state management - store lists in state to enable transition wrapping
  const [feasibleTrainsState, setFeasibleTrainsState] = useState<TrainDeparture[]>([])
  const [feasibleBusesState, setFeasibleBusesState] = useState<BusDeparture[]>([])

  // Detect structural changes and update with ViewTransitions
  useEffect(() => {
    const hasStructuralChange = (oldList: any[], newList: any[], generateId: (item: any) => string) => {
      const oldIds = new Set(oldList.map(generateId))
      const newIds = new Set(newList.map(generateId))
      return oldIds.size !== newIds.size || ![...oldIds].every(id => newIds.has(id))
    }

    const trainsChanged = hasStructuralChange(feasibleTrainsState, feasibleTrainsForHooks, generateTrainId)
    const busesChanged = hasStructuralChange(feasibleBusesState, feasibleBusesForHooks, generateBusId)

    if (trainsChanged) {
      startListTransition(setFeasibleTrainsState, feasibleTrainsForHooks, true)
    }

    if (busesChanged) {
      startListTransition(setFeasibleBusesState, feasibleBusesForHooks, true)
    }
  }, [feasibleTrainsForHooks, feasibleBusesForHooks])

  // Now we can do conditional returns after all hooks are called
  if (!trainData || !isStructuredData) {
    // Legacy fallback - show message about format upgrade
    return (
      <div className="text-orange-400">
        <div>Uppgraderar dataformat...</div>
        <div className="text-xs text-purple-200 mt-1">
          (Startar om server för strukturerad data)
        </div>
      </div>
    )
  }

  // Safe to use structured data now
  const { buses, deviations } = structuredData
  const trainsWithMergedDelays = trainsForHooks
  // Use ViewTransition-managed state for rendering (falls back to derived data on first render)
  const feasibleTrains = feasibleTrainsState.length > 0 ? feasibleTrainsState : feasibleTrainsForHooks
  const feasibleBuses = feasibleBusesState.length > 0 ? feasibleBusesState : feasibleBusesForHooks

  // Debug logging
  console.log('Bus data debug:', {
    totalBuses: buses.length,
    buses: buses.map(b => `${b.line_number} to ${b.destination} at ${b.departure_time} (${b.minutes_until}m)`),
    feasibleBuses: feasibleBuses.length,
    generatedAt: structuredData.generated_at
  })

  // Only show deviations for feasible departures (accounting for delays)
  const feasibleDeviations = deviations.filter(deviation => {
    // Check if this is a delay deviation and extract delay minutes
    const isDelayDeviation = /försenad (\d+) min/.test(deviation.reason)
    if (isDelayDeviation) {
      const delayMatch = deviation.reason.match(/försenad (\d+) min/)
      const delayMinutes = delayMatch ? parseInt(delayMatch[1]) : 0

      // Parse original departure time for TODAY only (no tomorrow logic like getMinutesUntilFromTime)
      const [hours, minutes] = deviation.time.split(':').map(Number)
      const originalDeparture = new Date()
      originalDeparture.setHours(hours, minutes, 0, 0)

      // Calculate actual departure time (original + delay)
      const actualDeparture = new Date(originalDeparture.getTime() + delayMinutes * 60 * 1000)

      // Calculate minutes until actual departure (can be negative for already-departed)
      const now = new Date()
      const minutesUntilActual = Math.round((actualDeparture.getTime() - now.getTime()) / (1000 * 60))

      // Only show if actual departure is in future and feasible
      return minutesUntilActual >= 6
    }

    // For non-delay deviations, use original time
    return isFeasibleTrainDeparture(getMinutesUntilFromTime(deviation.time))
  })

  return (
    <div>
      <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
        {/* Train Section */}
        <div>
          <h4 className="text-xl font-medium text-purple-100 mb-6 tracking-wide uppercase font-[Horsemen]">
            Pendel norrut
          </h4>

          <DeviationAlerts deviations={feasibleDeviations} trains={feasibleTrains} />

          <div className="mb-3">
            <div className="leading-relaxed">
              {feasibleTrains.length > 0 ? (
                <div className="train-list-container">
                  {feasibleTrains.map((train, index) => {
                    const trainId = generateTrainId(train)
                    const departureState = trainStates.get(trainId) || 'feasible'
                    const isUrgentFlashing = urgentFlashingTrains.has(trainId)
                    const isCriticalFlashing = criticalFlashingTrains.has(trainId)

                    // Build CSS classes based on departure state (ViewTransitions handle animations)
                    const cssClasses = ['train-departure-item']
                    if (departureState === 'warning') cssClasses.push('warning-glow')
                    if (departureState === 'critical') cssClasses.push('critical-glow')

                    return (
                      <div
                        key={trainId}
                        className={cssClasses.join(' ')}
                        style={{
                          '--item-index': index,
                          viewTransitionName: trainId
                        } as React.CSSProperties}
                      >
                        <TrainDepartureLine
                          departure={train}
                          isUrgentFlashing={isUrgentFlashing}
                          isCriticalFlashing={isCriticalFlashing}
                        />
                      </div>
                    )
                  })}
                </div>
              ) : (
                <div style={{ opacity: 0.6 }}>Inga pendeltåg inom en timme</div>
              )}
            </div>
          </div>
        </div>

        {/* Bus Section */}
        <div>
          <h4 className="text-xl font-medium text-purple-100 mb-6 tracking-wide uppercase font-[Horsemen]">
            Bussar
          </h4>

          <div className="mb-3">
            <div className="leading-relaxed">
              {feasibleBuses.length > 0 ? (
                <div className="train-list-container">
                  {feasibleBuses.map((bus, index) => {
                    const busId = generateBusId(bus)
                    const isUrgentFlashing = urgentFlashingBuses.has(busId)
                    const isCriticalFlashing = criticalFlashingBuses.has(busId)

                    return (
                      <div
                        key={busId}
                        className="train-departure-item"
                        style={{
                          '--item-index': index,
                          viewTransitionName: busId
                        } as React.CSSProperties}
                      >
                        <BusDepartureLine
                          departure={bus}
                          isUrgentFlashing={isUrgentFlashing}
                          isCriticalFlashing={isCriticalFlashing}
                        />
                      </div>
                    )
                  })}
                </div>
              ) : (
                <div style={{ opacity: 0.6 }}>Inga bussar tillgängliga</div>
              )}
            </div>
          </div>
        </div>
      </div>
    </div>
  )
}

// Helper function to calculate minutes until departure from time string
function getMinutesUntilFromTime(timeStr: string): number {
  const now = new Date()
  const [hours, minutes] = timeStr.split(':').map(Number)
  const departureTime = new Date(now.getFullYear(), now.getMonth(), now.getDate(), hours, minutes)

  // If time is earlier than current time, assume it's tomorrow
  if (departureTime <= now) {
    departureTime.setDate(departureTime.getDate() + 1)
  }

  return Math.round((departureTime.getTime() - now.getTime()) / (1000 * 60))
}

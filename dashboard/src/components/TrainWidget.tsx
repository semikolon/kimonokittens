import React, { useState, useEffect, useMemo, useRef } from 'react'
import { useData } from '../context/DataContext'
import { motion, AnimatePresence, LayoutGroup } from 'framer-motion'

// Types for structured transport data
interface TrainDeparture {
  departure_time: string
  departure_timestamp: number
  minutes_until: number
  can_walk?: boolean  // Deprecated: no longer used
  line_number: string
  destination: string
  deviation_note: string
  summary_deviation_note: string
  suffix?: string  // Deprecated: calculated in frontend from adjusted time
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

// Calculate urgency suffix based on delay-adjusted departure time
const calculateSuffix = (adjusted: AdjustedDeparture): string => {
  const WALK_TIME = 8      // minutes to walk to station
  const MARGIN_TIME = 5    // alarm margin to get ready

  if (adjusted.adjustedMinutesUntil < WALK_TIME) {
    return "spring/cykla!"
  } else if (adjusted.adjustedMinutesUntil > WALK_TIME + MARGIN_TIME + 5) {
    // Calculate alarm time: adjusted departure - (walk + margin)
    const [hours, minutes] = adjusted.adjustedTime.split(':').map(Number)
    const adjustedDeparture = new Date()
    adjustedDeparture.setHours(hours, minutes, 0, 0)
    const alarmTime = new Date(adjustedDeparture.getTime() - (WALK_TIME + MARGIN_TIME) * 60 * 1000)
    return `var redo ${alarmTime.getHours().toString().padStart(2, '0')}:${alarmTime.getMinutes().toString().padStart(2, '0')}`
  } else {
    return "du hinner gå"
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
// Use exact timestamps - Framer Motion handles time updates gracefully with exit/enter animations
const generateTrainId = (train: TrainDeparture): string => {
  return `${train.departure_timestamp}-${train.line_number}-${train.destination}`
}

const generateBusId = (bus: BusDeparture): string => {
  return `${bus.departure_timestamp}-${bus.line_number}-${bus.destination}`
}

// NOTE: useTrainListChanges and useBusListChanges removed in Phase 4
// Framer Motion AnimatePresence handles structural change detection automatically

// Shine swoosh animation (9-8-7m trains, 4-3-2m buses) + pre-emptive removal for smooth exit
const useTrainDepartureAnimation = (trains: TrainDeparture[]) => {
  // Map stores trainId -> isRedTinted (true for last swoosh at 7m)
  const [shineAnimatedTrains, setShineAnimatedTrains] = useState<Map<string, boolean>>(new Map())
  const [trainsMarkedForRemoval, setTrainsMarkedForRemoval] = useState<Set<string>>(new Set())
  const animatedAtMinuteRef = useRef<Map<string, Set<number>>>(new Map())
  const markedForRemovalRef = useRef<Set<string>>(new Set())

  // Cleanup function to remove shine animation after it completes
  const cleanupShineAnimation = (trainId: string) => {
    setShineAnimatedTrains(prev => {
      const newMap = new Map(prev)
      newMap.delete(trainId)
      return newMap
    })
  }

  useEffect(() => {
    trains.forEach(train => {
      const trainId = generateTrainId(train)
      const adjusted = calculateAdjustedDeparture(train)
      const minutesUntil = adjusted.adjustedMinutesUntil

      // Trigger shine swoosh at 10m, 9m, 8m, 7m, 6m (signals: time to go catch this train!)
      if (minutesUntil === 10 || minutesUntil === 9 || minutesUntil === 8 || minutesUntil === 7 || minutesUntil === 6) {
        const animatedMinutes = animatedAtMinuteRef.current.get(trainId) || new Set()
        if (!animatedMinutes.has(minutesUntil)) {
          const isLastSwoosh = minutesUntil === 6 // Red-tinted at 6m (final warning before removal)
          console.log(`Shine swoosh animation for train ${trainId} at ${minutesUntil}m${isLastSwoosh ? ' (RED)' : ''}`)
          animatedMinutes.add(minutesUntil)
          animatedAtMinuteRef.current.set(trainId, animatedMinutes)

          setShineAnimatedTrains(prev => new Map(prev).set(trainId, isLastSwoosh))
          // Cleanup happens via onAnimationEnd callback, not setTimeout
        }
      }
      // Natural feasibility filtering handles removal at 6m → triggers Framer Motion exit animation
    })
  }, [trains])

  // Clean up removed trains set when they're actually gone from incoming data
  useEffect(() => {
    const currentTrainIds = new Set(trains.map(generateTrainId))
    setTrainsMarkedForRemoval(prev => {
      const filtered = new Set([...prev].filter(id => currentTrainIds.has(id)))
      // Only update if actually changed
      if (filtered.size === prev.size) return prev
      return filtered
    })
  }, [trains])

  return {
    shineAnimatedTrains,
    trainsMarkedForRemoval,
    cleanupShineAnimation
  }
}

// Bus shine animation at 4m, 3m, 2m
const useBusDepartureAnimation = (buses: BusDeparture[]) => {
  // Map stores busId -> isRedTinted (true for last swoosh at 2m)
  const [shineAnimatedBuses, setShineAnimatedBuses] = useState<Map<string, boolean>>(new Map())
  const animatedAtMinuteRef = useRef<Map<string, Set<number>>>(new Map())

  // Cleanup function to remove shine animation after it completes
  const cleanupShineAnimation = (busId: string) => {
    setShineAnimatedBuses(prev => {
      const newMap = new Map(prev)
      newMap.delete(busId)
      return newMap
    })
  }

  useEffect(() => {
    buses.forEach(bus => {
      const busId = generateBusId(bus)
      const minutesUntil = bus.minutes_until

      // Trigger shine swoosh at 3m, 2m, 1m, 0m (signals: time to go catch this bus!)
      if (minutesUntil === 3 || minutesUntil === 2 || minutesUntil === 1 || minutesUntil === 0) {
        const animatedMinutes = animatedAtMinuteRef.current.get(busId) || new Set()
        if (!animatedMinutes.has(minutesUntil)) {
          const isLastSwoosh = minutesUntil === 0 // Red-tinted at 0m (final urgent warning!)
          console.log(`Shine swoosh animation for bus ${busId} at ${minutesUntil}m${isLastSwoosh ? ' (RED)' : ''}`)
          animatedMinutes.add(minutesUntil)
          animatedAtMinuteRef.current.set(busId, animatedMinutes)

          setShineAnimatedBuses(prev => new Map(prev).set(busId, isLastSwoosh))
          // Cleanup happens via onAnimationEnd callback, not setTimeout
        }
      }
    })
  }, [buses])

  // Clean up animated buses map when they're gone from incoming data
  useEffect(() => {
    const currentBusIds = new Set(buses.map(generateBusId))
    setShineAnimatedBuses(prev => {
      const filtered = new Map([...prev].filter(([id]) => currentBusIds.has(id)))
      // Only update if actually changed
      if (filtered.size === prev.size) return prev
      return filtered
    })
  }, [buses])

  return { shineAnimatedBuses, cleanupShineAnimation }
}

// Helper functions for time-based styling
const getTimeOpacity = (minutesUntil: number): number => {
  if (minutesUntil < 0) return 0.3 // Past times very faded
  if (minutesUntil <= 15) return 1.0 // Next 15m fully visible
  if (minutesUntil >= 50) return 0.15 // 50m+ very faded

  // Smooth gradual fade from 15m (1.0) to 50m (0.15)
  const progress = (minutesUntil - 15) / (50 - 15)
  return 1.0 - (progress * 0.85)
}

const isFeasibleTrainDeparture = (minutesUntil: number): boolean => {
  return minutesUntil >= 6 // Trains leaving in <6 minutes are too hard to catch
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
  shineAnimation?: 'orange' | 'red' | null;
  onAnimationEnd?: () => void;
}> = ({ departure, shineAnimation = null, onAnimationEnd }) => {
  const adjusted = calculateAdjustedDeparture(departure)
  const opacity = adjusted.adjustedMinutesUntil === 0 ? 1.0 : getTimeOpacity(adjusted.adjustedMinutesUntil)
  const timeDisplay = formatDelayAwareTimeDisplay(departure)

  // Filter out delay info from summary_deviation_note since it's now inline
  const nonDelayNote = adjusted.isDelayed ? '' : departure.summary_deviation_note

  // Calculate delay-aware suffix
  const suffix = calculateSuffix(adjusted)

  // Apply shine swoosh gradient to entire line
  const textClass = shineAnimation === 'red' ? 'shine-swoosh-red' : shineAnimation === 'orange' ? 'shine-swoosh' : ''

  return (
    <div
      style={{
        opacity,
        mixBlendMode: 'hard-light' as const,
        display: 'flex',
        alignItems: 'flex-start'
      }}
    >
      <span
        className={textClass}
        onAnimationEnd={shineAnimation ? onAnimationEnd : undefined}
      >
        <strong>{timeDisplay}</strong>
        {nonDelayNote && `\u00A0${nonDelayNote}`}
        {suffix && `\u00A0- ${suffix}`}
      </span>
    </div>
  )
}

// Render bus departure line
const BusDepartureLine: React.FC<{
  departure: BusDeparture;
  shineAnimation?: 'orange' | 'red' | null;
  onAnimationEnd?: () => void;
}> = ({ departure, shineAnimation = null, onAnimationEnd }) => {
  const { line_number, destination, minutes_until } = departure
  const opacity = minutes_until === 0 ? 1.0 : getTimeOpacity(minutes_until)
  const timeDisplay = formatTimeDisplay(departure)

  // Apply shine swoosh gradient to entire line
  const textClass = shineAnimation === 'red' ? 'shine-swoosh-red' : shineAnimation === 'orange' ? 'shine-swoosh' : ''

  return (
    <div
      style={{
        opacity,
        mixBlendMode: 'hard-light' as const,
        display: 'flex',
        alignItems: 'flex-start'
      }}
    >
      <span
        className={textClass}
        onAnimationEnd={shineAnimation ? onAnimationEnd : undefined}
      >
        {line_number} till {destination}:{'\u00A0'}<strong>{timeDisplay}</strong>
      </span>
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

  // Shine animation at 8-9min + pre-emptive removal at 5min
  const { shineAnimatedTrains, trainsMarkedForRemoval, cleanupShineAnimation: cleanupTrainAnimation } = useTrainDepartureAnimation(trainsForHooks)

  const feasibleTrainsForHooks = trainsForHooks.filter(train => {
    const adjusted = calculateAdjustedDeparture(train)
    // Simple feasibility check - Framer Motion will animate exit when train drops below 6m
    return adjusted.adjustedMinutesUntil >= 6
  })

  const busesForHooks = structuredData?.buses || []
  const feasibleBusesForHooks = busesForHooks.filter(bus =>
    bus.minutes_until >= 0 && isFeasibleBusDeparture(bus.minutes_until)
  )

  // Call all hooks with safe data (React Hooks Rules - must be called in same order every render)
  const { shineAnimatedBuses, cleanupShineAnimation: cleanupBusAnimation } = useBusDepartureAnimation(feasibleBusesForHooks)

  // Framer Motion will handle all structural changes and animations automatically

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
  // Use derived feasible data directly (Framer Motion handles all transitions)
  const feasibleTrains = feasibleTrainsForHooks
  const feasibleBuses = feasibleBusesForHooks

  // Only show deviations for imminent departures (within next 20 minutes)
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

      // Only show if within next 20 minutes (relevant to visible departure list)
      return minutesUntilActual >= 6 && minutesUntilActual <= 20
    }

    // For non-delay deviations, limit to next 20 minutes (not just "feasible")
    const minutesUntil = getMinutesUntilFromTime(deviation.time)
    return minutesUntil >= 6 && minutesUntil <= 20
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
                <LayoutGroup>
                  <AnimatePresence mode="popLayout">
                    {feasibleTrains
                      .slice(0, 4)
                      .map((train, index) => {
                      const trainId = generateTrainId(train)
                      const isRedTinted = shineAnimatedTrains.get(trainId) // undefined if not animating, true if red, false if orange

                      // Determine shine animation state (applied to text element, not container)
                      const shineAnimation = isRedTinted === true ? 'red' : isRedTinted === false ? 'orange' : null

                      return (
                        <motion.div
                          key={trainId}
                          layout
                          initial={{ opacity: 0, y: 20 }}
                          animate={{ opacity: 1, y: 0 }}
                          exit={{ opacity: 0, y: -20 }}
                          transition={{ duration: 1 }}
                          className="train-departure-item"
                        >
                          <TrainDepartureLine
                            departure={train}
                            shineAnimation={shineAnimation}
                            onAnimationEnd={() => cleanupTrainAnimation(trainId)}
                          />
                        </motion.div>
                      )
                    })}
                  </AnimatePresence>
                </LayoutGroup>
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
                <LayoutGroup>
                  <AnimatePresence mode="popLayout">
                    {feasibleBuses.slice(0, 4).map((bus, index) => {
                      const busId = generateBusId(bus)
                      const isRedTinted = shineAnimatedBuses.get(busId) // undefined if not animating, true if red, false if orange

                      // Determine shine animation state (applied to text element, not container)
                      const shineAnimation = isRedTinted === true ? 'red' : isRedTinted === false ? 'orange' : null

                      return (
                        <motion.div
                          key={busId}
                          layout
                          initial={{ opacity: 0, y: 20 }}
                          animate={{ opacity: 1, y: 0 }}
                          exit={{ opacity: 0, y: -20 }}
                          transition={{ duration: 1 }}
                          className="bus-departure-item"
                        >
                          <BusDepartureLine
                            departure={bus}
                            shineAnimation={shineAnimation}
                            onAnimationEnd={() => cleanupBusAnimation(busId)}
                          />
                        </motion.div>
                      )
                    })}
                  </AnimatePresence>
                </LayoutGroup>
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

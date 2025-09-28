import React, { useState, useEffect, useMemo } from 'react'
import { useData } from '../context/DataContext'

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
  // Handle both "försenad X min" and just "försenad"
  const delayWithMinutes = note.match(/försenad (\d+) min/)
  if (delayWithMinutes) {
    return {
      isDelayed: true,
      delayMinutes: parseInt(delayWithMinutes[1]),
      originalNote: note
    }
  }

  // Check for just "försenad" without specific minutes
  if (note.includes('försenad')) {
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
    // If train already has delay info in summary_deviation_note, use it
    if (train.summary_deviation_note.trim()) {
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

  if (adjusted.isDelayed) {
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

// Hook for detecting list changes (not just data updates)
const useTrainListChanges = (currentTrains: TrainDeparture[]) => {
  const [prevTrainIds, setPrevTrainIds] = useState<Set<string>>(new Set())

  return useMemo(() => {
    const currentIds = new Set(currentTrains.map(generateTrainId))
    const added = [...currentIds].filter(id => !prevTrainIds.has(id))
    const removed = [...prevTrainIds].filter(id => !currentIds.has(id))

    const hasStructuralChange = added.length > 0 || removed.length > 0

    // Update state for next comparison (but don't trigger re-render)
    setTimeout(() => {
      setPrevTrainIds(currentIds)
    }, 0)

    return { hasStructuralChange, added, removed }
  }, [currentTrains, prevTrainIds])
}

const useBusListChanges = (currentBuses: BusDeparture[]) => {
  const [prevBusIds, setPrevBusIds] = useState<Set<string>>(new Set())

  return useMemo(() => {
    const currentIds = new Set(currentBuses.map(generateBusId))
    const added = [...currentIds].filter(id => !prevBusIds.has(id))
    const removed = [...prevBusIds].filter(id => !currentIds.has(id))

    const hasStructuralChange = added.length > 0 || removed.length > 0

    setTimeout(() => {
      setPrevBusIds(currentIds)
    }, 0)

    return { hasStructuralChange, added, removed }
  }, [currentBuses, prevBusIds])
}

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

const useUrgentDepartureFlashing = (trains: TrainDeparture[]) => {
  const [urgentFlashingTrains, setUrgentFlashingTrains] = useState<Set<string>>(new Set())
  const [criticalFlashingTrains, setCriticalFlashingTrains] = useState<Set<string>>(new Set())
  const [alreadyFlashed, setAlreadyFlashed] = useState<Set<string>>(new Set())

  useEffect(() => {
    trains.forEach(train => {
      const trainId = generateTrainId(train)

      // Check for urgent departures (warning phase)
      if (isUrgentDeparture(train) && !alreadyFlashed.has(trainId + '-urgent')) {
        setAlreadyFlashed(prev => new Set([...prev, trainId + '-urgent']))
        setUrgentFlashingTrains(prev => new Set([...prev, trainId]))

        // Stop flashing after 4 flashes × 2.5s = 10s
        setTimeout(() => {
          setUrgentFlashingTrains(prev => {
            const newSet = new Set(prev)
            newSet.delete(trainId)
            return newSet
          })
        }, 10000)
      }

      // Check for critical departures (emergency phase)
      if (isCriticalDeparture(train) && !alreadyFlashed.has(trainId + '-critical')) {
        setAlreadyFlashed(prev => new Set([...prev, trainId + '-critical']))
        setCriticalFlashingTrains(prev => new Set([...prev, trainId]))

        // Stop flashing after 2 flashes × 2s = 4s
        setTimeout(() => {
          setCriticalFlashingTrains(prev => {
            const newSet = new Set(prev)
            newSet.delete(trainId)
            return newSet
          })
        }, 4000)
      }
    })
  }, [trains, alreadyFlashed])

  return { urgentFlashingTrains, criticalFlashingTrains }
}

// Bus urgent departure detection and flashing
const isUrgentBusDeparture = (bus: BusDeparture): boolean => {
  // Flash when 4 minutes left (orange warning)
  return bus.minutes_until === 4
}

const isCriticalBusDeparture = (bus: BusDeparture): boolean => {
  // Flash when 3 minutes left (red-orange critical)
  return bus.minutes_until === 3
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
  return minutesUntil >= 6 // Need at least 6 minutes to reach train station
}

const isFeasibleBusDeparture = (minutesUntil: number): boolean => {
  return minutesUntil >= 0 // Bus stop is right outside (1min walk), show until departure
}

// Animated Train List Wrapper
const AnimatedTrainList: React.FC<{
  trains: TrainDeparture[];
  renderItem: (train: TrainDeparture, index: number, isUrgentFlashing: boolean, isCriticalFlashing: boolean) => React.ReactNode;
  urgentFlashingTrains?: Set<string>;
  criticalFlashingTrains?: Set<string>;
}> = ({ trains, renderItem, urgentFlashingTrains = new Set(), criticalFlashingTrains = new Set() }) => {
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
        const isUrgentFlashing = urgentFlashingTrains.has(trainId)
        const isCriticalFlashing = criticalFlashingTrains.has(trainId)

        return (
          <div
            key={trainId}
            className={`train-departure-item ${isAnimating ? 'departing' : ''}`}
            style={{ '--item-index': index } as React.CSSProperties}
          >
            {renderItem(train, index, isUrgentFlashing, isCriticalFlashing)}
          </div>
        )
      })}
    </div>
  )
}

// Animated Bus List Wrapper
const AnimatedBusList: React.FC<{
  buses: BusDeparture[];
  renderItem: (bus: BusDeparture, index: number, isUrgentFlashing: boolean, isCriticalFlashing: boolean) => React.ReactNode;
  urgentFlashingBuses?: Set<string>;
  criticalFlashingBuses?: Set<string>;
}> = ({ buses, renderItem, urgentFlashingBuses = new Set(), criticalFlashingBuses = new Set() }) => {
  const { hasStructuralChange, added, removed } = useBusListChanges(buses)
  const [animatingItems, setAnimatingItems] = useState<Set<string>>(new Set())
  const [arrivingItems, setArrivingItems] = useState<Set<string>>(new Set())

  // Handle bus removal animation
  useEffect(() => {
    if (removed.length > 0) {
      setAnimatingItems(new Set(removed))

      const timer = setTimeout(() => {
        setAnimatingItems(new Set())
      }, 400)

      return () => clearTimeout(timer)
    }
  }, [removed])

  // Handle bus arrival animation
  useEffect(() => {
    if (added.length > 0) {
      setArrivingItems(new Set(added))

      // Trigger arrival animation after a brief delay
      const timer = setTimeout(() => {
        setArrivingItems(new Set())
      }, 100)

      return () => clearTimeout(timer)
    }
  }, [added])

  return (
    <div className="train-list-container">
      {buses.map((bus, index) => {
        const busId = generateBusId(bus)
        const isDeparting = animatingItems.has(busId)
        const isArriving = arrivingItems.has(busId)
        const isUrgentFlashing = urgentFlashingBuses.has(busId)
        const isCriticalFlashing = criticalFlashingBuses.has(busId)

        const classNames = [
          'train-departure-item',
          isDeparting ? 'departing' : '',
          isArriving ? 'arriving' : 'arrived'
        ].filter(Boolean).join(' ')

        return (
          <div
            key={busId}
            className={classNames}
            style={{ '--item-index': index } as React.CSSProperties}
          >
            {renderItem(bus, index, isUrgentFlashing, isCriticalFlashing)}
          </div>
        )
      })}
    </div>
  )
}

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
        marginBottom: '2px',
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
        marginBottom: '2px',
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

  const feasibleTrainsForHooks = trainsForHooks.filter(train => {
    const adjusted = calculateAdjustedDeparture(train)
    return adjusted.adjustedMinutesUntil >= 0 && isFeasibleTrainDeparture(adjusted.adjustedMinutesUntil)
  })

  const busesForHooks = structuredData?.buses || []
  const feasibleBusesForHooks = busesForHooks.filter(bus =>
    bus.minutes_until >= 0 && isFeasibleBusDeparture(bus.minutes_until)
  )

  // Call all hooks with safe data (React Hooks Rules - must be called in same order every render)
  const { urgentFlashingTrains, criticalFlashingTrains } = useUrgentDepartureFlashing(feasibleTrainsForHooks)
  const { urgentFlashingBuses, criticalFlashingBuses } = useUrgentBusFlashing(feasibleBusesForHooks)

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
  const feasibleTrains = feasibleTrainsForHooks
  const feasibleBuses = feasibleBusesForHooks

  // Debug logging
  console.log('Bus data debug:', {
    totalBuses: buses.length,
    buses: buses.map(b => `${b.line_number} to ${b.destination} at ${b.departure_time} (${b.minutes_until}m)`),
    feasibleBuses: feasibleBuses.length,
    generatedAt: structuredData.generated_at
  })

  // Only show deviations for feasible departures
  const feasibleDeviations = deviations.filter(deviation =>
    isFeasibleTrainDeparture(getMinutesUntilFromTime(deviation.time))
  )

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
                <AnimatedTrainList
                  trains={feasibleTrains}
                  renderItem={(train, index, isUrgentFlashing, isCriticalFlashing) => (
                    <TrainDepartureLine
                      departure={train}
                      isUrgentFlashing={isUrgentFlashing}
                      isCriticalFlashing={isCriticalFlashing}
                    />
                  )}
                  urgentFlashingTrains={urgentFlashingTrains}
                  criticalFlashingTrains={criticalFlashingTrains}
                />
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
                <AnimatedBusList
                  buses={feasibleBuses}
                  renderItem={(bus, index, isUrgentFlashing, isCriticalFlashing) => (
                    <BusDepartureLine
                      departure={bus}
                      isUrgentFlashing={isUrgentFlashing}
                      isCriticalFlashing={isCriticalFlashing}
                    />
                  )}
                  urgentFlashingBuses={urgentFlashingBuses}
                  criticalFlashingBuses={criticalFlashingBuses}
                />
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

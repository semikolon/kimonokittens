import React from 'react'
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

// Helper functions for time-based styling
const getTimeOpacity = (minutesUntil: number): number => {
  if (minutesUntil < 0) return 0.3 // Past times very faded
  if (minutesUntil <= 20) return 1.0 // Next 20m fully visible
  if (minutesUntil >= 50) return 0.15 // 50m+ very faded

  // Smooth gradual fade from 20m (1.0) to 50m (0.15)
  const progress = (minutesUntil - 20) / (50 - 20)
  return 1.0 - (progress * 0.85)
}

const isFeasibleDeparture = (minutesUntil: number): boolean => {
  return minutesUntil >= 6 // Need at least 6 minutes to reach station
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
const TrainDepartureLine: React.FC<{ departure: TrainDeparture }> = ({ departure }) => {
  const { departure_time, minutes_until, summary_deviation_note, suffix } = departure
  const opacity = minutes_until === 0 ? 1.0 : getTimeOpacity(minutes_until)
  const timeDisplay = formatTimeDisplay(departure)

  return (
    <div
      style={{
        opacity,
        mixBlendMode: 'hard-light' as const,
        marginBottom: '2px',
        display: 'flex',
        alignItems: 'flex-start'
      }}
    >
      <strong>{timeDisplay}</strong>
      {summary_deviation_note}
      {suffix && ` ${suffix}`}
    </div>
  )
}

// Render bus departure line
const BusDepartureLine: React.FC<{ departure: BusDeparture }> = ({ departure }) => {
  const { line_number, destination, minutes_until } = departure
  const opacity = minutes_until === 0 ? 1.0 : getTimeOpacity(minutes_until)
  const timeDisplay = formatTimeDisplay(departure)

  return (
    <div
      style={{
        opacity,
        mixBlendMode: 'hard-light' as const,
        marginBottom: '2px',
        display: 'flex',
        alignItems: 'flex-start'
      }}
    >
      {line_number} till {destination}: <strong>{timeDisplay}</strong>
    </div>
  )
}

// Render deviation alerts
const DeviationAlerts: React.FC<{ deviations: Deviation[] }> = ({ deviations }) => {
  if (!deviations.length) return null

  // Group deviations by reason for cleaner display
  const grouped = deviations.reduce((acc, deviation) => {
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

  const loading = connectionStatus === 'connecting' && !trainData
  const error = connectionStatus === 'closed' ? 'WebSocket-anslutning avbruten' : null

  if (loading) {
    return <div className="text-purple-200">Laddar...</div>
  }

  if (error) {
    return (
      <div>
        <div className="text-red-400">Fel: {error}</div>
        <div className="text-xs text-purple-200 mt-1">
          (Kontrollera att SL API fungerar)
        </div>
      </div>
    )
  }

  if (!trainData) {
    return <div className="text-purple-200">Ingen data tillgänglig</div>
  }

  // Handle both old HTML format (backwards compatibility) and new structured format
  const isStructuredData = trainData.trains !== undefined

  if (!isStructuredData) {
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

  const structuredData = trainData as StructuredTransportData
  const { trains, buses, deviations } = structuredData

  // Filter for feasible departures (past and too-soon departures are hidden)
  const feasibleTrains = trains.filter(train =>
    train.minutes_until >= 0 && isFeasibleDeparture(train.minutes_until)
  )

  const feasibleBuses = buses.filter(bus =>
    bus.minutes_until >= 0 && isFeasibleDeparture(bus.minutes_until)
  )

  // Only show deviations for feasible departures
  const feasibleDeviations = deviations.filter(deviation =>
    isFeasibleDeparture(getMinutesUntilFromTime(deviation.time))
  )

  return (
    <div>
      <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
        {/* Train Section */}
        <div>
          <h4 className="text-xl font-medium text-purple-100 mb-6 tracking-wide uppercase font-[Horsemen]">
            Pendel norrut
          </h4>

          <DeviationAlerts deviations={feasibleDeviations} />

          <div className="mb-3">
            <div className="leading-relaxed">
              {feasibleTrains.length > 0 ? (
                feasibleTrains.map((train, index) => (
                  <TrainDepartureLine key={index} departure={train} />
                ))
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
                feasibleBuses.map((bus, index) => (
                  <BusDepartureLine key={index} departure={bus} />
                ))
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
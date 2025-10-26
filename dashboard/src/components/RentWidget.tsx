import React from 'react'
import { useData } from '../context/DataContext'

// Daily Electricity Cost Bar Component
function DailyElectricityCostBar({ dailyCosts }: { dailyCosts: Array<{ date: string; weekday: string; price: number; consumption: number; avg_temp_c?: number }> }) {
  if (!dailyCosts || dailyCosts.length === 0) return null

  // Reverse to show oldest first (left to right chronologically)
  const days = dailyCosts.slice().reverse()

  // Prepare sparkline data
  const prices = days.map(d => d.price)
  const minPrice = Math.min(...prices)
  const maxPrice = Math.max(...prices)
  const priceRange = maxPrice - minPrice || 1

  // Generate electricity cost sparkline path
  const electricityPath = days.map((day, index) => {
    const x = (index / (days.length - 1)) * 100
    const normalizedPrice = ((day.price - minPrice) / priceRange)
    const y = 100 - (normalizedPrice * 80) // Use 0-80% range (leave 20% margin at top)
    return `${x},${y}`
  }).join(' L ')

  // Generate temperature sparkline path (if we have temperature data)
  const hasTemperatureData = days.some(d => d.avg_temp_c !== undefined)
  let temperaturePath = ''
  if (hasTemperatureData) {
    const temps = days.map(d => d.avg_temp_c || 0).filter(t => t !== 0)
    if (temps.length > 0) {
      const minTemp = Math.min(...temps)
      const maxTemp = Math.max(...temps)
      const tempRange = maxTemp - minTemp || 1

      temperaturePath = days.map((day, index) => {
        const x = (index / (days.length - 1)) * 100
        const normalizedTemp = ((day.avg_temp_c || 0) - minTemp) / tempRange
        const y = 100 - (normalizedTemp * 80) // Use 0-80% range (leave 20% margin at top)
        return `${x},${y}`
      }).join(' L ')
    }
  }

  return (
    <div className="mt-3">
      <div className="text-purple-200 mb-2" style={{ textTransform: 'uppercase', fontSize: '0.8em' }}>
        Senaste veckans elkostnader
      </div>
      <div
        className="relative h-16 rounded-lg overflow-visible"
        style={{
          background: 'rgba(255, 255, 255, 0.1)',
          mixBlendMode: 'overlay'
        }}
      >
        {/* Sparkline overlays */}
        <svg
          className="absolute inset-0 w-full h-full pointer-events-none"
          viewBox="0 0 100 100"
          preserveAspectRatio="none"
          style={{
            zIndex: 5,
            clipPath: 'inset(0 round 0.5rem)'
          }}
        >
          {/* Temperature sparkline (orange, behind) */}
          {temperaturePath && (
            <path
              d={`M ${temperaturePath}`}
              fill="none"
              stroke="#ffcc99"
              strokeWidth="1.5"
              vectorEffect="non-scaling-stroke"
              opacity="0.4"
            />
          )}

          {/* Electricity cost sparkline (purple, front) */}
          <path
            d={`M ${electricityPath}`}
            fill="none"
            stroke="rgb(216, 180, 254)"
            strokeWidth="2"
            vectorEffect="non-scaling-stroke"
            opacity="0.6"
          />
        </svg>

        {/* Day sections */}
        <div className="absolute inset-0 flex">
          {days.map((day, index) => (
            <div
              key={`${day.date}-${index}`}
              className="flex-1 relative h-full flex flex-col items-center justify-center"
              style={{
                marginRight: index < days.length - 1 ? '2px' : '0'
              }}
            >
              {/* Background chunk */}
              <div
                className={`absolute inset-0 ${index === 0 ? 'rounded-l-lg' : ''} ${index === days.length - 1 ? 'rounded-r-lg' : ''}`}
                style={{
                  backgroundColor: '#ffffff',
                  opacity: '30%',
                  mixBlendMode: 'overlay'
                }}
              />

              {/* Text content */}
              <div className="relative z-10 flex flex-col items-center">
                <div className="text-purple-200 text-xs font-semibold">{day.weekday}</div>
                <div className="text-purple-100 text-sm font-bold">{Math.round(day.price)} kr</div>
              </div>
            </div>
          ))}
        </div>
      </div>
    </div>
  )
}

export function RentWidget() {
  const { state } = useData()
  const { rentData, electricityDailyCostsData, connectionStatus } = state

  if (connectionStatus !== 'open') {
    return (
      <div className="p-6 flex justify-center">
        <div className="w-4 h-4 text-red-400/30" title="No connection to server">
          <svg viewBox="0 0 20 20" fill="currentColor">
            <path fillRule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zM8.707 7.293a1 1 0 00-1.414 1.414L8.586 10l-1.293 1.293a1 1 0 101.414 1.414L10 11.414l1.293 1.293a1 1 0 001.414-1.414L11.414 10l1.293-1.293a1 1 0 00-1.414-1.414L10 8.586 8.707 7.293z" clipRule="evenodd" />
          </svg>
        </div>
      </div>
    )
  }

  if (!rentData) {
    return (
      <div className="p-6 text-purple-300">
        <div className="text-sm">No rent data available</div>
      </div>
    )
  }

  // Parse the friendly message to extract the header and amount(s)
  if (!rentData.message) {
    return (
      <div className="p-6 text-purple-300">
        <div className="text-sm">Invalid rent data format</div>
      </div>
    )
  }

  const lines = rentData.message.split('\n').filter(line => line.trim())

  // Function to convert markdown-style bold (*text*) to React elements
  const parseMarkdown = (text: string) => {
    const parts = text.split(/(\*[^*]+\*)/)
    return parts.map((part, index) => {
      if (part.startsWith('*') && part.endsWith('*')) {
        // Remove asterisks and make bold
        const boldText = part.slice(1, -1)
        return <strong key={index} className="font-bold">{boldText}</strong>
      }
      return part
    })
  }

  const header = lines[0]
  const amounts = lines.slice(1) // Everything after header

  return (
    <div>
      {header && (
        <div className="text-purple-200 mb-3 leading-relaxed">
          {parseMarkdown(header)}
        </div>
      )}

      <div className="space-y-2">
        {amounts.map((line, index) => {
          // Parse individual rent lines - look for bold amounts (marked with *)
          const cleanLine = line.replace(/\*/g, '') // Remove all asterisks

          // Split on "kr" to separate amount from description
          const parts = cleanLine.split(' kr')
          if (parts.length >= 2) {
            const beforeKr = parts[0]
            const afterKr = parts.slice(1).join(' kr') // In case there are multiple "kr" instances

            return (
              <div key={index} className="flex items-baseline gap-2">
                <span className="text-2xl font-bold text-purple-100">
                  {beforeKr.trim()} kr
                </span>
                <span className="text-purple-300">
                  {afterKr.trim()}
                </span>
              </div>
            )
          } else {
            // Fallback for lines that don't follow expected format
            return (
              <div key={index} className="text-purple-200">
                {parseMarkdown(cleanLine)}
              </div>
            )
          }
        })}
      </div>

      {/* Data source transparency indicator */}
      {rentData.data_source && (
        <div className="text-purple-300 text-xs mt-3" style={{ opacity: 0.5 }}>
          {rentData.data_source.description_sv}
          {rentData.electricity_amount && rentData.electricity_month &&
            ` - ${rentData.electricity_amount} kr för ${rentData.electricity_month} månads förbrukning`
          }
        </div>
      )}

      {/* Heating cost impact line */}
      {rentData.heating_cost_line && (
        <div className="text-purple-300 text-xs mt-2" style={{ opacity: 0.5 }}>
          {rentData.heating_cost_line}
        </div>
      )}

      {/* Electricity daily costs bar */}
      {electricityDailyCostsData && electricityDailyCostsData.daily_costs.length > 0 && (
        <DailyElectricityCostBar dailyCosts={electricityDailyCostsData.daily_costs} />
      )}
    </div>
  )
}
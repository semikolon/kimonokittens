import React, { useState, useEffect } from 'react'
import { useData } from '../context/DataContext'

// Anomaly Summary Component - generates dynamic text about anomalous electricity usage
function AnomalySummaryText({ anomalySummary }: {
  anomalySummary?: {
    total_anomalies: number
    anomalous_days: Array<{
      date: string
      consumption: number
      expected: number
      temp_c: number
      excess_pct: number  // Positive = higher than expected, Negative = lower than expected
    }>
  }
}) {
  const [summaryText, setSummaryText] = useState<string | null>(null)

  useEffect(() => {
    if (!anomalySummary || anomalySummary.anomalous_days.length === 0) {
      setSummaryText(null)
      return
    }

    const anomalousDays = anomalySummary.anomalous_days

    // Parse and sort dates
    const sortedDays = [...anomalousDays].sort((a, b) => {
      const aDate = new Date(`${a.date} 2025`)
      const bDate = new Date(`${b.date} 2025`)
      return aDate.getTime() - bDate.getTime()
    })

    // Group consecutive dates into ranges
    interface DateRange {
      start: string
      end: string
      days: typeof sortedDays
      avgExcess: number
      isHigh: boolean
    }

    const ranges: DateRange[] = []
    let currentRange: DateRange | null = null

    sortedDays.forEach((day, index) => {
      const isHigh = day.excess_pct > 0
      const dayDate = new Date(`${day.date} 2025`)

      if (!currentRange) {
        // Start new range
        currentRange = {
          start: day.date,
          end: day.date,
          days: [day],
          avgExcess: day.excess_pct,
          isHigh
        }
      } else {
        const prevDate = new Date(`${currentRange.end} 2025`)
        const daysDiff = (dayDate.getTime() - prevDate.getTime()) / (1000 * 60 * 60 * 24)
        const sameType = currentRange.isHigh === isHigh

        if (daysDiff <= 3 && sameType) {
          // Extend current range (within 3 days and same type)
          currentRange.end = day.date
          currentRange.days.push(day)
        } else {
          // Finalize current range and start new one
          currentRange.avgExcess = currentRange.days.reduce((sum, d) => sum + d.excess_pct, 0) / currentRange.days.length
          ranges.push(currentRange)
          currentRange = {
            start: day.date,
            end: day.date,
            days: [day],
            avgExcess: day.excess_pct,
            isHigh
          }
        }
      }

      // Finalize last range
      if (index === sortedDays.length - 1 && currentRange) {
        currentRange.avgExcess = currentRange.days.reduce((sum, d) => sum + d.excess_pct, 0) / currentRange.days.length
        ranges.push(currentRange)
      }
    })

    // Build granular sentence
    const segments = ranges.map(range => {
      const dateStr = range.start === range.end ? range.start : `${range.start}-${range.end}`
      const type = range.isHigh ? 'oväntat hög' : 'oväntat låg'
      const pct = range.avgExcess > 0 ? `+${Math.round(range.avgExcess)}` : Math.round(range.avgExcess)
      return `${dateStr}: ${type} (ca ${pct}%)`
    })

    const finalText = `Elförbrukning ${segments.join(', ')}`
    setSummaryText(finalText)
  }, [anomalySummary])

  if (!summaryText) return null

  return (
    <div className="text-purple-300 text-xs mb-3" style={{ opacity: 0.7 }}>
      {summaryText}
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

      {/* Anomaly summary text - dynamic based on detected anomalies */}
      {electricityDailyCostsData?.summary?.anomaly_summary && (
        <AnomalySummaryText anomalySummary={electricityDailyCostsData.summary.anomaly_summary} />
      )}

      {/* Heating cost impact line */}
      {rentData.heating_cost_line && (
        <div className="text-purple-300 text-xs mt-2" style={{ opacity: 0.5 }}>
          {rentData.heating_cost_line}
        </div>
      )}
    </div>
  )
}
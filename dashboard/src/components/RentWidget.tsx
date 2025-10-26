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
      price_per_kwh: number
      cost_impact: number  // In SEK, positive = cost, negative = savings
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

    // Separate high and low anomalies
    const highAnomalies = sortedDays.filter(d => d.excess_pct > 0)
    const lowAnomalies = sortedDays.filter(d => d.excess_pct < 0)

    // Build intelligent summary with smart grouping
    interface AnomalyGroup {
      type: 'high' | 'low'
      dateRange: string
      avgPct: number
    }

    // Helper to group anomalies with temporal clustering
    const clusterAnomalies = (anomalies: typeof sortedDays, maxGapDays: number) => {
      if (anomalies.length === 0) return []

      const clusters: typeof sortedDays[] = []
      let currentCluster: typeof sortedDays = [anomalies[0]]

      for (let i = 1; i < anomalies.length; i++) {
        const prevDate = new Date(`${currentCluster[currentCluster.length - 1].date} 2025`)
        const currDate = new Date(`${anomalies[i].date} 2025`)
        const daysDiff = (currDate.getTime() - prevDate.getTime()) / (1000 * 60 * 60 * 24)

        if (daysDiff <= maxGapDays) {
          // Add to current cluster
          currentCluster.push(anomalies[i])
        } else {
          // Start new cluster
          clusters.push(currentCluster)
          currentCluster = [anomalies[i]]
        }
      }

      // Add final cluster
      clusters.push(currentCluster)
      return clusters
    }

    // Helper to format date range
    const formatDateRange = (cluster: typeof sortedDays) => {
      if (cluster.length === 1) return cluster[0].date

      const first = cluster[0].date
      const last = cluster[cluster.length - 1].date

      // If same month, show compact format
      if (first.split(' ')[0] === last.split(' ')[0]) {
        const month = first.split(' ')[0]
        const firstDay = first.split(' ')[1]
        const lastDay = last.split(' ')[1]
        return `${firstDay}-${lastDay} ${month}`
      }

      return `${first} - ${last}`
    }

    const groups: AnomalyGroup[] = []

    // Process high anomalies with 14-day clustering
    const highClusters = clusterAnomalies(highAnomalies, 14)
    highClusters.forEach(cluster => {
      const avgPct = cluster.reduce((sum, d) => sum + d.excess_pct, 0) / cluster.length
      groups.push({
        type: 'high',
        dateRange: formatDateRange(cluster),
        avgPct: Math.round(avgPct)
      })
    })

    // Process low anomalies with 14-day clustering
    const lowClusters = clusterAnomalies(lowAnomalies, 14)
    lowClusters.forEach(cluster => {
      const avgPct = cluster.reduce((sum, d) => sum + d.excess_pct, 0) / cluster.length
      groups.push({
        type: 'low',
        dateRange: formatDateRange(cluster),
        avgPct: Math.round(avgPct)
      })
    })

    // Sort groups chronologically by first date
    groups.sort((a, b) => {
      const aDate = new Date(`${a.dateRange.split(' ')[0].split('-')[0]} ${a.dateRange.split(' ')[a.dateRange.split(' ').length - 1]} 2025`)
      const bDate = new Date(`${b.dateRange.split(' ')[0].split('-')[0]} ${b.dateRange.split(' ')[b.dateRange.split(' ').length - 1]} 2025`)
      return aDate.getTime() - bDate.getTime()
    })

    // Build final text
    const segments = groups.map(g => {
      const typeText = g.type === 'high' ? 'oväntat hög' : 'oväntat låg'
      const pctText = g.avgPct > 0 ? `+${g.avgPct}` : g.avgPct
      return `${g.dateRange}: ${typeText} (ca ${pctText}%)`
    })

    // Add explanation based on what types of anomalies exist
    const hasHigh = groups.some(g => g.type === 'high')
    const hasLow = groups.some(g => g.type === 'low')

    let explanation = ''
    if (hasHigh && hasLow) {
      explanation = '. Förmodligen pga varierande antal personer i huset'
    } else if (hasHigh) {
      explanation = '. Förmodligen pga fler personer i huset'
    } else if (hasLow) {
      explanation = '. Förmodligen pga färre personer i huset'
    }

    const finalText = `Elförbrukning ${segments.join(', ')}${explanation}`
    setSummaryText(finalText)
  }, [anomalySummary])

  if (!summaryText) return null

  return (
    <div className="text-purple-300 text-xs mb-3" style={{ opacity: 0.7 }}>
      {summaryText}
    </div>
  )
}

// Anomaly Sparkline Bar - Visual representation of electricity usage anomalies
function AnomalySparklineBar({ anomalySummary, regressionData }: {
  anomalySummary?: {
    total_anomalies: number
    anomalous_days: Array<{
      date: string
      consumption: number
      expected: number
      temp_c: number
      excess_pct: number
      price_per_kwh: number
      cost_impact: number
    }>
  }
  regressionData?: Array<{
    date: string
    excess_pct: number
  }>
}) {
  if (!anomalySummary || anomalySummary.anomalous_days.length === 0) {
    return null
  }

  // Prepare chunk data for visualization
  const anomalousDays = anomalySummary.anomalous_days

  // Parse and sort dates
  const sortedDays = [...anomalousDays].sort((a, b) => {
    const aDate = new Date(`${a.date} 2025`)
    const bDate = new Date(`${b.date} 2025`)
    return aDate.getTime() - bDate.getTime()
  })

  // Separate high and low anomalies
  const highAnomalies = sortedDays.filter(d => d.excess_pct > 0)
  const lowAnomalies = sortedDays.filter(d => d.excess_pct < 0)

  // Cluster anomalies (same logic as text component - 14-day window)
  const clusterAnomalies = (anomalies: typeof sortedDays, maxGapDays: number) => {
    if (anomalies.length === 0) return []

    const clusters: typeof sortedDays[] = []
    let currentCluster: typeof sortedDays = [anomalies[0]]

    for (let i = 1; i < anomalies.length; i++) {
      const prevDate = new Date(`${currentCluster[currentCluster.length - 1].date} 2025`)
      const currDate = new Date(`${anomalies[i].date} 2025`)
      const daysDiff = (currDate.getTime() - prevDate.getTime()) / (1000 * 60 * 60 * 24)

      if (daysDiff <= maxGapDays) {
        currentCluster.push(anomalies[i])
      } else {
        clusters.push(currentCluster)
        currentCluster = [anomalies[i]]
      }
    }
    clusters.push(currentCluster)
    return clusters
  }

  const highClusters = clusterAnomalies(highAnomalies, 14)
  const lowClusters = clusterAnomalies(lowAnomalies, 14)

  // Build chunks for visualization
  interface AnomalyChunk {
    type: 'high' | 'low'
    dateRange: string
    startDate: Date
    endDate: Date
    durationDays: number
    avgExcessPct: number
    totalCostImpact: number
  }

  const chunks: AnomalyChunk[] = []

  // Process high clusters
  highClusters.forEach((cluster, clusterIndex) => {
    const startDate = new Date(`${cluster[0].date} 2025`)
    const endDate = new Date(`${cluster[cluster.length - 1].date} 2025`)
    const durationDays = Math.round((endDate.getTime() - startDate.getTime()) / (1000 * 60 * 60 * 24)) + 1
    const avgExcessPct = Math.round(cluster.reduce((sum, d) => sum + d.excess_pct, 0) / cluster.length)
    const totalCostImpact = cluster.reduce((sum, d) => sum + d.cost_impact, 0)

    // Debug: Log individual days in cluster
    console.log(`High cluster ${clusterIndex + 1}:`, cluster.map(d => ({
      date: d.date,
      consumption: d.consumption,
      expected: d.expected,
      excess_pct: d.excess_pct,
      price_per_kwh: d.price_per_kwh,
      cost_impact: d.cost_impact
    })))

    // Format date range
    let dateRange
    if (cluster.length === 1) {
      dateRange = cluster[0].date
    } else {
      const first = cluster[0].date
      const last = cluster[cluster.length - 1].date
      if (first.split(' ')[0] === last.split(' ')[0]) {
        const month = first.split(' ')[0]
        const firstDay = first.split(' ')[1]
        const lastDay = last.split(' ')[1]
        dateRange = `${firstDay}-${lastDay} ${month}`
      } else {
        dateRange = `${first} - ${last}`
      }
    }

    chunks.push({
      type: 'high',
      dateRange,
      startDate,
      endDate,
      durationDays,
      avgExcessPct,
      totalCostImpact: Math.round(totalCostImpact)
    })
  })

  // Process low clusters
  lowClusters.forEach((cluster, clusterIndex) => {
    const startDate = new Date(`${cluster[0].date} 2025`)
    const endDate = new Date(`${cluster[cluster.length - 1].date} 2025`)
    const durationDays = Math.round((endDate.getTime() - startDate.getTime()) / (1000 * 60 * 60 * 24)) + 1
    const avgExcessPct = Math.round(cluster.reduce((sum, d) => sum + d.excess_pct, 0) / cluster.length)
    const totalCostImpact = cluster.reduce((sum, d) => sum + d.cost_impact, 0)

    // Debug: Log individual days in cluster
    console.log(`Low cluster ${clusterIndex + 1}:`, cluster.map(d => ({
      date: d.date,
      consumption: d.consumption,
      expected: d.expected,
      excess_pct: d.excess_pct,
      price_per_kwh: d.price_per_kwh,
      cost_impact: d.cost_impact
    })))

    let dateRange
    if (cluster.length === 1) {
      dateRange = cluster[0].date
    } else {
      const first = cluster[0].date
      const last = cluster[cluster.length - 1].date
      if (first.split(' ')[0] === last.split(' ')[0]) {
        const month = first.split(' ')[0]
        const firstDay = first.split(' ')[1]
        const lastDay = last.split(' ')[1]
        dateRange = `${firstDay}-${lastDay} ${month}`
      } else {
        dateRange = `${first} - ${last}`
      }
    }

    chunks.push({
      type: 'low',
      dateRange,
      startDate,
      endDate,
      durationDays,
      avgExcessPct,
      totalCostImpact: Math.round(totalCostImpact)
    })
  })

  // Sort chunks chronologically
  chunks.sort((a, b) => a.startDate.getTime() - b.startDate.getTime())

  // Debug logging for cost verification
  console.log('Anomaly chunks:', chunks.map(c => ({
    dateRange: c.dateRange,
    type: c.type,
    avgExcessPct: c.avgExcessPct,
    totalCostImpact: c.totalCostImpact,
    durationDays: c.durationDays
  })))

  // Generate continuous sparkline from full regression data (all 90 days)
  const generateSparkline = () => {
    if (!regressionData || regressionData.length === 0) return ''

    const width = 100
    const totalDays = regressionData.length

    // Map each day to SVG coordinates
    const points = regressionData.map((day, index) => {
      const x = (index / totalDays) * width
      // Map excess_pct to y coordinate (invert y-axis, center at 50)
      // -50% → y=75, 0% → y=50, +50% → y=25
      const y = 50 - (day.excess_pct / 2)
      return `${x},${y}`
    })

    // Create smooth continuous path
    return `M ${points.join(' L ')}`
  }

  const sparklinePath = generateSparkline()

  return (
    <div className="mt-3 mb-3">
      <div className="relative h-20 rounded-lg overflow-hidden"
           style={{ background: 'rgba(255, 255, 255, 0.05)' }}>

        {/* Sparkline SVG overlay */}
        <svg className="absolute inset-0 w-full h-full" viewBox="0 0 100 100" preserveAspectRatio="none">
          <path
            d={sparklinePath}
            stroke="rgba(216, 180, 254, 0.4)"
            strokeWidth="1"
            fill="none"
            vectorEffect="non-scaling-stroke"
          />
          {/* Baseline at 0% */}
          <line
            x1="0"
            y1="50"
            x2="100"
            y2="50"
            stroke="rgba(216, 180, 254, 0.2)"
            strokeWidth="0.5"
            vectorEffect="non-scaling-stroke"
          />
        </svg>

        {/* Chunk visualization */}
        <div className="absolute inset-0 flex">
          {chunks.map((chunk, index) => (
            <div
              key={index}
              className="relative h-full"
              style={{ flex: `${chunk.durationDays} 0 0` }}
            >
              {/* Background chunk */}
              <div className="absolute inset-0 bg-white" style={{ opacity: 0.05 }} />

              {/* Text content with horizontal padding */}
              <div className="relative z-10 flex flex-col items-center justify-center h-full text-center"
                   style={{ padding: '0 1em' }}>
                <div className="text-[10px] text-purple-100 leading-tight">{chunk.dateRange}</div>
                <div className="text-sm font-bold text-purple-50">
                  {chunk.avgExcessPct > 0 ? '+' : ''}{chunk.avgExcessPct}%
                </div>
                <div className="text-[10px] text-purple-200">
                  {chunk.totalCostImpact > 0 ? '+' : ''}{chunk.totalCostImpact} kr
                </div>
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

      {/* Anomaly sparkline bar - visual representation of detected anomalies */}
      {electricityDailyCostsData?.summary?.anomaly_summary && (
        <AnomalySparklineBar
          anomalySummary={electricityDailyCostsData.summary.anomaly_summary}
          regressionData={electricityDailyCostsData.summary.regression_data}
        />
      )}
    </div>
  )
}
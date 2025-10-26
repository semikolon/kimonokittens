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
  const [isLoading, setIsLoading] = useState(false)

  useEffect(() => {
    if (!anomalySummary || anomalySummary.anomalous_days.length === 0) {
      setSummaryText(null)
      return
    }

    const anomalousDays = anomalySummary.anomalous_days

    // Create cache key based on anomaly dates and percentages
    const cacheKey = `anomaly_summary_${anomalousDays.map(d => `${d.date}_${d.excess_pct}`).join('_')}`
    const today = new Date().toISOString().split('T')[0]

    // Check cache first (valid for 24 hours)
    // TEMPORARILY DISABLED for prompt testing
    // try {
    //   const cached = localStorage.getItem(cacheKey)
    //   if (cached) {
    //     const { text, date } = JSON.parse(cached)
    //     if (date === today) {
    //       setSummaryText(text)
    //       return
    //     }
    //   }
    // } catch (e) {
    //   // Ignore cache errors
    // }

    // Separate high and low anomalies
    const highAnomalies = anomalousDays.filter(d => d.excess_pct > 0)
    const lowAnomalies = anomalousDays.filter(d => d.excess_pct < 0)

    // Generate summary text via GPT-5-nano
    const generateSummary = async () => {
      setIsLoading(true)
      try {
        // Build date ranges string
        const formatDateRange = (days: typeof anomalousDays) => {
          if (days.length === 0) return ''
          if (days.length === 1) return days[0].date
          if (days.length === 2) return `${days[0].date} och ${days[1].date}`

          // Group consecutive dates
          const sorted = days.sort((a, b) => {
            const aDate = new Date(`${a.date} 2025`)
            const bDate = new Date(`${b.date} 2025`)
            return aDate.getTime() - bDate.getTime()
          })

          return `${sorted[0].date} -> ${sorted[sorted.length - 1].date}`
        }

        const prompt = `Du är en svensk textgenerator. Följ EXAKT denna meningsstruktur:

${highAnomalies.length > 0 ? `"Högre förbrukning än väntat ${formatDateRange(highAnomalies)}. Förmodligen pga fler personer i huset."` : ''}
${lowAnomalies.length > 0 ? `"Lägre förbrukning än väntat ${formatDateRange(lowAnomalies)}. Förmodligen pga färre personer i huset."` : ''}

Data:
${highAnomalies.length > 0 ? `HÖGRE: ${highAnomalies.map(d => `${d.date} (+${Math.round(d.excess_pct)}%)`).join(', ')}` : ''}
${lowAnomalies.length > 0 ? `LÄGRE: ${lowAnomalies.map(d => `${d.date} (${Math.round(d.excess_pct)}%)`).join(', ')}` : ''}

Använd EXAKT formatet ovan. Om flera datum: använd "datum1 -> datum2" format. Max 25 ord total.`

        const response = await fetch('https://api.openai.com/v1/chat/completions', {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'Authorization': `Bearer ${import.meta.env.VITE_OPENAI_API_KEY || import.meta.env.OPENAI_API_KEY || ''}`
          },
          body: JSON.stringify({
            model: 'gpt-5-nano',
            messages: [{ role: 'user', content: prompt }],
            max_completion_tokens: 5000  // GPT-5-nano needs generous allocation for hidden reasoning tokens
            // Note: gpt-5-nano only supports default temperature (1), custom values cause 400 error
          })
        })

        if (!response.ok) {
          const errorBody = await response.json()
          console.error('OpenAI API error:', response.status, errorBody)
          setSummaryText(null)
          return
        }

        const data = await response.json()
        const text = data.choices?.[0]?.message?.content?.trim()

        if (text) {
          // Cache the result
          try {
            localStorage.setItem(cacheKey, JSON.stringify({ text, date: today }))
          } catch (e) {
            // Ignore cache write errors
          }
          setSummaryText(text)
        }
      } catch (error) {
        console.error('Error generating anomaly summary:', error)
        setSummaryText(null)
      } finally {
        setIsLoading(false)
      }
    }

    generateSummary()
  }, [anomalySummary])

  if (!summaryText && !isLoading) return null

  return (
    <div className="text-purple-300 text-xs mb-3" style={{ opacity: 0.7 }}>
      {isLoading ? 'Analyserar elförbrukning...' : summaryText}
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
import React, { useState, useEffect } from 'react'
import { useData } from '../context/DataContext'

// Anomaly Summary Component - generates dynamic text about anomalous electricity usage
function AnomalySummaryText({ dailyCosts }: { dailyCosts: Array<{ date: string; weekday: string; price: number; consumption: number; avg_temp_c?: number; anomalous_usage_pct?: number }> }) {
  const [summaryText, setSummaryText] = useState<string | null>(null)
  const [isLoading, setIsLoading] = useState(false)

  useEffect(() => {
    // Extract anomalous days (threshold: 20% excess)
    const anomalousDays = dailyCosts.filter(day => day.anomalous_usage_pct && day.anomalous_usage_pct >= 20)

    if (anomalousDays.length === 0) {
      setSummaryText(null)
      return
    }

    // Generate summary text via GPT-5-nano
    const generateSummary = async () => {
      setIsLoading(true)
      try {
        const prompt = `Du är en svensk textgenerator för en hyresräkningsapp. Skapa EN KORT MENING (max 20 ord) på svenska som förklarar avvikande eldagar.

Anomalidata:
${anomalousDays.map(d => `- ${d.weekday} ${d.date}: +${Math.round(d.anomalous_usage_pct!)}% över normalt (${d.consumption} kWh)`).join('\n')}

Kontext:
- Högre förbrukning beror troligen på fler personer i huset
- Juli/augusti 2025 hade extra person (Amanda)
- Fokusera på VARFÖR, inte bara VAD

Exempel godkänd mening: "Högre förbrukning vissa dagar (juli/augusti) beror troligen på fler personer i huset då."

Generera EN mening (max 20 ord):`

        const response = await fetch('https://api.openai.com/v1/chat/completions', {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'Authorization': `Bearer ${import.meta.env.VITE_OPENAI_API_KEY || import.meta.env.OPENAI_API_KEY || ''}`
          },
          body: JSON.stringify({
            model: 'gpt-5-nano',
            messages: [{ role: 'user', content: prompt }],
            max_completion_tokens: 100,
            temperature: 0.3
          })
        })

        if (!response.ok) {
          console.error('Failed to generate anomaly summary:', response.statusText)
          setSummaryText(null)
          return
        }

        const data = await response.json()
        const text = data.choices?.[0]?.message?.content?.trim()
        setSummaryText(text || null)
      } catch (error) {
        console.error('Error generating anomaly summary:', error)
        setSummaryText(null)
      } finally {
        setIsLoading(false)
      }
    }

    generateSummary()
  }, [dailyCosts])

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
      {electricityDailyCostsData && electricityDailyCostsData.daily_costs.length > 0 && (
        <AnomalySummaryText dailyCosts={electricityDailyCostsData.daily_costs} />
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
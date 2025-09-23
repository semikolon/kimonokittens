import React from 'react'
import { useData } from '../context/DataContext'

// Helper functions for time-based filtering and styling
const parseTime = (timeStr: string): Date | null => {
  const match = timeStr.match(/(\d{2}):(\d{2})/)
  if (!match) return null

  const now = new Date()
  const [, hours, minutes] = match
  const time = new Date(now.getFullYear(), now.getMonth(), now.getDate(), parseInt(hours), parseInt(minutes))

  // If time is earlier than current time, assume it's tomorrow
  if (time <= now) {
    time.setDate(time.getDate() + 1)
  }

  return time
}

const getMinutesUntil = (timeStr: string): number => {
  const time = parseTime(timeStr)
  if (!time) return -1

  const now = new Date()
  return Math.round((time.getTime() - now.getTime()) / (1000 * 60))
}

const isFeasibleDeparture = (timeStr: string): boolean => {
  const minutesUntil = getMinutesUntil(timeStr)
  return minutesUntil >= 6 // Need at least 6 minutes to reach station
}

const getTimeOpacity = (timeStr: string): number => {
  const minutesUntil = getMinutesUntil(timeStr)
  if (minutesUntil < 0) return 0.3 // Past times very faded
  if (minutesUntil <= 20) return 1.0 // Next 20m fully visible
  if (minutesUntil >= 50) return 0.15 // 50m+ very faded

  // Smooth gradual fade from 20m (1.0) to 50m (0.15)
  const progress = (minutesUntil - 20) / (50 - 20)
  return 1.0 - (progress * 0.85)
}

// Parse and style departure times HTML with time-based opacity
const parseAndStyleDepartureTimes = (htmlContent: string) => {
  const timePattern = /(\d{2}:\d{2})/g

  // Split content into lines and process each line separately
  const lines = htmlContent.split(/(<br\s*\/?>)/gi)

  return lines.map((line, lineIndex) => {
    if (line.match(/<br\s*\/?>/i)) {
      return null // Skip <br> elements entirely
    }

    if (line.trim() === '') return null

    // Find the first time in this line to determine opacity for the entire line
    const timeMatch = line.match(timePattern)
    if (!timeMatch) return null // Skip lines without times

    const minutesUntil = getMinutesUntil(timeMatch[0])
    if (minutesUntil < 0) return null // Skip past times

    // For 0m departures, show normal opacity since they display "- spring!"
    const lineOpacity = minutesUntil === 0 ? 1.0 : getTimeOpacity(timeMatch[0])

    // Parse HTML in this line while preserving structure
    const tempDiv = document.createElement('div')
    tempDiv.innerHTML = line

    const processElement = (element: Node): React.ReactNode[] => {
      const result: React.ReactNode[] = []

      element.childNodes.forEach((child, index) => {
        if (child.nodeType === Node.TEXT_NODE) {
          let text = child.textContent || ''
          if (text.trim()) {
            // Fix spacing issues in the text content
            // Add space after colon for bus lines (e.g., "station:16:03" -> "station: 16:03")
            text = text.replace(/([^:\s]):(\d{2}:\d{2})/, '$1: $2')

            // Add space after "om Xm" before "- du hinner gå" for train lines
            text = text.replace(/(om \d+m)(-\s)/, '$1 $2')

            // Add space before "(försenad)" and similar parenthetical content
            text = text.replace(/(\d+m)(\([^)]+\))/, '$1 $2')

            // Handle 0m case - replace "om 0m" with "spring!" to avoid double dash
            text = text.replace(/om 0m/, 'spring!')

            result.push(text)
          }
        } else if (child.nodeType === Node.ELEMENT_NODE) {
          const elem = child as Element
          let content = processElement(child)

          if (elem.tagName === 'STRONG') {
            // Handle 0m case in strong elements too
            if (content.length === 1 && typeof content[0] === 'string') {
              let strongText = content[0] as string
              // Fix spacing issues in strong text
              strongText = strongText.replace(/([^:\s]):(\d{2}:\d{2})/, '$1: $2')
              strongText = strongText.replace(/(om \d+m)(-\s)/, '$1 $2')
              strongText = strongText.replace(/(\d+m)(\([^)]+\))/, '$1 $2')
              strongText = strongText.replace(/om 0m/, 'spring!')
              content = [strongText]
            }
            result.push(<strong key={index}>{content}</strong>)
          } else {
            result.push(<span key={index}>{content}</span>)
          }
        }
      })

      return result
    }

    const lineContent = processElement(tempDiv)

    return (
      <div
        key={`line-${lineIndex}`}
        style={{
          opacity: lineOpacity,
          mixBlendMode: 'hard-light' as const,
          marginBottom: '2px',
          display: 'flex',
          alignItems: 'flex-start'
        }}
      >
        {lineContent}
      </div>
    )
  }).filter(Boolean)
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

  // Parse the HTML content to extract and style the sections properly
  const parseTrainData = (htmlContent: string) => {
    // Split by common patterns to separate train and bus sections
    const sections = htmlContent.split(/(?=Bussar från)/g)

    return sections.map((section, index) => {
      if (section.includes('Pendeltåg Norrut') || (!section.includes('Bussar från') && index === 0)) {
        // Train section
        return (
          <div key="train">
            <h4 className="text-xl font-medium text-purple-100 mb-6 tracking-wide uppercase font-[Horsemen]">
              Pendel norrut
            </h4>
{trainData.deviation_summary && (() => {
              // Parse and group disruptions by reason
              const disruptions = trainData.deviation_summary.split(/(?=\d{2}:\d{2}\s+till)/g)
                .filter(line => line.trim())
                .map(line => {
                  const timeMatch = line.match(/(\d{2}:\d{2})\s+till\s+([^:]+):\s*(.+)/);
                  if (timeMatch) {
                    return {
                      time: timeMatch[1],
                      destination: timeMatch[2],
                      reason: timeMatch[3]
                    };
                  }
                  return null;
                })
                .filter(Boolean);

              // Group by reason
              const grouped = disruptions.reduce((acc, item) => {
                const key = item.reason.trim();
                if (!acc[key]) acc[key] = [];
                acc[key].push(item);
                return acc;
              }, {});

              // Filter out non-feasible departures and render grouped disruptions
              const feasibleItems = Object.entries(grouped)
                .map(([reason, items]) => ({
                  reason,
                  items: items.filter(item => isFeasibleDeparture(item.time))
                }))
                .filter(({ items }) => items.length > 0); // Only show groups with feasible departures

              // Only render if we have feasible disruptions (minimal fix)
              return feasibleItems.length > 0 ? (
                <div className="text-yellow-400 bg-yellow-400/10 p-2 rounded inline-block max-w-full mb-3 -ml-2">
                  <div className="space-y-1">
                    {feasibleItems.map(({ reason, items }, index) => (
                      <div key={index} className="leading-tight">
                        <strong>{items.map(item => item.time).join(', ')}:</strong> {reason.replace(/\.\s*läs mer på trafikläget\.?/gi, '.')}
                      </div>
                    ))}
                  </div>
                </div>
              ) : null;
            })()}
            <div className="mb-3">
              <div className="leading-relaxed">
                {parseAndStyleDepartureTimes(section.replace(/Pendeltåg Norrut[:\s]*/g, '').replace(/^(<br\s*\/?>)+/gi, '').replace(/<br\s*\/?>\s*<br\s*\/?>\s*<strong>\s*<\/strong>\s*$/gi, ' ').replace(/(<br\s*\/?>)+$/gi, ''))}
              </div>
            </div>
          </div>
        )
      } else if (section.includes('Bussar från')) {
        // Bus section
        return (
          <div key="bus">
            <h4 className="text-xl font-medium text-purple-100 mb-6 tracking-wide uppercase font-[Horsemen]">
              Bussar
            </h4>
            <div className="mb-3">
              <div className="leading-relaxed">
                {parseAndStyleDepartureTimes(section.replace(/Bussar från Sördalavägen[:\s]*/g, '').replace(/^(<br\s*\/?>)+/gi, '').replace(/(<br\s*\/?>)+$/gi, ''))}
              </div>
            </div>
          </div>
        )
      }
      return null
    }).filter(Boolean)
  }

  const sections = parseTrainData(trainData.summary)

  return (
    <div>
      <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
        {sections}
      </div>
    </div>
  )
}

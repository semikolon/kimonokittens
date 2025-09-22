import React from 'react'
import { useData } from '../context/DataContext'

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
            <h4 className="text-xl font-medium text-purple-100 mb-2 tracking-wide uppercase font-[Horsemen]">
              Pendel
            </h4>
            <div className="mb-3">
              <div
                className="leading-relaxed"
                dangerouslySetInnerHTML={{ __html: section.replace(/Pendeltåg Norrut[:\s]*/g, '') }}
              />
            </div>
            {trainData.deviation_summary && (
              <div className="text-yellow-400 bg-yellow-400/10 p-2 rounded inline-block max-w-full">
                <div className="font-bold mb-1">Störningar:</div>
                <div className="space-y-1">
                  {trainData.deviation_summary.split(/(?=\d{2}:\d{2}\s+till)/g)
                    .filter(line => line.trim())
                    .map((line, index) => (
                      <div key={index} className="leading-tight">
                        {line.trim()}
                      </div>
                    ))}
                </div>
              </div>
            )}
          </div>
        )
      } else if (section.includes('Bussar från')) {
        // Bus section
        return (
          <div key="bus">
            <h4 className="text-xl font-medium text-purple-100 mb-2 tracking-wide uppercase font-[Horsemen]">
              Bussar
            </h4>
            <div className="mb-3">
              <div
                className="leading-relaxed"
                dangerouslySetInnerHTML={{ __html: section.replace(/Bussar från Sördalavägen[:\s]*/g, '').replace(/^\s+/g, '').replace(/^[\n\r]+/g, '') }}
              />
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

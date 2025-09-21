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
          <div key="train" className="mb-4">
            <h4 className="text-sm font-medium text-purple-100 mb-2 tracking-wide uppercase font-[Horsemen]">
              Pendeltåg Norrut
            </h4>
            <div
              className="text-sm leading-relaxed"
              dangerouslySetInnerHTML={{ __html: section.replace(/Pendeltåg Norrut[:\s]*/g, '') }}
            />
          </div>
        )
      } else if (section.includes('Bussar från')) {
        // Bus section
        return (
          <div key="bus">
            <h4 className="text-sm font-medium text-purple-100 mb-2 tracking-wide uppercase font-[Horsemen]">
              Bussar från Sördalavägen
            </h4>
            <div
              className="text-sm leading-relaxed"
              dangerouslySetInnerHTML={{ __html: section.replace(/Bussar från Sördalavägen[:\s]*/g, '') }}
            />
          </div>
        )
      }
      return null
    }).filter(Boolean)
  }

  return (
    <div>
      {parseTrainData(trainData.summary)}
      {trainData.deviation_summary && (
        <div className="mt-3 text-xs text-yellow-400 bg-yellow-400/10 p-2 rounded">
          <strong>Störningar:</strong> {trainData.deviation_summary}
        </div>
      )}
    </div>
  )
} 
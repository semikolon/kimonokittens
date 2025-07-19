import React from 'react'
import { useData } from '../context/DataContext'

export function TrainWidget() {
  const { state } = useData()
  const { trainData, connectionStatus } = state
  
  const loading = connectionStatus === 'connecting' && !trainData
  const error = connectionStatus === 'closed' ? 'WebSocket-anslutning avbruten' : null

  if (loading) {
    return (
      <div className="widget">
        <div className="widget-title">Pendeltåg Norrut</div>
        <div className="widget-content">
          <div className="text-gray-400">Laddar...</div>
        </div>
      </div>
    )
  }

  if (error) {
    return (
      <div className="widget">
        <div className="widget-title">Pendeltåg Norrut</div>
        <div className="widget-content">
          <div className="text-red-400">Fel: {error}</div>
          <div className="text-xs text-gray-400 mt-1">
            (Kontrollera att SL API fungerar)
          </div>
        </div>
      </div>
    )
  }

  if (!trainData) {
    return (
      <div className="widget">
        <div className="widget-title">Pendeltåg Norrut</div>
        <div className="widget-content">
          <div className="text-gray-400">Ingen data tillgänglig</div>
        </div>
      </div>
    )
  }

  return (
    <div className="widget">
      <div className="widget-title">Pendeltåg Norrut</div>
      <div className="widget-content">
        <div 
          className="text-sm leading-relaxed"
          dangerouslySetInnerHTML={{ __html: trainData.summary }}
        />
        {trainData.deviation_summary && (
          <div className="mt-3 text-xs text-yellow-400 bg-yellow-400/10 p-2 rounded">
            <strong>Störningar:</strong> {trainData.deviation_summary}
          </div>
        )}
      </div>
    </div>
  )
} 
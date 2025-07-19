import React from 'react'
import { useData } from '../context/DataContext'

export function StravaWidget() {
  const { state } = useData()
  const { stravaData, connectionStatus } = state
  
  const loading = connectionStatus === 'connecting' && !stravaData
  const error = connectionStatus === 'closed' ? 'WebSocket-anslutning avbruten' : null

  if (loading) {
    return (
      <div className="widget">
        <div className="widget-title">Fredriks Löpning</div>
        <div className="widget-content">
          <div className="text-gray-400">Laddar...</div>
        </div>
      </div>
    )
  }

  if (error) {
    return (
      <div className="widget">
        <div className="widget-title">Fredriks Löpning</div>
        <div className="widget-content">
          <div className="text-red-400">Fel: {error}</div>
        </div>
      </div>
    )
  }

  if (!stravaData) {
    return (
      <div className="widget">
        <div className="widget-title">Fredriks Löpning</div>
        <div className="widget-content">
          <div className="text-gray-400">Ingen data tillgänglig</div>
        </div>
      </div>
    )
  }

  return (
    <div className="widget">
      <div className="widget-title">Fredriks Löpning</div>
      <div className="widget-content">
        <div className="flex items-center mb-2">
          <span className="text-2xl mr-2">🏃‍♂️</span>
        </div>
        <div 
          className="text-sm leading-relaxed"
          dangerouslySetInnerHTML={{ __html: stravaData.runs }}
        />
      </div>
    </div>
  )
} 
import React from 'react'
import { useData } from '../context/DataContext'

export function StravaWidget() {
  const { state } = useData()
  const { stravaData, connectionStatus } = state

  const loading = connectionStatus === 'connecting' && !stravaData
  const error = connectionStatus === 'closed' ? 'WebSocket-anslutning avbruten' : null

  if (loading) {
    return <div className="text-purple-200">Laddar...</div>
  }

  if (error) {
    return <div className="text-red-400">Fel: {error}</div>
  }

  if (!stravaData) {
    return <div className="text-purple-200">Ingen data tillgänglig</div>
  }

  return (
    <div
      className="text-purple-200 leading-relaxed"
      dangerouslySetInnerHTML={{ __html: stravaData.runs }}
    />
  )
}
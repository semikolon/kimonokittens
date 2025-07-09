import React, { useState, useEffect } from 'react'

interface StravaData {
  runs: string
}

export function StravaWidget() {
  const [data, setData] = useState<StravaData | null>(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    const fetchStravaData = async () => {
      try {
        const response = await fetch('/data/strava_stats')
        if (!response.ok) {
          throw new Error(`HTTP ${response.status}`)
        }
        const stravaData = await response.json()
        setData(stravaData)
        setError(null)
      } catch (error) {
        console.error('Failed to fetch Strava data:', error)
        setError(error instanceof Error ? error.message : 'Unknown error')
      } finally {
        setLoading(false)
      }
    }

    fetchStravaData()
    const interval = setInterval(fetchStravaData, 300000) // Update every 5 minutes

    return () => clearInterval(interval)
  }, [])

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
          <div className="text-xs text-gray-400 mt-1">
            (Kontrollera Strava API-nycklar)
          </div>
        </div>
      </div>
    )
  }

  if (!data) {
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
          dangerouslySetInnerHTML={{ __html: data.runs }}
        />
      </div>
    </div>
  )
} 
import React, { useState, useEffect } from 'react'

interface TrainData {
  summary: string
  deviation_summary: string
}

export function TrainWidget() {
  const [data, setData] = useState<TrainData | null>(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    const fetchTrainData = async () => {
      try {
        const response = await fetch('/data/train_departures')
        if (!response.ok) {
          throw new Error(`HTTP ${response.status}`)
        }
        const trainData = await response.json()
        setData(trainData)
        setError(null)
      } catch (error) {
        console.error('Failed to fetch train data:', error)
        setError(error instanceof Error ? error.message : 'Unknown error')
      } finally {
        setLoading(false)
      }
    }

    fetchTrainData()
    const interval = setInterval(fetchTrainData, 60000) // Update every minute

    return () => clearInterval(interval)
  }, [])

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

  if (!data) {
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
          dangerouslySetInnerHTML={{ __html: data.summary }}
        />
        {data.deviation_summary && (
          <div className="mt-3 text-xs text-yellow-400 bg-yellow-400/10 p-2 rounded">
            <strong>Störningar:</strong> {data.deviation_summary}
          </div>
        )}
      </div>
    </div>
  )
} 
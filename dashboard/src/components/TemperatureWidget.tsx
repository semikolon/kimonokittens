import React, { useState, useEffect } from 'react'

interface TemperatureData {
  indoor_temperature: string
  target_temperature: string
  supplyline_temperature: string
  hotwater_temperature: string
  indoor_humidity: string
  heatpump_disabled: number
  heating_demand: string
  current_schedule: string
  last_updated_time: string
  last_updated_date: string
  offline_percentage: string
}

export function TemperatureWidget() {
  const [data, setData] = useState<TemperatureData | null>(null)
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    const fetchTemperature = async () => {
      try {
        const response = await fetch('http://localhost:3001/data/temperature')
        const tempData = await response.json()
        setData(tempData)
      } catch (error) {
        console.error('Failed to fetch temperature data:', error)
      } finally {
        setLoading(false)
      }
    }

    fetchTemperature()
    const interval = setInterval(fetchTemperature, 30000) // Update every 30 seconds

    return () => clearInterval(interval)
  }, [])

  if (loading) {
    return (
      <div className="widget">
        <div className="widget-title">Inomhus</div>
        <div className="widget-content">
          <div className="text-gray-400">Laddar...</div>
        </div>
      </div>
    )
  }

  if (!data) {
    return (
      <div className="widget">
        <div className="widget-title">Inomhus</div>
        <div className="widget-content">
          <div className="text-gray-400">Ingen data tillgänglig</div>
        </div>
      </div>
    )
  }

  return (
    <div className="widget">
      <div className="widget-title">Inomhus</div>
      <div className="widget-content space-y-2">
        <div className="flex justify-between">
          <span>Temperatur:</span>
          <span className="font-bold">{data.indoor_temperature}</span>
        </div>
        <div className="flex justify-between">
          <span>Mål:</span>
          <span>{data.target_temperature}</span>
        </div>
        <div className="flex justify-between">
          <span>Luftfuktighet:</span>
          <span>{data.indoor_humidity}</span>
        </div>
        <div className="flex justify-between">
          <span>Varmvatten:</span>
          <span>{data.hotwater_temperature}</span>
        </div>
        <div className="flex justify-between">
          <span>Värme:</span>
          <span className={data.heating_demand === 'NEJ' ? 'text-green-400' : 'text-red-400'}>
            {data.heating_demand}
          </span>
        </div>
        <div className="text-xs text-gray-400 mt-2">
          Uppdaterad: {data.last_updated_date} {data.last_updated_time}
        </div>
      </div>
    </div>
  )
} 
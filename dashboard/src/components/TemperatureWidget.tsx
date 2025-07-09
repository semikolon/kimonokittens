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
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    const fetchTemperature = async () => {
      try {
        const response = await fetch('/data/temperature')
        if (!response.ok) {
          throw new Error(`HTTP ${response.status}`)
        }
        const tempData = await response.json()
        setData(tempData)
        setError(null)
      } catch (error) {
        console.error('Failed to fetch temperature data:', error)
        setError(error instanceof Error ? error.message : 'Unknown error')
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

  if (error) {
    return (
      <div className="widget">
        <div className="widget-title">Inomhus</div>
        <div className="widget-content">
          <div className="text-red-400">Fel: {error}</div>
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

  const getTemperatureIcon = (temp: string, target: string) => {
    const tempNum = parseFloat(temp.replace('º', ''))
    const targetNum = parseFloat(target.replace('º', ''))
    
    if (tempNum > targetNum + 1) return '🔥'
    if (tempNum < targetNum - 1) return '❄️'
    return '🌡️'
  }

  const getHumidityIcon = (humidity: string) => {
    const humidityNum = parseFloat(humidity.replace('%', ''))
    if (humidityNum > 60) return '💧'
    if (humidityNum < 40) return '🏜️'
    return '💨'
  }

  return (
    <div className="widget">
      <div className="widget-title">Inomhus</div>
      <div className="widget-content">
        <div className="grid grid-cols-2 gap-3 mb-4">
          <div className="flex items-center">
            <span className="text-2xl mr-2">
              {getTemperatureIcon(data.indoor_temperature, data.target_temperature)}
            </span>
            <div>
              <div className="text-2xl font-bold">{data.indoor_temperature}</div>
              <div className="text-xs text-gray-400">Temperatur</div>
            </div>
          </div>
          
          <div className="flex items-center">
            <span className="text-2xl mr-2">🎯</span>
            <div>
              <div className="text-2xl font-bold">{data.target_temperature}</div>
              <div className="text-xs text-gray-400">Mål</div>
            </div>
          </div>
          
          <div className="flex items-center">
            <span className="text-2xl mr-2">
              {getHumidityIcon(data.indoor_humidity)}
            </span>
            <div>
              <div className="text-2xl font-bold">{data.indoor_humidity}</div>
              <div className="text-xs text-gray-400">Luftfuktighet</div>
            </div>
          </div>
          
          <div className="flex items-center">
            <span className="text-2xl mr-2">♨️</span>
            <div>
              <div className="text-2xl font-bold">{data.hotwater_temperature}</div>
              <div className="text-xs text-gray-400">Varmvatten</div>
            </div>
          </div>
        </div>

        <div className="text-xs text-gray-400 space-y-1">
          <div className="flex justify-between">
            <span>Värmepump:</span>
            <span className={data.heatpump_disabled ? 'text-red-400' : 'text-green-400'}>
              {data.heatpump_disabled ? 'Av' : 'På'}
            </span>
          </div>
          <div className="flex justify-between">
            <span>Värmebehov:</span>
            <span className={data.heating_demand === 'JA' ? 'text-orange-400' : 'text-gray-400'}>
              {data.heating_demand}
            </span>
          </div>
          <div className="flex justify-between">
            <span>Uppdaterad:</span>
            <span>{data.last_updated_date} {data.last_updated_time}</span>
          </div>
        </div>
      </div>
    </div>
  )
} 
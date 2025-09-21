import React from 'react'
import { useData } from '../context/DataContext'

export function TemperatureWidget() {
  const { state } = useData()
  const { temperatureData, connectionStatus } = state

  const loading = connectionStatus === 'connecting' && !temperatureData
  const error = connectionStatus === 'closed' ? 'WebSocket-anslutning avbruten' : null

  if (loading) {
    return <div className="text-purple-200">Laddar...</div>
  }

  if (error) {
    return (
      <div>
        <div className="text-red-400">Fel: {error}</div>
      </div>
    )
  }

  if (!temperatureData) {
    return <div className="text-purple-200">Ingen data tillgänglig</div>
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
    <div>
      <div className="grid grid-cols-2 gap-3 mb-4">
        <div className="flex items-center">
          <span className="text-2xl mr-2">
            {getTemperatureIcon(temperatureData.indoor_temperature, temperatureData.target_temperature)}
          </span>
          <div>
            <div className="text-2xl font-bold text-purple-100">{temperatureData.indoor_temperature}</div>
            <div className="text-xs text-purple-200">Temperatur</div>
          </div>
        </div>

        <div className="flex items-center">
          <span className="text-2xl mr-2">🎯</span>
          <div>
            <div className="text-2xl font-bold text-purple-100">{temperatureData.target_temperature}</div>
            <div className="text-xs text-purple-200">Mål</div>
          </div>
        </div>

        <div className="flex items-center">
          <span className="text-2xl mr-2">
            {getHumidityIcon(temperatureData.indoor_humidity)}
          </span>
          <div>
            <div className="text-2xl font-bold text-purple-100">{temperatureData.indoor_humidity}</div>
            <div className="text-xs text-purple-200">Luftfuktighet</div>
          </div>
        </div>

        <div className="flex items-center">
          <span className="text-2xl mr-2">♨️</span>
          <div>
            <div className="text-2xl font-bold text-purple-100">{temperatureData.hotwater_temperature}</div>
            <div className="text-xs text-purple-200">Varmvatten</div>
          </div>
        </div>
      </div>

      <div className="text-xs text-purple-200 space-y-1">
        <div className="flex justify-between">
          <span>Värmepump:</span>
          <span className={temperatureData.heatpump_disabled ? 'text-red-400' : 'text-green-400'}>
            {temperatureData.heatpump_disabled ? 'Av' : 'På'}
          </span>
        </div>
        <div className="flex justify-between">
          <span>Värmebehov:</span>
          <span className={temperatureData.heating_demand === 'JA' ? 'text-orange-400' : 'text-purple-200'}>
            {temperatureData.heating_demand}
          </span>
        </div>
        <div className="flex justify-between">
          <span>Uppdaterad:</span>
          <span>{temperatureData.last_updated_date} {temperatureData.last_updated_time}</span>
        </div>
      </div>
    </div>
  )
} 
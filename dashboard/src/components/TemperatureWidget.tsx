import React from 'react'
import { useData } from '../context/DataContext'
import { Thermometer, Target, Droplets, Zap } from 'lucide-react'

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

  const getTemperatureIcon = () => <Thermometer className="w-6 h-6 text-purple-200" />
  const getTargetIcon = () => <Target className="w-6 h-6 text-purple-200" />
  const getHumidityIcon = () => <Droplets className="w-6 h-6 text-purple-200" />
  const getHotWaterIcon = () => <Zap className="w-6 h-6 text-purple-200" />

  return (
    <div>
      <div className="grid grid-cols-2 gap-3 mb-4">
        <div className="flex items-center">
          <div className="mr-2">
            {getTemperatureIcon()}
          </div>
          <div>
            <div className="text-3xl font-bold text-purple-100">{temperatureData.indoor_temperature}</div>
            <div className="text-purple-200">Temperatur</div>
          </div>
        </div>

        <div className="flex items-center">
          <div className="mr-2">
            {getTargetIcon()}
          </div>
          <div>
            <div className="text-3xl font-bold text-purple-100">{temperatureData.target_temperature}</div>
            <div className="text-purple-200">Mål</div>
          </div>
        </div>

        <div className="flex items-center">
          <div className="mr-2">
            {getHumidityIcon()}
          </div>
          <div>
            <div className="text-3xl font-bold text-purple-100">{temperatureData.indoor_humidity}</div>
            <div className="text-purple-200">Luftfuktighet</div>
          </div>
        </div>

        <div className="flex items-center">
          <div className="mr-2">
            {getHotWaterIcon()}
          </div>
          <div>
            <div className="text-3xl font-bold text-purple-100">{temperatureData.hotwater_temperature}</div>
            <div className="text-purple-200">Varmvatten</div>
          </div>
        </div>
      </div>

      <div className="text-purple-200 space-y-1">
        <div className="flex justify-between">
          <span>Värmepump:</span>
          <span className={temperatureData.heatpump_disabled ? 'text-purple-100' : 'text-purple-100'}>
            {temperatureData.heatpump_disabled ? 'Av' : 'På'}
          </span>
        </div>
        <div className="flex justify-between">
          <span>Värmebehov:</span>
          <span className={temperatureData.heating_demand === 'JA' ? 'text-purple-100' : 'text-purple-200'}>
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
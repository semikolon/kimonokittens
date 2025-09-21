import React from 'react'
import { useData } from '../context/DataContext'

export function WeatherWidget() {
  const { state } = useData()
  const { weatherData, connectionStatus } = state

  const loading = connectionStatus === 'connecting' && !weatherData
  const error = connectionStatus === 'closed' ? 'WebSocket-anslutning avbruten' : null

  if (loading) {
    return <div className="text-purple-200">Laddar...</div>
  }

  if (error) {
    return <div className="text-red-400">Fel: {error}</div>
  }

  if (!weatherData) {
    return <div className="text-purple-200">Ingen data tillgänglig</div>
  }

  if (weatherData.error) {
    return <div className="text-red-400">{weatherData.error}</div>
  }

  const getWeatherIcon = (iconUrl: string) => {
    // Convert weather API icon to emoji
    if (iconUrl.includes('sun') || iconUrl.includes('clear')) return '☀️'
    if (iconUrl.includes('cloud')) return '☁️'
    if (iconUrl.includes('rain')) return '🌧️'
    if (iconUrl.includes('snow')) return '❄️'
    if (iconUrl.includes('thunder')) return '⛈️'
    return '🌤️'
  }

  const getTemperatureColor = (temp: number | null) => {
    if (!temp) return 'text-purple-200'
    if (temp < 0) return 'text-blue-400'
    if (temp < 10) return 'text-blue-300'
    if (temp < 20) return 'text-green-400'
    if (temp < 30) return 'text-yellow-400'
    return 'text-red-400'
  }

  const getAQIColor = (usEpaIndex: number) => {
    if (usEpaIndex <= 1) return 'text-green-400'
    if (usEpaIndex <= 2) return 'text-yellow-400'
    if (usEpaIndex <= 3) return 'text-orange-400'
    if (usEpaIndex <= 4) return 'text-red-400'
    if (usEpaIndex <= 5) return 'text-purple-400'
    return 'text-red-600'
  }

  const getAQIText = (usEpaIndex: number) => {
    if (usEpaIndex <= 1) return 'Bra'
    if (usEpaIndex <= 2) return 'OK'
    if (usEpaIndex <= 3) return 'Måttlig'
    if (usEpaIndex <= 4) return 'Dålig'
    if (usEpaIndex <= 5) return 'Mycket dålig'
    return 'Farlig'
  }

  return (
    <div>
      {/* Current Weather */}
      <div className="flex items-center justify-between mb-4">
        <div className="flex items-center">
          <span className="text-4xl mr-3">
            {getWeatherIcon(weatherData.current.condition.icon)}
          </span>
          <div>
            <div className={`text-3xl font-bold ${getTemperatureColor(weatherData.current.temp_c)}`}>
              {weatherData.current.temp_c}°
            </div>
            <div className="text-xs text-purple-200">
              {weatherData.current.condition.text}
            </div>
          </div>
        </div>

        <div className="text-xs text-purple-200 text-right">
          <div>💧 {weatherData.current.humidity}%</div>
          <div>💨 {weatherData.current.wind_kph} km/h {weatherData.current.wind_dir}</div>
          {weatherData.current.air_quality && (
            <div className={getAQIColor(weatherData.current.air_quality.us_epa_index)}>
              🏭 AQI: {getAQIText(weatherData.current.air_quality.us_epa_index)}
            </div>
          )}
        </div>
      </div>

      {/* 3-Day Forecast */}
      <div className="space-y-2">
        <div className="text-xs text-purple-200 mb-2">3-dagars prognos</div>
        {weatherData.forecast.forecastday.slice(0, 3).map((day, index) => (
          <div key={day.date} className="flex items-center justify-between text-xs">
            <div className="flex items-center">
              <span className="text-lg mr-2">
                {getWeatherIcon(day.day.condition.icon)}
              </span>
              <span className="text-purple-100">
                {index === 0 ? 'Idag' :
                 index === 1 ? 'Imorgon' :
                 new Date(day.date).toLocaleDateString('sv-SE', { weekday: 'short' })}
              </span>
            </div>

            <div className="flex items-center space-x-2">
              <span className={`font-bold ${getTemperatureColor(day.day.maxtemp_c)}`}>
                {Math.round(day.day.maxtemp_c)}°
              </span>
              <span className="text-purple-200">
                {Math.round(day.day.mintemp_c)}°
              </span>
              {day.day.chance_of_rain > 30 && (
                <span className="text-blue-400">
                  💧{day.day.chance_of_rain}%
                </span>
              )}
            </div>
          </div>
        ))}
      </div>
    </div>
  )
} 
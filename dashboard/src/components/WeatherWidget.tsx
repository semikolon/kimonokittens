import React from 'react'
import { useData } from '../context/DataContext'

export function WeatherWidget() {
  const { state } = useData()
  const { weatherData, connectionStatus } = state
  
  const loading = connectionStatus === 'connecting' && !weatherData
  const error = connectionStatus === 'closed' ? 'WebSocket-anslutning avbruten' : null

  if (loading) {
    return (
      <div className="widget">
        <div className="widget-title">Väder</div>
        <div className="widget-content">
          <div className="text-gray-400">Laddar...</div>
        </div>
      </div>
    )
  }

  if (error) {
    return (
      <div className="widget">
        <div className="widget-title">Väder</div>
        <div className="widget-content">
          <div className="text-red-400">Fel: {error}</div>
        </div>
      </div>
    )
  }

  if (!weatherData) {
    return (
      <div className="widget">
        <div className="widget-title">Väder</div>
        <div className="widget-content">
          <div className="text-gray-400">Ingen data tillgänglig</div>
        </div>
      </div>
    )
  }

  if (weatherData.error) {
    return (
      <div className="widget">
        <div className="widget-title">Väder</div>
        <div className="widget-content">
          <div className="text-red-400">{weatherData.error}</div>
        </div>
      </div>
    )
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
    if (!temp) return 'text-gray-400'
    if (temp < 0) return 'text-blue-400'
    if (temp < 10) return 'text-blue-300'
    if (temp < 20) return 'text-green-400'
    if (temp < 30) return 'text-yellow-400'
    return 'text-red-400'
  }

  return (
    <div className="widget">
      <div className="widget-title">Väder - {weatherData.location.name}</div>
      <div className="widget-content">
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
              <div className="text-xs text-gray-400">
                {weatherData.current.condition.text}
              </div>
            </div>
          </div>
          
          <div className="text-xs text-gray-400 text-right">
            <div>💧 {weatherData.current.humidity}%</div>
            <div>💨 {weatherData.current.wind_kph} km/h {weatherData.current.wind_dir}</div>
          </div>
        </div>

        {/* 3-Day Forecast */}
        <div className="space-y-2">
          <div className="text-xs text-gray-400 mb-2">3-dagars prognos</div>
          {weatherData.forecast.forecastday.slice(0, 3).map((day, index) => (
            <div key={day.date} className="flex items-center justify-between text-xs">
              <div className="flex items-center">
                <span className="text-lg mr-2">
                  {getWeatherIcon(day.day.condition.icon)}
                </span>
                <span className="text-gray-300">
                  {index === 0 ? 'Idag' : 
                   index === 1 ? 'Imorgon' : 
                   new Date(day.date).toLocaleDateString('sv-SE', { weekday: 'short' })}
                </span>
              </div>
              
              <div className="flex items-center space-x-2">
                <span className={`font-bold ${getTemperatureColor(day.day.maxtemp_c)}`}>
                  {Math.round(day.day.maxtemp_c)}°
                </span>
                <span className="text-gray-400">
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
    </div>
  )
} 
import React, { useState, useEffect } from 'react'

interface WeatherCondition {
  text: string
  icon: string
}

interface WeatherCurrent {
  temp_c: number | null
  condition: WeatherCondition
  humidity: number | null
  wind_kph: number | null
  wind_dir: string | null
}

interface ForecastDay {
  date: string
  day: {
    maxtemp_c: number
    mintemp_c: number
    condition: WeatherCondition
    chance_of_rain: number
  }
}

interface WeatherData {
  current: WeatherCurrent
  forecast: {
    forecastday: ForecastDay[]
  }
  location: {
    name: string
    country: string
  }
  error?: string
}

export function WeatherWidget() {
  const [data, setData] = useState<WeatherData | null>(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    const fetchWeatherData = async () => {
      try {
        const response = await fetch('/data/weather')
        if (!response.ok) {
          throw new Error(`HTTP ${response.status}`)
        }
        const rawData = await response.json()
        
        // Transform the server response format (with colons) to our expected format
        const weatherData: WeatherData = {
          current: {
            temp_c: rawData[':current']?.[':temp_c'] || null,
            condition: {
              text: rawData[':current']?.[':condition']?.[':text'] || 'Okänt',
              icon: rawData[':current']?.[':condition']?.[':icon'] || ''
            },
            humidity: rawData[':current']?.[':humidity'] || null,
            wind_kph: rawData[':current']?.[':wind_kph'] || null,
            wind_dir: rawData[':current']?.[':wind_dir'] || null
          },
          forecast: {
            forecastday: rawData[':forecast']?.[':forecastday'] || []
          },
          location: {
            name: rawData[':location']?.[':name'] || 'Okänd plats',
            country: rawData[':location']?.[':country'] || 'Okänt land'
          },
          error: rawData[':error']
        }
        
        setData(weatherData)
        setError(null)
      } catch (error) {
        console.error('Failed to fetch weather data:', error)
        setError(error instanceof Error ? error.message : 'Unknown error')
      } finally {
        setLoading(false)
      }
    }

    fetchWeatherData()
    const interval = setInterval(fetchWeatherData, 600000) // Update every 10 minutes

    return () => clearInterval(interval)
  }, [])

  if (loading) {
    return (
      <div className="widget">
        <div className="widget-title">Väder - Huddinge</div>
        <div className="widget-content">
          <div className="text-gray-400">Laddar...</div>
        </div>
      </div>
    )
  }

  if (error) {
    return (
      <div className="widget">
        <div className="widget-title">Väder - Huddinge</div>
        <div className="widget-content">
          <div className="text-red-400">Fel: {error}</div>
        </div>
      </div>
    )
  }

  if (!data) {
    return (
      <div className="widget">
        <div className="widget-title">Väder - Huddinge</div>
        <div className="widget-content">
          <div className="text-gray-400">Ingen data tillgänglig</div>
        </div>
      </div>
    )
  }

  const current = data.current
  const today = data.forecast.forecastday && data.forecast.forecastday.length > 0 ? data.forecast.forecastday[0] : null

  return (
    <div className="widget">
      <div className="widget-title">Väder - {data.location.name}</div>
      <div className="widget-content">
        {data.error ? (
          <div className="text-yellow-400">
            <div className="text-4xl mb-2">🌧️</div>
            <div className="text-lg font-bold mb-1">Det regnar</div>
            <div className="text-xs text-gray-400">{data.error}</div>
          </div>
        ) : (
          <>
            <div className="flex items-center mb-3">
              {current.condition.icon && (
                <img 
                  src={`https:${current.condition.icon}`} 
                  alt={current.condition.text}
                  className="w-12 h-12 mr-3"
                />
              )}
              <div>
                <div className="text-2xl font-bold">
                  {current.temp_c !== null ? `${Math.round(current.temp_c)}°` : '--°'}
                </div>
                <div className="text-sm text-gray-300">
                  {current.condition.text}
                </div>
              </div>
            </div>

            {today && (
              <div className="text-sm text-gray-300 mb-2">
                Max: {Math.round(today.day.maxtemp_c)}° / Min: {Math.round(today.day.mintemp_c)}°
                {today.day.chance_of_rain > 0 && (
                  <span className="text-blue-300 ml-2">
                    🌧️ {today.day.chance_of_rain}%
                  </span>
                )}
              </div>
            )}

            {current.humidity !== null && (
              <div className="text-xs text-gray-400">
                Luftfuktighet: {current.humidity}%
                {current.wind_kph !== null && (
                  <span className="ml-2">
                    Vind: {Math.round(current.wind_kph)} km/h {current.wind_dir}
                  </span>
                )}
              </div>
            )}
          </>
        )}
      </div>
    </div>
  )
} 
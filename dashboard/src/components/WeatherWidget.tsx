import { useData } from '../context/DataContext'
import { Sun, Cloud, CloudRain, CloudSnow, Zap, CloudDrizzle, Droplets, Wind, SunDim } from 'lucide-react'

export function WeatherWidget() {
  const { state } = useData()
  const { weatherData, sunData, connectionStatus } = state

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
    // Extract numeric code from WeatherAPI icon URL (e.g., "113.png" from "//cdn.weatherapi.com/weather/64x64/day/113.png")
    const codeMatch = iconUrl.match(/\/(\d+)\.png$/)
    const code = codeMatch ? codeMatch[1] : null

    // Map WeatherAPI codes to Lucide icons
    switch (code) {
      case '113': // Sunny/Clear
        return <Sun className="w-6 h-6 text-purple-200" />
      case '116': // Partly cloudy
      case '119': // Cloudy
      case '122': // Overcast
        return <Cloud className="w-6 h-6 text-purple-200" />
      case '143': // Mist
      case '248': // Fog
      case '260': // Freezing fog
        return <Cloud className="w-6 h-6 text-purple-200" />
      case '176': // Patchy rain possible
      case '263': // Patchy light drizzle
      case '266': // Light drizzle
      case '281': // Freezing drizzle
      case '284': // Heavy freezing drizzle
        return <CloudDrizzle className="w-6 h-6 text-purple-200" />
      case '296': // Light rain
      case '299': // Moderate rain at times
      case '302': // Moderate rain
      case '305': // Heavy rain at times
      case '308': // Heavy rain
      case '353': // Light rain shower
      case '356': // Moderate or heavy rain shower
      case '359': // Torrential rain shower
        return <CloudRain className="w-6 h-6 text-purple-200" />
      case '179': // Patchy snow possible
      case '227': // Blowing snow
      case '230': // Blizzard
      case '323': // Patchy light snow
      case '326': // Light snow
      case '329': // Patchy moderate snow
      case '332': // Moderate snow
      case '335': // Patchy heavy snow
      case '338': // Heavy snow
      case '368': // Light snow showers
      case '371': // Moderate or heavy snow showers
        return <CloudSnow className="w-6 h-6 text-purple-200" />
      case '200': // Thundery outbreaks possible
      case '386': // Patchy light rain with thunder
      case '389': // Moderate or heavy rain with thunder
      case '392': // Patchy light snow with thunder
      case '395': // Moderate or heavy snow with thunder
        return <Zap className="w-6 h-6 text-purple-200" />
      default:
        // Fallback for unknown codes
        return <Cloud className="w-6 h-6 text-purple-200" />
    }
  }

  const shortenWeatherText = (text: string) => {
    // Shorten common long Swedish weather descriptions to prevent wrapping
    return text.replace('Områden med regn i närheten', 'Regn i närheten')
  }

  // Get sun hours text for a specific date (YYYY-MM-DD format)
  const getSunHoursForDate = (dateStr: string): string | null => {
    if (!sunData?.daily_sun_hours) return null
    const entry = sunData.daily_sun_hours.find(d => d.date === dateStr)
    return entry?.sun_hours_text || null
  }

  // Get brightness display for current conditions
  const getBrightnessDisplay = () => {
    if (!sunData) return null
    if (!sunData.is_daylight) return null // Don't show at night

    const brightness = sunData.current_brightness_percent
    // Only show if there's meaningful brightness (sun partially visible)
    if (brightness < 60) return null

    return `${brightness}%`
  }

  return (
    <div>
      {/* Current Weather */}
      <div className="flex items-center justify-between mb-4">
        <div className="flex items-center">
          <div className="text-4xl mr-3">
            {getWeatherIcon(weatherData.current.condition.icon)}
          </div>
          <div>
            <div className="text-4xl font-bold text-purple-100">
              {weatherData.current.temp_c}°
            </div>
            <div className="text-purple-200">
              {shortenWeatherText(weatherData.current.condition.text)}
            </div>
          </div>
        </div>

        <div className="text-purple-200 text-right">
          {getBrightnessDisplay() && (
            <div className="flex items-center justify-end space-x-1">
              <SunDim className="w-4 h-4 text-yellow-400" />
              <span className="text-yellow-400">{getBrightnessDisplay()}</span>
            </div>
          )}
          <div className="flex items-center justify-end space-x-1">
            <Droplets className="w-4 h-4" />
            <span>{weatherData.current.humidity}%</span>
          </div>
          <div className="flex items-center justify-end space-x-1">
            <Wind className="w-4 h-4" />
            <span>{weatherData.current.wind_kph} km/h {weatherData.current.wind_dir}</span>
          </div>
        </div>
      </div>

      {/* 3-Day Forecast */}
      <div className="space-y-2">
        <div className="text-purple-200 mb-2" style={{ textTransform: 'uppercase', fontSize: '0.8em' }}>3-dagars prognos</div>
        {weatherData.forecast.forecastday.slice(0, 3).map((day, index) => {
          const sunHours = getSunHoursForDate(day.date)
          return (
            <div key={day.date} className="flex items-center justify-between">
              <div className="flex items-center">
                <div className="mr-2">
                  {getWeatherIcon(day.day.condition.icon)}
                </div>
                <span className="text-purple-100">
                  {index === 0 ? 'Idag' :
                   index === 1 ? 'Imorgon' :
                   new Date(day.date).toLocaleDateString('sv-SE', { weekday: 'short' })}
                </span>
              </div>

              <div className="flex items-center space-x-3">
                {sunHours && (
                  <span className="text-yellow-400 text-sm">
                    {sunHours} sol
                  </span>
                )}
                <div className="flex items-center space-x-2">
                  <span className="font-bold text-purple-100">
                    {Math.round(day.day.maxtemp_c)}°
                  </span>
                  <span className="text-purple-200">
                    {Math.round(day.day.mintemp_c)}°
                  </span>
                </div>
              </div>
            </div>
          )
        })}
      </div>
    </div>
  )
}

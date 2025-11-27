import { useData } from '../context/DataContext'
import { Sun, Cloud, CloudRain, CloudSnow, Zap, CloudDrizzle, SunDim } from 'lucide-react'

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

  // Generate a 3-word max Swedish weather vibe based on conditions
  const getWeatherVibe = (): string => {
    const temp = weatherData.current.temp_c
    const humidity = weatherData.current.humidity
    const wind = weatherData.current.wind_kph
    const condition = weatherData.current.condition.text.toLowerCase()

    const isFreezing = temp < -5
    const isCold = temp < 5
    const isMild = temp >= 5 && temp < 15
    const isCalm = wind < 10
    const isWindy = wind >= 25
    const isStormy = wind >= 40
    const isDamp = humidity > 70 && temp > -2 && temp < 8

    const isRaining = /regn|dugg|skur/.test(condition)
    const isSnowing = /snö/.test(condition)
    const isFoggy = /dimma|dis/.test(condition)
    const isCloudy = /mulet|molnigt|övervägande/.test(condition)
    const isSunny = /sol|klart|klar/.test(condition)

    // Stormy - always takes priority
    if (isStormy) return 'Stanna inne idag'

    // Snow conditions
    if (isSnowing && isWindy) return 'Snöyra ute'
    if (isSnowing) return 'Mysigt snöväder'

    // Rain conditions
    if (isRaining && isWindy) return 'Riktigt ruskigt'
    if (isRaining && isCold) return 'Kallt och blött'
    if (isRaining) return 'Regnigt ute'

    // Fog conditions
    if (isFoggy && isCold) return 'Dimmigt och rått'
    if (isFoggy) return 'Dimmigt ute'

    // Sunny conditions
    if (isSunny && isFreezing) return 'Soligt men kallt'
    if (isSunny && isCold && isCalm) return 'Friskt vinterväder'
    if (isSunny && isCold && isWindy) return 'Soligt men blåsigt'
    if (isSunny && isMild) return 'Skönt väder ute'
    if (isSunny) return 'Fint väder'

    // Cloudy/overcast conditions (most common in Swedish winter)
    if (isCloudy && isFreezing && isWindy) return 'Bitande kallt'
    if (isCloudy && isCold && isDamp) return 'Råkallt och grått'
    if (isCloudy && isCold && isWindy) return 'Kallt och blåsigt'
    if (isCloudy && isFreezing) return 'Grått och kallt'
    if (isCloudy && isCold) return 'Grått vinterväder'
    if (isCloudy && isDamp) return 'Fuktigt och grått'
    if (isCloudy) return 'Grått som vanligt'

    // Fallbacks based on temp/wind
    if (isFreezing && isWindy) return 'Bitande kallt'
    if (isFreezing) return 'Riktigt kallt'
    if (isCold && isWindy) return 'Kallt och blåsigt'
    if (isCold && isDamp) return 'Råkallt ute'
    if (isCold) return 'Kyligt ute'
    if (isWindy) return 'Blåsigt ute'

    return 'Helt okej'
  }

  // Get sun hours text with timing for a specific date (YYYY-MM-DD format)
  // Returns: "Sol 9-11" or null if no sun (duration implicit from range)
  const getSunHoursForDate = (dateStr: string): string | null => {
    if (!sunData?.daily_sun_hours) return null
    const entry = sunData.daily_sun_hours.find(d => d.date === dateStr)
    if (!entry?.first_sun_hour || !entry?.last_sun_end) return null
    const start = parseInt(entry.first_sun_hour).toString()
    const end = parseInt(entry.last_sun_end).toString()
    return `Sol ${start}-${end}`
  }

  // Get today's sun status for display (Option D):
  // - "Sol nu" when currently sunny
  // - "Sol vid HH" when sun is coming today
  // - "Sol var H-H" when sun already passed today (no leading zeros)
  // - "Grått idag" when no sun today
  const getTodaySunStatus = (): string | null => {
    if (!sunData) return null
    if (!sunData.is_daylight) return null  // Don't show at night

    const now = new Date()
    const currentHour = now.getHours()
    const BRIGHTNESS_THRESHOLD = 80

    // Get today's sun data from daily_sun_hours
    const todayStr = now.toISOString().split('T')[0]
    const todayData = sunData.daily_sun_hours?.find(d => d.date === todayStr)

    // Check if currently sunny
    if (sunData.current_brightness_percent >= BRIGHTNESS_THRESHOLD) {
      return 'Sol nu'
    }

    // Check if there's sun data for today
    if (!todayData || todayData.sun_hours === 0) {
      return 'Grått idag'
    }

    // Has sun today - check if it's upcoming or already passed
    const firstSunHour = todayData.first_sun_hour ? parseInt(todayData.first_sun_hour) : null
    const lastSunEnd = todayData.last_sun_end ? parseInt(todayData.last_sun_end) : null

    if (firstSunHour !== null && lastSunEnd !== null) {
      // Format without leading zeros
      const startStr = firstSunHour.toString()
      const endStr = lastSunEnd.toString()

      if (currentHour < firstSunHour) {
        // Sun is coming later today
        return `Sol vid ${startStr}`
      } else if (currentHour >= lastSunEnd) {
        // Sun already passed
        return `Sol var ${startStr}-${endStr}`
      } else {
        // We're in the sun window but brightness is below threshold (edge case)
        return `Sol vid ${startStr}`
      }
    }

    return 'Grått idag'
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
          {getTodaySunStatus() && (
            <div className="flex items-center justify-end space-x-1">
              <SunDim className="w-4 h-4 text-orange-400" />
              <span className="text-orange-400">{getTodaySunStatus()}</span>
            </div>
          )}
          <div>{getWeatherVibe()}</div>
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
                  <span className="text-orange-400">
                    {sunHours}
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

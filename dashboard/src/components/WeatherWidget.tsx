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

  // ============================================================================
  // WEATHER VIBES - Single source of truth for all weather descriptions
  // ============================================================================
  // WeatherAPI Swedish condition texts (shown below temp as "Växlande molnighet" etc):
  //   Clear/Sunny: "Klart", "Soligt", "Sol"
  //   Cloudy: "Delvis molnigt", "Molnigt", "Mulet", "Växlande molnighet"
  //   Fog: "Dis", "Dimma", "Underkyld dimma"
  //   Rain: "Lätt duggregn", "Duggregn", "Lätt regn", "Måttligt regn", "Kraftigt regn",
  //         "Regnskurar", "Lätt regnskur", "Störtregn", "Områden med regn"
  //   Snow: "Lätt snöfall", "Måttligt snöfall", "Kraftigt snöfall", "Snöbyar",
  //         "Snöblandat regn", "Isnålar", "Yr"
  //   Thunder: "Åska möjlig", "Åskregn", "Åskväder"
  //   Freezing: "Underkylt regn", "Underkylt duggregn"
  // Keep vibes FEELING-based to complement (not repeat) these descriptions!

  // All vibes defined ONCE with short (forecast) and long (current) versions
  // This prevents drift between the two display contexts
  const VIBES = {
    // Extreme conditions
    stormy:           { short: 'Storm!',          long: 'Stanna inne' },
    sleet:            { short: 'Ruskigt',         long: 'Ruskigt' },

    // Snow conditions
    snow_windy:       { short: 'Snöyra',          long: 'Snöyra' },
    snow:             { short: 'Mysigt',          long: 'Mysigt ute' },

    // Rain conditions
    rain_windy:       { short: 'Ruskigt',         long: 'Stanna inne' },
    rain:             { short: 'Ta paraply',      long: 'Ta paraply' },

    // Fog conditions
    fog_icy:          { short: 'Halt!',           long: 'Akta halkan' },
    fog_cold:         { short: 'Rått',            long: 'Dimmigt och rått' },
    fog:              { short: 'Dimmigt',         long: 'Se dig för i dimman' },

    // Sunny conditions (from WeatherAPI)
    sunny_freezing:   { short: 'Kallt',           long: 'Soligt men kallt' },
    sunny_cold_windy: { short: 'Blåsigt',         long: 'Soligt men blåsigt' },
    sunny_cold:       { short: 'Friskt',          long: 'Friskt vinterväder' },
    sunny_mild:       { short: 'Skönt',           long: 'Riktigt skönt' },
    sunny:            { short: 'Fint',            long: 'Njut av solen' },

    // Sun-aware fallbacks (Meteoblue predicts sun even if WeatherAPI says cloudy)
    sun_3h:           { short: 'Soligt',          long: 'Lite sol idag' },
    sun_2h:           { short: 'Fint',            long: 'Glimtar av sol' },
    sun_1h:           { short: 'Lite sol',        long: 'Kanske lite sol' },

    // Cold/overcast fallbacks
    freezing_windy:   { short: 'Iskallt',         long: 'Biter i kinderna' },
    freezing:         { short: 'Iskallt',         long: 'Riktigt kallt' },
    cold_damp_windy:  { short: 'Ruskigt',         long: 'Riktigt otrevligt' },
    cold_damp:        { short: 'Rått',            long: 'Klä dig varmt' },
    cold_windy:       { short: 'Blåsigt',         long: 'Blåser kallt' },
    cold:             { short: 'Kyligt',          long: 'Lite kyligt' },
    damp:             { short: 'Fuktigt',         long: 'Lite fuktigt' },
    windy:            { short: 'Blåsigt',         long: 'Blåser på' },

    // Default
    default:          { short: 'Grått',           long: 'Helt okej' },
  } as const

  type VibeKey = keyof typeof VIBES

  // Single detection function - returns the vibe key based on weather parameters
  const detectVibeKey = (params: {
    temp: number
    wind: number
    humidity?: number
    condition: string
    sunHours?: number
  }): VibeKey => {
    const { temp, wind, humidity, condition, sunHours } = params

    const isFreezing = temp < -5
    const isCold = temp < 5
    const isMild = temp >= 5 && temp < 15
    const isWindy = wind >= 25
    const isStormy = wind >= 40
    const isDamp = humidity !== undefined && humidity > 70 && temp > -2 && temp < 8

    const condLower = condition.toLowerCase()
    const isSleet = /snöblandat/.test(condLower)
    const isSnowing = /snö/.test(condLower) && !isSleet
    const isRaining = /regn|dugg|skur/.test(condLower)
    const isFoggy = /dimma|dis/.test(condLower)
    const isSunny = /sol|klart|klar/.test(condLower)
    const isIcy = isFreezing || /underkyld|frys/.test(condLower)

    // Priority-ordered detection (order matters!)
    if (isStormy) return 'stormy'
    if (isSleet) return 'sleet'
    if (isSnowing && isWindy) return 'snow_windy'
    if (isSnowing) return 'snow'
    if (isRaining && isWindy) return 'rain_windy'
    if (isRaining) return 'rain'
    if (isFoggy && isIcy) return 'fog_icy'
    if (isFoggy && isCold) return 'fog_cold'
    if (isFoggy) return 'fog'
    if (isSunny && isFreezing) return 'sunny_freezing'
    if (isSunny && isCold && isWindy) return 'sunny_cold_windy'
    if (isSunny && isCold) return 'sunny_cold'
    if (isSunny && isMild) return 'sunny_mild'
    if (isSunny) return 'sunny'

    // Sun-aware fallbacks (Meteoblue predicts sun even if WeatherAPI says cloudy)
    if (sunHours !== undefined && sunHours >= 3) return 'sun_3h'
    if (sunHours !== undefined && sunHours >= 2) return 'sun_2h'
    if (sunHours !== undefined && sunHours >= 1) return 'sun_1h'

    // Cloudy/overcast fallbacks
    if (isFreezing && isWindy) return 'freezing_windy'
    if (isCold && isDamp && isWindy) return 'cold_damp_windy'
    if (isCold && isDamp) return 'cold_damp'
    if (isCold && isWindy) return 'cold_windy'
    if (isFreezing) return 'freezing'
    if (isCold) return 'cold'
    if (isDamp) return 'damp'
    if (isWindy) return 'windy'

    return 'default'
  }

  // Current weather vibe (uses humidity, returns long phrases)
  const getWeatherVibe = (): string => {
    const todayStr = new Date().toISOString().split('T')[0]
    const todaySunHours = sunData?.daily_sun_hours?.find(d => d.date === todayStr)?.sun_hours || 0

    const key = detectVibeKey({
      temp: weatherData.current.temp_c,
      wind: weatherData.current.wind_kph,
      humidity: weatherData.current.humidity,
      condition: weatherData.current.condition.text,
      sunHours: todaySunHours,
    })
    return VIBES[key].long
  }

  // Forecast vibe (no humidity available, returns short phrases)
  const getForecastVibe = (day: typeof weatherData.forecast.forecastday[0], sunHoursForDay: number): string => {
    const key = detectVibeKey({
      temp: day.day.maxtemp_c,
      wind: day.day.maxwind_kph,
      condition: day.day.condition.text,
      sunHours: sunHoursForDay,
    })
    return VIBES[key].short
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
          const sunHoursText = getSunHoursForDate(day.date)
          const sunHoursCount = sunData?.daily_sun_hours?.find(d => d.date === day.date)?.sun_hours || 0
          return (
            <div key={day.date} className="flex items-center justify-between">
              <div className="flex items-center space-x-2">
                <div className="mr-2">
                  {getWeatherIcon(day.day.condition.icon)}
                </div>
                <span className="text-purple-100">
                  {index === 0 ? 'Idag' :
                   index === 1 ? 'Imorgon' :
                   new Date(day.date).toLocaleDateString('sv-SE', { weekday: 'long' }).replace(/^./, c => c.toUpperCase())}
                </span>
                {index > 0 && (
                  <>
                    <span className="text-purple-300 opacity-25">•</span>
                    <span className="text-purple-300">{getForecastVibe(day, sunHoursCount)}</span>
                  </>
                )}
              </div>

              <div className="flex items-center space-x-2">
                {sunHoursText && index > 0 && (
                  <>
                    <span className="text-orange-400">{sunHoursText}</span>
                    <span className="text-purple-300 opacity-25">•</span>
                  </>
                )}
                <span className="font-bold text-purple-100">
                  {Math.round(day.day.maxtemp_c)}°
                </span>
                <span className="text-purple-300 opacity-25">•</span>
                <span className="text-purple-200">
                  {Math.round(day.day.mintemp_c)}°
                </span>
              </div>
            </div>
          )
        })}
      </div>
    </div>
  )
}

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
export const VIBES = {
  // Dangerous/extreme conditions (high priority)
  stormy:           { short: 'Storm!',          long: 'Stanna inne' },
  thunder:          { short: 'Åska!',           long: 'Åskväder' },
  rain_icy:         { short: 'Ishalka!',        long: 'Riktigt halt' },
  sleet:            { short: 'Ruskigt',         long: 'Ruskigt' },

  // Snow conditions
  snow_windy:       { short: 'Snöyra',          long: 'Snöyra' },
  snow_flurries:    { short: 'Snöyr',           long: 'Lätt snöyr' },
  snow:             { short: 'Mysigt',          long: 'Mysigt ute' },

  // Rain conditions (intensity-aware) - descriptive, not advisory
  rain_windy_damp:  { short: 'Ruskigt',         long: 'Rått och ruskigt' },
  rain_windy:       { short: 'Blåsigt',         long: 'Blåsigt regn' },
  rain_heavy:       { short: 'Ösregn',          long: 'Regnar rejält' },
  rain_showers:     { short: 'Skurar',          long: 'Regnskurar' },
  rain:             { short: 'Regn',            long: 'Regnigt' },
  rain_light:       { short: 'Duggigt',         long: 'Lite dugg' },

  // Fog conditions
  fog_icy:          { short: 'Halt!',           long: 'Akta halkan' },
  fog_cold:         { short: 'Rått',            long: 'Dimmigt och rått' },
  fog:              { short: 'Dimmigt',         long: 'Dimmigt ute' },

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

  // Air quality warning
  poor_air:         { short: 'Dålig luft',      long: 'Dålig luftkvalitet' },

  // Cold/overcast fallbacks (damp only triggers with cold, not standalone)
  freezing_windy:   { short: 'Iskallt',         long: 'Biter i kinderna' },
  freezing:         { short: 'Iskallt',         long: 'Riktigt kallt' },
  cold_damp_windy:  { short: 'Ruskigt',         long: 'Riktigt otrevligt' },
  cold_damp:        { short: 'Rått',            long: 'Rått ute' },
  cold_windy:       { short: 'Blåsigt',         long: 'Blåser kallt' },
  cold:             { short: 'Kyligt',          long: 'Lite kyligt' },
  windy:            { short: 'Blåsigt',         long: 'Blåser på' },

  // Default
  default:          { short: 'Grått',           long: 'Helt okej' },
} as const

export type VibeKey = keyof typeof VIBES

export interface WeatherParams {
  temp: number
  wind: number
  humidity?: number
  condition: string
  sunHours?: number
  airQualityIndex?: number  // US EPA index: 1=Good, 2=Moderate, 3+=Unhealthy
}

// Single detection function - returns the vibe key based on weather parameters
export function detectVibeKey(params: WeatherParams): VibeKey {
  const { temp, wind, humidity, condition, sunHours, airQualityIndex } = params

  const isFreezing = temp < -5
  const isCold = temp < 10
  const isMild = temp >= 10 && temp < 15
  const isWindy = wind >= 25
  const isStormy = wind >= 40
  const isDamp = humidity !== undefined && humidity > 70 && temp > -2 && temp < 10
  const isPoorAir = airQualityIndex !== undefined && airQualityIndex >= 3

  const condLower = condition.toLowerCase()
  const isSleet = /snöblandat/.test(condLower)
  const isFlurries = /\byr\b/.test(condLower)  // "Yr" = fine snow flurries
  const isSnowing = (/snö/.test(condLower) || isFlurries) && !isSleet
  const isThunder = /åska/.test(condLower)
  const isRaining = /regn|dugg|skur/.test(condLower)
  const isLightRain = isRaining && /lätt|dugg/.test(condLower) && !/kraftigt|stört/.test(condLower)
  const isHeavyRain = isRaining && /kraftigt|stört/.test(condLower)
  const isShowers = /skur/.test(condLower) && !isLightRain && !isHeavyRain
  const isFoggy = /dimma|dis/.test(condLower)
  const isSunny = /sol|klart|klar/.test(condLower)
  const isIcy = isFreezing || /underkyld|frys/.test(condLower)

  // Priority-ordered detection (order matters!)
  // Dangerous conditions first
  if (isStormy) return 'stormy'
  if (isThunder) return 'thunder'
  if (isRaining && isIcy) return 'rain_icy'  // Freezing rain = very dangerous!
  if (isSleet) return 'sleet'

  // Snow conditions
  if (isSnowing && isWindy) return 'snow_windy'
  if (isFlurries) return 'snow_flurries'
  if (isSnowing) return 'snow'

  // Rain conditions
  if (isRaining && isWindy && isDamp) return 'rain_windy_damp'
  if (isRaining && isWindy) return 'rain_windy'
  if (isHeavyRain) return 'rain_heavy'
  if (isShowers) return 'rain_showers'
  if (isLightRain) return 'rain_light'
  if (isRaining) return 'rain'

  // Fog conditions
  if (isFoggy && isIcy) return 'fog_icy'
  if (isFoggy && isCold) return 'fog_cold'
  if (isFoggy) return 'fog'

  // Sunny conditions
  if (isSunny && isFreezing) return 'sunny_freezing'
  if (isSunny && isCold && isWindy) return 'sunny_cold_windy'
  if (isSunny && isCold) return 'sunny_cold'
  if (isSunny && isMild) return 'sunny_mild'
  if (isSunny) return 'sunny'

  // Sun-aware fallbacks (Meteoblue predicts sun even if WeatherAPI says cloudy)
  if (sunHours !== undefined && sunHours >= 3) return 'sun_3h'
  if (sunHours !== undefined && sunHours >= 2) return 'sun_2h'
  if (sunHours !== undefined && sunHours >= 1) return 'sun_1h'

  // Air quality warning (only show when no other notable weather)
  if (isPoorAir) return 'poor_air'

  // Cloudy/overcast fallbacks (damp only with cold, not standalone)
  if (isFreezing && isWindy) return 'freezing_windy'
  if (isCold && isDamp && isWindy) return 'cold_damp_windy'
  if (isCold && isDamp) return 'cold_damp'
  if (isCold && isWindy) return 'cold_windy'
  if (isFreezing) return 'freezing'
  if (isCold) return 'cold'
  // Note: standalone 'damp' removed - humidity without cold isn't notable enough
  if (isWindy) return 'windy'

  return 'default'
}

// Helper to get vibe text
export function getVibe(params: WeatherParams, format: 'short' | 'long'): string {
  const key = detectVibeKey(params)
  return VIBES[key][format]
}

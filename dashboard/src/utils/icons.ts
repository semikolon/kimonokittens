export const weatherIcons = {
  sun: '☀️',
  clear: '☀️',
  cloud: '☁️',
  rain: '🌧️',
  snow: '❄️',
  thunder: '⛈️',
  default: '🌤️'
}

export const statusIcons = {
  connected: '🟢',
  connecting: '🟡',
  disconnected: '🔴',
  success: '✅',
  error: '❌',
  warning: '⚠️'
}

export const getWeatherIcon = (iconUrl: string): string => {
  if (iconUrl.includes('sun') || iconUrl.includes('clear')) return weatherIcons.sun
  if (iconUrl.includes('cloud')) return weatherIcons.cloud
  if (iconUrl.includes('rain')) return weatherIcons.rain
  if (iconUrl.includes('snow')) return weatherIcons.snow
  if (iconUrl.includes('thunder')) return weatherIcons.thunder
  return weatherIcons.default
}
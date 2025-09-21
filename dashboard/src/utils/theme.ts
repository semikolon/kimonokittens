export const neonTheme = {
  text: {
    primary: 'text-purple-200',        // #E9D5FF
    secondary: 'text-purple-300/70',   // rgba(196,181,253,0.7)
    content: 'text-purple-100/90',     // rgba(243,232,255,0.9)
    accent: 'text-fuchsia-300',        // #F0ABFC
    muted: 'text-purple-300/60'        // rgba(196,181,253,0.6)
  },
  status: {
    success: 'text-emerald-300',
    warning: 'text-amber-300',
    error: 'text-rose-400',
    info: 'text-blue-300'
  }
}

export const getTemperatureColor = (temp: number): string => {
  if (temp < 0) return neonTheme.status.info
  if (temp < 10) return 'text-blue-200'
  if (temp < 20) return 'text-emerald-300'
  if (temp < 30) return neonTheme.status.warning
  return neonTheme.status.error
}
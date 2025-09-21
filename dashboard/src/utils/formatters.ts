export const formatSwedishTime = (date: Date): string =>
  date.toLocaleTimeString('sv-SE', { hour: '2-digit', minute: '2-digit', second: '2-digit' })

export const formatSwedishDate = (date: Date): string =>
  date.toLocaleDateString('sv-SE', { weekday: 'long', year: 'numeric', month: 'long', day: 'numeric' })

export const getGreeting = (hour: number): string => {
  if (hour < 6) return 'God natt'
  if (hour < 12) return 'God morgon'
  if (hour < 17) return 'God dag'
  if (hour < 22) return 'God kväll'
  return 'God natt'
}

export const getRelativeDate = (date: Date): string => {
  const today = new Date()
  const tomorrow = new Date(today)
  tomorrow.setDate(today.getDate() + 1)

  if (date.toDateString() === today.toDateString()) return 'Idag'
  if (date.toDateString() === tomorrow.toDateString()) return 'Imorgon'
  return formatSwedishDate(date)
}
/**
 * Date calculation utilities for timeline positioning
 * Used by CompactTenantTimeline to convert dates to pixel positions
 */

/**
 * Calculate the number of days between two dates
 * Normalizes both dates to start of day to avoid timezone issues
 */
export function daysBetween(start: Date, end: Date): number {
  const msPerDay = 1000 * 60 * 60 * 24

  // Normalize to start of day
  const startNormalized = new Date(start)
  startNormalized.setHours(0, 0, 0, 0)

  const endNormalized = new Date(end)
  endNormalized.setHours(0, 0, 0, 0)

  return Math.floor((endNormalized.getTime() - startNormalized.getTime()) / msPerDay)
}

/**
 * Add a specified number of days to a date
 */
export function addDays(date: Date, days: number): Date {
  const result = new Date(date)
  result.setDate(result.getDate() + days)
  return result
}

/**
 * Subtract a specified number of days from a date
 */
export function subDays(date: Date, days: number): Date {
  return addDays(date, -days)
}

/**
 * Find the minimum date from an array of dates
 */
export function minDate(dates: Date[]): Date {
  if (dates.length === 0) throw new Error('Cannot find min of empty array')
  return new Date(Math.min(...dates.map(d => d.getTime())))
}

/**
 * Find the maximum date from an array of dates
 */
export function maxDate(dates: Date[]): Date {
  if (dates.length === 0) throw new Error('Cannot find max of empty array')
  return new Date(Math.max(...dates.map(d => d.getTime())))
}

/**
 * Format a duration in days to human-readable Swedish format
 * Examples: "5d", "3v", "2m", "1å 3m", "2å"
 */
export function formatDuration(days: number): string {
  if (days < 7) {
    return `${days}d`
  }

  if (days < 30) {
    const weeks = Math.floor(days / 7)
    return `${weeks}v`
  }

  if (days < 365) {
    const months = Math.floor(days / 30)
    return `${months}m`
  }

  const years = Math.floor(days / 365)
  const remainingDays = days - (years * 365)
  const months = Math.floor(remainingDays / 30)

  if (months === 0) {
    return `${years}å`
  }

  return `${years}å ${months}m`
}

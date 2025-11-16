/**
 * Text measurement utilities for dynamic name placement in timeline bars
 * Uses canvas context for accurate pixel-width measurements
 */

// Singleton canvas for text measurement (reused for performance)
let measurementCanvas: HTMLCanvasElement | null = null

/**
 * Get or create the measurement canvas
 */
function getMeasurementCanvas(): HTMLCanvasElement {
  if (!measurementCanvas) {
    measurementCanvas = document.createElement('canvas')
  }
  return measurementCanvas
}

/**
 * Measure the pixel width of text with a given font
 * @param text - Text to measure
 * @param font - CSS font string (e.g., "12px Inter", "bold 14px Arial")
 * @returns Width in pixels
 */
export function measureTextWidth(text: string, font: string): number {
  const canvas = getMeasurementCanvas()
  const context = canvas.getContext('2d')

  if (!context) {
    // Fallback if canvas context unavailable (shouldn't happen in modern browsers)
    return text.length * 8 // Rough estimate
  }

  context.font = font
  return context.measureText(text).width
}

/**
 * Generate initials from a full name
 * @param fullName - Full name (e.g., "Frans Lukas Otis Pirat Lövenvald")
 * @returns Initials with dots (e.g., "F.L.O.P.L.")
 */
export function getInitials(fullName: string): string {
  return fullName
    .split(' ')
    .filter(word => word.length > 0) // Filter empty strings
    .map(word => word[0]?.toUpperCase() || '')
    .join('.')
}

/**
 * Truncate text to fit within a maximum pixel width
 * Adds "..." ellipsis to indicate truncation
 * @param text - Text to truncate
 * @param maxWidth - Maximum width in pixels
 * @param font - CSS font string
 * @returns Truncated text with ellipsis, or original if it fits
 */
export function truncateToFit(text: string, maxWidth: number, font: string): string {
  // Check if original text fits
  if (measureTextWidth(text, font) <= maxWidth) {
    return text
  }

  // Binary search for optimal truncation point (more efficient than linear)
  let left = 0
  let right = text.length
  let bestFit = ''

  while (left <= right) {
    const mid = Math.floor((left + right) / 2)
    const candidate = text.slice(0, mid) + '...'
    const width = measureTextWidth(candidate, font)

    if (width <= maxWidth) {
      bestFit = candidate
      left = mid + 1 // Try longer
    } else {
      right = mid - 1 // Try shorter
    }
  }

  // Ensure we have at least a few characters
  if (bestFit.length < 4) {
    return '...'
  }

  return bestFit
}

/**
 * Determine how to place a name in a bar based on available space
 * Returns placement strategy and text to display
 */
export interface NamePlacement {
  type: 'inside' | 'outside'
  text: string
  truncate: boolean
}

export function calculateNamePlacement(
  barWidth: number,
  fullName: string,
  font: string = '12px Inter'
): NamePlacement {
  // Measure full name width
  const fullNameWidth = measureTextWidth(fullName, font)

  // Strategy 1: Full name inside bar (with padding)
  if (barWidth >= fullNameWidth + 40) {
    return {
      type: 'inside',
      text: fullName,
      truncate: false,
    }
  }

  // Strategy 2: Initials inside bar
  const initials = getInitials(fullName)
  const initialsWidth = measureTextWidth(initials, font)

  if (barWidth >= initialsWidth + 24) {
    return {
      type: 'inside',
      text: initials,
      truncate: false,
    }
  }

  // Strategy 3: Truncated name inside
  if (barWidth >= 60) {
    const truncated = truncateToFit(fullName, barWidth - 24, font)
    return {
      type: 'inside',
      text: truncated,
      truncate: true,
    }
  }

  // Strategy 4: Name AFTER bar (outside)
  return {
    type: 'outside',
    text: fullName,
    truncate: false,
  }
}

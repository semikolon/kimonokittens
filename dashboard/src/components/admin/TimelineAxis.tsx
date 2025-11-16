/**
 * TimelineAxis - Renders date markers and vertical grid lines for the timeline
 * Dynamically adjusts marker frequency based on timeline span
 */
import React, { useMemo } from 'react'
import { daysBetween } from '../../utils/dateCalculations'

interface TimelineAxisProps {
  startDate: Date
  endDate: Date
  pixelPerDay: number
  containerWidth: number
}

interface TimelineMarker {
  date: Date
  label: string
  position: number // pixels from left
}

/**
 * Generate timeline markers based on span
 * < 2 years: Quarterly (Q1'22, Q2'22...)
 * 2-5 years: Semi-annual (Jan'22, Jul'22...)
 * > 5 years: Annual (2022, 2023...)
 */
function generateMarkers(
  startDate: Date,
  endDate: Date,
  pixelPerDay: number
): TimelineMarker[] {
  const years = endDate.getFullYear() - startDate.getFullYear()
  const markers: TimelineMarker[] = []

  if (years < 2) {
    // Quarterly markers
    let current = new Date(startDate.getFullYear(), 0, 1) // Start of year
    while (current <= endDate) {
      if (current >= startDate) {
        const quarter = Math.floor(current.getMonth() / 3) + 1
        const year = current.getFullYear().toString().slice(2) // "24" from "2024"
        markers.push({
          date: new Date(current),
          label: `Q${quarter}'${year}`,
          position: daysBetween(startDate, current) * pixelPerDay,
        })
      }
      current.setMonth(current.getMonth() + 3) // Next quarter
    }
  } else if (years <= 5) {
    // Semi-annual markers (Jan, Jul)
    let current = new Date(startDate.getFullYear(), 0, 1) // January
    while (current <= endDate) {
      if (current >= startDate) {
        const monthName = current.toLocaleString('sv-SE', { month: 'short' })
        const year = current.getFullYear().toString().slice(2)
        markers.push({
          date: new Date(current),
          label: `${monthName}'${year}`,
          position: daysBetween(startDate, current) * pixelPerDay,
        })
      }
      current.setMonth(current.getMonth() + 6) // Next half-year
    }
  } else {
    // Annual markers
    let current = new Date(startDate.getFullYear(), 0, 1)
    while (current <= endDate) {
      if (current >= startDate) {
        markers.push({
          date: new Date(current),
          label: current.getFullYear().toString(),
          position: daysBetween(startDate, current) * pixelPerDay,
        })
      }
      current.setFullYear(current.getFullYear() + 1)
    }
  }

  return markers
}

export const TimelineAxis: React.FC<TimelineAxisProps> = ({
  startDate,
  endDate,
  pixelPerDay,
  containerWidth,
}) => {
  const markers = useMemo(
    () => generateMarkers(startDate, endDate, pixelPerDay),
    [startDate, endDate, pixelPerDay]
  )

  return (
    <div className="relative h-8 border-b border-purple-500/10">
      {/* Grid lines and markers */}
      {markers.map((marker, index) => (
        <div
          key={index}
          className="absolute top-0 h-full"
          style={{ left: `${marker.position}px` }}
        >
          {/* Vertical grid line */}
          <div className="absolute top-0 h-full w-px bg-purple-500/10" />

          {/* Marker label */}
          <div className="absolute top-1 left-1 text-[10px] font-normal text-purple-300/40">
            {marker.label}
          </div>
        </div>
      ))}
    </div>
  )
}

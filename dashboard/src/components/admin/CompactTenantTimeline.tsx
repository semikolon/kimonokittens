/**
 * CompactTenantTimeline - Horizontal Gantt-style timeline for historic tenants
 * Replaces vertical MemberRow list to save ~54% vertical space
 */
import React, { useRef, useState, useEffect, useMemo } from 'react'
import { Member } from '../../views/AdminDashboard'
import { daysBetween, minDate, maxDate, addDays, subDays } from '../../utils/dateCalculations'
import { TimelineAxis } from './TimelineAxis'
import { TenantBar } from './TenantBar'

interface CompactTenantTimelineProps {
  members: Member[]
  containerWidth?: number // Optional override for testing
}

export interface TimelineMetrics {
  timelineStart: Date
  timelineEnd: Date
  totalDays: number
  pixelPerDay: number
  containerWidth: number
}

export const CompactTenantTimeline: React.FC<CompactTenantTimelineProps> = ({
  members,
  containerWidth: overrideWidth,
}) => {
  const containerRef = useRef<HTMLDivElement>(null)
  const [containerWidth, setContainerWidth] = useState<number>(overrideWidth || 900)
  const [hoveredMember, setHoveredMember] = useState<Member | null>(null)

  // Measure container width on mount and resize
  useEffect(() => {
    if (overrideWidth) {
      setContainerWidth(overrideWidth)
      return
    }

    const updateWidth = () => {
      if (containerRef.current) {
        setContainerWidth(containerRef.current.offsetWidth)
      }
    }

    updateWidth()

    // Use ResizeObserver for more accurate resize detection
    const resizeObserver = new ResizeObserver(updateWidth)
    if (containerRef.current) {
      resizeObserver.observe(containerRef.current)
    }

    return () => {
      resizeObserver.disconnect()
    }
  }, [overrideWidth])

  // Calculate timeline metrics
  const timelineMetrics = useMemo((): TimelineMetrics | null => {
    if (members.length === 0) return null

    // Extract start and end dates from all members
    const startDates = members
      .map(m => m.tenant_start_date)
      .filter((d): d is Date => d !== undefined)

    const endDates = members
      .map(m => m.tenant_departure_date || new Date())
      .filter((d): d is Date => d !== undefined)

    if (startDates.length === 0 || endDates.length === 0) return null

    // Find earliest start and latest end
    const earliestStart = minDate(startDates)
    const latestEnd = maxDate(endDates)

    // Calculate total days
    const totalDays = daysBetween(earliestStart, latestEnd)

    // Add 5% padding on each side for visual breathing room
    const paddingDays = Math.floor(totalDays * 0.05)
    const timelineStart = subDays(earliestStart, paddingDays)
    const timelineEnd = addDays(latestEnd, paddingDays)
    const totalTimelineDays = daysBetween(timelineStart, timelineEnd)

    // Calculate pixel-to-day ratio
    const pixelPerDay = containerWidth / totalTimelineDays

    return {
      timelineStart,
      timelineEnd,
      totalDays: totalTimelineDays,
      pixelPerDay,
      containerWidth,
    }
  }, [members, containerWidth])

  // If no members or invalid data, don't render
  if (members.length === 0 || !timelineMetrics) {
    return null
  }

  // Filter members with valid dates
  const validMembers = members.filter(
    m => m.tenant_start_date && m.tenant_departure_date
  )

  return (
    <div
      ref={containerRef}
      className="relative w-full"
      style={{
        minHeight: `${30 + validMembers.length * 26 + 10}px`, // Axis + bars + padding
      }}
    >
      {/* Timeline axis with date markers */}
      <TimelineAxis
        startDate={timelineMetrics.timelineStart}
        endDate={timelineMetrics.timelineEnd}
        pixelPerDay={timelineMetrics.pixelPerDay}
        containerWidth={timelineMetrics.containerWidth}
      />

      {/* Tenant bars stacked vertically */}
      <div className="relative mt-2" style={{ paddingTop: '8px' }}>
        {validMembers.map((member, index) => (
          <TenantBar
            key={member.id}
            member={member}
            timelineStart={timelineMetrics.timelineStart}
            pixelPerDay={timelineMetrics.pixelPerDay}
            index={index}
            isHovered={hoveredMember?.id === member.id}
            onHover={setHoveredMember}
          />
        ))}
      </div>
    </div>
  )
}

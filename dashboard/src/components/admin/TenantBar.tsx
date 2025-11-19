/**
 * TenantBar - Individual tenant timeline bar with smart name placement
 * Renders horizontal bar proportional to tenure duration
 */
import React, { useMemo, useRef, useEffect, useState } from 'react'
import type { Member } from '../../views/AdminDashboard'
import { daysBetween, formatDuration, formatDate } from '../../utils/dateCalculations'
import { calculateNamePlacement } from '../../utils/textMeasurement'

interface TenantBarProps {
  member: Member
  timelineStart: Date
  pixelPerDay: number
  index: number
  isHovered: boolean
  onHover: (member: Member | null) => void
}

export const TenantBar: React.FC<TenantBarProps> = ({
  member,
  timelineStart,
  pixelPerDay,
  index,
  isHovered,
  onHover,
}) => {
  const barRef = useRef<HTMLDivElement>(null)
  const [barWidth, setBarWidth] = useState<number>(0)

  // Calculate position and width
  const { leftOffset, width, tenureDays } = useMemo(() => {
    if (!member.tenant_start_date || !member.tenant_departure_date) {
      return { leftOffset: 0, width: 0, tenureDays: 0 }
    }

    const daysFromStart = daysBetween(timelineStart, member.tenant_start_date)
    const tenure = daysBetween(member.tenant_start_date, member.tenant_departure_date)

    return {
      leftOffset: daysFromStart * pixelPerDay,
      width: Math.max(tenure * pixelPerDay, 120), // Minimum 120px (fits "FirstName L." format)
      tenureDays: tenure,
    }
  }, [member, timelineStart, pixelPerDay])

  // Update bar width state when calculated width changes
  useEffect(() => {
    setBarWidth(width)
  }, [width])

  // Determine name placement
  const namePlacement = useMemo(() => {
    if (barWidth === 0) {
      return { type: 'outside', text: member.tenant_name, truncate: false }
    }
    return calculateNamePlacement(barWidth, member.tenant_name || '', '18px Inter')
  }, [barWidth, member.tenant_name])

  // Determine bar styling based on contract status (match MemberRow)
  const hasCompletedContract = member.type === 'contract' && member.status === 'completed'
  const barBackground = hasCompletedContract
    ? 'bg-slate-900/40 border-cyan-500/10'
    : 'bg-slate-900/40 border-purple-500/10'

  return (
    <div
      className="absolute"
      style={{
        height: '44px',
        top: `${index * 52}px`, // Stack vertically with 52px spacing
        left: 0,
        right: 0,
      }}
    >
      {/* The bar itself */}
      <div
        ref={barRef}
        className={`absolute h-full rounded-xl border ${barBackground} cursor-pointer transition-all duration-200 ${
          isHovered ? 'bg-purple-900/10 shadow-lg z-10' : ''
        }`}
        style={{
          left: `${leftOffset}px`,
          width: `${width}px`,
        }}
        onMouseEnter={() => onHover(member)}
        onMouseLeave={() => onHover(null)}
        tabIndex={0}
        role="button"
        aria-label={`${member.tenant_name}: ${formatDuration(tenureDays)}`}
        title={`${formatDate(member.tenant_start_date)} → ${formatDate(member.tenant_departure_date)}`}
      >
        {/* Name inside bar */}
        {namePlacement.type === 'inside' && (
          <div className="absolute inset-0 flex items-center justify-center px-3">
            <span className="text-white font-medium text-lg drop-shadow-sm truncate">
              {namePlacement.text}
            </span>
          </div>
        )}
      </div>

      {/* Name outside bar (to the right) */}
      {namePlacement.type === 'outside' && (
        <div
          className="absolute top-0 h-full flex items-center"
          style={{
            left: `${leftOffset + width + 12}px`, // 12px gap after bar
          }}
        >
          <span className="text-purple-200 font-medium text-lg whitespace-nowrap">
            {namePlacement.text}
          </span>
        </div>
      )}

      {/* Duration label (always to the right of bar or name) */}
      <div
        className="absolute top-0 h-full flex items-center"
        style={{
          left:
            namePlacement.type === 'outside'
              ? `${leftOffset + width + 12 + (namePlacement.text.length * 9) + 16}px` // After name
              : `${leftOffset + width + 12}px`, // After bar
        }}
      >
        <span className="text-purple-300/70 text-base font-normal whitespace-nowrap mr-4">
          {formatDuration(tenureDays)}
        </span>
      </div>
    </div>
  )
}

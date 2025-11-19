/**
 * TenantBar - Individual tenant timeline bar with smart name placement
 * Renders horizontal bar proportional to tenure duration
 */
import React, { useMemo, useRef, useEffect, useState } from 'react'
import type { Member } from '../../views/AdminDashboard'
import { daysBetween, formatDuration } from '../../utils/dateCalculations'
import { calculateNamePlacement } from '../../utils/textMeasurement'
import { TenantTooltip } from './TenantTooltip'

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
      width: Math.max(tenure * pixelPerDay, 24), // Minimum 24px
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
    return calculateNamePlacement(barWidth, member.tenant_name || '', '12px Inter')
  }, [barWidth, member.tenant_name])

  // Determine bar color based on contract status
  const hasCompletedContract = member.type === 'contract' && member.status === 'completed'
  const barGradient = hasCompletedContract
    ? 'bg-gradient-to-r from-cyan-500/80 to-cyan-600/80'
    : 'bg-gradient-to-r from-purple-500/60 to-purple-600/60'

  const borderColor = hasCompletedContract
    ? 'border-t border-cyan-400/30'
    : 'border-t border-purple-400/30'

  return (
    <div
      className="relative mb-1"
      style={{
        height: '22px',
        top: `${index * 26}px`, // Stack vertically
      }}
    >
      {/* The bar itself */}
      <div
        ref={barRef}
        className={`absolute h-full rounded ${barGradient} ${borderColor} cursor-pointer transition-all duration-200 ${
          isHovered ? 'brightness-110 -translate-y-0.5 shadow-lg z-10' : ''
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
      >
        {/* Name inside bar */}
        {namePlacement.type === 'inside' && (
          <div className="absolute inset-0 flex items-center justify-center px-2">
            <span className="text-white font-medium text-xs drop-shadow-sm truncate">
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
            left: `${leftOffset + width + 8}px`, // 8px gap after bar
          }}
        >
          <span className="text-purple-200 font-normal text-xs whitespace-nowrap">
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
              ? `${leftOffset + width + 8 + (namePlacement.text.length * 7) + 12}px` // After name
              : `${leftOffset + width + 8}px`, // After bar
        }}
      >
        <span className="text-purple-300/60 text-[10px] font-normal whitespace-nowrap">
          {formatDuration(tenureDays)}
        </span>
      </div>

      {/* Tooltip on hover */}
      {isHovered && barRef.current && (
        <TenantTooltip member={member} barElement={barRef.current} tenureDays={tenureDays} />
      )}
    </div>
  )
}

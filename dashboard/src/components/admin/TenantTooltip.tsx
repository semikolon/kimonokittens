/**
 * TenantTooltip - Hover tooltip showing full tenant details
 * Positioned above bar (or below if near top edge)
 */
import React, { useEffect, useState } from 'react'
import type { Member } from '../../views/AdminDashboard'
import { formatDuration } from '../../utils/dateCalculations'
import { MapPin, Calendar, CheckCircle2, XCircle } from 'lucide-react'

interface TenantTooltipProps {
  member: Member
  barElement: HTMLElement
  tenureDays: number
}

// Status label translation (matching MemberRow pattern)
const getStatusLabel = (status: string) => {
  const labels: Record<string, string> = {
    completed: 'Klar',
    pending: 'Väntar',
    landlord_signed: 'Signerat av hyresvärd',
    tenant_signed: 'Signerat av hyresgäst',
    expired: 'Utgången',
    cancelled: 'Avbruten',
    failed: 'Misslyckades',
    active: 'Aktiv',
  }
  return labels[status] || status
}

// Format date to Swedish format (DD MMM YYYY)
const formatDate = (date: Date | undefined): string => {
  if (!date) return '—'
  return date.toLocaleDateString('sv-SE', {
    day: 'numeric',
    month: 'short',
    year: 'numeric',
  })
}

export const TenantTooltip: React.FC<TenantTooltipProps> = ({
  member,
  barElement,
  tenureDays,
}) => {
  const [position, setPosition] = useState<{ top: number; left: number } | null>(null)

  useEffect(() => {
    if (!barElement) return

    const barRect = barElement.getBoundingClientRect()
    const tooltipHeight = 140 // Approximate tooltip height

    // Position above bar by default, below if near top
    const shouldPositionBelow = barRect.top < tooltipHeight + 20

    setPosition({
      top: shouldPositionBelow ? barRect.bottom + 8 : barRect.top - tooltipHeight - 8,
      left: barRect.left + barRect.width / 2, // Center horizontally on bar
    })
  }, [barElement])

  if (!position) return null

  const hasContract = member.type === 'contract'
  const status = hasContract ? member.status : 'active'
  const statusLabel = getStatusLabel(status)

  return (
    <div
      className="fixed z-50 pointer-events-none"
      style={{
        top: `${position.top}px`,
        left: `${position.left}px`,
        transform: 'translateX(-50%)', // Center on bar
      }}
    >
      <div className="bg-slate-800/95 backdrop-blur-sm border border-purple-500/30 rounded-lg shadow-xl p-3 max-w-xs">
        {/* Name */}
        <div className="font-semibold text-purple-100 text-sm mb-2 truncate">
          {member.tenant_name}
        </div>

        {/* Room */}
        {member.tenant_room && (
          <div className="flex items-center gap-2 text-xs text-purple-300/80 mb-1">
            <MapPin className="w-3 h-3" />
            <span>Rum {member.tenant_room}</span>
          </div>
        )}

        {/* Contract status */}
        <div className="flex items-center gap-2 text-xs mb-2">
          {hasContract && status === 'completed' ? (
            <CheckCircle2 className="w-3 h-3 text-cyan-400" />
          ) : hasContract ? (
            <XCircle className="w-3 h-3 text-purple-400" />
          ) : (
            <XCircle className="w-3 h-3 text-purple-400/60" />
          )}
          <span className="text-purple-300/80">
            {hasContract ? `Kontrakt: ${statusLabel}` : 'Inget kontrakt'}
          </span>
        </div>

        {/* Date range */}
        <div className="flex items-center gap-2 text-xs text-purple-300/70 mb-1">
          <Calendar className="w-3 h-3" />
          <span>
            {formatDate(member.tenant_start_date)} → {formatDate(member.tenant_departure_date)}
          </span>
        </div>

        {/* Duration */}
        <div className="text-xs font-medium text-purple-200 mt-2 pt-2 border-t border-purple-500/20">
          {formatDuration(tenureDays)}
        </div>
      </div>

      {/* Arrow pointing to bar */}
      <div
        className="absolute left-1/2 -translate-x-1/2 w-0 h-0"
        style={{
          bottom: position.top > barElement.getBoundingClientRect().top ? 'auto' : '-6px',
          top: position.top > barElement.getBoundingClientRect().top ? '-6px' : 'auto',
          borderLeft: '6px solid transparent',
          borderRight: '6px solid transparent',
          borderTop:
            position.top > barElement.getBoundingClientRect().top
              ? 'none'
              : '6px solid rgba(30, 41, 59, 0.95)',
          borderBottom:
            position.top > barElement.getBoundingClientRect().top
              ? '6px solid rgba(30, 41, 59, 0.95)'
              : 'none',
        }}
      />
    </div>
  )
}

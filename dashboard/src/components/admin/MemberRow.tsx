// MemberRow - Unified row for both contracts and standalone tenants
import React from 'react'
import { CheckCircle2, Clock, XCircle, Ban, AlertTriangle, UserCheck, ChevronRight, CircleUserRound, FileSignature, MapPin, Coins } from 'lucide-react'
import { ContractDetails } from './ContractDetails'
import { TenantDetails } from './TenantDetails'
import type { Member, SignedContract, TenantMember } from '../../views/AdminDashboard'
import { useAdminAuth } from '../../contexts/AdminAuthContext'

interface MemberRowProps {
  member: Member
  isExpanded: boolean
  isSelected: boolean
  onToggle: () => void
  onSelect: () => void
}

// Status icon mapping for contracts
const getStatusIcon = (contract: SignedContract) => {
  const landlordPersonnummer = contract.landlord_personnummer?.replace(/\D/g, '')
  const tenantPersonnummer = contract.tenant_personnummer?.replace(/\D/g, '')
  const isLandlord = Boolean(landlordPersonnummer && tenantPersonnummer === landlordPersonnummer)
  const landlordSigned = isLandlord || contract.landlord_signed

  if (contract.status === 'completed') {
    return <CheckCircle2 className="w-5 h-5 text-cyan-400" />
  } else if (contract.status === 'failed') {
    return <XCircle className="w-5 h-5 text-red-400" />
  } else if (contract.status === 'expired') {
    return <AlertTriangle className="w-5 h-5 text-orange-400" />
  } else if (contract.status === 'cancelled') {
    return <Ban className="w-5 h-5 text-red-400" />
  } else if (landlordSigned && !contract.tenant_signed) {
    return <UserCheck className="w-5 h-5 text-blue-400" />
  } else if (!landlordSigned && contract.tenant_signed) {
    return <UserCheck className="w-5 h-5 text-yellow-400" />
  } else {
    return <Clock className="w-5 h-5 text-yellow-400" />
  }
}

// Status badge color
const getStatusColor = (status: string) => {
  const colors = {
    completed: 'bg-cyan-400/20 text-cyan-300 border-cyan-400/30',
    pending: 'bg-yellow-400/20 text-yellow-300 border-yellow-400/30',
    landlord_signed: 'bg-blue-400/20 text-blue-300 border-blue-400/30',
    tenant_signed: 'bg-yellow-400/20 text-yellow-300 border-yellow-400/30',
    failed: 'bg-red-400/20 text-red-300 border-red-400/30',
    cancelled: 'bg-red-400/20 text-red-300 border-red-400/30',
    expired: 'bg-orange-400/20 text-orange-300 border-orange-400/30',
    departed: 'bg-slate-600/20 text-slate-400 border-slate-600/30',
    active: 'bg-slate-400/20 text-slate-300 border-slate-400/30'
  }
  return colors[status as keyof typeof colors] || colors.active
}

// Status label translation (Swedish)
const getStatusLabel = (status: string) => {
  const labels = {
    completed: 'Klar',
    pending: 'Väntar',
    landlord_signed: 'Signerat av hyresvärd',
    tenant_signed: 'Signerat av hyresgäst',
    failed: 'Misslyckat',
    cancelled: 'Avbrutet',
    expired: 'Utgånget',
    departed: 'Utflyttad',
    active: 'Aktiv'
  }
  return labels[status as keyof typeof labels] || 'Aktiv'
}

const formatDurationBetween = (startDate?: Date | null, endDate?: Date | null) => {
  if (!startDate) return null
  const start = new Date(startDate)
  const finish = endDate ? new Date(endDate) : new Date()
  if (isNaN(start.getTime()) || isNaN(finish.getTime()) || finish < start) return null

  const diffMs = finish.getTime() - start.getTime()
  const diffDays = Math.max(0, Math.floor(diffMs / (1000 * 60 * 60 * 24)))

  if (diffDays < 7) {
    const days = Math.max(diffDays, 1)
    return days === 1 ? '1 dag' : `${days} dagar`
  }

  if (diffDays < 30) {
    const weeks = Math.max(1, Math.floor(diffDays / 7))
    return weeks === 1 ? '1 vecka' : `${weeks} veckor`
  }

  let years = finish.getFullYear() - start.getFullYear()
  let months = finish.getMonth() - start.getMonth()
  const dayDiff = finish.getDate() - start.getDate()

  if (dayDiff < 0) {
    months -= 1
  }
  if (months < 0) {
    years -= 1
    months += 12
  }

  if (years <= 0) {
    if (months <= 0) {
      return '1 mån'
    }
    return months === 1 ? '1 mån' : `${months} mån`
  }

  if (months <= 0) {
    return years === 1 ? '1 år' : `${years} år`
  }

  return years === 1
    ? `1 år, ${months} mån`
    : `${years} år, ${months} mån`
}

// Format date range for tenant stay
const formatDateRange = (startDate?: Date, departureDate?: Date): string => {
  if (!startDate) return ''

  const monthNames = ['jan', 'feb', 'mar', 'apr', 'maj', 'jun', 'jul', 'aug', 'sep', 'okt', 'nov', 'dec']
  const currentYear = new Date().getFullYear()

  const formatDate = (date: Date, includeYear: boolean = false) => {
    const day = date.getDate()
    const month = monthNames[date.getMonth()]
    const year = includeYear ? ` ${date.getFullYear()}` : ''
    return `${day} ${month}${year}`
  }

  // Show year if start date is not current year
  const showStartYear = startDate.getFullYear() !== currentYear
  const startStr = formatDate(startDate, showStartYear)

  if (!departureDate) {
    return `${startStr} → ?`
  }

  // Show year if departure year differs from start year OR not current year
  const showEndYear = departureDate.getFullYear() !== startDate.getFullYear() || departureDate.getFullYear() !== currentYear
  const endStr = formatDate(departureDate, showEndYear)

  return `${startStr} → ${endStr}`
}

export const MemberRow: React.FC<MemberRowProps> = ({
  member,
  isExpanded,
  isSelected,
  onToggle,
  onSelect
}) => {
  const { ensureAuth } = useAdminAuth()
  const dateRange = formatDateRange(member.tenant_start_date, member.tenant_departure_date)
  const isContract = member.type === 'contract'
  const isTenant = member.type === 'tenant'

  // Check if tenant has departed (don't show create contract button for past tenants)
  const today = new Date()
  today.setHours(0, 0, 0, 0) // Start of today
  const hasDeparted = member.tenant_departure_date && member.tenant_departure_date < today
  const notStarted = member.tenant_start_date && member.tenant_start_date > today
  const shouldShowCreateButton = isTenant && !hasDeparted
  const shouldShowRent = !(hasDeparted || notStarted)
  const timeLivedLabel = shouldShowRent ? formatDurationBetween(member.tenant_start_date || null, null) : null
  const timeStayedLabel = hasDeparted ? formatDurationBetween(member.tenant_start_date || null, member.tenant_departure_date || null) : null

  // Compute tenant status
  const tenantStatus = isTenant ? (hasDeparted ? 'departed' : 'active') : 'active'

  const contractStatus = isContract ? (member as SignedContract).status : null
  const showTimeLabel = isContract
    ? contractStatus === 'completed' && timeLivedLabel
    : timeLivedLabel
  const statusLabel = hasDeparted && timeStayedLabel
    ? `Utflyttad: ${timeStayedLabel}`
    : (showTimeLabel
        ? showTimeLabel
        : getStatusLabel(isContract ? (contractStatus as string) : tenantStatus))

  const [creatingContract, setCreatingContract] = React.useState(false)
  const [toast, setToast] = React.useState<{ message: string; type: 'success' | 'error' } | null>(null)

  const showToast = (message: string, type: 'success' | 'error') => {
    setToast({ message, type })
    setTimeout(() => setToast(null), 3000)
  }

  const handleCreateContract = async () => {
    try {
      const adminToken = await ensureAuth()
      if (!adminToken) {
        return
      }

      setCreatingContract(true)
      const response = await fetch(`/api/admin/contracts/tenants/${member.tenant_id}/create-contract`, {
        method: 'POST',
        headers: {
          'X-Admin-Token': adminToken
        }
      })
      const data = await response.json()

      if (response.ok) {
        // Show success toast with what was sent
        const firstName = member.name.split(' ')[0]
        const hasPhone = member.phone && member.phone.trim().length > 0
        const sentMethod = hasPhone ? 'Email och SMS skickat' : 'Email skickat'
        showToast(
          `Kontrakt skapat för ${firstName}! ${sentMethod}.`,
          'success'
        )
        // WebSocket broadcast will update UI automatically
      } else {
        showToast(data.error || 'Kunde inte skapa kontrakt', 'error')
      }
    } catch (error) {
      showToast('Fel vid skapande av kontrakt', 'error')
    } finally {
      setCreatingContract(false)
    }
  }

  const detailsRef = React.useRef<HTMLDivElement>(null)
  const [contentHeight, setContentHeight] = React.useState(0)

  React.useLayoutEffect(() => {
    if (isExpanded && detailsRef.current) {
      setContentHeight(detailsRef.current.scrollHeight)
    }
  }, [isExpanded, member])

  const detailsStyle: React.CSSProperties = {
    maxHeight: isExpanded ? `${contentHeight}px` : '0px',
    opacity: isExpanded ? 1 : 0,
    overflow: 'hidden'
  }

  return (
    <div
      className={`
        rounded-2xl border transition-all duration-200
        ${isSelected
          ? 'border-purple-500/15 bg-purple-900/25'
          : 'border-purple-500/10 bg-slate-900/40'
        }
        hover:bg-purple-900/10
      `}
    >
      {/* Collapsed row header */}
      <div
        onClick={() => {
          onSelect()
          onToggle() // All rows are now expandable
        }}
        className="w-full p-4 flex items-center gap-4 text-left cursor-pointer"
        role="button"
        tabIndex={0}
        onKeyDown={(e) => {
          if (e.key === 'Enter' || e.key === ' ') {
            e.preventDefault()
            onSelect()
            onToggle()
          }
        }}
      >
        {/* Expand icon (all rows are expandable) */}
        <ChevronRight
          className={`
            w-4 h-4 text-purple-300 transition-transform duration-200
            ${isExpanded ? 'rotate-90' : ''}
          `}
        />

        {/* Status icon */}
        {isContract ? getStatusIcon(member as SignedContract) : (
          <CircleUserRound className="w-5 h-5 text-slate-400" />
        )}

        {/* Member info */}
        <div className="flex-1 flex items-center justify-between">
          <div className="flex items-center gap-4">
            <span className="text-purple-100 font-medium">
              {member.tenant_name}
            </span>
            {member.tenant_room && (
              <span className="text-purple-300/80 text-sm font-medium flex items-center gap-1">
                <MapPin className="w-3.5 h-3.5 text-purple-300/80" />
                {member.tenant_room}
              </span>
            )}
            {dateRange && (
              <span className="text-purple-300/60 text-sm">
                {dateRange}
              </span>
            )}
          </div>

          <div className="flex items-center gap-3">
            {/* Status badge */}
            <span className={`
              px-3 py-1 rounded-full text-xs font-medium border
              ${getStatusColor(isContract ? (member as SignedContract).status : tenantStatus)}
            `}>
              {statusLabel}
            </span>

            {/* Payment status badge (Phase 6: Rent Reminders) */}
            {shouldShowRent && (
              <span className={`
                px-2.5 py-1 rounded-full text-xs font-medium border flex items-center gap-1.5
                ${member.rent_paid
                  ? 'bg-cyan-400/20 text-cyan-300 border-cyan-400/30'
                  : member.rent_remaining && member.rent_remaining > 0
                    ? 'bg-yellow-400/20 text-yellow-300 border-yellow-400/30'
                    : 'bg-slate-600/20 text-slate-400 border-slate-600/30'
                }
              `}>
                <Coins className="w-3 h-3" />
                {member.rent_paid
                  ? 'Betald'
                  : member.rent_remaining && member.rent_remaining > 0
                    ? `${Math.round(member.rent_remaining).toLocaleString('sv-SE')} kr`
                    : 'Hyra'}
              </span>
            )}

            {/* Test mode badge */}
            {isContract && (member as SignedContract).test_mode && (
              <span className="px-2 py-1 rounded text-xs bg-slate-700/50 text-slate-300">
                Test
              </span>
            )}

            {/* Create contract button for active tenants only (not past tenants) */}
            {shouldShowCreateButton && (
              <button
                onClick={(e) => {
                  e.stopPropagation()
                  handleCreateContract()
                }}
                disabled={creatingContract}
                className="flex items-center gap-2 px-3 py-2.5 rounded-lg text-xs font-medium
                         text-white transition-all button-cursor-glow button-glow-orange button-hover-brighten
                         disabled:opacity-50 disabled:cursor-not-allowed"
                style={{
                  backgroundImage: 'linear-gradient(180deg, #c86c34 20%, #8f3c10 100%)'
                }}
              >
                <FileSignature className="w-3 h-3 text-white" />
                {creatingContract ? 'Skapar...' : 'Skapa kontrakt'}
              </button>
            )}
          </div>
        </div>
      </div>

      {/* Error message in collapsed state */}
      {isContract && (member as SignedContract).error_message && !isExpanded && (
        <div className="px-4 pb-3 text-sm text-red-400">
          Fel: {(member as SignedContract).error_message}
        </div>
      )}

      {/* Expanded details (for all rows) */}
      <div
        className={`${isExpanded ? 'rounded-b-2xl border-t border-purple-500/10' : ''}`}
        style={detailsStyle}
      >
        {isContract ? (
          <>
            <div ref={detailsRef}>
              <ContractDetails contract={member as SignedContract} />
              {/* Also show tenant details for contracts */}
              <TenantDetails
                tenant={{
                  ...(member as SignedContract),
                  type: 'tenant', // Override type for TenantMember interface
                  id: (member as SignedContract).tenant_id,
                  status: 'active'
                }}
                showRent={shouldShowRent}
              />
            </div>
          </>
        ) : (
          <div ref={detailsRef}>
            <TenantDetails tenant={member as TenantMember} showRent={shouldShowRent} />
          </div>
        )}
      </div>

      {/* Toast Notification */}
      {toast && (
        <div className="fixed bottom-4 right-4 z-50 animate-fade-in">
          <div
            className={`
              px-4 py-3 rounded-lg shadow-lg flex items-center gap-2
            ${toast.type === 'success'
                ? 'bg-cyan-600 text-white'
                : 'bg-red-600 text-white'
            }
            `}
          >
            {toast.type === 'success' ? (
              <CheckCircle2 className="w-5 h-5" />
            ) : (
              <XCircle className="w-5 h-5" />
            )}
            <span className="font-medium">{toast.message}</span>
          </div>
        </div>
      )}
    </div>
  )
}

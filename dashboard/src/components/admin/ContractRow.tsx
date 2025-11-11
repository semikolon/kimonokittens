// ContractRow - Collapsible row with expand/collapse
import React from 'react'
import { CheckCircle2, Clock, XCircle, Ban, AlertTriangle, UserCheck, ChevronRight } from 'lucide-react'
import { ContractDetails } from './ContractDetails'
import type { SignedContract } from '../../views/AdminDashboard'

interface ContractRowProps {
  contract: SignedContract
  isExpanded: boolean
  isSelected: boolean
  onToggle: () => void
  onSelect: () => void
}

// Status icon mapping
const getStatusIcon = (contract: SignedContract) => {
  if (contract.status === 'completed') {
    return <CheckCircle2 className="w-5 h-5 text-green-400" />
  } else if (contract.status === 'failed') {
    return <XCircle className="w-5 h-5 text-red-400" />
  } else if (contract.status === 'expired') {
    return <AlertTriangle className="w-5 h-5 text-orange-400" />
  } else if (contract.status === 'cancelled') {
    return <Ban className="w-5 h-5 text-red-400" />
  } else if (contract.landlord_signed && !contract.tenant_signed) {
    return <UserCheck className="w-5 h-5 text-blue-400" />
  } else if (!contract.landlord_signed && contract.tenant_signed) {
    return <UserCheck className="w-5 h-5 text-yellow-400" />
  } else {
    return <Clock className="w-5 h-5 text-yellow-400" />
  }
}

// Status badge color
const getStatusColor = (status: string) => {
  const colors = {
    completed: 'bg-green-400/20 text-green-300 border-green-400/30',
    pending: 'bg-yellow-400/20 text-yellow-300 border-yellow-400/30',
    landlord_signed: 'bg-blue-400/20 text-blue-300 border-blue-400/30',
    tenant_signed: 'bg-yellow-400/20 text-yellow-300 border-yellow-400/30',
    failed: 'bg-red-400/20 text-red-300 border-red-400/30',
    cancelled: 'bg-red-400/20 text-red-300 border-red-400/30',
    expired: 'bg-orange-400/20 text-orange-300 border-orange-400/30'
  }
  return colors[status as keyof typeof colors] || colors.pending
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
    expired: 'Utgånget'
  }
  return labels[status as keyof typeof labels] || 'Väntar'
}

export const ContractRow: React.FC<ContractRowProps> = ({
  contract,
  isExpanded,
  isSelected,
  onToggle,
  onSelect
}) => {
  const formattedDate = new Date(contract.created_at).toLocaleDateString('sv-SE', {
    month: 'long',
    day: 'numeric'
  })

  return (
    <div
      className={`
        rounded-lg border transition-all duration-200
        ${isSelected
          ? 'border-purple-400/30 bg-purple-900/20'
          : 'border-purple-500/20 bg-slate-900/40'
        }
        hover:bg-purple-900/10
      `}
    >
      {/* Collapsed row header */}
      <button
        onClick={() => {
          onSelect()
          onToggle()
        }}
        className="w-full p-4 flex items-center gap-4 text-left"
      >
        {/* Expand icon */}
        <ChevronRight
          className={`
            w-4 h-4 text-purple-300 transition-transform duration-200
            ${isExpanded ? 'rotate-90' : ''}
          `}
        />

        {/* Status icon */}
        {getStatusIcon(contract)}

        {/* Contract info */}
        <div className="flex-1 flex items-center justify-between">
          <div className="flex items-center gap-4">
            <span className="text-purple-100 font-medium">
              {contract.tenant_id}
            </span>
            <span className="text-purple-300/60 text-sm">
              {formattedDate}
            </span>
          </div>

          <div className="flex items-center gap-3">
            {/* Status badge */}
            <span className={`
              px-3 py-1 rounded-full text-xs font-medium border
              ${getStatusColor(contract.status)}
            `}>
              {getStatusLabel(contract.status)}
            </span>

            {/* Test mode badge */}
            {contract.test_mode && (
              <span className="px-2 py-1 rounded text-xs bg-slate-700/50 text-slate-300">
                Test
              </span>
            )}
          </div>
        </div>
      </button>

      {/* Error message in collapsed state */}
      {contract.error_message && !isExpanded && (
        <div className="px-4 pb-3 text-sm text-red-400">
          Fel: {contract.error_message}
        </div>
      )}

      {/* Expanded details */}
      {isExpanded && (
        <div className="border-t border-purple-500/20">
          <ContractDetails contract={contract} />
        </div>
      )}
    </div>
  )
}


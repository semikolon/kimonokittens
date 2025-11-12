// ContractList - List with filter toggle and keyboard navigation
import React, { useState } from 'react'
import { Filter } from 'lucide-react'
import { MemberRow } from './MemberRow'
import type { Member } from '../../views/AdminDashboard'

interface ContractListProps {
  contracts: Member[]  // Now accepts both contracts and tenants
  filterActive: boolean
  onFilterToggle: () => void
}

export const ContractList: React.FC<ContractListProps> = ({
  contracts,
  filterActive,
  onFilterToggle
}) => {
  const [selectedId, setSelectedId] = useState<string | null>(null)
  const [expandedId, setExpandedId] = useState<string | null>(null)

  // Keyboard navigation
  React.useEffect(() => {
    const handleKeyDown = (e: KeyboardEvent) => {
      if (e.key === 'ArrowDown') {
        e.preventDefault()
        const currentIndex = contracts.findIndex(c => c.id === selectedId)
        const nextIndex = (currentIndex + 1) % contracts.length
        setSelectedId(contracts[nextIndex]?.id || null)
      } else if (e.key === 'ArrowUp') {
        e.preventDefault()
        const currentIndex = contracts.findIndex(c => c.id === selectedId)
        const prevIndex = currentIndex <= 0 ? contracts.length - 1 : currentIndex - 1
        setSelectedId(contracts[prevIndex]?.id || null)
      } else if ((e.key === 'Enter' || e.key === 'ArrowRight') && selectedId) {
        e.preventDefault()
        setExpandedId(expandedId === selectedId ? null : selectedId)
      } else if (e.key === 'ArrowLeft' && expandedId) {
        e.preventDefault()
        setExpandedId(null)
      } else if (e.key === 'Escape') {
        e.preventDefault()
        setExpandedId(null)
      }
    }

    window.addEventListener('keydown', handleKeyDown)
    return () => window.removeEventListener('keydown', handleKeyDown)
  }, [selectedId, expandedId, contracts])

  // Segment members into current vs historical
  const today = new Date()
  today.setHours(0, 0, 0, 0)

  const currentMembers = contracts.filter(member => {
    const departureDate = member.tenant_departure_date
    return !departureDate || departureDate >= today
  })

  const historicalMembers = contracts.filter(member => {
    const departureDate = member.tenant_departure_date
    return departureDate && departureDate < today
  })

  // Calculate member statistics
  const contractMembers = contracts.filter(m => m.type === 'contract')
  const tenantMembers = contracts.filter(m => m.type === 'tenant')
  const completedCount = contractMembers.filter(c => c.type === 'contract' && c.status === 'completed').length
  const pendingCount = contractMembers.filter(c => c.type === 'contract' && (c.status === 'pending' || c.status === 'landlord_signed' || c.status === 'tenant_signed')).length

  // Generate summary message
  const getSummary = () => {
    const totalMembers = contracts.length
    const withoutContracts = tenantMembers.length

    if (totalMembers === 0) {
      return 'Inga medlemmar'
    } else if (withoutContracts === 0 && completedCount === contractMembers.length) {
      return `${totalMembers} ${totalMembers === 1 ? 'medlem' : 'medlemmar'} - alla har signerade kontrakt`
    } else if (withoutContracts > 0) {
      return `${totalMembers} ${totalMembers === 1 ? 'medlem' : 'medlemmar'} - ${withoutContracts} utan kontrakt`
    } else if (pendingCount > 0) {
      return `${totalMembers} ${totalMembers === 1 ? 'medlem' : 'medlemmar'} - ${pendingCount} inväntar signatur`
    } else {
      return `${totalMembers} ${totalMembers === 1 ? 'medlem' : 'medlemmar'}`
    }
  }

  return (
    <div className="space-y-4">
      {/* Summary line + Filter toggle on same line */}
      <div className="flex items-center justify-between mb-4">
        <div className="text-sm text-purple-200">
          {getSummary()}
        </div>
        <button
          onClick={onFilterToggle}
          className={`
            flex items-center gap-2 px-4 py-2 rounded-lg text-sm font-medium
            transition-all duration-200
            ${filterActive
              ? 'bg-purple-600 text-white hover:bg-purple-700'
              : 'bg-slate-800/50 text-purple-200 hover:bg-slate-700/50'
            }
            border ${filterActive ? 'border-purple-500' : 'border-purple-900/30'}
          `}
        >
          <Filter className="w-4 h-4" />
          {filterActive ? 'Aktiva' : 'Alla'}
        </button>
      </div>

      {/* Current members section */}
      {currentMembers.length > 0 && (
        <div className="space-y-2">
          <div className="text-purple-200 mb-3" style={{ textTransform: 'uppercase', fontSize: '0.8em' }}>
            Nuvarande
          </div>
          {currentMembers.map((member) => (
            <MemberRow
              key={member.id}
              member={member}
              isExpanded={expandedId === member.id}
              isSelected={selectedId === member.id}
              onToggle={() => setExpandedId(expandedId === member.id ? null : member.id)}
              onSelect={() => setSelectedId(member.id)}
            />
          ))}
        </div>
      )}

      {/* Historical members section */}
      {historicalMembers.length > 0 && (
        <div className="space-y-2 mt-6">
          <div className="text-purple-200 mb-3" style={{ textTransform: 'uppercase', fontSize: '0.8em' }}>
            Historiska
          </div>
          {historicalMembers.map((member) => (
            <MemberRow
              key={member.id}
              member={member}
              isExpanded={expandedId === member.id}
              isSelected={selectedId === member.id}
              onToggle={() => setExpandedId(expandedId === member.id ? null : member.id)}
              onSelect={() => setSelectedId(member.id)}
            />
          ))}
        </div>
      )}
    </div>
  )
}

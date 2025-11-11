// ContractList - List with filter toggle and keyboard navigation
import React, { useState } from 'react'
import { Filter } from 'lucide-react'
import { ContractRow } from './ContractRow'
import type { SignedContract } from '../../views/AdminDashboard'

interface ContractListProps {
  contracts: SignedContract[]
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

  // Calculate contract statistics
  const completedCount = contracts.filter(c => c.status === 'completed').length
  const pendingCount = contracts.filter(c => c.status === 'pending' || c.status === 'landlord_signed' || c.status === 'tenant_signed').length

  // Generate summary message
  const getSummary = () => {
    if (completedCount === 0 && pendingCount === 0) {
      return 'Inga kontrakt'
    } else if (completedCount === 0 && pendingCount === 1) {
      return 'Inväntar signatur för ett kontrakt'
    } else if (completedCount === 0) {
      return `Inväntar signaturer för ${pendingCount} st`
    } else if (pendingCount === 0) {
      return `${completedCount} ${completedCount === 1 ? 'signerat kontrakt' : 'signerade kontrakt'}`
    } else if (pendingCount === 1) {
      return `${completedCount} ${completedCount === 1 ? 'signerat kontrakt' : 'signerade kontrakt'} - inväntar signatur för ett`
    } else {
      return `${completedCount} ${completedCount === 1 ? 'signerat kontrakt' : 'signerade kontrakt'} - inväntar signaturer för ${pendingCount} st`
    }
  }

  return (
    <div className="space-y-4">
      {/* Summary line */}
      <div className="text-sm text-purple-200 mb-3">
        {getSummary()}
      </div>

      {/* Filter toggle */}
      <div className="flex items-center justify-end mb-4">
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

      {/* Contract rows */}
      <div className="space-y-2">
        {contracts.map((contract) => (
          <ContractRow
            key={contract.id}
            contract={contract}
            isExpanded={expandedId === contract.id}
            isSelected={selectedId === contract.id}
            onToggle={() => setExpandedId(expandedId === contract.id ? null : contract.id)}
            onSelect={() => setSelectedId(contract.id)}
          />
        ))}
      </div>
    </div>
  )
}

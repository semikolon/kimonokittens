// ContractList - List with filter toggle and keyboard navigation
import React, { useState } from 'react'
import { MemberRow } from './MemberRow'
import { CompactTenantTimeline } from './CompactTenantTimeline'
import type { Member } from '../../views/AdminDashboard'

interface ContractListProps {
  contracts: Member[]  // Now accepts both contracts and tenants
}

export const ContractList: React.FC<ContractListProps> = ({ contracts }) => {
  const [selectedId, setSelectedId] = useState<string | null>(null)
  const [expandedId, setExpandedId] = useState<string | null>(null)

  // Segment members into current vs historical (memoized to stabilize references)
  const { currentMembers, historicalMembers } = React.useMemo(() => {
    const today = new Date()
    today.setHours(0, 0, 0, 0)

    const current = contracts.filter(member => {
      const departureDate = member.tenant_departure_date
      return !departureDate || departureDate >= today
    })

    const historical = contracts.filter(member => {
      const departureDate = member.tenant_departure_date
      return departureDate && departureDate < today
    })

    return { currentMembers: current, historicalMembers: historical }
  }, [contracts])

  const orderedMembers = React.useMemo(
    () => [...currentMembers, ...historicalMembers],
    [currentMembers, historicalMembers]
  )

  // Keyboard navigation
  React.useEffect(() => {
    const handleKeyDown = (e: KeyboardEvent) => {
      const active = document.activeElement as HTMLElement | null
      if (active) {
        const tag = active.tagName
        const isFormField = tag === 'INPUT' || tag === 'TEXTAREA' || active.isContentEditable
        if (isFormField) return
      }
      if (e.key === 'ArrowDown') {
        e.preventDefault()
        if (orderedMembers.length === 0) return
        const currentIndex = orderedMembers.findIndex(c => c.id === selectedId)
        const nextIndex = (currentIndex + 1 + orderedMembers.length) % orderedMembers.length
        const nextId = orderedMembers[nextIndex]?.id || null
        setSelectedId(nextId)
        setExpandedId(nextId)
      } else if (e.key === 'ArrowUp') {
        e.preventDefault()
        if (orderedMembers.length === 0) return
        const currentIndex = orderedMembers.findIndex(c => c.id === selectedId)
        const prevIndex = currentIndex <= 0 ? orderedMembers.length - 1 : currentIndex - 1
        const prevId = orderedMembers[prevIndex]?.id || null
        setSelectedId(prevId)
        setExpandedId(prevId)
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
  }, [selectedId, expandedId, orderedMembers])

  const formatCount = (count: number, singular: string, plural: string) => `${count} ${count === 1 ? singular : plural}`

  const renderSectionHeader = (label: string, members: Member[]) => (
    <div
      className="text-purple-200 mb-4 flex items-center gap-2 flex-wrap"
      style={{ textTransform: 'uppercase', fontSize: '0.8em' }}
    >
      <span>{label}</span>
      <span className="text-purple-300/40">•</span>
      <span className="text-purple-300/80">
        {formatCount(members.length, 'medlem', 'medlemmar')}
      </span>
      <span className="text-purple-300/40">•</span>
      <span className="text-purple-300/80">
        {formatCount(members.filter(member => member.type === 'tenant').length, 'utan kontrakt', 'utan kontrakt')}
      </span>
    </div>
  )

  return (
    <div className="space-y-4">

      {/* Current members section */}
      {currentMembers.length > 0 && (
        <div className="space-y-2 mt-12 mb-12">
          {renderSectionHeader('Nuvarande', currentMembers)}
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
        <div className="space-y-4">
          {renderSectionHeader('Historiska', historicalMembers)}
          <CompactTenantTimeline members={historicalMembers} />
        </div>
      )}
    </div>
  )
}

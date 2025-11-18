// LeadsList - Tenant signup applications with status-based grouping and keyboard navigation
import React, { useState } from 'react'
import { LeadRow } from './LeadRow'
import type { TenantLead } from '../../context/DataContext'

interface LeadsListProps {
  leads: TenantLead[]
}

export const LeadsList: React.FC<LeadsListProps> = ({ leads }) => {
  const [selectedId, setSelectedId] = useState<string | null>(null)
  const [expandedId, setExpandedId] = useState<string | null>(null)

  // Group leads by status (memoized to stabilize references)
  const { pendingLeads, activeLeads, closedLeads } = React.useMemo(() => {
    const pending = leads.filter(lead => lead.status === 'pending_review')
    const active = leads.filter(lead =>
      ['contacted', 'interview_scheduled', 'approved'].includes(lead.status)
    )
    const closed = leads.filter(lead =>
      ['rejected', 'converted'].includes(lead.status)
    )

    // Sort by creation date (newest first)
    const sortByDate = (a: TenantLead, b: TenantLead) =>
      new Date(b.createdAt).getTime() - new Date(a.createdAt).getTime()

    return {
      pendingLeads: pending.sort(sortByDate),
      activeLeads: active.sort(sortByDate),
      closedLeads: closed.sort(sortByDate)
    }
  }, [leads])

  const orderedLeads = React.useMemo(
    () => [...pendingLeads, ...activeLeads, ...closedLeads],
    [pendingLeads, activeLeads, closedLeads]
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
        if (orderedLeads.length === 0) return
        const currentIndex = orderedLeads.findIndex(lead => lead.id === selectedId)
        const nextIndex = (currentIndex + 1 + orderedLeads.length) % orderedLeads.length
        const nextId = orderedLeads[nextIndex]?.id || null
        setSelectedId(nextId)
        setExpandedId(nextId)
      } else if (e.key === 'ArrowUp') {
        e.preventDefault()
        if (orderedLeads.length === 0) return
        const currentIndex = orderedLeads.findIndex(lead => lead.id === selectedId)
        const prevIndex = currentIndex <= 0 ? orderedLeads.length - 1 : currentIndex - 1
        const prevId = orderedLeads[prevIndex]?.id || null
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
  }, [selectedId, expandedId, orderedLeads])

  const formatCount = (count: number, singular: string, plural: string) =>
    `${count} ${count === 1 ? singular : plural}`

  const renderSectionHeader = (label: string, leads: TenantLead[]) => (
    <div
      className="text-purple-200 mb-4 flex items-center gap-2 flex-wrap"
      style={{ textTransform: 'uppercase', fontSize: '0.8em' }}
    >
      <span>{label}</span>
      <span className="text-purple-300/40">•</span>
      <span className="text-purple-300/80">
        {formatCount(leads.length, 'anmälan', 'anmälningar')}
      </span>
    </div>
  )

  if (leads.length === 0) {
    return (
      <div className="text-purple-300/60 text-center py-8">
        Inga intresseanmälningar ännu.
      </div>
    )
  }

  return (
    <div className="space-y-4">
      {/* Pending review section */}
      {pendingLeads.length > 0 && (
        <div className="space-y-2 mt-12 mb-12">
          {renderSectionHeader('Väntande granskning', pendingLeads)}
          {pendingLeads.map((lead) => (
            <LeadRow
              key={lead.id}
              lead={lead}
              isExpanded={expandedId === lead.id}
              isSelected={selectedId === lead.id}
              onToggle={() => setExpandedId(expandedId === lead.id ? null : lead.id)}
              onSelect={() => setSelectedId(lead.id)}
            />
          ))}
        </div>
      )}

      {/* Active leads section */}
      {activeLeads.length > 0 && (
        <div className="space-y-2 mb-12">
          {renderSectionHeader('Aktiva', activeLeads)}
          {activeLeads.map((lead) => (
            <LeadRow
              key={lead.id}
              lead={lead}
              isExpanded={expandedId === lead.id}
              isSelected={selectedId === lead.id}
              onToggle={() => setExpandedId(expandedId === lead.id ? null : lead.id)}
              onSelect={() => setSelectedId(lead.id)}
            />
          ))}
        </div>
      )}

      {/* Closed leads section */}
      {closedLeads.length > 0 && (
        <div className="space-y-2">
          {renderSectionHeader('Avslutade', closedLeads)}
          {closedLeads.map((lead) => (
            <LeadRow
              key={lead.id}
              lead={lead}
              isExpanded={expandedId === lead.id}
              isSelected={selectedId === lead.id}
              onToggle={() => setExpandedId(expandedId === lead.id ? null : lead.id)}
              onSelect={() => setSelectedId(lead.id)}
            />
          ))}
        </div>
      )}
    </div>
  )
}

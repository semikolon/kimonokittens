// ContractTimeline - Event timeline display
import React from 'react'
import type { SignedContract } from '../../views/AdminDashboard'

interface ContractTimelineProps {
  contract: SignedContract
}

interface TimelineEvent {
  timestamp: Date
  label: string
  actor?: string
}

export const ContractTimeline: React.FC<ContractTimelineProps> = ({ contract }) => {
  // Build timeline from contract data
  const events: TimelineEvent[] = []

  // Contract generated
  if (contract.generation_status === 'generated' || contract.generation_status === 'validated') {
    events.push({
      timestamp: contract.created_at,
      label: 'Kontrakt genererat',
      actor: 'System'
    })
  }

  // Agreement created (approximate from created_at + 1 minute)
  events.push({
    timestamp: new Date(contract.created_at.getTime() + 60000),
    label: 'Överenskommelse skapad (Zigned)',
    actor: 'System'
  })

  // Emails sent
  if (contract.email_status === 'sent') {
    events.push({
      timestamp: new Date(contract.created_at.getTime() + 120000),
      label: 'E-post skickad',
      actor: 'System'
    })
  }

  // Landlord signed
  if (contract.landlord_signed) {
    events.push({
      timestamp: contract.updated_at,
      label: 'Hyresvärd signerade',
      actor: 'Fredrik Brännström'
    })
  }

  // Tenant signed
  if (contract.tenant_signed) {
    events.push({
      timestamp: contract.updated_at,
      label: 'Hyresgäst signerade',
      actor: 'Hyresgäst'
    })
  }

  // Contract fulfilled
  if (contract.status === 'completed') {
    events.push({
      timestamp: new Date(contract.updated_at.getTime() + 60000),
      label: 'Kontrakt komplett',
      actor: 'System'
    })
  }

  // Sort by timestamp
  events.sort((a, b) => a.timestamp.getTime() - b.timestamp.getTime())

  return (
    <div className="space-y-3">
      {events.map((event, index) => (
        <div key={index} className="flex gap-3 text-sm">
          <div className="flex flex-col items-center">
            <div className="w-2 h-2 rounded-full bg-purple-500 mt-1.5 shrink-0" />
            {index < events.length - 1 && (
              <div className="w-px flex-1 bg-purple-500/30 mt-1" style={{ minHeight: '20px' }} />
            )}
          </div>
          <div className="flex-1 pb-3">
            <p className="text-purple-100">
              {event.timestamp.toLocaleString('sv-SE', {
                month: 'long',
                day: 'numeric',
                hour: '2-digit',
                minute: '2-digit'
              })}
              {' '}
              {event.label}
            </p>
            {event.actor && (
              <p className="text-purple-300/60 text-xs mt-0.5">{event.actor}</p>
            )}
          </div>
        </div>
      ))}
    </div>
  )
}

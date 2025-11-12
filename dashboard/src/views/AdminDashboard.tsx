// Admin Dashboard - Contract Management View
// Matches existing dashboard Widget component pattern with purple/slate glass-morphism
import React, { useState, useEffect } from 'react'
import { CheckCircle2, Clock, XCircle, Ban, AlertTriangle, UserCheck } from 'lucide-react'
import { ContractList } from '../components/admin/ContractList'
import { useContracts } from '../hooks/useContracts'
import { useKeyboardNav } from '../hooks/useKeyboardNav'

// TypeScript interfaces matching requirements
export interface SignedContract {
  id: string                    // UUID
  tenant_id: string            // Foreign key to tenant
  tenant_name: string          // Tenant full name
  tenant_start_date?: Date     // Move-in date
  tenant_departure_date?: Date // Move-out date (nullable)
  case_id: string              // Zigned agreement ID
  pdf_url: string              // Generated PDF path
  status: 'pending' | 'landlord_signed' | 'tenant_signed' | 'completed' | 'expired' | 'cancelled' | 'failed'
  landlord_signed: boolean
  tenant_signed: boolean
  landlord_signing_url: string
  tenant_signing_url: string
  test_mode: boolean
  expires_at: Date
  created_at: Date
  updated_at: Date

  // Webhook lifecycle tracking
  generation_status?: 'draft' | 'generated' | 'validated' | 'failed'
  email_status?: 'pending' | 'sent' | 'bounced' | 'failed'
  error_message?: string
}

export interface ContractParticipant {
  id: string
  contract_id: string
  participant_type: 'landlord' | 'tenant'
  name: string
  email: string
  status: 'pending' | 'signed' | 'rejected'
  email_delivered: boolean
  email_delivered_at?: Date
  signed_at?: Date
}

// Widget component matching App.tsx pattern
const Widget = ({
  children,
  title,
  className = "",
  accent = false,
  horsemenFont = false
}: {
  children: React.ReactNode,
  title?: string,
  className?: string,
  accent?: boolean,
  horsemenFont?: boolean
}) => {
  return (
    <div
      className={`overflow-hidden backdrop-blur-sm ${accent ? 'bg-purple-900/30' : 'bg-slate-900/40'}
      rounded-2xl shadow-md border border-purple-900/10 ${className}`}
    >
      <div className="p-8">
        {title && (
          <h3 className={`text-2xl font-medium ${accent ? 'text-purple-200' : 'text-purple-100'}
          mb-6 tracking-wide uppercase ${horsemenFont ? 'font-[Horsemen]' : ''}`}>
            {title}
          </h3>
        )}
        <div>{children}</div>
      </div>
    </div>
  )
}

export const AdminDashboard: React.FC = () => {
  const { contracts, loading, error, refreshContracts } = useContracts()
  const [filterActive, setFilterActive] = useState(false)

  // Filter contracts based on active toggle
  const displayContracts = filterActive
    ? contracts.filter(c => c.status === 'pending' || c.status === 'landlord_signed' || c.status === 'tenant_signed')
    : contracts

  // WebSocket updates for real-time contract status changes
  useEffect(() => {
    const ws = new WebSocket('ws://localhost:3001')

    ws.onmessage = (event) => {
      const data = JSON.parse(event.data)

      if (data.type === 'zigned_webhook_event') {
        // Update contract status in real-time
        refreshContracts()
      }

      if (data.type === 'contract_list_changed') {
        // Refresh contract list
        refreshContracts()
      }
    }

    return () => ws.close()
  }, [refreshContracts])

  if (loading) {
    return (
      <Widget title="Kontrakt" horsemenFont={true} accent={true}>
        <div className="text-purple-200">Laddar kontrakt...</div>
      </Widget>
    )
  }

  if (error) {
    return (
      <Widget title="Kontrakt" horsemenFont={true} accent={true}>
        <div className="text-red-400">Fel vid laddning: {error}</div>
      </Widget>
    )
  }

  return (
    <Widget title="Kontrakt" horsemenFont={true} accent={true}>
      <ContractList
        contracts={displayContracts}
        filterActive={filterActive}
        onFilterToggle={() => setFilterActive(!filterActive)}
      />
    </Widget>
  )
}

// Admin Dashboard - Contract Management View
// Matches existing dashboard Widget component pattern with purple/slate glass-morphism
import React from 'react'
import { CheckCircle2, Clock, XCircle, Ban, AlertTriangle, UserCheck, Wifi, WifiOff } from 'lucide-react'
import { ContractList } from '../components/admin/ContractList'
import { TenantForm } from '../components/admin/TenantForm'
import { useContracts } from '../hooks/useContracts'
import { useKeyboardNav } from '../hooks/useKeyboardNav'
import { useData } from '../context/DataContext'

// TypeScript interfaces matching requirements
export interface SignedContract {
  type: 'contract'
  id: string                    // UUID
  tenant_id: string            // Foreign key to tenant
  tenant_name: string          // Tenant full name
  tenant_email?: string        // Tenant email
  tenant_personnummer?: string // Tenant personnummer for landlord detection
  tenant_room?: string         // Room assignment
  tenant_room_adjustment?: number // Room adjustment in kr
  tenant_start_date?: Date     // Move-in date
  tenant_departure_date?: Date // Move-out date (nullable)
  current_rent?: number        // Current rent for tenant
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

  // Participant tracking
  participants?: Array<{
    id: string
    name: string
    email: string
    role: string
    status: string
    signed_at?: string
    signing_url?: string
    email_delivered: boolean
    email_delivered_at?: string
  }>
}

export interface TenantMember {
  type: 'tenant'
  id: string
  tenant_id: string
  tenant_name: string
  tenant_email?: string
  tenant_room?: string
  tenant_room_adjustment?: number
  tenant_start_date?: Date
  tenant_departure_date?: Date
  current_rent?: number
  status: string
  created_at: Date
}

export type Member = SignedContract | TenantMember

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
  const { state } = useData()
  const { contracts, loading, error } = useContracts()
  // Track connection status for UI feedback
  const isConnected = state.connectionStatus === 'open'
  const isReconnecting = state.connectionStatus === 'connecting'

  // Filter contracts based on active toggle
  const displayContracts = contracts

  // Real-time updates via DataContext - no separate WebSocket needed
  // Backend handlers call DataBroadcaster.broadcast_contract_list_changed which sends fresh data

  if (loading) {
    return (
      <Widget title="Medlemmar" horsemenFont={true} accent={true}>
        <div className="text-purple-200">Laddar medlemmar...</div>
      </Widget>
    )
  }

  if (error) {
    return (
      <Widget title="Medlemmar" horsemenFont={true} accent={true}>
        <div className="text-red-400">Fel vid laddning: {error}</div>
      </Widget>
    )
  }

  return (
    <>
      {/* Connection Status Indicator */}
      {!isConnected && (
        <div className={`
          mb-4 p-3 rounded-lg flex items-center gap-3 text-sm font-medium
          ${isReconnecting
            ? 'bg-yellow-900/30 border border-yellow-500/30 text-yellow-200'
            : 'bg-red-900/30 border border-red-500/30 text-red-200'
          }
        `}>
          {isReconnecting ? (
            <>
              <Wifi className="w-4 h-4 animate-pulse" />
              <span>Återansluter till servern...</span>
            </>
          ) : (
            <>
              <WifiOff className="w-4 h-4" />
              <span>Anslutning till servern förlorad. Real-tidsuppdateringar pausade.</span>
            </>
          )}
        </div>
      )}

      <Widget title="Medlemmar" horsemenFont={true} accent={true}>
        <ContractList contracts={displayContracts} />
      </Widget>

      {/* Tenant creation form - darker style matching electricity anomaly widget */}
      <div className="mt-6 backdrop-blur-sm bg-purple-900/15 rounded-2xl shadow-md border border-purple-900/10 p-8">
        <TenantForm />
      </div>
    </>
  )
}

// useContracts - Contract data from centralized DataContext (WebSocket updates)
import { useMemo } from 'react'
import { useData } from '../context/DataContext'
import type { Member } from '../views/AdminDashboard'

export const useContracts = () => {
  const { state } = useData()
  const adminData = state.adminContractsData

  // Parse date strings to Date objects for members (contracts + tenants)
  const contracts = useMemo(() => {
    if (!adminData || !adminData.members) return []

    return adminData.members.map((m: any) => ({
      ...m,
      // Parse all date fields (only present on contracts, not tenant-only members)
      expires_at: m.expires_at ? new Date(m.expires_at) : undefined,
      created_at: m.created_at ? new Date(m.created_at) : undefined,
      updated_at: m.updated_at ? new Date(m.updated_at) : undefined,
      landlord_signed_at: m.landlord_signed_at ? new Date(m.landlord_signed_at) : undefined,
      tenant_signed_at: m.tenant_signed_at ? new Date(m.tenant_signed_at) : undefined,
      completed_at: m.completed_at ? new Date(m.completed_at) : undefined,
      tenant_start_date: m.tenant_start_date ? new Date(m.tenant_start_date) : undefined,
      tenant_departure_date: m.tenant_departure_date ? new Date(m.tenant_departure_date) : undefined
    })) as Member[]
  }, [adminData])

  // Loading state: true until we receive first data
  const loading = adminData === null

  // Error state: could be expanded to handle WebSocket connection errors
  const error = null

  return {
    contracts,
    loading,
    error
  }
}

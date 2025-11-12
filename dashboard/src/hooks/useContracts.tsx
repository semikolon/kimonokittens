// useContracts - Contract data fetching with WebSocket updates
import { useState, useEffect, useCallback } from 'react'
import { useData } from '../context/DataContext'
import type { SignedContract } from '../views/AdminDashboard'

export const useContracts = () => {
  const [contracts, setContracts] = useState<SignedContract[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const { state } = useData()

  const fetchContracts = useCallback(async () => {
    try {
      setLoading(true)
      setError(null)

      const response = await fetch('/api/admin/contracts')
      if (!response.ok) {
        throw new Error(`HTTP ${response.status}: ${response.statusText}`)
      }

      const data = await response.json()

      // Parse date strings to Date objects for members (contracts + tenants)
      const membersWithDates = (data.members || []).map((m: any) => ({
        ...m,
        expires_at: m.expires_at ? new Date(m.expires_at) : null,
        created_at: m.created_at ? new Date(m.created_at) : null,
        updated_at: m.updated_at ? new Date(m.updated_at) : null,
        landlord_signed_at: m.landlord_signed_at ? new Date(m.landlord_signed_at) : null,
        tenant_signed_at: m.tenant_signed_at ? new Date(m.tenant_signed_at) : null,
        completed_at: m.completed_at ? new Date(m.completed_at) : null,
        tenant_start_date: m.tenant_start_date ? new Date(m.tenant_start_date) : null,
        tenant_departure_date: m.tenant_departure_date ? new Date(m.tenant_departure_date) : null
      }))

      setContracts(membersWithDates)
    } catch (err) {
      console.error('Failed to fetch contracts:', err)
      setError(err instanceof Error ? err.message : 'Failed to fetch contracts')
    } finally {
      setLoading(false)
    }
  }, [])

  const refreshContracts = useCallback(() => {
    fetchContracts()
  }, [fetchContracts])

  // Initial fetch
  useEffect(() => {
    fetchContracts()
  }, [fetchContracts])

  // Subscribe to WebSocket contract updates
  // Note: The DataContext handles all WebSocket messages, but we don't have
  // a specific contract_update type in the state yet. This will need to be
  // added when webhook integration is complete. For now, we rely on manual refresh.
  useEffect(() => {
    // TODO: Add contract_update handling to DataContext state
    // For now, manual refreshContracts() will be called by admin UI
  }, [state, refreshContracts])

  return {
    contracts,
    loading,
    error,
    refreshContracts
  }
}

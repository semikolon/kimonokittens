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

      // Parse date strings to Date objects
      const contractsWithDates = (data.contracts || []).map((c: any) => ({
        ...c,
        expires_at: c.expires_at ? new Date(c.expires_at) : null,
        created_at: new Date(c.created_at),
        updated_at: new Date(c.updated_at),
        landlord_signed_at: c.landlord_signed_at ? new Date(c.landlord_signed_at) : null,
        tenant_signed_at: c.tenant_signed_at ? new Date(c.tenant_signed_at) : null,
        completed_at: c.completed_at ? new Date(c.completed_at) : null,
        tenant_start_date: c.tenant_start_date ? new Date(c.tenant_start_date) : null,
        tenant_departure_date: c.tenant_departure_date ? new Date(c.tenant_departure_date) : null
      }))

      setContracts(contractsWithDates)
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

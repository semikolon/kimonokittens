// useContracts - Contract data fetching with WebSocket updates
import { useState, useEffect, useCallback, useContext } from 'react'
import { DataContext } from '../context/DataContext'
import type { SignedContract } from '../views/AdminDashboard'

export const useContracts = () => {
  const [contracts, setContracts] = useState<SignedContract[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const dataContext = useContext(DataContext)

  const fetchContracts = useCallback(async () => {
    try {
      setLoading(true)
      setError(null)

      const response = await fetch('/api/admin/contracts')
      if (!response.ok) {
        throw new Error(`HTTP ${response.status}: ${response.statusText}`)
      }

      const data = await response.json()
      setContracts(data.contracts || [])
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
  useEffect(() => {
    if (!dataContext?.data) return

    const wsData = dataContext.data

    // Listen for contract_update events from webhook handler
    if (wsData.type === 'contract_update') {
      console.log('Contract update received:', wsData.payload)
      // Refresh contract list when any contract changes
      refreshContracts()
    }
  }, [dataContext?.data, refreshContracts])

  return {
    contracts,
    loading,
    error,
    refreshContracts
  }
}

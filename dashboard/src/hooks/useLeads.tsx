// useLeads - Tenant leads data from centralized DataContext (WebSocket updates)
import { useMemo } from 'react'
import { useData } from '../context/DataContext'
import type { TenantLead } from '../context/DataContext'

export const useLeads = () => {
  const { state } = useData()
  const leadsData = state.adminLeadsData

  // Parse date strings to Date objects for leads
  const leads = useMemo(() => {
    if (!leadsData || !leadsData.leads) return []

    return leadsData.leads.map((lead: any) => ({
      ...lead,
      // Keep dates as strings for display - no Date parsing needed
    })) as TenantLead[]
  }, [leadsData])

  // Loading state: true until we receive first data
  const loading = leadsData === null

  // Error state: could be expanded to handle WebSocket connection errors
  const error = null

  return {
    leads,
    total: leadsData?.total || 0,
    loading,
    error
  }
}

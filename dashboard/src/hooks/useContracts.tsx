// useContracts - Contract data fetching with WebSocket updates
import { useState, useEffect, useCallback } from 'react'
import type { SignedContract } from '../views/AdminDashboard'

// Sample contracts for development (matching requirements example data)
const sampleContracts: SignedContract[] = [
  {
    id: 'contract-001',
    tenant_id: 'Sanna Juni Benemar',
    case_id: 'agr_abc123def456',
    pdf_url: '/contracts/generated/Sanna_Benemar_Hyresavtal_2025-11-01.pdf',
    status: 'pending',
    landlord_signed: true,
    tenant_signed: false,
    landlord_signing_url: 'https://app.zigned.se/sign/landlord-abc123',
    tenant_signing_url: 'https://app.zigned.se/sign/tenant-def456',
    test_mode: false,
    expires_at: new Date('2025-12-10'),
    created_at: new Date('2025-11-10T12:34:56Z'),
    updated_at: new Date('2025-11-10T14:22:11Z'),
    generation_status: 'validated',
    email_status: 'sent'
  },
  {
    id: 'contract-002',
    tenant_id: 'Fredrik Brännström',
    case_id: 'agr_test789xyz',
    pdf_url: '/contracts/generated/Test_Tenant_Hyresavtal_2025-11-11.pdf',
    status: 'completed',
    landlord_signed: true,
    tenant_signed: true,
    landlord_signing_url: 'https://app.zigned.se/sign/test-landlord',
    tenant_signing_url: 'https://app.zigned.se/sign/test-tenant',
    test_mode: true,
    expires_at: new Date('2025-12-11'),
    created_at: new Date('2025-11-11T09:15:00Z'),
    updated_at: new Date('2025-11-11T10:30:00Z'),
    generation_status: 'validated',
    email_status: 'sent'
  },
  {
    id: 'contract-003',
    tenant_id: 'Adam Nilsson',
    case_id: 'agr_failed123',
    pdf_url: '',
    status: 'failed',
    landlord_signed: false,
    tenant_signed: false,
    landlord_signing_url: '',
    tenant_signing_url: '',
    test_mode: false,
    expires_at: new Date('2025-12-09'),
    created_at: new Date('2025-11-09T16:45:00Z'),
    updated_at: new Date('2025-11-09T16:45:30Z'),
    generation_status: 'failed',
    email_status: 'pending',
    error_message: 'PDF generation timeout: Failed to render contract template'
  }
]

export const useContracts = () => {
  const [contracts, setContracts] = useState<SignedContract[]>(sampleContracts)
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)

  const fetchContracts = useCallback(async () => {
    try {
      setLoading(true)
      setError(null)

      // TODO: Replace with actual API call when backend is ready
      // const response = await fetch('/api/admin/contracts')
      // const data = await response.json()
      // setContracts(data.contracts)

      // For now, use sample data
      setContracts(sampleContracts)
    } catch (err) {
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

  return {
    contracts,
    loading,
    error,
    refreshContracts
  }
}

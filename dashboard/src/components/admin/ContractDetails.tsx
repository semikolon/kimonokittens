// ContractDetails - Expanded content area (email, signing, timeline)
import React, { useState } from 'react'
import { CheckCircle2, Clock, XCircle, Mail, AlertCircle } from 'lucide-react'
import { ContractTimeline } from './ContractTimeline'
import type { SignedContract } from '../../views/AdminDashboard'
import { useAdminAuth } from '../../contexts/AdminAuthContext'

interface ContractDetailsProps {
  contract: SignedContract
}

export const ContractDetails: React.FC<ContractDetailsProps> = ({ contract }) => {
  const daysLeft = Math.ceil((new Date(contract.expires_at).getTime() - Date.now()) / (1000 * 60 * 60 * 24))

  // If tenant IS the landlord (match on personnummer), landlord signature is implicit/automatic
  const landlordPersonnummer = contract.landlord_personnummer?.replace(/\D/g, '')
  const tenantPersonnummer = contract.tenant_personnummer?.replace(/\D/g, '')
  const isLandlord = Boolean(landlordPersonnummer && tenantPersonnummer === landlordPersonnummer)
  const landlordSigned = isLandlord || contract.landlord_signed
  const landlordName = contract.landlord_name || 'Hyresvärd'

  // State for button actions
  const [resendingEmail, setResendingEmail] = useState(false)
  const [cancelling, setCancelling] = useState(false)
  const [showCancelConfirm, setShowCancelConfirm] = useState(false)
  const [toast, setToast] = useState<{ message: string; type: 'success' | 'error' } | null>(null)
  const { ensureAuth } = useAdminAuth()

  // Button disabled logic based on contract status
  const canResendEmail = contract.status !== 'completed' && contract.status !== 'cancelled' && contract.status !== 'expired'
  const canCancel = contract.status !== 'completed' && contract.status !== 'cancelled'
  const canCopyLinks = contract.status !== 'cancelled' // Links may still work for completed contracts

  // Show toast notification
  const showToast = (message: string, type: 'success' | 'error') => {
    setToast({ message, type })
    setTimeout(() => setToast(null), 3000)
  }

  // Resend email handler
  const handleResendEmail = async () => {
    try {
      const adminToken = await ensureAuth()
      if (!adminToken) {
        return
      }

      setResendingEmail(true)
      const response = await fetch(`/api/admin/contracts/${contract.id}/resend-email`, {
        method: 'POST',
        headers: {
          'X-Admin-Token': adminToken
        }
      })
      const data = await response.json()

      if (response.ok) {
        showToast('Påminnelse skickad!', 'success')
      } else {
        showToast(data.error || 'Kunde inte skicka påminnelse', 'error')
      }
    } catch (error) {
      showToast('Fel vid skickande av påminnelse', 'error')
    } finally {
      setResendingEmail(false)
    }
  }

  // Cancel contract handler
  const handleCancel = async () => {
    try {
      const adminToken = await ensureAuth()
      if (!adminToken) {
        return
      }

      setCancelling(true)
      const response = await fetch(`/api/admin/contracts/${contract.id}/cancel`, {
        method: 'POST',
        headers: {
          'X-Admin-Token': adminToken
        }
      })
      const data = await response.json()

      if (response.ok) {
        showToast('Kontrakt avbrutet!', 'success')
        setShowCancelConfirm(false)
        // WebSocket broadcast from backend will update UI automatically
        // (DataBroadcaster.broadcast_contract_list_changed called after DB update)
      } else {
        showToast(data.error || 'Kunde inte avbryta kontrakt', 'error')
      }
    } catch (error) {
      showToast('Fel vid avbrytande av kontrakt', 'error')
    } finally {
      setCancelling(false)
    }
  }

  // Copy links to clipboard
  const handleCopyLinks = async () => {
    const text = `Hyresvärd: ${contract.landlord_signing_url}\nHyresgäst: ${contract.tenant_signing_url}`

    try {
      await navigator.clipboard.writeText(text)
      showToast('Kopierat!', 'success')
    } catch (error) {
      showToast('Kunde inte kopiera', 'error')
    }
  }

  return (
    <div className="p-6 space-y-6">
      {/* Email Status Section */}
      <div>
        <h4 className="text-sm font-semibold text-purple-200 mb-3">E-poststatus:</h4>
        <div className="space-y-2 text-sm">
          <div className="flex items-center gap-2">
            {contract.email_status === 'sent' ? (
              <>
                <CheckCircle2 className="w-4 h-4 text-green-400" />
                <span className="text-purple-100">
                  Hyresvärd: Levererad ({new Date(contract.created_at).toLocaleString('sv-SE', {
                    month: 'long',
                    day: 'numeric',
                    hour: '2-digit',
                    minute: '2-digit'
                  })})
                </span>
              </>
            ) : (
              <>
                <Clock className="w-4 h-4 text-yellow-400" />
                <span className="text-purple-200">Hyresvärd: Väntar</span>
              </>
            )}
          </div>
          <div className="flex items-center gap-2">
            {contract.email_status === 'sent' ? (
              <>
                <CheckCircle2 className="w-4 h-4 text-green-400" />
                <span className="text-purple-100">
                  Hyresgäst: Levererad ({new Date(contract.created_at).toLocaleString('sv-SE', {
                    month: 'long',
                    day: 'numeric',
                    hour: '2-digit',
                    minute: '2-digit'
                  })})
                </span>
              </>
            ) : (
              <>
                <Clock className="w-4 h-4 text-yellow-400" />
                <span className="text-purple-200">Hyresgäst: Väntar</span>
              </>
            )}
          </div>
        </div>
      </div>

      {/* Signing Status Section */}
      <div>
        <h4 className="text-sm font-semibold text-purple-200 mb-3">Signeringsstatus:</h4>
        <div className="space-y-2 text-sm">
          <div className="flex items-center gap-2">
            {landlordSigned ? (
              <>
                <CheckCircle2 className="w-4 h-4 text-cyan-400" />
                <span className="text-purple-100">
                  {landlordName} - Signerad {isLandlord ? '(automatisk)' : `(${new Date(contract.updated_at).toLocaleString('sv-SE', {
                    month: 'long',
                    day: 'numeric',
                    hour: '2-digit',
                    minute: '2-digit'
                  })})`}
                </span>
              </>
            ) : (
              <>
                <Clock className="w-4 h-4 text-yellow-400" />
                <span className="text-purple-200">{landlordName} - Väntar ({daysLeft} dagar kvar)</span>
              </>
            )}
          </div>
          <div className="flex items-center gap-2">
            {contract.tenant_signed ? (
              <>
                <CheckCircle2 className="w-4 h-4 text-cyan-400" />
                <span className="text-purple-100">
                  Hyresgäst - Signerad ({new Date(contract.updated_at).toLocaleString('sv-SE', {
                    month: 'long',
                    day: 'numeric',
                    hour: '2-digit',
                    minute: '2-digit'
                  })})
                </span>
              </>
            ) : (
              <>
                <Clock className="w-4 h-4 text-yellow-400" />
                <span className="text-purple-200">Hyresgäst - Väntar ({daysLeft} dagar kvar)</span>
              </>
            )}
          </div>
        </div>
      </div>

      {/* Timeline Section */}
      {contract.status !== 'completed' && (
        <div>
          <h4 className="text-sm font-semibold text-purple-200 mb-3">Tidslinje:</h4>
          <ContractTimeline contract={contract} />
        </div>
      )}

      {/* Action Buttons */}
      <div className="flex gap-3 pt-2">
        {contract.pdf_url && (
          <button
            onClick={() => window.open(`/api/contracts/${contract.id}/pdf`, '_blank')}
            className="px-4 py-2 bg-[#ffaa88] hover:bg-[#ff9977] text-slate-900 rounded-lg text-sm font-medium transition-colors shadow-sm"
            style={{
              background: 'linear-gradient(135deg, #ffaa88 0%, #ff9977 100%)'
            }}
          >
            Visa PDF
          </button>
        )}
        <button
          onClick={handleResendEmail}
          disabled={!canResendEmail || resendingEmail}
          className="px-4 py-2 text-purple-100 rounded-lg text-sm font-medium transition-colors shadow-sm hover:opacity-90 disabled:opacity-40 disabled:cursor-not-allowed"
          style={{
            background: 'linear-gradient(135deg, #4a2b87 0%, #3d1f70 100%)'
          }}
        >
          {resendingEmail ? 'Skickar...' : 'Skicka igen'}
        </button>
        <button
          onClick={() => setShowCancelConfirm(true)}
          disabled={!canCancel}
          className="px-4 py-2 text-purple-100 rounded-lg text-sm font-medium transition-colors shadow-sm hover:opacity-90 disabled:opacity-40 disabled:cursor-not-allowed"
          style={{
            background: 'linear-gradient(135deg, #4a2b87 0%, #3d1f70 100%)'
          }}
        >
          Avbryt
        </button>
        <button
          onClick={handleCopyLinks}
          disabled={!canCopyLinks}
          className="px-4 py-2 text-purple-100 rounded-lg text-sm font-medium transition-colors shadow-sm hover:opacity-90 disabled:opacity-40 disabled:cursor-not-allowed"
          style={{
            background: 'linear-gradient(135deg, #4a2b87 0%, #3d1f70 100%)'
          }}
        >
          Kopiera länkar
        </button>
      </div>

      {/* Confirmation Dialog for Cancel */}
      {showCancelConfirm && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 backdrop-blur-sm">
          <div className="bg-slate-900 border border-purple-500/30 rounded-lg p-6 max-w-md mx-4 shadow-xl">
            <div className="flex items-center gap-3 mb-4">
              <AlertCircle className="w-6 h-6 text-orange-400" />
              <h3 className="text-lg font-semibold text-purple-100">Är du säker?</h3>
            </div>
            <p className="text-purple-200 mb-6">
              Detta kommer att avbryta kontraktet och kan inte ångras. Signeringslänkar kommer inte längre att fungera.
            </p>
            <div className="flex gap-3 justify-end">
              <button
                onClick={() => setShowCancelConfirm(false)}
                disabled={cancelling}
                className="px-4 py-2 text-purple-100 rounded-lg text-sm font-medium transition-colors shadow-sm hover:opacity-90"
                style={{
                  background: 'linear-gradient(135deg, #4a2b87 0%, #3d1f70 100%)'
                }}
              >
                Nej, behåll
              </button>
              <button
                onClick={handleCancel}
                disabled={cancelling}
                className="px-4 py-2 bg-red-600 hover:bg-red-700 text-white rounded-lg text-sm font-medium transition-colors shadow-sm disabled:opacity-50"
              >
                {cancelling ? 'Avbryter...' : 'Ja, avbryt kontrakt'}
              </button>
            </div>
          </div>
        </div>
      )}

      {/* Toast Notification */}
      {toast && (
        <div className="fixed bottom-4 right-4 z-50 animate-fade-in">
          <div
            className={`
              px-4 py-3 rounded-lg shadow-lg flex items-center gap-2
              ${toast.type === 'success'
                ? 'bg-green-600 text-white'
                : 'bg-red-600 text-white'
              }
            `}
          >
            {toast.type === 'success' ? (
              <CheckCircle2 className="w-5 h-5" />
            ) : (
              <XCircle className="w-5 h-5" />
            )}
            <span className="font-medium">{toast.message}</span>
          </div>
        </div>
      )}
    </div>
  )
}

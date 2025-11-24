// ContractDetails - Expanded content area (email, signing, timeline)
import React, { useState } from 'react'
import { createPortal } from 'react-dom'
import { CheckCircle2, Clock, XCircle, AlertCircle, Signature } from 'lucide-react'
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
        // Build detailed success message showing which methods were used
        const methods = []
        if (data.email_sent) methods.push('E-post')
        if (data.sms_sent) methods.push('SMS')

        const message = methods.length > 0
          ? `Påminnelse skickad via ${methods.join(' och ')}!`
          : 'Påminnelse skickad!'

        showToast(message, 'success')
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
    <div className="p-6">
      {/* Two-column layout: Status left, Timeline right */}
      {contract.status !== 'completed' && (
        <div className="grid grid-cols-2 gap-6 mb-6">
          {/* Left Column: Condensed Status */}
          <div className="space-y-2 text-sm">
            {/* Notifieringar (combined email/SMS status) */}
            <div className="flex items-center gap-2">
            {(() => {
              // Find participants or use fallback logic
              const landlordParticipant = contract.participants?.find(p =>
                p.email === contract.landlord_email
              )
              const tenantParticipant = contract.participants?.find(p =>
                p.email === contract.tenant_email
              )

              // Determine notification methods for each
              const landlordEmail = landlordParticipant?.email_delivered || contract.email_status === 'sent'
              const landlordSMS = landlordParticipant?.sms_delivered || false
              const tenantEmail = tenantParticipant?.email_delivered || contract.email_status === 'sent'
              const tenantSMS = tenantParticipant?.sms_delivered || false

              // Get first names
              const landlordFirstName = landlordName.split(' ')[0]
              const tenantFirstName = contract.tenant_name.split(' ')[0]

              // Build notification text combining email and SMS
              const landlordMethods = []
              if (landlordEmail) landlordMethods.push('email')
              if (landlordSMS) landlordMethods.push('SMS')
              const landlordNotif = landlordMethods.length > 0 ? landlordMethods.join(' och ') : null

              const tenantMethods = []
              if (tenantEmail) tenantMethods.push('email')
              if (tenantSMS) tenantMethods.push('SMS')
              const tenantNotif = tenantMethods.length > 0 ? tenantMethods.join(' och ') : null

              if (!landlordNotif && !tenantNotif) {
                return (
                  <>
                    <Clock className="w-4 h-4 text-yellow-400" />
                    <span className="text-purple-200">Väntar på notifieringar</span>
                  </>
                )
              }

              // Both notified with same method
              if (landlordNotif && tenantNotif && landlordNotif === tenantNotif) {
                return (
                  <>
                    <CheckCircle2 className="w-4 h-4 text-cyan-400" />
                    <span className="text-purple-100">
                      {landlordFirstName} och {tenantFirstName} har båda fått {tenantNotif}
                    </span>
                  </>
                )
              }

              // One or both notified, show individual statuses
              const parts = []
              if (landlordNotif) parts.push(`${landlordFirstName} har fått ${landlordNotif}`)
              else parts.push(`${landlordFirstName} väntar`)
              if (tenantNotif) parts.push(`${tenantFirstName} har fått ${tenantNotif}`)
              else parts.push(`${tenantFirstName} väntar`)

              const allNotified = landlordNotif && tenantNotif
              return (
                <>
                  {allNotified ? (
                    <CheckCircle2 className="w-4 h-4 text-cyan-400" />
                  ) : (
                    <Clock className="w-4 h-4 text-yellow-400" />
                  )}
                  <span className={allNotified ? "text-purple-100" : "text-purple-200"}>
                    {parts.join(', ')}
                  </span>
                </>
              )
            })()}
          </div>

          {/* Signeringar (combined signing status) */}
          <div className="flex items-center gap-2">
            {(() => {
              const landlordFirstName = landlordName.split(' ')[0]
              const tenantFirstName = contract.tenant_name.split(' ')[0]

              // Both signed
              if (landlordSigned && contract.tenant_signed) {
                return (
                  <>
                    <CheckCircle2 className="w-4 h-4 text-cyan-400" />
                    <span className="text-purple-100">Båda har signerat ✓</span>
                  </>
                )
              }

              // None signed
              if (!landlordSigned && !contract.tenant_signed) {
                return (
                  <>
                    <Clock className="w-4 h-4 text-yellow-400" />
                    <span className="text-purple-200">
                      Ingen har signerat än ({daysLeft} dagar kvar)
                    </span>
                  </>
                )
              }

              // One signed (partial)
              const signedName = landlordSigned ? landlordFirstName : tenantFirstName
              const unsignedName = landlordSigned ? tenantFirstName : landlordFirstName
              return (
                <>
                  <Clock className="w-4 h-4 text-yellow-400" />
                  <span className="text-purple-200">
                    {signedName} har signerat, {unsignedName} inte ({daysLeft} dagar kvar)
                  </span>
                </>
              )
            })()}
          </div>
        </div>

        {/* Right Column: Timeline */}
        <div>
          <h4 className="text-sm font-semibold text-purple-200 mb-3">Tidslinje:</h4>
          <ContractTimeline contract={contract} />
        </div>
      </div>
      )}

      {/* Action Buttons + Signing Status for Completed */}
      <div className={contract.status === 'completed' ? 'flex gap-8 pt-2 items-start' : 'flex gap-3 pt-2'}>
        {contract.pdf_url && (
          <button
            onClick={() => window.open(`/api/contracts/${contract.id}/pdf`, '_blank')}
            className="flex items-center gap-2 px-4 py-2.5 rounded-lg text-sm font-medium text-white transition-all button-cursor-glow button-glow-teal button-hover-brighten"
            style={{
              backgroundImage: 'linear-gradient(180deg, #06b6d4 20%, #0e7490 100%)'
            }}
          >
            <Signature className="w-4 h-4" />
            Visa kontrakt
          </button>
        )}

        {/* Signing status for completed contracts */}
        {contract.status === 'completed' && (
          <div className="text-sm flex items-center gap-2">
            <CheckCircle2 className="w-4 h-4 text-cyan-400" />
            <span className="text-purple-100">Båda har signerat ✓</span>
          </div>
        )}
        {/* Hide extra buttons for completed contracts */}
        {contract.status !== 'completed' && (
          <>
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
          </>
        )}
      </div>

      {/* Confirmation Dialog for Cancel */}
      {showCancelConfirm && createPortal(
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-slate-950/80 backdrop-blur-sm">
          <div className="border border-purple-500/30 rounded-2xl w-full max-w-md mx-4 overflow-hidden" style={{
            backgroundImage: 'linear-gradient(180deg, rgba(41, 22, 64, 0.95) 0%, rgba(30, 14, 50, 0.99) 100%)'
          }}>
            <div className="p-6">
              <div className="flex items-center gap-3 mb-4">
                <AlertCircle className="w-6 h-6 text-orange-400" />
                <h3 className="text-xl font-semibold text-slate-100">Är du säker?</h3>
              </div>
              <p className="text-slate-300 mb-6">
                Detta kommer att avbryta kontraktet och kan inte ångras. Signeringslänkar kommer inte längre att fungera.
              </p>
              <div className="flex gap-3 justify-end">
                <button
                  onClick={() => setShowCancelConfirm(false)}
                  disabled={cancelling}
                  className="px-4 py-2 text-slate-300 hover:text-slate-100 rounded-lg text-sm font-medium transition-colors"
                >
                  Nej, behåll
                </button>
                <button
                  onClick={handleCancel}
                  disabled={cancelling}
                  className="px-4 py-2 bg-red-600 hover:bg-red-700 text-white rounded-lg text-sm font-medium transition-colors disabled:opacity-50"
                >
                  {cancelling ? 'Avbryter...' : 'Ja, avbryt kontrakt'}
                </button>
              </div>
            </div>
          </div>
        </div>,
        document.body
      )}

      {/* Toast Notification */}
      {toast && (
        <div className="fixed bottom-4 right-4 z-50 animate-fade-in">
          <div
            className={`
              px-4 py-3 rounded-lg shadow-lg flex items-center gap-2
              ${toast.type === 'success'
                ? 'bg-cyan-600 text-white'
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

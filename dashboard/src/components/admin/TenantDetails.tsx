// TenantDetails - Expanded content for tenant-only rows
import React, { useMemo, useState } from 'react'
import { DollarSign, TrendingDown, TrendingUp, Calendar, Clock, XCircle, MessageSquare } from 'lucide-react'
import type { TenantMember } from '../../views/AdminDashboard'
import { useAdminAuth } from '../../contexts/AdminAuthContext'
import { useData } from '../../context/DataContext'

interface TenantDetailsProps {
  tenant: TenantMember
  showRent?: boolean
}

export const TenantDetails: React.FC<TenantDetailsProps> = ({ tenant, showRent = true }) => {
  const currentRent = tenant.current_rent || 0
  const roomAdjustment = tenant.tenant_room_adjustment || 0
  const baseDeposit = tenant.tenant_deposit
  const furnishingDeposit = tenant.tenant_furnishing_deposit
  const [isSettingDepartureDate, setIsSettingDepartureDate] = useState(false)
  const [departureDate, setDepartureDate] = useState('')
  const [roomInput, setRoomInput] = useState(tenant.tenant_room || '')
  const [updatingRoom, setUpdatingRoom] = useState(false)
  const [updatingPersonnummer, setUpdatingPersonnummer] = useState(false)
  const [updatingFacebookId, setUpdatingFacebookId] = useState(false)
  const [updatingPhone, setUpdatingPhone] = useState(false)

  // Inline form editing states
  const [editingPersonnummer, setEditingPersonnummer] = useState(false)
  const [personnummerInput, setPersonnummerInput] = useState('')
  const [editingFacebookId, setEditingFacebookId] = useState(false)
  const [facebookIdInput, setFacebookIdInput] = useState('')
  const [editingPhone, setEditingPhone] = useState(false)
  const [phoneInput, setPhoneInput] = useState('')
  const [editingRoom, setEditingRoom] = useState(false)

  const { ensureAuth } = useAdminAuth()
  const { state } = useData()
  const rentData = state.rentData

  const rentClarifications = useMemo(() => {
    const lines: string[] = []
    if (rentData?.data_source?.description_sv) {
      let text = rentData.data_source.description_sv
      if (rentData.electricity_amount && rentData.electricity_month) {
        text += ` - ${rentData.electricity_amount} kr för ${rentData.electricity_month} månads förbrukning`
      }
      lines.push(text)
    }
    return lines
  }, [rentData])

  const formatDeposit = (value?: number | string | null) => {
    if (value === null || value === undefined) return '—'
    const numeric = typeof value === 'string' ? parseFloat(value) : value
    if (!Number.isFinite(numeric)) return '—'
    return `${Math.round(numeric).toLocaleString('sv-SE')} kr`
  }

  const handleSetDepartureDate = async () => {
    if (!departureDate) return

    try {
      const adminToken = await ensureAuth()
      if (!adminToken) {
        return
      }

      const response = await fetch(`/api/admin/contracts/tenants/${tenant.tenant_id}/departure-date`, {
        method: 'PATCH',
        headers: {
          'Content-Type': 'application/json',
          'X-Admin-Token': adminToken
        },
        body: JSON.stringify({ date: departureDate })
      })

      if (!response.ok) {
        const error = await response.json()
        throw new Error(error.error || 'Failed to update departure date')
      }

      const result = await response.json()
      console.log('✅ Departure date updated:', result)

      // Close the form and clear state
      setIsSettingDepartureDate(false)
      setDepartureDate('')

      // UI will auto-refresh via WebSocket broadcast
    } catch (error) {
      console.error('❌ Error setting departure date:', error)
      alert(`Failed to set departure date: ${error instanceof Error ? error.message : 'Unknown error'}`)
    }
  }

  // Obfuscate personnummer - show first 6 digits, hide last 4
  const formatPersonnummer = (pnr?: string) => {
    if (!pnr) return '—'
    // Show first 6 digits (YYMMDD), hide last 4
    if (pnr.length >= 10) {
      const firstSix = pnr.slice(0, 6)
      return `${firstSix}-****`
    }
    return pnr // Fallback for unexpected formats
  }

  const handleSavePersonnummer = async () => {
    const trimmed = personnummerInput.trim()
    if (!trimmed) {
      alert('Personnummer kan inte vara tomt')
      return
    }
    // Basic client-side validation
    const digitsOnly = trimmed.replace(/\D/g, '')
    if (digitsOnly.length !== 10 && digitsOnly.length !== 12) {
      alert('Personnummer måste vara 10 eller 12 siffror (YYMMDD-XXXX eller YYYYMMDD-XXXX)')
      return
    }
    try {
      setUpdatingPersonnummer(true)
      const adminToken = await ensureAuth()
      if (!adminToken) return
      const response = await fetch(`/api/admin/contracts/tenants/${tenant.tenant_id}/personnummer`, {
        method: 'PATCH',
        headers: {
          'Content-Type': 'application/json',
          'X-Admin-Token': adminToken
        },
        body: JSON.stringify({ personnummer: trimmed })
      })
      if (!response.ok) {
        const error = await response.json()
        throw new Error(error.error || 'Kunde inte uppdatera personnummer')
      }
      setEditingPersonnummer(false)
    } catch (error) {
      alert(error instanceof Error ? error.message : 'Kunde inte uppdatera personnummer')
    } finally {
      setUpdatingPersonnummer(false)
    }
  }

  const handleSaveFacebookId = async () => {
    const trimmed = facebookIdInput.trim()
    if (!trimmed) {
      alert('Facebook ID kan inte vara tomt')
      return
    }
    try {
      setUpdatingFacebookId(true)
      const adminToken = await ensureAuth()
      if (!adminToken) return
      const response = await fetch(`/api/admin/contracts/tenants/${tenant.tenant_id}/facebook-id`, {
        method: 'PATCH',
        headers: {
          'Content-Type': 'application/json',
          'X-Admin-Token': adminToken
        },
        body: JSON.stringify({ facebook_id: trimmed })
      })
      if (!response.ok) {
        const error = await response.json()
        throw new Error(error.error || 'Kunde inte uppdatera Facebook ID')
      }
      setEditingFacebookId(false)
    } catch (error) {
      alert(error instanceof Error ? error.message : 'Kunde inte uppdatera Facebook ID')
    } finally {
      setUpdatingFacebookId(false)
    }
  }

  const handleSavePhone = async () => {
    const trimmed = phoneInput.trim()
    if (!trimmed) {
      alert('Telefonnummer kan inte vara tomt')
      return
    }
    try {
      setUpdatingPhone(true)
      const adminToken = await ensureAuth()
      if (!adminToken) return
      const response = await fetch(`/api/admin/contracts/tenants/${tenant.tenant_id}/phone`, {
        method: 'PATCH',
        headers: {
          'Content-Type': 'application/json',
          'X-Admin-Token': adminToken
        },
        body: JSON.stringify({ phone: trimmed })
      })
      if (!response.ok) {
        const error = await response.json()
        throw new Error(error.error || 'Kunde inte uppdatera telefonnummer')
      }
      setEditingPhone(false)
    } catch (error) {
      alert(error instanceof Error ? error.message : 'Kunde inte uppdatera telefonnummer')
    } finally {
      setUpdatingPhone(false)
    }
  }

  const handleSaveRoom = async () => {
    const trimmed = roomInput.trim()
    if (!trimmed) {
      alert('Rumsnamn kan inte vara tomt')
      return
    }
    try {
      setUpdatingRoom(true)
      const adminToken = await ensureAuth()
      if (!adminToken) return
      const response = await fetch(`/api/admin/contracts/tenants/${tenant.tenant_id}/room`, {
        method: 'PATCH',
        headers: {
          'Content-Type': 'application/json',
          'X-Admin-Token': adminToken
        },
        body: JSON.stringify({ room: trimmed })
      })
      if (!response.ok) {
        const error = await response.json()
        throw new Error(error.error || 'Kunde inte uppdatera rum')
      }
      setEditingRoom(false)
    } catch (error) {
      alert(error instanceof Error ? error.message : 'Kunde inte uppdatera rum')
    } finally {
      setUpdatingRoom(false)
    }
  }

  return (
    <div className="p-6 space-y-6 bg-slate-900/60">
      {/* Room Adjustment */}
      {roomAdjustment !== 0 && (
        <div>
          <h4 className="text-sm font-semibold text-purple-200 mb-3">Rumsjustering:</h4>
          <div className="flex items-center gap-2">
            {roomAdjustment < 0 ? (
              <TrendingDown className="w-5 h-5 text-cyan-400" />
            ) : (
              <TrendingUp className="w-5 h-5 text-red-400" />
            )}
            <span className={`text-lg font-medium ${roomAdjustment < 0 ? 'text-cyan-400' : 'text-red-400'}`}>
              {roomAdjustment > 0 ? '+' : ''}{roomAdjustment} kr/månad
            </span>
            <span className="text-sm text-purple-300/60 ml-2">
              ({roomAdjustment < 0 ? 'rabatt' : 'tillägg'} för rum)
            </span>
          </div>
        </div>
      )}

      {/* Personnummer, Facebook, Phone - 3 column grid */}
      <div className="grid gap-6 md:grid-cols-3">
        {/* Personnummer */}
        <div>
          <h4 className="text-sm font-semibold text-purple-200 mb-3">Personnummer:</h4>
          {tenant.tenant_personnummer ? (
            <div className="text-lg font-mono text-purple-100 mb-2">
              {formatPersonnummer(tenant.tenant_personnummer)}
            </div>
          ) : (
            <div className="text-xs text-yellow-400/80 mb-3">
              ⚠️ Krävs för att skapa avtal
            </div>
          )}
          {!tenant.has_completed_contract && (
            !editingPersonnummer ? (
              <button
                onClick={() => {
                  setPersonnummerInput(tenant.tenant_personnummer || '')
                  setEditingPersonnummer(true)
                }}
                className="flex items-center gap-2 px-4 py-2 rounded-lg text-sm font-medium
                         bg-slate-800/50 hover:bg-slate-700/50 text-purple-200
                         transition-all border border-purple-900/30"
              >
                {tenant.tenant_personnummer ? 'Ändra personnummer' : 'Lägg till personnummer'}
              </button>
            ) : (
              <form onSubmit={(e) => { e.preventDefault(); handleSavePersonnummer(); }} className="flex items-center gap-2">
                <input
                  type="text"
                  value={personnummerInput}
                  onChange={(e) => setPersonnummerInput(e.target.value)}
                  placeholder="YYYYMMDD-XXXX"
                  autoFocus
                  className="px-3 py-2 rounded-lg bg-slate-950/60 border border-purple-900/40 text-purple-100 text-sm placeholder-purple-400/40 focus:outline-none focus:border-purple-400 focus:ring-2 focus:ring-purple-500/30"
                />
                <button
                  type="submit"
                  disabled={updatingPersonnummer}
                  className="px-4 py-2 rounded-lg text-sm font-medium bg-cyan-600 hover:bg-cyan-700 text-white disabled:opacity-50 disabled:cursor-not-allowed transition-all"
                >
                  {updatingPersonnummer ? 'Sparar…' : 'Spara'}
                </button>
                <button
                  type="button"
                  onClick={() => setEditingPersonnummer(false)}
                  disabled={updatingPersonnummer}
                  className="px-4 py-2 rounded-lg text-sm font-medium bg-slate-800/50 hover:bg-slate-700/50 text-purple-200 transition-all"
                >
                  Avbryt
                </button>
              </form>
            )
          )}
          {tenant.has_completed_contract && tenant.tenant_personnummer && (
            <div className="text-xs text-purple-300/60 mt-1">
              🔒 Personnummer kan inte ändras efter signerat kontrakt
            </div>
          )}
        </div>

        {/* Facebook ID */}
        <div>
          <h4 className="text-sm font-semibold text-purple-200 mb-3">Facebook:</h4>
          {tenant.tenant_facebook_id && !editingFacebookId && (
            <a
              href={`https://facebook.com/${tenant.tenant_facebook_id}`}
              target="_blank"
              rel="noopener noreferrer"
              className="text-lg text-cyan-400 hover:text-cyan-300 underline mb-2 block"
            >
              facebook.com/{tenant.tenant_facebook_id}
            </a>
          )}
          {!editingFacebookId ? (
            <button
              onClick={() => {
                setFacebookIdInput(tenant.tenant_facebook_id || '')
                setEditingFacebookId(true)
              }}
              className="flex items-center gap-2 px-4 py-2 rounded-lg text-sm font-medium
                       bg-slate-800/50 hover:bg-slate-700/50 text-purple-200
                       transition-all border border-purple-900/30"
            >
              {tenant.tenant_facebook_id ? 'Ändra Facebook ID' : 'Lägg till Facebook ID'}
            </button>
          ) : (
            <form onSubmit={(e) => { e.preventDefault(); handleSaveFacebookId(); }} className="flex items-center gap-2">
              <input
                type="text"
                value={facebookIdInput}
                onChange={(e) => setFacebookIdInput(e.target.value)}
                placeholder="john.doe"
                autoFocus
                className="px-3 py-2 rounded-lg bg-slate-950/60 border border-purple-900/40 text-purple-100 text-sm placeholder-purple-400/40 focus:outline-none focus:border-purple-400 focus:ring-2 focus:ring-purple-500/30"
              />
              <button
                type="submit"
                disabled={updatingFacebookId}
                className="px-4 py-2 rounded-lg text-sm font-medium bg-cyan-600 hover:bg-cyan-700 text-white disabled:opacity-50 disabled:cursor-not-allowed transition-all"
              >
                {updatingFacebookId ? 'Sparar…' : 'Spara'}
              </button>
              <button
                type="button"
                onClick={() => setEditingFacebookId(false)}
                disabled={updatingFacebookId}
                className="px-4 py-2 rounded-lg text-sm font-medium bg-slate-800/50 hover:bg-slate-700/50 text-purple-200 transition-all"
              >
                Avbryt
              </button>
            </form>
          )}
        </div>

        {/* Phone Number */}
        <div>
          <h4 className="text-sm font-semibold text-purple-200 mb-3">Telefon:</h4>
          {tenant.tenant_phone && !editingPhone && (
            <div className="text-lg font-mono text-purple-100 mb-2">
              {tenant.tenant_phone}
            </div>
          )}
          {!editingPhone ? (
            <button
              onClick={() => {
                setPhoneInput(tenant.tenant_phone || '')
                setEditingPhone(true)
              }}
              className="flex items-center gap-2 px-4 py-2 rounded-lg text-sm font-medium
                       bg-slate-800/50 hover:bg-slate-700/50 text-purple-200
                       transition-all border border-purple-900/30"
            >
              {tenant.tenant_phone ? 'Ändra telefonnummer' : 'Lägg till telefonnummer'}
            </button>
          ) : (
            <form onSubmit={(e) => { e.preventDefault(); handleSavePhone(); }} className="flex items-center gap-2">
              <input
                type="tel"
                value={phoneInput}
                onChange={(e) => setPhoneInput(e.target.value)}
                placeholder="+46701234567"
                autoFocus
                className="px-3 py-2 rounded-lg bg-slate-950/60 border border-purple-900/40 text-purple-100 text-sm placeholder-purple-400/40 focus:outline-none focus:border-purple-400 focus:ring-2 focus:ring-purple-500/30"
              />
              <button
                type="submit"
                disabled={updatingPhone}
                className="px-4 py-2 rounded-lg text-sm font-medium bg-cyan-600 hover:bg-cyan-700 text-white disabled:opacity-50 disabled:cursor-not-allowed transition-all"
              >
                {updatingPhone ? 'Sparar…' : 'Spara'}
              </button>
              <button
                type="button"
                onClick={() => setEditingPhone(false)}
                disabled={updatingPhone}
                className="px-4 py-2 rounded-lg text-sm font-medium bg-slate-800/50 hover:bg-slate-700/50 text-purple-200 transition-all"
              >
                Avbryt
              </button>
            </form>
          )}
        </div>
      </div>

      {showRent && (
        <div className="grid gap-6 md:grid-cols-3 pt-6 border-t border-purple-500/10">
          <div>
            <h4 className="text-sm font-semibold text-purple-200 mb-3">Aktuell hyra:</h4>
            <div className="flex items-center gap-3">
              <DollarSign className="w-5 h-5 text-purple-300" />
              <div>
                <div className="text-2xl font-semibold text-purple-100">
                  {currentRent.toLocaleString('sv-SE')} kr
                </div>
                <div className="text-xs text-purple-300/60 mt-1">
                  per månad (inkl. el, internet, avgifter)
                </div>
              </div>
            </div>
          </div>

          <div>
            <h4 className="text-sm font-semibold text-purple-200 mb-3">Depositioner:</h4>
            <div className="space-y-2 text-purple-100">
              <div>
                <div className="text-xs text-purple-300/60 uppercase tracking-wide">Bas</div>
                <div className="text-xl font-semibold">{formatDeposit(baseDeposit)}</div>
              </div>
              <div>
                <div className="text-xs text-purple-300/60 uppercase tracking-wide">Inredning</div>
                <div className="text-xl font-semibold">{formatDeposit(furnishingDeposit)}</div>
              </div>
            </div>
          </div>

          <div className="space-y-5">
            <div>
              <h4 className="text-sm font-semibold text-purple-200 mb-3">Rum:</h4>
              {!editingRoom ? (
                <button
                  onClick={() => setEditingRoom(true)}
                  className="flex items-center gap-2 px-4 py-2 rounded-lg text-sm font-medium
                           bg-slate-800/50 hover:bg-slate-700/50 text-purple-200
                           transition-all border border-purple-900/30"
                >
                  Ändra rum
                </button>
              ) : (
                <form onSubmit={(e) => { e.preventDefault(); handleSaveRoom(); }} className="flex items-center gap-2">
                  <input
                    type="text"
                    value={roomInput}
                    onChange={(e) => setRoomInput(e.target.value)}
                    placeholder="Rum A"
                    autoFocus
                    className="px-3 py-2 rounded-lg bg-slate-950/60 border border-purple-900/40 text-purple-100 text-sm placeholder-purple-400/40 focus:outline-none focus:border-purple-400 focus:ring-2 focus:ring-purple-500/30"
                  />
                  <button
                    type="submit"
                    disabled={updatingRoom}
                    className="px-4 py-2 rounded-lg text-sm font-medium bg-cyan-600 hover:bg-cyan-700 text-white disabled:opacity-50 disabled:cursor-not-allowed transition-all"
                  >
                    {updatingRoom ? 'Sparar…' : 'Spara'}
                  </button>
                  <button
                    type="button"
                    onClick={() => setEditingRoom(false)}
                    disabled={updatingRoom}
                    className="px-4 py-2 rounded-lg text-sm font-medium bg-slate-800/50 hover:bg-slate-700/50 text-purple-200 transition-all"
                  >
                    Avbryt
                  </button>
                </form>
              )}
            </div>

            <div>
              <h4 className="text-sm font-semibold text-purple-200 mb-3">Utflyttningsdatum:</h4>
              {tenant.tenant_departure_date ? (
                <div className="flex items-center gap-3">
                  <Calendar className="w-5 h-5 text-purple-300" />
                  <div className="text-purple-100">
                    {new Date(tenant.tenant_departure_date).toLocaleDateString('sv-SE')}
                  </div>
                </div>
              ) : (
                <>
                  {!isSettingDepartureDate ? (
                    <button
                      onClick={() => setIsSettingDepartureDate(true)}
                      className="flex items-center gap-2 px-4 py-2 rounded-lg text-sm font-medium
                               bg-slate-800/50 hover:bg-slate-700/50 text-purple-200
                               transition-all border border-purple-900/30"
                    >
                      <Calendar className="w-4 h-4" />
                      Sätt utflyttningsdatum
                    </button>
                  ) : (
                    <form onSubmit={(e) => { e.preventDefault(); handleSetDepartureDate(); }} className="flex items-center gap-2">
                      <input
                        type="date"
                        value={departureDate}
                        onChange={(e) => setDepartureDate(e.target.value)}
                        className="px-3 py-2 rounded-lg bg-slate-900 border border-purple-500/30
                                 text-purple-100 text-sm focus:outline-none focus:border-purple-500"
                      />
                      <button
                        type="submit"
                        disabled={!departureDate}
                        className="px-4 py-2 rounded-lg text-sm font-medium
                                 bg-cyan-600 hover:bg-cyan-700 text-white
                                 disabled:opacity-50 disabled:cursor-not-allowed
                                 transition-all"
                      >
                        Spara
                      </button>
                      <button
                        type="button"
                        onClick={() => {
                          setIsSettingDepartureDate(false)
                          setDepartureDate('')
                        }}
                        className="px-4 py-2 rounded-lg text-sm font-medium
                                 bg-slate-800/50 hover:bg-slate-700/50 text-purple-200
                                 transition-all"
                      >
                        Avbryt
                      </button>
                    </form>
                  )}
                </>
              )}
            </div>
          </div>
        </div>
      )}

      {/* Payment Status Section - shown when:
          1. has_overdue_rent: Previous period rent is unpaid (urgent!)
          2. OR day >= 20 AND current rent unpaid (reminder for upcoming rent)
          Hidden early in month when nothing is actionable */}
      {(tenant.has_overdue_rent || (new Date().getDate() >= 20 && !tenant.rent_paid)) && (
        <>
          <div className="grid gap-6 md:grid-cols-3 pt-6 border-t border-purple-500/10">
            <div>
              <div className="text-xs text-purple-300/60 uppercase tracking-wide mb-1">Betalningsstatus</div>
              <div className="flex items-center gap-2">
                {tenant.has_overdue_rent ? (
                  <>
                    <XCircle className="w-4 h-4 text-red-400" />
                    <span className="text-red-300">Försenad betalning!</span>
                  </>
                ) : tenant.rent_remaining && tenant.rent_remaining > 0 ? (
                  <>
                    <Clock className="w-4 h-4 text-yellow-400" />
                    <span className="text-purple-100">
                      {Math.round(tenant.rent_remaining).toLocaleString('sv-SE')} kr kvar
                    </span>
                  </>
                ) : (
                  <>
                    <XCircle className="w-4 h-4 text-red-400" />
                    <span className="text-purple-100">Obetald</span>
                  </>
                )}
              </div>
            </div>

            <div>
              <div className="text-xs text-purple-300/60 uppercase tracking-wide mb-1">Senaste betalning</div>
              <div className="text-purple-100">
                {tenant.last_payment_date
                  ? new Date(tenant.last_payment_date).toLocaleDateString('sv-SE')
                  : '—'}
              </div>
            </div>

            <div>
              <div className="text-xs text-purple-300/60 uppercase tracking-wide mb-1 flex items-center gap-2">
                <MessageSquare className="w-3 h-3" />
                <span>SMS påminnelser</span>
              </div>
              <div className="text-purple-100">
                {tenant.sms_reminder_count || 0} skickade
              </div>
            </div>
          </div>

          {showRent && rentClarifications.length > 0 && (
            <div className="text-xs text-purple-300/60 pt-4 border-t border-purple-500/10 space-y-1">
              {rentClarifications.map((line, idx) => (
                <div key={idx}>{line}</div>
              ))}
            </div>
          )}
        </>
      )}
    </div>
  )
}

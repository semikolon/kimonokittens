// TenantDetails - Expanded content for tenant-only rows
import React, { useMemo, useState } from 'react'
import { DollarSign, TrendingDown, TrendingUp, Calendar } from 'lucide-react'
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
  const [isSettingDepartureDate, setIsSettingDepartureDate] = useState(false)
  const [departureDate, setDepartureDate] = useState('')
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
    if (rentData?.heating_cost_line) {
      lines.push(rentData.heating_cost_line)
    }
    return lines
  }, [rentData])

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

      {showRent && (
        <div className="grid gap-6 md:grid-cols-3">
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
                <div className="text-xl font-semibold">{tenant.tenant_deposit ? `${tenant.tenant_deposit.toLocaleString('sv-SE')} kr` : '—'}</div>
              </div>
              <div>
                <div className="text-xs text-purple-300/60 uppercase tracking-wide">Inredning</div>
                <div className="text-xl font-semibold">{tenant.tenant_furnishing_deposit ? `${tenant.tenant_furnishing_deposit.toLocaleString('sv-SE')} kr` : '—'}</div>
              </div>
            </div>
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
                  <div className="flex items-center gap-2">
                    <input
                      type="date"
                      value={departureDate}
                      onChange={(e) => setDepartureDate(e.target.value)}
                      className="px-3 py-2 rounded-lg bg-slate-900 border border-purple-500/30
                               text-purple-100 text-sm focus:outline-none focus:border-purple-500"
                    />
                    <button
                      onClick={handleSetDepartureDate}
                      disabled={!departureDate}
                      className="px-4 py-2 rounded-lg text-sm font-medium
                               bg-cyan-600 hover:bg-cyan-700 text-white
                               disabled:opacity-50 disabled:cursor-not-allowed
                               transition-all"
                    >
                      Spara
                    </button>
                    <button
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
                  </div>
                )}
              </>
            )}
          </div>
        </div>
      )}

      {showRent && rentClarifications.length > 0 && (
        <div className="text-xs text-purple-300/60 pt-4 border-t border-purple-500/10 space-y-1">
          {rentClarifications.map((line, idx) => (
            <div key={idx}>{line}</div>
          ))}
        </div>
      )}
    </div>
  )
}

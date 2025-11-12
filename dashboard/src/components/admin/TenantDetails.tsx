// TenantDetails - Expanded content for tenant-only rows
import React from 'react'
import { DollarSign, TrendingDown, TrendingUp } from 'lucide-react'
import type { TenantMember } from '../../views/AdminDashboard'

interface TenantDetailsProps {
  tenant: TenantMember
}

export const TenantDetails: React.FC<TenantDetailsProps> = ({ tenant }) => {
  const currentRent = tenant.current_rent || 0
  const roomAdjustment = tenant.tenant_room_adjustment || 0

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

      {/* Current Rent */}
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

      {/* Info note */}
      <div className="text-xs text-purple-300/50 pt-4 border-t border-purple-500/10">
        Hyran beräknas från aktuella elkostnader och delad grundhyra mellan aktiva hyresgäster.
      </div>
    </div>
  )
}

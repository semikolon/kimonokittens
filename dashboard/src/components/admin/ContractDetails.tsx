// ContractDetails - Expanded content area (email, signing, timeline)
import React from 'react'
import { CheckCircle2, Clock, XCircle, Mail } from 'lucide-react'
import { ContractTimeline } from './ContractTimeline'
import type { SignedContract } from '../../views/AdminDashboard'

interface ContractDetailsProps {
  contract: SignedContract
}

export const ContractDetails: React.FC<ContractDetailsProps> = ({ contract }) => {
  const daysLeft = Math.ceil((new Date(contract.expires_at).getTime() - Date.now()) / (1000 * 60 * 60 * 24))

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
            {contract.landlord_signed ? (
              <>
                <CheckCircle2 className="w-4 h-4 text-green-400" />
                <span className="text-purple-100">
                  Fredrik Brännström - Signerad ({new Date(contract.updated_at).toLocaleString('sv-SE', {
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
                <span className="text-purple-200">Fredrik Brännström - Väntar ({daysLeft} dagar kvar)</span>
              </>
            )}
          </div>
          <div className="flex items-center gap-2">
            {contract.tenant_signed ? (
              <>
                <CheckCircle2 className="w-4 h-4 text-green-400" />
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
      <div>
        <h4 className="text-sm font-semibold text-purple-200 mb-3">Tidslinje:</h4>
        <ContractTimeline contract={contract} />
      </div>

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
          className="px-4 py-2 text-purple-100 rounded-lg text-sm font-medium transition-colors shadow-sm hover:opacity-90"
          style={{
            background: 'linear-gradient(135deg, #4a2b87 0%, #3d1f70 100%)'
          }}
        >
          Skicka igen
        </button>
        <button
          className="px-4 py-2 text-purple-100 rounded-lg text-sm font-medium transition-colors shadow-sm hover:opacity-90"
          style={{
            background: 'linear-gradient(135deg, #4a2b87 0%, #3d1f70 100%)'
          }}
        >
          Avbryt
        </button>
        <button
          className="px-4 py-2 text-purple-100 rounded-lg text-sm font-medium transition-colors shadow-sm hover:opacity-90"
          style={{
            background: 'linear-gradient(135deg, #4a2b87 0%, #3d1f70 100%)'
          }}
        >
          Kopiera länkar
        </button>
      </div>
    </div>
  )
}

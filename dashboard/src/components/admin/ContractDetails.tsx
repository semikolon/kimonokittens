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
            onClick={() => window.open(contract.pdf_url, '_blank')}
            className="px-4 py-2 bg-purple-600 hover:bg-purple-700 text-white rounded-lg text-sm font-medium transition-colors"
          >
            Visa PDF
          </button>
        )}
        <button className="px-4 py-2 bg-slate-700/50 hover:bg-slate-600/50 text-purple-200 rounded-lg text-sm font-medium transition-colors">
          Skicka igen
        </button>
        <button className="px-4 py-2 bg-slate-700/50 hover:bg-slate-600/50 text-purple-200 rounded-lg text-sm font-medium transition-colors">
          Avbryt
        </button>
        <button className="px-4 py-2 bg-slate-700/50 hover:bg-slate-600/50 text-purple-200 rounded-lg text-sm font-medium transition-colors">
          Kopiera länkar
        </button>
      </div>
    </div>
  )
}

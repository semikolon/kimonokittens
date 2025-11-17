// LeadRow - Individual tenant lead display with status management
import React from 'react'
import {
  Clock,
  CheckCircle2,
  XCircle,
  UserCheck,
  Mail,
  MessageCircle,
  Phone,
  Calendar,
  ChevronRight,
  Trash2,
  FileText
} from 'lucide-react'
import type { TenantLead } from '../../context/DataContext'
import { useAdminAuth } from '../../contexts/AdminAuthContext'

interface LeadRowProps {
  lead: TenantLead
  isExpanded: boolean
  isSelected: boolean
  onToggle: () => void
  onSelect: () => void
}

// Status icon mapping for leads
const getStatusIcon = (status: TenantLead['status']) => {
  switch (status) {
    case 'pending_review':
      return <Clock className="w-5 h-5 text-yellow-400" />
    case 'contacted':
      return <Mail className="w-5 h-5 text-blue-400" />
    case 'interview_scheduled':
      return <Calendar className="w-5 h-5 text-purple-400" />
    case 'approved':
      return <CheckCircle2 className="w-5 h-5 text-cyan-400" />
    case 'rejected':
      return <XCircle className="w-5 h-5 text-red-400" />
    case 'converted':
      return <UserCheck className="w-5 h-5 text-cyan-400" />
    default:
      return <Clock className="w-5 h-5 text-yellow-400" />
  }
}

// Status badge color
const getStatusColor = (status: TenantLead['status']) => {
  const colors = {
    pending_review: 'bg-yellow-400/20 text-yellow-300 border-yellow-400/30',
    contacted: 'bg-blue-400/20 text-blue-300 border-blue-400/30',
    interview_scheduled: 'bg-purple-400/20 text-purple-300 border-purple-400/30',
    approved: 'bg-cyan-400/20 text-cyan-300 border-cyan-400/30',
    rejected: 'bg-red-400/20 text-red-300 border-red-400/30',
    converted: 'bg-cyan-400/20 text-cyan-300 border-cyan-400/30'
  }
  return colors[status] || colors.pending_review
}

// Status label translation (Swedish)
const getStatusLabel = (status: TenantLead['status']) => {
  const labels = {
    pending_review: 'Väntar granskning',
    contacted: 'Kontaktad',
    interview_scheduled: 'Visning bokad',
    approved: 'Godkänd',
    rejected: 'Avböjd',
    converted: 'Hyresgäst'
  }
  return labels[status] || 'Väntar'
}

// Move-in flexibility label (Swedish)
const getMoveInLabel = (flexibility: string) => {
  const labels: Record<string, string> = {
    immediate: 'Omedelbart',
    '1month': '1 månads uppsägningstid',
    '2months': '2 månaders uppsägningstid',
    '3months': '3 månaders uppsägningstid',
    specific: 'Specifikt datum',
    other: 'Annat'
  }
  return labels[flexibility] || flexibility
}

// Format date for display
const formatDate = (dateString: string): string => {
  const date = new Date(dateString)
  const monthNames = ['jan', 'feb', 'mar', 'apr', 'maj', 'jun', 'jul', 'aug', 'sep', 'okt', 'nov', 'dec']
  const day = date.getDate()
  const month = monthNames[date.getMonth()]
  const year = date.getFullYear()
  return `${day} ${month} ${year}`
}

export const LeadRow: React.FC<LeadRowProps> = ({
  lead,
  isExpanded,
  isSelected,
  onToggle,
  onSelect
}) => {
  const { ensureAuth } = useAdminAuth()
  const [toast, setToast] = React.useState<{ message: string; type: 'success' | 'error' } | null>(null)
  const [updatingStatus, setUpdatingStatus] = React.useState(false)
  const [deleting, setDeleting] = React.useState(false)

  const showToast = (message: string, type: 'success' | 'error') => {
    setToast({ message, type })
    setTimeout(() => setToast(null), 3000)
  }

  const handleStatusChange = async (newStatus: TenantLead['status']) => {
    try {
      const adminToken = await ensureAuth()
      if (!adminToken) return

      setUpdatingStatus(true)
      const response = await fetch(`/api/admin/leads/${lead.id}/status`, {
        method: 'PATCH',
        headers: {
          'Content-Type': 'application/json',
          'X-Admin-Token': adminToken
        },
        body: JSON.stringify({ status: newStatus })
      })

      if (response.ok) {
        showToast('Status uppdaterad!', 'success')
      } else {
        const data = await response.json()
        showToast(data.error || 'Kunde inte uppdatera status', 'error')
      }
    } catch (error) {
      showToast('Fel vid uppdatering av status', 'error')
    } finally {
      setUpdatingStatus(false)
    }
  }

  const handleDelete = async () => {
    if (!window.confirm(`Ta bort anmälan från ${lead.name}?`)) return

    try {
      const adminToken = await ensureAuth()
      if (!adminToken) return

      setDeleting(true)
      const response = await fetch(`/api/admin/leads/${lead.id}`, {
        method: 'DELETE',
        headers: {
          'X-Admin-Token': adminToken
        }
      })

      if (response.ok) {
        showToast('Anmälan borttagen!', 'success')
      } else {
        const data = await response.json()
        showToast(data.error || 'Kunde inte ta bort anmälan', 'error')
      }
    } catch (error) {
      showToast('Fel vid borttagning', 'error')
    } finally {
      setDeleting(false)
    }
  }

  const handleAddNote = async () => {
    const note = window.prompt('Lägg till anteckning:', lead.adminNotes || '')
    if (note === null) return // User cancelled

    try {
      const adminToken = await ensureAuth()
      if (!adminToken) return

      const response = await fetch(`/api/admin/leads/${lead.id}/notes`, {
        method: 'PATCH',
        headers: {
          'Content-Type': 'application/json',
          'X-Admin-Token': adminToken
        },
        body: JSON.stringify({ admin_notes: note })
      })

      if (response.ok) {
        showToast('Anteckning sparad!', 'success')
      } else {
        const data = await response.json()
        showToast(data.error || 'Kunde inte spara anteckning', 'error')
      }
    } catch (error) {
      showToast('Fel vid sparande', 'error')
    }
  }

  const detailsRef = React.useRef<HTMLDivElement>(null)
  const [contentHeight, setContentHeight] = React.useState(0)

  React.useLayoutEffect(() => {
    if (isExpanded && detailsRef.current) {
      setContentHeight(detailsRef.current.scrollHeight)
    }
  }, [isExpanded, lead])

  const detailsStyle: React.CSSProperties = {
    maxHeight: isExpanded ? `${contentHeight}px` : '0px',
    opacity: isExpanded ? 1 : 0,
    overflow: 'hidden'
  }

  // Contact info display
  const contactIcon = lead.contactMethod === 'email' ? (
    <Mail className="w-4 h-4 text-purple-300/80" />
  ) : (
    <MessageCircle className="w-4 h-4 text-purple-300/80" />
  )
  const contactValue = lead.contactMethod === 'email' ? lead.email : lead.facebookId

  return (
    <div
      className={`
        rounded-2xl border transition-all duration-200
        ${isSelected
          ? 'border-purple-500/15 bg-purple-900/25'
          : 'border-purple-500/10 bg-slate-900/40'
        }
        hover:bg-purple-900/10
      `}
    >
      {/* Collapsed row header */}
      <button
        onClick={() => {
          onSelect()
          onToggle()
        }}
        className="w-full p-4 flex items-center gap-4 text-left"
      >
        {/* Expand icon */}
        <ChevronRight
          className={`
            w-4 h-4 text-purple-300 transition-transform duration-200
            ${isExpanded ? 'rotate-90' : ''}
          `}
        />

        {/* Status icon */}
        {getStatusIcon(lead.status)}

        {/* Lead info */}
        <div className="flex-1 flex items-center justify-between">
          <div className="flex items-center gap-4">
            <span className="text-purple-100 font-medium">
              {lead.name}
            </span>
            <span className="text-purple-300/80 text-sm flex items-center gap-1.5">
              {contactIcon}
              {contactValue}
            </span>
            <span className="text-purple-300/60 text-sm">
              {getMoveInLabel(lead.moveInFlexibility)}
            </span>
          </div>

          <div className="flex items-center gap-3">
            {/* Status badge */}
            <span className={`
              px-3 py-1 rounded-full text-xs font-medium border
              ${getStatusColor(lead.status)}
            `}>
              {getStatusLabel(lead.status)}
            </span>

            {/* Created date */}
            <span className="text-purple-300/60 text-xs">
              {formatDate(lead.createdAt)}
            </span>
          </div>
        </div>
      </button>

      {/* Expanded details */}
      <div
        className={`${isExpanded ? 'rounded-b-2xl border-t border-purple-500/10' : ''}`}
        style={detailsStyle}
      >
        <div ref={detailsRef} className="p-6 space-y-6">
          {/* Contact Information */}
          <div className="grid grid-cols-2 gap-4">
            <div>
              <div className="text-purple-300/60 text-sm mb-1">Kontaktmetod</div>
              <div className="text-purple-100 flex items-center gap-2">
                {contactIcon}
                <span>{lead.contactMethod === 'email' ? 'E-post' : 'Facebook Messenger'}</span>
              </div>
            </div>
            <div>
              <div className="text-purple-300/60 text-sm mb-1">Kontaktuppgifter</div>
              <div className="text-purple-100">
                {lead.contactMethod === 'email' ? (
                  <a href={`mailto:${lead.email}`} className="hover:text-cyan-400 transition-colors">
                    {lead.email}
                  </a>
                ) : (
                  <a
                    href={`https://facebook.com/${lead.facebookId}`}
                    target="_blank"
                    rel="noopener noreferrer"
                    className="hover:text-cyan-400 transition-colors"
                  >
                    facebook.com/{lead.facebookId}
                  </a>
                )}
              </div>
            </div>
            {lead.phone && (
              <div>
                <div className="text-purple-300/60 text-sm mb-1">Telefon</div>
                <div className="text-purple-100 flex items-center gap-2">
                  <Phone className="w-4 h-4 text-purple-300/80" />
                  <a href={`tel:${lead.phone}`} className="hover:text-cyan-400 transition-colors">
                    {lead.phone}
                  </a>
                </div>
              </div>
            )}
          </div>

          {/* Move-in Details */}
          <div>
            <div className="text-purple-300/60 text-sm mb-1">Inflyttning</div>
            <div className="text-purple-100">
              {getMoveInLabel(lead.moveInFlexibility)}
              {lead.moveInExtra && (
                <span className="text-purple-300/80 ml-2">
                  ({lead.moveInExtra})
                </span>
              )}
            </div>
          </div>

          {/* Motivation */}
          {lead.motivation && (
            <div>
              <div className="text-purple-300/60 text-sm mb-2">Motivering</div>
              <div className="text-purple-100 bg-slate-900/40 rounded-lg p-3 whitespace-pre-wrap">
                {lead.motivation}
              </div>
            </div>
          )}

          {/* Admin Notes */}
          <div>
            <div className="text-purple-300/60 text-sm mb-2 flex items-center justify-between">
              <span>Anteckningar</span>
              <button
                onClick={handleAddNote}
                className="text-xs text-cyan-400 hover:text-cyan-300 transition-colors"
              >
                {lead.adminNotes ? 'Redigera' : 'Lägg till'}
              </button>
            </div>
            {lead.adminNotes ? (
              <div className="text-purple-100 bg-slate-900/40 rounded-lg p-3 whitespace-pre-wrap">
                {lead.adminNotes}
              </div>
            ) : (
              <div className="text-purple-300/40 text-sm italic">
                Inga anteckningar ännu
              </div>
            )}
          </div>

          {/* Actions */}
          <div className="flex items-center gap-3 pt-4 border-t border-purple-500/10">
            {/* Status change buttons */}
            <div className="flex-1 flex gap-2">
              {lead.status === 'pending_review' && (
                <>
                  <button
                    onClick={() => handleStatusChange('contacted')}
                    disabled={updatingStatus}
                    className="px-3 py-2 rounded-lg text-xs font-medium bg-blue-600/80 hover:bg-blue-600
                             text-white transition-all disabled:opacity-50"
                  >
                    Markera kontaktad
                  </button>
                  <button
                    onClick={() => handleStatusChange('rejected')}
                    disabled={updatingStatus}
                    className="px-3 py-2 rounded-lg text-xs font-medium bg-red-600/80 hover:bg-red-600
                             text-white transition-all disabled:opacity-50"
                  >
                    Avböj
                  </button>
                </>
              )}
              {lead.status === 'contacted' && (
                <>
                  <button
                    onClick={() => handleStatusChange('interview_scheduled')}
                    disabled={updatingStatus}
                    className="px-3 py-2 rounded-lg text-xs font-medium bg-purple-600/80 hover:bg-purple-600
                             text-white transition-all disabled:opacity-50"
                  >
                    Boka visning
                  </button>
                  <button
                    onClick={() => handleStatusChange('approved')}
                    disabled={updatingStatus}
                    className="px-3 py-2 rounded-lg text-xs font-medium bg-cyan-600/80 hover:bg-cyan-600
                             text-white transition-all disabled:opacity-50"
                  >
                    Godkänn
                  </button>
                </>
              )}
              {lead.status === 'interview_scheduled' && (
                <button
                  onClick={() => handleStatusChange('approved')}
                  disabled={updatingStatus}
                  className="px-3 py-2 rounded-lg text-xs font-medium bg-cyan-600/80 hover:bg-cyan-600
                           text-white transition-all disabled:opacity-50"
                >
                  Godkänn
                </button>
              )}
            </div>

            {/* Delete button */}
            <button
              onClick={handleDelete}
              disabled={deleting}
              className="px-3 py-2 rounded-lg text-xs font-medium bg-red-900/40 hover:bg-red-900/60
                       text-red-300 transition-all disabled:opacity-50 flex items-center gap-1.5"
            >
              <Trash2 className="w-3 h-3" />
              {deleting ? 'Tar bort...' : 'Ta bort'}
            </button>
          </div>
        </div>
      </div>

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

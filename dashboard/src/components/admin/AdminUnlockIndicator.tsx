import React from 'react'
import { useAdminAuth } from '../../contexts/AdminAuthContext'

const DEMO_MODE = false

interface AdminUnlockIndicatorProps {
  compact?: boolean
}

export const AdminUnlockIndicator: React.FC<AdminUnlockIndicatorProps> = ({ compact }) => {
  const { token, expiresAt, sessionDurationMs, clearAuth } = useAdminAuth()
  const [remainingSeconds, setRemainingSeconds] = React.useState<number>(0)

  const isActive = token && expiresAt && Date.now() < expiresAt

  React.useEffect(() => {
    if (!isActive) {
      setRemainingSeconds(0)
      return
    }

    const update = () => {
      if (!expiresAt) return
      const diff = Math.max(0, Math.ceil((expiresAt - Date.now()) / 1000))
      setRemainingSeconds(diff)
      if (diff <= 0) {
        clearAuth()
      }
    }

    update()
    const id = window.setInterval(update, 1000)
    return () => window.clearInterval(id)
  }, [isActive, expiresAt, clearAuth])

  if (!isActive || !expiresAt || remainingSeconds <= 0) {
    return null
  }

  const totalSeconds = sessionDurationMs ? Math.max(1, Math.round(sessionDurationMs / 1000)) : remainingSeconds
  const progress = Math.max(0, Math.min(1, remainingSeconds / totalSeconds))
  const circumference = 2 * Math.PI * 17
  const strokeDashoffset = circumference * progress
  const remainingLabel = remainingSeconds >= 60
    ? `${Math.ceil(remainingSeconds / 60)}m`
    : `${remainingSeconds}s`

  const containerClass = compact ? '' : 'fixed bottom-5 right-5 z-40'

  return (
    <div className={containerClass}>
      <div className="relative group">
        <svg className="w-12 h-12 -rotate-90" viewBox="0 0 40 40">
          <circle
            cx="20"
            cy="20"
            r="16"
            fill="rgba(99, 102, 241, 0.2)"
            stroke="rgba(99, 102, 241, 0.35)"
            strokeWidth="2"
          />
          <circle
            cx="20"
            cy="20"
            r="16"
            fill="none"
            stroke="url(#adminUnlockGradient)"
            strokeWidth="3"
            strokeDasharray={circumference}
            strokeDashoffset={strokeDashoffset}
            strokeLinecap="round"
            className="transition-all duration-500"
          />
          <defs>
            <linearGradient id="adminUnlockGradient" x1="0%" y1="0%" x2="0%" y2="100%">
              <stop offset="0%" stopColor="#f472b6" />
              <stop offset="100%" stopColor="#7c3aed" />
            </linearGradient>
          </defs>
        </svg>
        <div className="absolute inset-0 flex flex-col items-center justify-center text-purple-100 text-[10px] font-semibold">
          <span>PIN</span>
          <span>{remainingLabel}</span>
        </div>
        <div className="absolute bottom-full left-1/2 -translate-x-1/2 mb-2 opacity-0 group-hover:opacity-100 transition-opacity pointer-events-none">
          <div className="bg-slate-900/90 text-purple-100 text-xs px-3 py-2 rounded-lg shadow-lg backdrop-blur-sm whitespace-nowrap">
            Upplåst i {remainingSeconds}s
          </div>
        </div>
      </div>
    </div>
  )
}

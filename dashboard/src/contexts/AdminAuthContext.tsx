import React from 'react'

interface AdminAuthContextValue {
  token: string | null
  expiresAt: number | null
  sessionDurationMs: number | null
  ensureAuth: () => Promise<string | null>
  clearAuth: () => void
}

const AdminAuthContext = React.createContext<AdminAuthContextValue | undefined>(undefined)

const TOKEN_KEY = 'kimonokittens_admin_token'
const EXPIRY_KEY = 'kimonokittens_admin_token_expiry'
const TTL_KEY = 'kimonokittens_admin_token_ttl'

interface PendingRequest {
  resolve: (value: string | null) => void
}

export const AdminAuthProvider: React.FC<{ children: React.ReactNode }> = ({ children }) => {
  const [token, setToken] = React.useState<string | null>(() => localStorage.getItem(TOKEN_KEY))
  const [expiresAt, setExpiresAt] = React.useState<number | null>(() => {
    const raw = localStorage.getItem(EXPIRY_KEY)
    return raw ? parseInt(raw, 10) : null
  })
  const [sessionDurationMs, setSessionDurationMs] = React.useState<number | null>(() => {
    const raw = localStorage.getItem(TTL_KEY)
    return raw ? parseInt(raw, 10) : null
  })
  const [modalOpen, setModalOpen] = React.useState(false)
  const [pin, setPin] = React.useState('')
  const [error, setError] = React.useState<string | null>(null)
  const [submitting, setSubmitting] = React.useState(false)
  const pendingRequests = React.useRef<PendingRequest[]>([])

  const isTokenValid = React.useCallback(() => {
    if (!token || !expiresAt) return false
    return Date.now() < expiresAt
  }, [token, expiresAt])

  const resolveAll = (value: string | null) => {
    pendingRequests.current.forEach(({ resolve }) => resolve(value))
    pendingRequests.current = []
  }

  const closeModal = (result: string | null = null) => {
    setModalOpen(false)
    setPin('')
    setError(null)
    setSubmitting(false)
    resolveAll(result)
  }

  const clearAuth = React.useCallback(() => {
    setToken(null)
    setExpiresAt(null)
    setSessionDurationMs(null)
    localStorage.removeItem(TOKEN_KEY)
    localStorage.removeItem(EXPIRY_KEY)
    localStorage.removeItem(TTL_KEY)
  }, [])

  const ensureAuth = React.useCallback(() => {
    if (isTokenValid()) {
      return Promise.resolve(token)
    }

    return new Promise<string | null>((resolve) => {
      pendingRequests.current.push({ resolve })
      setModalOpen(true)
      setError(null)
    })
  }, [isTokenValid, token])

  const submitPin = async (event?: React.FormEvent) => {
    if (event) event.preventDefault()
    if (!pin) {
      setError('Ange PIN')
      return
    }

    setSubmitting(true)
    setError(null)

    try {
      const response = await fetch('/api/admin/auth', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ pin })
      })

      const data = await response.json()

      if (!response.ok) {
        setError(data.error || 'Fel PIN')
        setSubmitting(false)
        return
      }

      const expiryMs = data.expires_at ? Date.parse(data.expires_at) : null
      const ttlMs = data.ttl_seconds ? data.ttl_seconds * 1000 : (expiryMs ? expiryMs - Date.now() : null)
      setToken(data.token)
      setExpiresAt(expiryMs)
      setSessionDurationMs(ttlMs)
      if (data.token) {
        localStorage.setItem(TOKEN_KEY, data.token)
      }
      if (expiryMs) {
        localStorage.setItem(EXPIRY_KEY, expiryMs.toString())
      }
      if (ttlMs) {
        localStorage.setItem(TTL_KEY, ttlMs.toString())
      }

      closeModal(data.token)
    } catch (err) {
      console.error('Admin auth error', err)
      setError('Kunde inte verifiera PIN')
      setSubmitting(false)
    }
  }

  React.useEffect(() => {
    if (token && expiresAt && !isTokenValid()) {
      clearAuth()
    }
  }, [token, expiresAt, clearAuth, isTokenValid])

  const contextValue = React.useMemo(() => ({
    token,
    expiresAt,
    sessionDurationMs,
    ensureAuth,
    clearAuth
  }), [token, expiresAt, sessionDurationMs, ensureAuth, clearAuth])

  return (
    <AdminAuthContext.Provider value={contextValue}>
      {children}
      {modalOpen && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-slate-950/80 backdrop-blur-sm">
          <div className="bg-slate-900/60 border border-purple-500/30 rounded-2xl p-6 w-full max-w-sm">
            <h2 className="text-xl font-semibold text-purple-100 mb-4">Ange admin-PIN</h2>
            <form onSubmit={submitPin} className="space-y-4">
              <input
                type="password"
                value={pin}
                onChange={(e) => setPin(e.target.value)}
                className="w-full px-4 py-3 text-lg bg-slate-950/60 border border-purple-900/40 rounded-xl text-purple-100 placeholder-purple-400/40 focus:outline-none focus:border-purple-400 focus:ring-2 focus:ring-purple-500/30"
                placeholder="••••"
                autoFocus
                disabled={submitting}
              />
              {error && <p className="text-sm text-red-400">{error}</p>}
              <div className="flex gap-3">
                <button
                  type="submit"
                  disabled={submitting}
                  className="flex-1 px-4 py-2 rounded-xl bg-cyan-600 text-white font-medium hover:bg-cyan-500 transition-all disabled:opacity-50"
                >
                  {submitting ? 'Kontrollerar…' : 'Lås upp'}
                </button>
                <button
                  type="button"
                  onClick={() => closeModal(null)}
                  disabled={submitting}
                  className="flex-1 px-4 py-2 rounded-xl bg-slate-800/70 text-purple-200 font-medium hover:bg-slate-700/70 transition-all"
                >
                  Avbryt
                </button>
              </div>
            </form>
          </div>
        </div>
      )}
    </AdminAuthContext.Provider>
  )
}

export const useAdminAuth = () => {
  const ctx = React.useContext(AdminAuthContext)
  if (!ctx) {
    throw new Error('useAdminAuth måste användas inom AdminAuthProvider')
  }
  return ctx
}

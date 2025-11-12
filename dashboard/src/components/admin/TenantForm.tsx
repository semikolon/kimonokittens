// Tenant Form Component - Add new tenants with or without contracts
import React, { useState } from 'react'
import { UserPlus, FileSignature, Loader2 } from 'lucide-react'

interface TenantFormData {
  name: string
  email: string
  personnummer: string
  phone: string
  startDate: string
  departureDate: string
}

interface TenantFormProps {
  onSuccess?: () => void
}

export const TenantForm: React.FC<TenantFormProps> = ({ onSuccess }) => {
  const [formData, setFormData] = useState<TenantFormData>({
    name: '',
    email: '',
    personnummer: '',
    phone: '',
    startDate: '',
    departureDate: ''
  })

  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [success, setSuccess] = useState<string | null>(null)

  const handleChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    setFormData(prev => ({
      ...prev,
      [e.target.name]: e.target.value
    }))
    // Clear messages on input
    setError(null)
    setSuccess(null)
  }

  const validateForm = (requireStartDate: boolean): string | null => {
    if (!formData.name.trim()) return 'Namn krävs'
    if (!formData.email.trim()) return 'E-post krävs'
    if (!formData.email.includes('@')) return 'Ogiltig e-postadress'
    if (requireStartDate && !formData.startDate) return 'Startdatum krävs för att skapa kontrakt'
    if (!formData.personnummer.trim()) return 'Personnummer rekommenderas starkt för kontraktsskapande'
    return null
  }

  const handleSubmit = async (withContract: boolean) => {
    setError(null)
    setSuccess(null)

    const validationError = validateForm(withContract)
    if (validationError) {
      setError(validationError)
      return
    }

    setLoading(true)

    try {
      const endpoint = withContract ? '/api/tenants/with-contract' : '/api/tenants'
      const response = await fetch(endpoint, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          name: formData.name,
          email: formData.email,
          personnummer: formData.personnummer || null,
          phone: formData.phone || null,
          startDate: formData.startDate || null,
          departureDate: formData.departureDate || null
        })
      })

      if (!response.ok) {
        const errorData = await response.json()
        throw new Error(errorData.error || 'Fel vid skapande')
      }

      const result = await response.json()

      // Clear form on success
      setFormData({
        name: '',
        email: '',
        personnummer: '',
        phone: '',
        startDate: '',
        departureDate: ''
      })

      setSuccess(withContract
        ? `Hyresgäst och kontrakt skapade! ${result.tenant?.name || 'Hyresgäst'} tillagd.`
        : `Hyresgäst skapad! ${result.name} tillagd.`
      )

      if (onSuccess) onSuccess()
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Ett oväntat fel inträffade')
    } finally {
      setLoading(false)
    }
  }

  return (
    <div className="space-y-6">
      {/* Status messages */}
      {error && (
        <div className="bg-red-900/20 border border-red-500/30 rounded-lg px-4 py-3">
          <p className="text-red-200 text-sm">{error}</p>
        </div>
      )}

      {success && (
        <div className="bg-cyan-900/20 border border-cyan-500/30 rounded-lg px-4 py-3">
          <p className="text-cyan-200 text-sm">{success}</p>
        </div>
      )}

      {/* Form fields - large and wide */}
      <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
        {/* Name field */}
        <div className="md:col-span-2">
          <label className="block text-purple-200 text-sm font-medium mb-2">
            Namn <span className="text-red-400">*</span>
          </label>
          <input
            type="text"
            name="name"
            value={formData.name}
            onChange={handleChange}
            className="w-full px-6 py-4 text-lg bg-slate-900/60 border border-purple-900/30 rounded-xl
                     text-purple-100 placeholder-purple-300/40
                     focus:outline-none focus:border-purple-500/50 focus:ring-2 focus:ring-purple-500/20
                     transition-all"
            placeholder="Fredrik Bränström"
            disabled={loading}
          />
        </div>

        {/* Email field */}
        <div className="md:col-span-2">
          <label className="block text-purple-200 text-sm font-medium mb-2">
            E-post <span className="text-red-400">*</span>
          </label>
          <input
            type="email"
            name="email"
            value={formData.email}
            onChange={handleChange}
            className="w-full px-6 py-4 text-lg bg-slate-900/60 border border-purple-900/30 rounded-xl
                     text-purple-100 placeholder-purple-300/40
                     focus:outline-none focus:border-purple-500/50 focus:ring-2 focus:ring-purple-500/20
                     transition-all"
            placeholder="fredrik@example.com"
            disabled={loading}
          />
        </div>

        {/* Personal number */}
        <div>
          <label className="block text-purple-200 text-sm font-medium mb-2">
            Personnummer <span className="text-purple-300/60">(rekommenderas för kontrakt)</span>
          </label>
          <input
            type="text"
            name="personnummer"
            value={formData.personnummer}
            onChange={handleChange}
            className="w-full px-6 py-4 text-lg bg-slate-900/60 border border-purple-900/30 rounded-xl
                     text-purple-100 placeholder-purple-300/40
                     focus:outline-none focus:border-purple-500/50 focus:ring-2 focus:ring-purple-500/20
                     transition-all"
            placeholder="ÅÅÅÅMMDD-XXXX"
            disabled={loading}
          />
        </div>

        {/* Phone */}
        <div>
          <label className="block text-purple-200 text-sm font-medium mb-2">
            Telefon
          </label>
          <input
            type="tel"
            name="phone"
            value={formData.phone}
            onChange={handleChange}
            className="w-full px-6 py-4 text-lg bg-slate-900/60 border border-purple-900/30 rounded-xl
                     text-purple-100 placeholder-purple-300/40
                     focus:outline-none focus:border-purple-500/50 focus:ring-2 focus:ring-purple-500/20
                     transition-all"
            placeholder="070-123 45 67"
            disabled={loading}
          />
        </div>

        {/* Start date */}
        <div>
          <label className="block text-purple-200 text-sm font-medium mb-2">
            Startdatum <span className="text-purple-300/60">(krävs för kontrakt)</span>
          </label>
          <input
            type="date"
            name="startDate"
            value={formData.startDate}
            onChange={handleChange}
            className="w-full px-6 py-4 text-lg bg-slate-900/60 border border-purple-900/30 rounded-xl
                     text-purple-100
                     focus:outline-none focus:border-purple-500/50 focus:ring-2 focus:ring-purple-500/20
                     transition-all"
            disabled={loading}
          />
        </div>

        {/* Departure date */}
        <div>
          <label className="block text-purple-200 text-sm font-medium mb-2">
            Utflyttningsdatum <span className="text-purple-300/60">(valfritt)</span>
          </label>
          <input
            type="date"
            name="departureDate"
            value={formData.departureDate}
            onChange={handleChange}
            className="w-full px-6 py-4 text-lg bg-slate-900/60 border border-purple-900/30 rounded-xl
                     text-purple-100
                     focus:outline-none focus:border-purple-500/50 focus:ring-2 focus:ring-purple-500/20
                     transition-all"
            disabled={loading}
          />
        </div>
      </div>

      {/* Action buttons - large and prominent */}
      <div className="flex flex-col sm:flex-row gap-4 pt-4">
        <button
          onClick={() => handleSubmit(false)}
          disabled={loading}
          className="flex-1 flex items-center justify-center gap-3 px-8 py-4 text-lg font-medium
                   bg-purple-600/80 hover:bg-purple-600 text-white rounded-xl
                   transition-all disabled:opacity-50 disabled:cursor-not-allowed
                   focus:outline-none focus:ring-2 focus:ring-purple-500/50"
        >
          {loading ? (
            <Loader2 className="w-5 h-5 animate-spin" />
          ) : (
            <UserPlus className="w-5 h-5" />
          )}
          Lägg till hyresgäst
        </button>

        <button
          onClick={() => handleSubmit(true)}
          disabled={loading}
          className="flex-1 flex items-center justify-center gap-3 px-8 py-4 text-lg font-medium
                   bg-cyan-600/80 hover:bg-cyan-600 text-white rounded-xl
                   transition-all disabled:opacity-50 disabled:cursor-not-allowed
                   focus:outline-none focus:ring-2 focus:ring-cyan-500/50"
        >
          {loading ? (
            <Loader2 className="w-5 h-5 animate-spin" />
          ) : (
            <FileSignature className="w-5 h-5" />
          )}
          Lägg till hyresgäst + kontrakt
        </button>
      </div>

      {/* Helper text */}
      <p className="text-purple-300/60 text-sm text-center pt-2">
        <span className="text-red-400">*</span> obligatoriska fält •
        Personnummer krävs för kontraktsskapande
      </p>
    </div>
  )
}

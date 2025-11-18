import { useState } from 'react'
import { Turnstile } from '@marsidev/react-turnstile'
import { Loader2 } from 'lucide-react'
import ContactMethod from './ContactMethod'
import MoveInField from './MoveInField'

interface SignupFormProps {
  onSuccess: () => void
}

export default function SignupForm({ onSuccess }: SignupFormProps) {
  const [name, setName] = useState('')
  const [contactMethod, setContactMethod] = useState<'email' | 'facebook'>('facebook')
  const [contactValue, setContactValue] = useState('')
  const [phone, setPhone] = useState('')
  const [moveIn, setMoveIn] = useState('')
  const [moveInExtra, setMoveInExtra] = useState('')
  const [motivation, setMotivation] = useState('')
  const [captchaToken, setCaptchaToken] = useState<string | null>(null)
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    setError(null)

    if (!captchaToken) {
      setError('Vänligen slutför CAPTCHA-verifieringen')
      return
    }

    setLoading(true)

    try {
      const response = await fetch('/api/signup', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          name,
          contact_method: contactMethod,
          [contactMethod === 'email' ? 'email' : 'facebook_id']: contactValue,
          phone: phone || null,
          move_in_flexibility: moveIn,
          move_in_extra: moveInExtra || null,
          motivation: motivation || null,
          captcha: captchaToken
        })
      })

      if (!response.ok) {
        const data = await response.json()
        throw new Error(data.error || 'Något gick fel')
      }

      // Success!
      onSuccess()

      // Reset form
      setName('')
      setContactValue('')
      setPhone('')
      setMoveIn('')
      setMoveInExtra('')
      setMotivation('')
      setCaptchaToken(null)

    } catch (err) {
      setError(err instanceof Error ? err.message : 'Något gick fel')
    } finally {
      setLoading(false)
    }
  }

  return (
    <form onSubmit={handleSubmit} className="space-y-6">
      {/* Name field */}
      <div>
        <label className="block text-purple-200 text-sm font-medium mb-2">
          Namn *
        </label>
        <input
          type="text"
          required
          value={name}
          onChange={(e) => setName(e.target.value)}
          className="w-full px-6 py-4 text-2xl bg-slate-900/60 border border-purple-900/30 rounded-xl
                     text-purple-100 placeholder-purple-300/40
                     focus:outline-none focus:border-purple-500/50 focus:ring-2 focus:ring-purple-500/20"
          placeholder="Lisa Andersson"
        />
      </div>

      {/* Contact method */}
      <ContactMethod
        method={contactMethod}
        value={contactValue}
        onMethodChange={setContactMethod}
        onValueChange={setContactValue}
      />

      {/* Phone (optional) */}
      <div>
        <label className="block text-purple-200 text-sm font-medium mb-2">
          Telefon (valfritt)
        </label>
        <input
          type="tel"
          value={phone}
          onChange={(e) => setPhone(e.target.value)}
          className="w-full px-6 py-4 text-2xl bg-slate-900/60 border border-purple-900/30 rounded-xl
                     text-purple-100 placeholder-purple-300/40
                     focus:outline-none focus:border-purple-500/50 focus:ring-2 focus:ring-purple-500/20"
          placeholder="070-123 45 67"
        />
      </div>

      {/* Move-in flexibility */}
      <MoveInField
        value={moveIn}
        extraValue={moveInExtra}
        onValueChange={setMoveIn}
        onExtraChange={setMoveInExtra}
      />

      {/* Motivation */}
      <div>
        <label className="block text-purple-200 text-sm font-medium mb-2">
          Vem är du och varför vill du bo här? (valfritt)
        </label>
        <textarea
          value={motivation}
          onChange={(e) => setMotivation(e.target.value)}
          rows={6}
          className="w-full px-6 py-4 text-xl bg-slate-900/60 border border-purple-900/30 rounded-xl
                     text-purple-100 placeholder-purple-300/40
                     focus:outline-none focus:border-purple-500/50 focus:ring-2 focus:ring-purple-500/20
                     resize-none"
          placeholder="Berätta lite om dig själv..."
        />
      </div>

      {/* CAPTCHA */}
      <Turnstile
        siteKey={import.meta.env.VITE_TURNSTILE_SITE_KEY || 'DEVELOPMENT_KEY'}
        onSuccess={(token) => setCaptchaToken(token)}
        theme="dark"
        size="invisible"
      />

      {/* Error message */}
      {error && (
        <div className="p-4 bg-red-900/20 border border-red-500/30 rounded-xl text-red-300 text-sm">
          {error}
        </div>
      )}

      {/* Submit button */}
      <button
        type="submit"
        disabled={loading}
        className="w-full flex items-center justify-center gap-3 px-8 py-4 text-lg font-medium
                   text-white rounded-xl transition-all
                   disabled:opacity-50 disabled:cursor-not-allowed
                   focus:outline-none focus:ring-2 focus:ring-purple-500/50
                   hover:brightness-110"
        style={{
          backgroundImage: 'linear-gradient(180deg, #cb6f38 0%, #903f14 100%)'
        }}
      >
        {loading ? (
          <>
            <Loader2 className="w-5 h-5 animate-spin" />
            Skickar...
          </>
        ) : (
          'SKICKA'
        )}
      </button>
    </form>
  )
}

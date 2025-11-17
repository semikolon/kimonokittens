interface ContactMethodProps {
  method: 'email' | 'facebook'
  value: string
  onMethodChange: (method: 'email' | 'facebook') => void
  onValueChange: (value: string) => void
}

export default function ContactMethod({
  method,
  value,
  onMethodChange,
  onValueChange
}: ContactMethodProps) {
  return (
    <div>
      <label className="block text-purple-200 text-sm font-medium mb-2">
        Hur vill du bli kontaktad? *
      </label>

      {/* Radio buttons */}
      <div className="flex gap-4 mb-4">
        <label className="flex items-center gap-2 cursor-pointer">
          <input
            type="radio"
            name="contactMethod"
            value="email"
            checked={method === 'email'}
            onChange={() => {
              onMethodChange('email')
              onValueChange('') // Clear value when switching
            }}
            className="w-4 h-4 text-purple-500"
          />
          <span className="text-purple-100">E-post</span>
        </label>

        <label className="flex items-center gap-2 cursor-pointer">
          <input
            type="radio"
            name="contactMethod"
            value="facebook"
            checked={method === 'facebook'}
            onChange={() => {
              onMethodChange('facebook')
              onValueChange('') // Clear value when switching
            }}
            className="w-4 h-4 text-purple-500"
          />
          <span className="text-purple-100">Facebook Messenger</span>
        </label>
      </div>

      {/* Conditional input field */}
      {method === 'email' && (
        <input
          type="email"
          required
          value={value}
          onChange={(e) => onValueChange(e.target.value)}
          className="w-full px-6 py-4 text-2xl bg-slate-900/60 border border-purple-900/30 rounded-xl
                     text-purple-100 placeholder-purple-300/40
                     focus:outline-none focus:border-purple-500/50 focus:ring-2 focus:ring-purple-500/20"
          placeholder="lisa@example.com"
        />
      )}

      {method === 'facebook' && (
        <input
          type="text"
          required
          value={value}
          onChange={(e) => onValueChange(e.target.value)}
          className="w-full px-6 py-4 text-2xl bg-slate-900/60 border border-purple-900/30 rounded-xl
                     text-purple-100 placeholder-purple-300/40
                     focus:outline-none focus:border-purple-500/50 focus:ring-2 focus:ring-purple-500/20"
          placeholder="lisa.andersson"
        />
      )}
    </div>
  )
}

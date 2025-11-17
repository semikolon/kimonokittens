interface MoveInFieldProps {
  value: string
  extraValue: string
  onValueChange: (value: string) => void
  onExtraChange: (value: string) => void
}

export default function MoveInField({
  value,
  extraValue,
  onValueChange,
  onExtraChange
}: MoveInFieldProps) {
  return (
    <div className="space-y-4">
      <div>
        <label className="block text-purple-200 text-sm font-medium mb-2">
          Inflyttningsflexibilitet *
        </label>
        <select
          required
          value={value}
          onChange={(e) => {
            onValueChange(e.target.value)
            // Clear extra value when changing selection
            if (e.target.value !== 'specific' && e.target.value !== 'other') {
              onExtraChange('')
            }
          }}
          className="w-full px-6 py-4 text-2xl bg-slate-900/60 border border-purple-900/30 rounded-xl
                     text-purple-100
                     focus:outline-none focus:border-purple-500/50 focus:ring-2 focus:ring-purple-500/20"
        >
          <option value="">Välj alternativ...</option>
          <option value="immediate">Omgående</option>
          <option value="1month">1 månads uppsägningstid</option>
          <option value="2months">2 månaders uppsägningstid</option>
          <option value="3months">3 månaders uppsägningstid</option>
          <option value="specific">Specifikt datum</option>
          <option value="other">Annat</option>
        </select>
      </div>

      {/* Conditional date picker */}
      {value === 'specific' && (
        <input
          type="date"
          required
          value={extraValue}
          onChange={(e) => onExtraChange(e.target.value)}
          className="w-full px-6 py-4 text-2xl bg-slate-900/60 border border-purple-900/30 rounded-xl
                     text-purple-100
                     focus:outline-none focus:border-purple-500/50 focus:ring-2 focus:ring-purple-500/20"
        />
      )}

      {/* Conditional text field */}
      {value === 'other' && (
        <input
          type="text"
          required
          value={extraValue}
          onChange={(e) => onExtraChange(e.target.value)}
          className="w-full px-6 py-4 text-2xl bg-slate-900/60 border border-purple-900/30 rounded-xl
                     text-purple-100 placeholder-purple-300/40
                     focus:outline-none focus:border-purple-500/50 focus:ring-2 focus:ring-purple-500/20"
          placeholder="Beskriv din flexibilitet..."
        />
      )}
    </div>
  )
}

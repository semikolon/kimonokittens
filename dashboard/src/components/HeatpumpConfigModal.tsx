import React, { useState, useEffect } from 'react'
import { X } from 'lucide-react'

interface HeatpumpConfig {
  hoursOn: number
  emergencyTempOffset: number
  minHotwater: number
}

interface HeatpumpConfigModalProps {
  isOpen: boolean
  onClose: () => void
  currentConfig: HeatpumpConfig | null
}

export function HeatpumpConfigModal({ isOpen, onClose, currentConfig }: HeatpumpConfigModalProps) {
  const [config, setConfig] = useState<HeatpumpConfig>({
    hoursOn: 12,
    emergencyTempOffset: 2.0,
    minHotwater: 40
  })
  const [isSaving, setIsSaving] = useState(false)
  const [error, setError] = useState<string | null>(null)

  // Load current config when modal opens
  useEffect(() => {
    if (isOpen && currentConfig) {
      setConfig(currentConfig)
    }
  }, [isOpen, currentConfig])

  if (!isOpen) return null

  const handleSave = async () => {
    setIsSaving(true)
    setError(null)

    try {
      const response = await fetch('/api/heatpump/config', {
        method: 'PUT',
        headers: {
          'Content-Type': 'application/json'
        },
        body: JSON.stringify(config)
      })

      if (!response.ok) {
        const errorData = await response.json()
        throw new Error(errorData.error || 'Failed to save configuration')
      }

      // Success - close modal
      onClose()
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Unknown error')
    } finally {
      setIsSaving(false)
    }
  }

  const handleCancel = () => {
    // Reset to current config
    if (currentConfig) {
      setConfig(currentConfig)
    }
    setError(null)
    onClose()
  }

  return (
    <div className="fixed inset-0 bg-black/50 backdrop-blur-sm flex items-center justify-center z-50">
      <div className="bg-slate-800 rounded-lg shadow-xl max-w-md w-full mx-4 border border-slate-700">
        {/* Header */}
        <div className="flex items-center justify-between p-6 border-b border-slate-700">
          <h2 className="text-xl font-bold text-purple-100">Värmepumpsinställningar</h2>
          <button
            onClick={handleCancel}
            className="text-purple-200 hover:text-purple-100 transition-colors"
          >
            <X className="w-6 h-6" />
          </button>
        </div>

        {/* Content */}
        <div className="p-6 space-y-6">
          {/* Hours On Slider */}
          <div>
            <label className="block text-purple-200 text-sm uppercase mb-2">
              Antal timmar per dag
            </label>
            <div className="flex items-center space-x-4">
              <input
                type="range"
                min="5"
                max="22"
                step="1"
                value={config.hoursOn}
                onChange={(e) => setConfig({ ...config, hoursOn: parseInt(e.target.value) })}
                className="flex-1 h-2 bg-slate-700 rounded-lg appearance-none cursor-pointer accent-purple-500"
              />
              <span className="text-2xl font-bold text-purple-100 w-16 text-right">
                {config.hoursOn}h
              </span>
            </div>
            <p className="text-sm text-purple-300 mt-2">
              Väljer de {config.hoursOn} billigaste timmarna per dag
            </p>
          </div>

          {/* Emergency Temperature Offset Slider */}
          <div>
            <label className="block text-purple-200 text-sm uppercase mb-2">
              Nödtemperaturskydd
            </label>
            <div className="flex items-center space-x-4">
              <input
                type="range"
                min="0.5"
                max="5.0"
                step="0.5"
                value={config.emergencyTempOffset}
                onChange={(e) => setConfig({ ...config, emergencyTempOffset: parseFloat(e.target.value) })}
                className="flex-1 h-2 bg-slate-700 rounded-lg appearance-none cursor-pointer accent-purple-500"
              />
              <span className="text-2xl font-bold text-purple-100 w-16 text-right">
                {config.emergencyTempOffset.toFixed(1)}°
              </span>
            </div>
            <p className="text-sm text-purple-300 mt-2">
              Startar värmepump om inomhustemp ≤ måltemp − {config.emergencyTempOffset.toFixed(1)}°C
            </p>
          </div>

          {/* Minimum Hot Water Slider */}
          <div>
            <label className="block text-purple-200 text-sm uppercase mb-2">
              Minsta varmvatten
            </label>
            <div className="flex items-center space-x-4">
              <input
                type="range"
                min="35"
                max="50"
                step="1"
                value={config.minHotwater}
                onChange={(e) => setConfig({ ...config, minHotwater: parseInt(e.target.value) })}
                className="flex-1 h-2 bg-slate-700 rounded-lg appearance-none cursor-pointer accent-purple-500"
              />
              <span className="text-2xl font-bold text-purple-100 w-16 text-right">
                {config.minHotwater}°
              </span>
            </div>
            <p className="text-sm text-purple-300 mt-2">
              Startar värmepump om varmvatten &lt; {config.minHotwater}°C
            </p>
          </div>

          {/* Error Display */}
          {error && (
            <div className="bg-red-900/20 border border-red-400/30 rounded-lg p-4">
              <p className="text-red-400 text-sm">{error}</p>
            </div>
          )}
        </div>

        {/* Footer */}
        <div className="flex items-center justify-end space-x-3 p-6 border-t border-slate-700">
          <button
            onClick={handleCancel}
            disabled={isSaving}
            className="px-4 py-2 text-purple-200 hover:text-purple-100 transition-colors disabled:opacity-50"
          >
            Avbryt
          </button>
          <button
            onClick={handleSave}
            disabled={isSaving}
            className="px-6 py-2 bg-cyan-600/80 hover:bg-cyan-600 text-white font-medium rounded-lg transition-colors disabled:opacity-50 disabled:cursor-not-allowed"
          >
            {isSaving ? 'Sparar...' : 'Spara'}
          </button>
        </div>
      </div>
    </div>
  )
}

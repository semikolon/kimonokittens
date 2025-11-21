import React, { useState, useEffect } from 'react'
import { createPortal } from 'react-dom'
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
      // Convert from snake_case (API) to camelCase (frontend) and merge with defaults
      setConfig(prev => ({
        hoursOn: currentConfig.hours_on ?? prev.hoursOn,
        emergencyTempOffset: currentConfig.emergency_temp_offset ?? prev.emergencyTempOffset,
        minHotwater: currentConfig.min_hotwater ?? prev.minHotwater
      }))
    }
  }, [isOpen, currentConfig])

  const handleSave = async () => {
    setIsSaving(true)
    setError(null)

    try {
      // Convert from camelCase (frontend) to snake_case (API)
      const apiPayload = {
        hours_on: config.hoursOn,
        emergency_temp_offset: config.emergencyTempOffset,
        min_hotwater: config.minHotwater
      }

      const response = await fetch('/api/heatpump/config', {
        method: 'PUT',
        headers: {
          'Content-Type': 'application/json'
        },
        body: JSON.stringify(apiPayload)
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

  if (!isOpen) return null

  const modalContent = (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-slate-950/80 backdrop-blur-sm">
      <div className="bg-slate-900 border border-purple-500/30 rounded-2xl w-full max-w-md mx-4 overflow-hidden">
        {/* Header */}
        <div className="flex items-center justify-between p-6 border-b border-purple-500/20">
          <h2 className="text-xl font-semibold text-slate-100">Värmepumpsinställningar</h2>
          <button
            onClick={handleCancel}
            className="text-slate-300 hover:text-slate-100 transition-colors"
          >
            <X className="w-6 h-6" />
          </button>
        </div>

        {/* Content - scrollable if needed */}
        <div className="p-6 space-y-6 max-h-[60vh] overflow-y-auto">
          {/* Hours On Slider */}
          <div>
            <label className="block text-slate-200 text-sm uppercase mb-3 font-medium">
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
                className="flex-1 h-2 bg-slate-950/60 border border-purple-900/40 rounded-xl appearance-none cursor-pointer accent-purple-500"
              />
              <span className="text-2xl font-bold text-slate-100 w-16 text-right">
                {config.hoursOn}h
              </span>
            </div>
            <p className="text-sm text-slate-400/70 mt-2">
              Väljer de {config.hoursOn} billigaste timmarna per dag
            </p>
          </div>

          {/* Emergency Temperature Offset Slider */}
          <div>
            <label className="block text-slate-200 text-sm uppercase mb-3 font-medium">
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
                className="flex-1 h-2 bg-slate-950/60 border border-purple-900/40 rounded-xl appearance-none cursor-pointer accent-purple-500"
              />
              <span className="text-2xl font-bold text-slate-100 w-16 text-right">
                {config.emergencyTempOffset.toFixed(1)}°
              </span>
            </div>
            <p className="text-sm text-slate-400/70 mt-2">
              Startar värmepump om inomhustemp ≤ måltemp − {config.emergencyTempOffset.toFixed(1)}°C
            </p>
          </div>

          {/* Minimum Hot Water Slider */}
          <div>
            <label className="block text-slate-200 text-sm uppercase mb-3 font-medium">
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
                className="flex-1 h-2 bg-slate-950/60 border border-purple-900/40 rounded-xl appearance-none cursor-pointer accent-purple-500"
              />
              <span className="text-2xl font-bold text-slate-100 w-16 text-right">
                {config.minHotwater}°
              </span>
            </div>
            <p className="text-sm text-slate-400/70 mt-2">
              Startar värmepump om varmvatten &lt; {config.minHotwater}°C
            </p>
          </div>

          {/* Error Display */}
          {error && (
            <div className="bg-red-900/20 border border-red-400/30 rounded-xl p-4">
              <p className="text-red-400 text-sm">{error}</p>
            </div>
          )}
        </div>

        {/* Footer - Match PIN modal button style */}
        <div className="p-6 border-t border-purple-500/20">
          <div className="flex gap-3">
            <button
              onClick={handleCancel}
              disabled={isSaving}
              className="flex-1 px-4 py-2 rounded-xl bg-slate-800/70 text-slate-200 font-medium hover:bg-slate-700/70 transition-all disabled:opacity-50"
            >
              Avbryt
            </button>
            <button
              onClick={handleSave}
              disabled={isSaving}
              className="flex-1 px-4 py-2 rounded-xl bg-cyan-600 text-white font-medium hover:bg-cyan-500 transition-all disabled:opacity-50"
            >
              {isSaving ? 'Sparar…' : 'Spara'}
            </button>
          </div>
        </div>
      </div>
    </div>
  )

  return createPortal(modalContent, document.body)
}

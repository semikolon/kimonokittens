import React, { useState, useEffect } from 'react'
import { createPortal } from 'react-dom'
import { X, Zap, Clock, TrendingDown, TrendingUp, Minus } from 'lucide-react'

interface HeatpumpConfig {
  hoursOn: number
  emergencyTempOffset: number
  minHotwater: number
}

interface AutoTunerStatus {
  enabled: boolean
  status: 'ready' | 'rate_limited'
  last_adjustment: string | null
  next_eligible: string
  days_since_last?: number
  message: string
  adjustments_last_30_days: number
}

interface AdjustmentHistoryItem {
  id: string
  adjustment_type: string
  previous_value: string
  new_value: string
  reason: string
  created_at: string
}

interface AnalysisData {
  current_config: {
    hours_on: number
    block_distribution: number[]
    last_auto_adjustment: string | null
  }
  auto_tuner: AutoTunerStatus
  adjustment_history: AdjustmentHistoryItem[]
}

interface HeatpumpConfigModalProps {
  isOpen: boolean
  onClose: () => void
  currentConfig: HeatpumpConfig | null
  onSave?: () => void
  adminToken: string | null
}

// Block names in Swedish
const BLOCK_NAMES = ['Natt', 'Morgon', 'Eftermiddag', 'Kväll']
const BLOCK_TIMES = ['00–06', '06–12', '12–18', '18–24']

// Format relative time in Swedish
function formatRelativeTime(dateStr: string): string {
  const date = new Date(dateStr)
  const now = new Date()
  const diffMs = now.getTime() - date.getTime()
  const diffDays = Math.floor(diffMs / (1000 * 60 * 60 * 24))
  const diffHours = Math.floor(diffMs / (1000 * 60 * 60))
  const diffMinutes = Math.floor(diffMs / (1000 * 60))

  if (diffMinutes < 60) return `${diffMinutes} min sedan`
  if (diffHours < 24) return `${diffHours} tim sedan`
  if (diffDays === 1) return 'igår'
  if (diffDays < 7) return `${diffDays} dagar sedan`
  if (diffDays < 30) return `${Math.floor(diffDays / 7)} veckor sedan`
  return date.toLocaleDateString('sv-SE')
}

// Format future time in Swedish
function formatFutureTime(dateStr: string): string {
  const date = new Date(dateStr)
  const now = new Date()
  const diffMs = date.getTime() - now.getTime()
  const diffDays = Math.ceil(diffMs / (1000 * 60 * 60 * 24))

  if (diffDays <= 0) return 'nu'
  if (diffDays === 1) return 'imorgon'
  if (diffDays < 7) return `om ${diffDays} dagar`
  return date.toLocaleDateString('sv-SE')
}

// Parse adjustment values
function parseAdjustmentValue(jsonStr: string, type: string): string {
  try {
    const parsed = JSON.parse(jsonStr)
    if (type === 'hours_on') {
      return `${parsed.hours_on}h`
    } else if (type === 'block_distribution') {
      return parsed.blocks?.join('/') || jsonStr
    }
    return jsonStr
  } catch {
    return jsonStr
  }
}

export function HeatpumpConfigModal({ isOpen, onClose, currentConfig, onSave, adminToken }: HeatpumpConfigModalProps) {
  const [config, setConfig] = useState<HeatpumpConfig>({
    hoursOn: 12,
    emergencyTempOffset: 2.0,
    minHotwater: 40
  })
  const [analysisData, setAnalysisData] = useState<AnalysisData | null>(null)
  const [isLoadingAnalysis, setIsLoadingAnalysis] = useState(false)
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

  // Fetch analysis data when modal opens
  useEffect(() => {
    if (isOpen) {
      setIsLoadingAnalysis(true)
      fetch('/api/heatpump/analysis?days=30')
        .then(res => res.json())
        .then(data => {
          setAnalysisData(data)
          setIsLoadingAnalysis(false)
        })
        .catch(err => {
          console.error('Failed to load analysis data:', err)
          setIsLoadingAnalysis(false)
        })
    }
  }, [isOpen])

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
          'Content-Type': 'application/json',
          ...(adminToken && { 'X-Admin-Token': adminToken })
        },
        body: JSON.stringify(apiPayload)
      })

      if (!response.ok) {
        const errorData = await response.json()
        throw new Error(errorData.error || 'Failed to save configuration')
      }

      // Success - trigger refetch and close modal
      onSave?.()
      onClose()
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Unknown error')
    } finally {
      setIsSaving(false)
    }
  }

  const handleCancel = () => {
    setError(null)
    onClose()
    // Config will be reloaded from useEffect when modal reopens
  }

  if (!isOpen) return null

  const autoTuner = analysisData?.auto_tuner
  const adjustmentHistory = analysisData?.adjustment_history || []
  const blockDistribution = analysisData?.current_config?.block_distribution || [2, 2, 2, 2]

  const modalContent = (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-slate-950/80 backdrop-blur-sm">
      <div className="border border-purple-500/30 rounded-2xl w-full max-w-md mx-4 overflow-hidden" style={{
        backgroundImage: 'linear-gradient(180deg, rgba(41, 22, 64, 0.95) 0%, rgba(30, 14, 50, 0.99) 100%)'
      }}>
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
        <div className="p-6 space-y-6 max-h-[70vh] overflow-y-auto">
          {/* Emergency Temperature Offset Slider - FIRST (safety priority) */}
          <div>
            <label className="block text-sm font-semibold text-purple-200 uppercase tracking-wide mb-3">
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
            <p className="text-sm text-purple-100/90 mt-2">
              Startar värmepump om inomhustemp ≤ måltemp − {config.emergencyTempOffset.toFixed(1)}°C
            </p>
          </div>

          {/* Minimum Hot Water Slider - SECOND (safety threshold) */}
          <div className="pt-4 border-t border-purple-500/15">
            <label className="block text-sm font-semibold text-purple-200 uppercase tracking-wide mb-3">
              Minsta varmvattentemperatur
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
            <p className="text-sm text-purple-100/90 mt-2">
              Startar värmepump om varmvatten &lt; {config.minHotwater}°C
            </p>
          </div>

          {/* Auto-Learning Section - THIRD (between thresholds and manual hours) */}
          <div className="pt-4 border-t border-purple-500/15">
            <div className="flex items-center justify-between mb-4">
              <label className="block text-sm font-semibold text-purple-200 uppercase tracking-wide">
                Automatisk optimering
              </label>
              {isLoadingAnalysis ? (
                <span className="text-xs text-purple-300/60">Laddar...</span>
              ) : autoTuner ? (
                <span className={`
                  px-2.5 py-1 rounded-full text-xs font-medium border flex items-center gap-1.5
                  ${autoTuner.status === 'ready'
                    ? 'bg-cyan-400/20 text-cyan-300 border-cyan-400/30'
                    : 'bg-yellow-400/20 text-yellow-300 border-yellow-400/30'}
                `}>
                  <Zap className="w-3 h-3" />
                  {autoTuner.status === 'ready' ? 'Redo' : 'Pausad'}
                </span>
              ) : null}
            </div>

            {analysisData && (
              <div className="space-y-4">
                {/* Status info */}
                <div className="bg-slate-950/40 border border-purple-500/10 rounded-xl p-4 space-y-3">
                  {/* Last adjustment */}
                  <div className="flex items-center justify-between text-sm">
                    <span className="text-purple-300/70">Senaste justering</span>
                    <span className="text-slate-200">
                      {autoTuner?.last_adjustment
                        ? formatRelativeTime(autoTuner.last_adjustment)
                        : 'Aldrig'}
                    </span>
                  </div>

                  {/* Next eligible */}
                  <div className="flex items-center justify-between text-sm">
                    <span className="text-purple-300/70">Nästa möjliga</span>
                    <span className="text-slate-200">
                      {autoTuner?.next_eligible
                        ? formatFutureTime(autoTuner.next_eligible)
                        : '—'}
                    </span>
                  </div>

                  {/* Adjustments last 30 days */}
                  <div className="flex items-center justify-between text-sm">
                    <span className="text-purple-300/70">Justeringar (30 dagar)</span>
                    <span className="text-slate-200">
                      {autoTuner?.adjustments_last_30_days ?? 0}
                    </span>
                  </div>
                </div>

                {/* Block Distribution */}
                <div>
                  <div className="flex items-center gap-2 mb-2">
                    <Clock className="w-4 h-4 text-purple-300/70" />
                    <span className="text-sm text-purple-300/70">Timfördelning per block</span>
                  </div>
                  <div className="grid grid-cols-4 gap-2">
                    {blockDistribution.map((hours, i) => (
                      <div
                        key={i}
                        className="bg-slate-950/40 border border-purple-500/10 rounded-lg p-2 text-center"
                      >
                        <div className="text-lg font-bold text-slate-100">{hours}h</div>
                        <div className="text-xs text-purple-300/60">{BLOCK_NAMES[i]}</div>
                        <div className="text-xs text-purple-300/40">{BLOCK_TIMES[i]}</div>
                      </div>
                    ))}
                  </div>
                  <p className="text-xs text-purple-100/60 mt-2">
                    Garanterar minst {blockDistribution.reduce((a, b) => a + b, 0)}h fördelat över dygnet
                  </p>
                </div>

                {/* Recent Adjustments History */}
                {adjustmentHistory.length > 0 && (
                  <div>
                    <span className="text-sm text-purple-300/70 block mb-2">Senaste justeringar</span>
                    <div className="space-y-2">
                      {adjustmentHistory.slice(0, 3).map((adj) => {
                        const prevVal = parseAdjustmentValue(adj.previous_value, adj.adjustment_type)
                        const newVal = parseAdjustmentValue(adj.new_value, adj.adjustment_type)
                        const isIncrease = adj.adjustment_type === 'hours_on' &&
                          parseInt(newVal) > parseInt(prevVal)
                        const isDecrease = adj.adjustment_type === 'hours_on' &&
                          parseInt(newVal) < parseInt(prevVal)

                        return (
                          <div
                            key={adj.id}
                            className="bg-slate-950/30 border border-purple-500/10 rounded-lg p-3"
                          >
                            <div className="flex items-center justify-between mb-1">
                              <div className="flex items-center gap-2">
                                {isIncrease ? (
                                  <TrendingUp className="w-4 h-4 text-yellow-400" />
                                ) : isDecrease ? (
                                  <TrendingDown className="w-4 h-4 text-cyan-400" />
                                ) : (
                                  <Minus className="w-4 h-4 text-purple-400" />
                                )}
                                <span className="text-sm font-medium text-slate-200">
                                  {prevVal} → {newVal}
                                </span>
                              </div>
                              <span className="text-xs text-purple-300/50">
                                {formatRelativeTime(adj.created_at)}
                              </span>
                            </div>
                            <p className="text-xs text-purple-300/70 line-clamp-2">
                              {adj.reason}
                            </p>
                          </div>
                        )
                      })}
                    </div>
                  </div>
                )}

                {/* Explanation */}
                <p className="text-xs text-purple-100/50 italic">
                  Systemet analyserar temperaturövertramp och justerar automatiskt timmar och fördelning
                  varje söndag kl 03:00.
                </p>
              </div>
            )}
          </div>

          {/* Hours On Slider - LAST (less important with auto-tuning) */}
          <div className="pt-4 border-t border-purple-500/15">
            <label className="block text-sm font-semibold text-purple-200 uppercase tracking-wide mb-3">
              Antal timmar per dag (manuell)
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
            <p className="text-sm text-purple-100/90 mt-2">
              Väljer de {config.hoursOn} billigaste timmarna per dag
            </p>
            <p className="text-xs text-purple-100/50 mt-1 italic">
              OBS: Kan ändras av automatisk optimering
            </p>
          </div>

          {/* Error Display */}
          {error && (
            <div className="bg-red-900/20 border border-red-400/30 rounded-xl p-4">
              <p className="text-red-400 text-sm">{error}</p>
            </div>
          )}
        </div>

        {/* Footer - Match tenant form button style */}
        <div className="p-6 border-t border-purple-500/20">
          <div className="flex gap-3">
            <button
              onClick={handleCancel}
              disabled={isSaving}
              className="flex-1 px-4 py-2 text-lg font-medium text-white/70 rounded-xl transition-all button-cursor-glow button-glow-default button-hover-brighten disabled:opacity-50 disabled:cursor-not-allowed focus:outline-none focus:ring-2 focus:ring-purple-500/50"
              style={{
                backgroundImage: 'linear-gradient(180deg, rgba(41, 22, 64, 0.92) 0%, rgba(33, 15, 53, 0.92) 100%)'
              }}
            >
              Avbryt
            </button>
            <button
              onClick={handleSave}
              disabled={isSaving}
              className="flex-1 px-4 py-2 text-lg font-medium text-white rounded-xl transition-all button-cursor-glow button-glow-orange button-hover-brighten disabled:opacity-50 disabled:cursor-not-allowed focus:outline-none focus:ring-2 focus:ring-purple-500/50"
              style={{
                backgroundImage: 'linear-gradient(180deg, #cb6f38 0%, #903f14 100%)'
              }}
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

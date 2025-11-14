import React, { useMemo, useState, useEffect } from 'react'
import { useData } from '../context/DataContext'
import { Thermometer, Target, Droplets, Zap } from 'lucide-react'

interface ElectricityPriceSparklineProps {
  hours: Array<{ hour: number }>
  electricityPrices?: Array<{
    time_start: string
    time_end: string
    price_sek: number
    price_eur: number
  }>
}

const ElectricityPriceSparkline: React.FC<ElectricityPriceSparklineProps> = ({ hours, electricityPrices }) => {
  if (!electricityPrices || electricityPrices.length === 0) return null

  // Map hours to prices
  const priceData = useMemo(() => {
    return hours.map(hourData => {
      // Find matching price for this hour
      const priceEntry = electricityPrices.find(p => {
        const hour = new Date(p.time_start).getHours()
        return hour === hourData.hour
      })
      return {
        hour: hourData.hour,
        price: priceEntry ? priceEntry.price_sek : null
      }
    })
  }, [hours, electricityPrices])

  // Filter out null prices and get min/max for scaling
  const validPrices = priceData.filter(d => d.price !== null).map(d => d.price!)
  if (validPrices.length === 0) return null

  const minPrice = Math.min(...validPrices)
  const maxPrice = Math.max(...validPrices)
  const priceRange = maxPrice - minPrice

  // Generate SVG path
  const pathData = useMemo(() => {
    if (priceRange === 0) return '' // Flat line if all prices are the same

    const points = priceData.map((d, index) => {
      if (d.price === null) return null

      const x = (index / (priceData.length - 1)) * 100 // 0-100%
      const y = 100 - ((d.price - minPrice) / priceRange) * 80 // 20-100% (leave 20% margin at top)

      return `${x},${y}`
    }).filter(p => p !== null)

    if (points.length === 0) return ''

    return `M ${points.join(' L ')}`
  }, [priceData, minPrice, priceRange])

  if (!pathData) return null

  return (
    <svg
      className="absolute inset-0 w-full h-full pointer-events-none"
      viewBox="0 0 100 100"
      preserveAspectRatio="none"
      style={{
        zIndex: 5,
        clipPath: 'inset(0 round 0.5rem)' // Clip to match rounded-lg of parent container
      }}
    >
      <path
        d={pathData}
        fill="none"
        stroke="rgba(255, 255, 255, 0.1)"
        strokeWidth="2"
        vectorEffect="non-scaling-stroke"
      />
    </svg>
  )
}

export function TemperatureWidget() {
  const { state } = useData()
  const { temperatureData, connectionStatus } = state
  const [isStatusChanging, setIsStatusChanging] = useState(false)
  const [prevSmartStatus, setPrevSmartStatus] = useState('')

  // TESTING: Show comparison cursors (active + residual glows side by side)
  const showTestCursors = false

  // Smart status function for animation tracking
  const getSmartStatus = () => {
    if (!temperatureData) return ''

    const supplyTemp = parseFloat(temperatureData.supplyline_temperature?.replace('°', '') || '0')
    const isOn = !temperatureData.heatpump_disabled
    const hasDemand = temperatureData.heating_demand === 'JA'

    if (isOn && hasDemand && supplyTemp > 35) {
      return 'värmer aktivt'
    } else if (isOn && !hasDemand) {
      return 'lagom varmt'
    } else if (!isOn && hasDemand) {
      return 'ineffektiv drift'
    } else {
      return 'värmer ej'
    }
  }

  // Track status changes for animation
  const currentSmartStatus = getSmartStatus()
  useEffect(() => {
    if (currentSmartStatus && prevSmartStatus && currentSmartStatus !== prevSmartStatus) {
      setIsStatusChanging(true)
      const timer = setTimeout(() => setIsStatusChanging(false), 800) // Match animation duration
      setPrevSmartStatus(currentSmartStatus)
      return () => clearTimeout(timer)
    } else if (!prevSmartStatus) {
      // Initialize on first render
      setPrevSmartStatus(currentSmartStatus)
    }
  }, [currentSmartStatus])

  // Heatpump schedule progress bar logic using schedule_data
  const heatpumpSchedule = useMemo(() => {
    if (!temperatureData || !temperatureData.schedule_data) {
      return null
    }

    // Fixed time offset for Thermiq device (1 hour behind browser)
    // TODO: Remove when device clock is corrected
    const THERMIQ_TIME_OFFSET_HOURS = -1
    const browserTime = new Date()
    const now = new Date(browserTime.getTime() + (THERMIQ_TIME_OFFSET_HOURS * 60 * 60 * 1000))

    // Parse device timestamp for staleness detection
    let deviceTime = new Date()
    try {
      const [time, date] = [temperatureData.last_updated_time, temperatureData.last_updated_date]
      if (time && date) {
        const months = ['JAN', 'FEB', 'MAR', 'APR', 'MAJ', 'JUN', 'JUL', 'AUG', 'SEP', 'OKT', 'NOV', 'DEC']
        const [day, monthStr] = date.split(' ')
        const monthIndex = months.indexOf(monthStr.toUpperCase())
        const [hourStr, minuteStr] = time.split('.')

        if (monthIndex !== -1) {
          deviceTime = new Date()
          deviceTime.setMonth(monthIndex)
          deviceTime.setDate(parseInt(day))
          deviceTime.setHours(parseInt(hourStr))
          deviceTime.setMinutes(parseInt(minuteStr))
        }
      }
    } catch (e) {
      console.warn('Could not parse device timestamp:', e)
    }
    const currentHour = now.getHours()

    // Build hour-by-hour schedule from schedule_data
    const scheduleMap = new Map()

    const scheduleEntries = temperatureData.schedule_data

    scheduleEntries.forEach((period) => {
      const startTime = new Date(period.time)
      const countHours = period.countHours
      const isOn = period.value

      // Apply the same time offset to schedule data
      const adjustedStartTime = new Date(startTime.getTime() + (THERMIQ_TIME_OFFSET_HOURS * 60 * 60 * 1000))

      for (let i = 0; i < countHours; i++) {
        const hour = new Date(adjustedStartTime.getTime() + (i * 60 * 60 * 1000))
        // Use both date and hour for unique key to handle multi-day schedules
        const hourKey = `${hour.getFullYear()}-${hour.getMonth()}-${hour.getDate()}-${hour.getHours()}`
        scheduleMap.set(hourKey, isOn)
      }
    })

    // Dynamic timeline: cursor slides from left (morning) to right (evening)
    const currentMinutes = now.getMinutes()
    const hours = []

    // Calculate sliding window based on time of day
    let hoursBefore, hoursAfter
    if (currentHour >= 7 && currentHour <= 23) {
      // 7am-11pm: cursor gradually moves from index 3 to index 13
      const progressThroughDay = (currentHour - 7) / 16 // 0.0 at 7am, 1.0 at 11pm
      hoursBefore = 3 + Math.round(progressThroughDay * 10) // 3→13
      hoursAfter = 12 - Math.round(progressThroughDay * 10)  // 12→2
    } else {
      // Midnight-6am: reset to morning view (show future)
      hoursBefore = 3
      hoursAfter = 12
    }

    for (let i = -hoursBefore; i <= hoursAfter; i++) {
      const timelineHour = new Date(now.getTime() + (i * 60 * 60 * 1000))
      const hour = timelineHour.getHours()
      const isCurrentHour = i === 0

      // Create key with date info for proper lookup
      const hourKey = `${timelineHour.getFullYear()}-${timelineHour.getMonth()}-${timelineHour.getDate()}-${hour}`
      const isScheduledOn = scheduleMap.get(hourKey) || false
      // For current hour, use ACTUAL heatpump state instead of schedule prediction
      const actualState = isCurrentHour ? !temperatureData.heatpump_disabled : isScheduledOn

      hours.push({
        hour,
        isScheduledOn: actualState,
        isCurrentHour,
        displayHour: hour.toString().padStart(2, '0'),
        minuteProgress: isCurrentHour ? currentMinutes / 60 : 0
      })
    }

    // Check if data is stale (>2h old) - compare browser time vs device timestamp
    const hoursOld = (now.getTime() - deviceTime.getTime()) / (1000 * 60 * 60)
    const isStale = Math.abs(hoursOld) > 2 // Use absolute value to handle timezone issues

    // Check heating states based on supply line temperature
    const supplyTemp = parseFloat(temperatureData.supplyline_temperature?.replace('°', '') || '0')

    // OVERRIDE FOR TESTING - change this to true to test full glow
    const forceActiveHeating = false

    const isActivelyHeating = forceActiveHeating || (!temperatureData.heatpump_disabled &&
                              temperatureData.heating_demand === 'JA' &&
                              supplyTemp > 40)
    const hasHotSupplyLine = !forceActiveHeating && (!temperatureData.heatpump_disabled &&
                             temperatureData.heating_demand === 'NEJ' &&
                             supplyTemp > 40)

    return {
      hours,
      isStale,
      isActivelyHeating,
      hasHotSupplyLine
    }
  }, [temperatureData])

  // Early returns after all hooks are called
  const loading = connectionStatus === 'connecting' && !temperatureData
  const error = connectionStatus === 'closed' ? 'WebSocket-anslutning avbruten' : null

  if (loading) {
    return <div className="text-purple-200">Laddar...</div>
  }

  if (error) {
    return (
      <div>
        <div className="text-red-400">Fel: {error}</div>
      </div>
    )
  }

  if (!temperatureData) {
    return <div className="text-purple-200">Ingen data tillgänglig</div>
  }

  // Helper functions
  const getTemperatureIcon = () => <Thermometer className="w-6 h-6 text-purple-200" />
  const getTargetIcon = () => <Target className="w-6 h-6 text-purple-200" />
  const getHumidityIcon = () => <Droplets className="w-6 h-6 text-purple-200" />
  const getHotWaterIcon = () => <Zap className="w-6 h-6 text-purple-200" />

  const HeatpumpScheduleBar = () => {
    if (!heatpumpSchedule) return null

    const { hours, isStale, isActivelyHeating, hasHotSupplyLine } = heatpumpSchedule
    const barOpacity = isStale ? '40%' : '100%'

    // Use the smart status from parent component

    return (
      <div className="mt-10 mb-6">
        <div
          className={`text-purple-200 mb-2 heatpump-status ${isStatusChanging ? 'changing' : ''}`}
          style={{ textTransform: 'uppercase', fontSize: '0.8em' }}
        >
          {currentSmartStatus}{(isActivelyHeating || hasHotSupplyLine) && (
            <>
              <span style={{ opacity: 0.25, margin: '0 0.3em' }}>•</span>
              {temperatureData.supplyline_temperature} i elementen
            </>
          )}
        </div>
        <div
          className="relative h-5 rounded-lg overflow-visible"
          style={{
            opacity: barOpacity,
            background: 'rgba(170, 90, 255, 0.06)'
          }}
        >
          {/* Electricity price sparkline overlay */}
          <ElectricityPriceSparkline
            hours={hours}
            electricityPrices={state.electricityPriceData?.prices}
          />

          {/* TEST CURSORS: Toggle with showTestCursors variable */}
          {showTestCursors && (() => {
            const firstOnIndex = hours.findIndex(h => h.isScheduledOn && !h.isCurrentHour)
            if (firstOnIndex === -1) return null
            const position = (firstOnIndex / (hours.length - 1)) * 100
            return (
              <div
                className="absolute top-0 h-full z-10 rounded-sm schedule-cursor heating-active"
                style={{
                  width: '12px',
                  left: `${position}%`,
                  transform: 'translateX(-50%)',
                  opacity: '100%',
                  backgroundColor: '#ffaa88',
                  mixBlendMode: 'overlay'
                }}
              />
            )
          })()}

          {showTestCursors && (() => {
            // Find last transition to ON (last chunk start)
            let lastChunkStartIndex = -1
            for (let i = hours.length - 1; i >= 0; i--) {
              if (hours[i].isScheduledOn && !hours[i].isCurrentHour) {
                const prevIsOff = i === 0 || !hours[i-1].isScheduledOn
                if (prevIsOff) {
                  lastChunkStartIndex = i
                  break
                }
              }
            }
            if (lastChunkStartIndex === -1) return null
            const position = (lastChunkStartIndex / (hours.length - 1)) * 100
            return (
              <div
                className="absolute top-0 h-full z-10 rounded-sm schedule-cursor heating-residual"
                style={{
                  width: '12px',
                  left: `${position}%`,
                  transform: 'translateX(-50%)',
                  opacity: '100%',
                  backgroundColor: '#ffa684',
                  mixBlendMode: 'overlay'
                }}
              />
            )
          })()}

          {/* Single loop for all hour elements */}
          <div className="absolute inset-0 flex">
            {hours.map((hourData, index) => {
              const chunkOpacity = hourData.isScheduledOn ? '20%' : '5%'
              const isCurrentHour = hourData.isCurrentHour

              return (
                <div
                  key={`${hourData.hour}-${index}`}
                  className="flex-1 relative h-full"
                  style={{
                    marginRight: index < hours.length - 1 ? '2px' : '0'
                  }}
                >
                  {/* Background chunk */}
                  <div
                    className={`h-full ${index === 0 ? 'rounded-l-lg' : ''} ${index === hours.length - 1 ? 'rounded-r-lg' : ''}`}
                    style={{
                      backgroundColor: '#ffffff',
                      opacity: chunkOpacity,
                      mixBlendMode: 'overlay'
                    }}
                  />

                  {/* Time cursor - only for current hour */}
                  {isCurrentHour && (
                    <div
                      className={`absolute top-0 h-full z-10 rounded-sm schedule-cursor ${isActivelyHeating ? 'heating-active' : hasHotSupplyLine ? 'heating-residual' : ''}`}
                      style={{
                        width: '12px',
                        left: `${hourData.minuteProgress * 100}%`,
                        transform: 'translateX(-50%)',
                        opacity: '100%',
                        backgroundColor: isActivelyHeating ? '#ffaa88' : hasHotSupplyLine ? '#ffa684' : '#ffffff',
                        mixBlendMode: 'overlay',
                        // Only default state uses inline boxShadow - animations handle heating states
                        boxShadow: !isActivelyHeating && !hasHotSupplyLine
                          ? '0 0 8px rgba(255, 255, 255, 0.8), 0 0 16px rgba(255, 255, 255, 0.7), 0 0 32px rgba(255, 255, 255, 0.6), 0 0 64px rgba(255, 255, 255, 0.5), 0 0 96px rgba(255, 255, 255, 0.4), 0 0 128px rgba(255, 255, 255, 0.3), 0 0 192px rgba(255, 255, 255, 0.25), 0 0 256px rgba(255, 255, 255, 0.2), 0 0 320px rgba(255, 255, 255, 0.15)'
                          : undefined
                      }}
                    />
                  )}
                </div>
              )
            })}
          </div>
        </div>
      </div>
    )
  }

  return (
    <div>
      <HeatpumpScheduleBar />
      <div className="grid grid-cols-2 gap-3 mb-4">
        <div className="flex items-center">
          <div className="mr-2">
            {getTemperatureIcon()}
          </div>
          <div>
            <div className="text-3xl font-bold text-purple-100">{temperatureData.indoor_temperature}</div>
            <div className="text-purple-200" style={{ textTransform: 'uppercase', fontSize: '0.8em' }}>temperatur</div>
          </div>
        </div>

        <div className="flex items-center">
          <div className="mr-2">
            {getTargetIcon()}
          </div>
          <div>
            <div className="text-3xl font-bold text-purple-100">{temperatureData.target_temperature}</div>
            <div className="text-purple-200" style={{ textTransform: 'uppercase', fontSize: '0.8em' }}>mål</div>
          </div>
        </div>

        <div className="flex items-center">
          <div className="mr-2">
            {getHumidityIcon()}
          </div>
          <div>
            <div className="text-3xl font-bold text-purple-100">{temperatureData.indoor_humidity}</div>
            <div className="text-purple-200" style={{ textTransform: 'uppercase', fontSize: '0.8em' }}>luftfuktighet</div>
          </div>
        </div>

        <div className="flex items-center">
          <div className="mr-2">
            {getHotWaterIcon()}
          </div>
          <div>
            <div className="text-3xl font-bold text-purple-100">{temperatureData.hotwater_temperature}</div>
            <div className="text-purple-200" style={{ textTransform: 'uppercase', fontSize: '0.8em' }}>varmvatten</div>
          </div>
        </div>
      </div>
    </div>
  )
}

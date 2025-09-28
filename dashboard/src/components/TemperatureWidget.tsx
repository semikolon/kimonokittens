import React, { useMemo, useState, useEffect } from 'react'
import { useData } from '../context/DataContext'
import { Thermometer, Target, Droplets, Zap } from 'lucide-react'

export function TemperatureWidget() {
  const { state } = useData()
  const { temperatureData, connectionStatus } = state
  const [isStatusChanging, setIsStatusChanging] = useState(false)
  const [prevSmartStatus, setPrevSmartStatus] = useState('')

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
      return () => clearTimeout(timer)
    }
    setPrevSmartStatus(currentSmartStatus)
  }, [currentSmartStatus, prevSmartStatus])

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

    temperatureData.schedule_data.forEach(period => {
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

    // Create 16-hour timeline: prev 3 + current/next 12 hours
    const currentMinutes = now.getMinutes()
    const hours = []
    for (let i = -3; i <= 12; i++) {
      const timelineHour = new Date(now.getTime() + (i * 60 * 60 * 1000))
      const hour = timelineHour.getHours()
      const isCurrentHour = i === 0

      // Create key with date info for proper lookup
      const hourKey = `${timelineHour.getFullYear()}-${timelineHour.getMonth()}-${timelineHour.getDate()}-${hour}`
      const isScheduledOn = scheduleMap.get(hourKey) || false

      hours.push({
        hour,
        isScheduledOn,
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
          {currentSmartStatus}
        </div>
        <div
          className="relative h-5 rounded-lg overflow-visible"
          style={{
            opacity: barOpacity,
            background: 'rgba(255, 255, 255, 0.1)',
            mixBlendMode: 'overlay'
          }}
        >
          {/* Single loop for all hour elements */}
          <div className="absolute inset-0 flex">
            {hours.map((hourData, index) => {
              const chunkOpacity = hourData.isScheduledOn ? '30%' : '5%'
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
                      className={`absolute top-0 h-full z-10 rounded-sm schedule-cursor ${isActivelyHeating ? 'heating-active' : ''}`}
                      style={{
                        width: '12px',
                        left: `${hourData.minuteProgress * 100}%`,
                        transform: 'translateX(-50%)',
                        opacity: isActivelyHeating ? '100%' : '80%',
                        backgroundColor: isActivelyHeating || hasHotSupplyLine ? '#ffcc99' : '#ffffff',
                        boxShadow: isActivelyHeating
                          ? '0 0 16px rgba(255, 40, 0, 4), 0 0 32px rgba(255, 60, 0, 3.5), 0 0 48px rgba(255, 80, 0, 3), 0 0 64px rgba(255, 100, 0, 2.5), 0 0 96px rgba(255, 120, 0, 2), 0 0 128px rgba(255, 140, 0, 1.5), 0 0 160px rgba(255, 160, 0, 1)'
                          : hasHotSupplyLine
                          ? '0 0 12px rgba(255, 60, 0, 2.5), 0 0 24px rgba(255, 80, 0, 2), 0 0 36px rgba(255, 100, 0, 1.5), 0 0 48px rgba(255, 120, 0, 1.2), 0 0 72px rgba(255, 140, 0, 0.8), 0 0 96px rgba(255, 160, 0, 0.6), 0 0 120px rgba(255, 180, 0, 0.4)'
                          : '0 0 12px rgba(255, 255, 255, 0.8), 0 0 24px rgba(255, 255, 255, 0.5), 0 0 36px rgba(255, 255, 255, 0.3)'
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

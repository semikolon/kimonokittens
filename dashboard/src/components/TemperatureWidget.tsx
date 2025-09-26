import React, { useMemo } from 'react'
import { useData } from '../context/DataContext'
import { Thermometer, Target, Droplets, Zap } from 'lucide-react'

export function TemperatureWidget() {
  const { state } = useData()
  const { temperatureData, connectionStatus } = state

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

  const getTemperatureIcon = () => <Thermometer className="w-6 h-6 text-purple-200" />
  const getTargetIcon = () => <Target className="w-6 h-6 text-purple-200" />
  const getHumidityIcon = () => <Droplets className="w-6 h-6 text-purple-200" />
  const getHotWaterIcon = () => <Zap className="w-6 h-6 text-purple-200" />

  // Heatpump schedule progress bar logic
  const heatpumpSchedule = useMemo(() => {
    if (!temperatureData || !temperatureData.current_schedule) {
      return null
    }

    const now = new Date()
    const currentHour = now.getHours()

    // Parse schedule (e.g., "11-17" means 11:00 to 17:00)
    const scheduleMatch = temperatureData.current_schedule.match(/(\d+)-(\d+)/)
    if (!scheduleMatch) return null

    const scheduleStart = parseInt(scheduleMatch[1])
    const scheduleEnd = parseInt(scheduleMatch[2])

    // Create 12-hour timeline: prev 3 + current/next 9 hours
    const currentMinutes = now.getMinutes()
    const hours = []
    for (let i = -3; i <= 8; i++) {
      const hour = (currentHour + i + 24) % 24
      const isScheduledOn = hour >= scheduleStart && hour <= scheduleEnd
      const isCurrentHour = i === 0

      hours.push({
        hour,
        isScheduledOn,
        isCurrentHour,
        displayHour: hour.toString().padStart(2, '0'),
        minuteProgress: isCurrentHour ? currentMinutes / 60 : 0
      })
    }

    // Check if data is stale (>2h old)
    let isStale = false
    try {
      const [time, date] = [temperatureData.last_updated_time, temperatureData.last_updated_date]
      if (time && date) {
        // Parse Swedish date format "9 JUL" and time "14.12"
        const months = ['JAN', 'FEB', 'MAR', 'APR', 'MAJ', 'JUN', 'JUL', 'AUG', 'SEP', 'OKT', 'NOV', 'DEC']
        const [day, monthStr] = date.split(' ')
        const monthIndex = months.indexOf(monthStr.toUpperCase())
        const [hourStr, minuteStr] = time.split('.')

        if (monthIndex !== -1) {
          const lastUpdate = new Date()
          lastUpdate.setMonth(monthIndex)
          lastUpdate.setDate(parseInt(day))
          lastUpdate.setHours(parseInt(hourStr))
          lastUpdate.setMinutes(parseInt(minuteStr))

          const hoursOld = (now.getTime() - lastUpdate.getTime()) / (1000 * 60 * 60)
          isStale = hoursOld > 2
        }
      }
    } catch (e) {
      console.warn('Could not parse last_updated timestamp:', e)
    }

    // Check if actively heating (on + demand + supply temp > 40°C)
    const supplyTemp = parseFloat(temperatureData.supplyline_temperature?.replace('°', '') || '0')
    const isActivelyHeating = !temperatureData.heatpump_disabled &&
                              temperatureData.heating_demand === 'JA' &&
                              supplyTemp > 40

    return {
      hours,
      isStale,
      isActivelyHeating
    }
  }, [temperatureData])

  const HeatpumpScheduleBar = () => {
    if (!heatpumpSchedule) return null

    const { hours, isStale, isActivelyHeating } = heatpumpSchedule
    const barOpacity = isStale ? '40%' : '100%'

    // Smart status consolidation
    const getSmartStatus = () => {
      const supplyTemp = parseFloat(temperatureData.supplyline_temperature?.replace('°', '') || '0')
      const isOn = !temperatureData.heatpump_disabled
      const hasDemand = temperatureData.heating_demand === 'JA'

      if (isOn && hasDemand && supplyTemp > 40) {
        return 'värmer aktivt'
      } else if (isOn && !hasDemand) {
        return 'standby'
      } else if (!isOn && hasDemand) {
        return 'ineffektiv drift'
      } else {
        return 'värmer ej'
      }
    }

    return (
      <div className="mb-6">
        <div className="text-purple-200 mb-1" style={{ textTransform: 'uppercase', fontSize: '0.8em' }}>
          {getSmartStatus()}
        </div>
        <div
          className="relative h-4 rounded-sm overflow-hidden"
          style={{ opacity: barOpacity }}
        >
          <div className="flex h-full">
            {hours.map((hourData, index) => {
              const chunkOpacity = hourData.isScheduledOn ? '90%' : '30%'
              const isCurrentHour = hourData.isCurrentHour

              return (
                <div
                  key={`${hourData.hour}-${index}`}
                  className="flex-1 relative"
                  style={{
                    marginRight: index < hours.length - 1 ? '2px' : '0'
                  }}
                >
                  <div
                    className={`h-full bg-white ${isCurrentHour && isActivelyHeating ? 'shadow-orange-400' : ''}`}
                    style={{
                      opacity: chunkOpacity,
                      mixBlendMode: 'overlay',
                      boxShadow: isCurrentHour && isActivelyHeating ? '0 0 8px orange' : 'none'
                    }}
                  />
                  {isCurrentHour && (
                    <div
                      className="absolute top-0 h-full bg-white z-10"
                      style={{
                        width: '5px',
                        left: `${hourData.minuteProgress * 100}%`,
                        transform: 'translateX(-50%)',
                        opacity: '90%'
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
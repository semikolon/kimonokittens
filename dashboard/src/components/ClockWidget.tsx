import React, { useState, useEffect } from 'react'
import { WidgetContainer } from './shared/WidgetContainer'
import { formatSwedishTime, formatSwedishDate, getGreeting } from '../utils/formatters'
import { neonTheme } from '../utils/theme'

export function ClockWidget() {
  const [time, setTime] = useState(new Date())

  useEffect(() => {
    const timer = setInterval(() => {
      setTime(new Date())
    }, 1000)

    return () => clearInterval(timer)
  }, [])

  return (
    <WidgetContainer title="Tid" variant="hero">
      <div className="text-7xl font-bold mb-3 font-sans tracking-tight text-center">
        {formatSwedishTime(time)}
      </div>
      <div className={`text-xl ${neonTheme.text.secondary} mb-2 capitalize text-center`}>
        {formatSwedishDate(time)}
      </div>
      <div className={`text-base ${neonTheme.text.accent} italic text-center`}>
        {getGreeting(time.getHours())} 🌸
      </div>
    </WidgetContainer>
  )
} 
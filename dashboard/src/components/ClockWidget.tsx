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
    <div className="flex items-center justify-between">
      <div className="flex-1">
        <div className="text-7xl font-bold mb-3 font-sans tracking-tight text-center text-purple-100">
          {formatSwedishTime(time)}
        </div>
        <div className={`text-xl ${neonTheme.text.secondary} mb-2 capitalize text-center`}>
          {formatSwedishDate(time)}
        </div>
      </div>
      <div className="flex-shrink-0 ml-8">
        <img
          src="/logo.png"
          alt="Kimonokittens"
          className="w-32 h-32 object-contain"
        />
      </div>
    </div>
  )
} 
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
    <div className="flex items-center gap-4 overflow-visible max-w-full relative">
      <div className="flex-1 min-w-0">
        <div className="text-[14.4rem] mb-24 font-[Horsemen] tracking-wide text-center text-purple-600 leading-[1.1] overflow-visible py-4">
          {formatSwedishTime(time)}
        </div>
        <div className={`text-2xl ${neonTheme.text.secondary} mb-2 capitalize text-center`}>
          {formatSwedishDate(time)}
        </div>
      </div>
      <div className="flex-shrink-0 w-1/2 max-w-full relative">
        <img
          src="/logo.png"
          alt="Kimonokittens"
          className="w-full h-auto object-contain block max-w-full transform translate-x-20"
        />
      </div>
    </div>
  )
} 
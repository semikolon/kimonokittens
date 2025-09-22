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
    <div className="flex items-start gap-4 overflow-visible max-w-full relative" style={{ minHeight: '110px' }}>
      <div className="flex-1 min-w-0 relative">
        {/* Time text positioned at very top of page */}
        <div className="relative overflow-visible" style={{ marginTop: '-65px', marginLeft: '-30px', height: '180px' }}>
          <svg className="absolute inset-0 overflow-visible" style={{ width: '600px', height: '180px', zIndex: 1 }}>
            <defs>
              <linearGradient id="timeGradient" x1="0%" y1="0%" x2="94%" y2="34%" gradientUnits="objectBoundingBox">
                <stop offset="0%" stopColor="#8b5cf6" />
                <stop offset="100%" stopColor="#a855f7" />
              </linearGradient>
            </defs>
            <text
              x="0"
              y="90"
              textAnchor="start"
              dominantBaseline="middle"
              fill="url(#timeGradient)"
              className="font-[Horsemen] tracking-wide"
              style={{ fontSize: '13.7rem', lineHeight: '1.1' }}
            >
              {formatSwedishTime(time)}
            </text>
          </svg>
        </div>

        {/* Date text with proper spacing below time */}
        <div className={`text-2xl ${neonTheme.text.secondary} capitalize text-center`} style={{ marginTop: '280px', marginLeft: '-50px' }}>
          {formatSwedishDate(time)}
        </div>
      </div>

      {/* Logo positioned within widget boundaries */}
      <div className="flex-shrink-0 w-1/2 max-w-full flex items-end justify-end relative" style={{ zIndex: 10, marginTop: '260px' }}>
        <img
          src="/logo.png"
          alt="Kimonokittens"
          className="w-full h-auto object-contain transform translate-x-12 translate-y-300"
          style={{ zIndex: 10 }}
        />
      </div>
    </div>
  )
} 
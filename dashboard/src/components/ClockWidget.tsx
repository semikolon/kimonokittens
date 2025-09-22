import React, { useState, useEffect } from 'react'
import { WidgetContainer } from './shared/WidgetContainer'
import { formatSwedishTime, formatSwedishDate, getGreeting } from '../utils/formatters'
import { neonTheme } from '../utils/theme'

export function ClockWidget() {
  const [time, setTime] = useState(new Date())
  const [isSimulating, setIsSimulating] = useState(false)
  const [simulationTime, setSimulationTime] = useState(new Date())

  useEffect(() => {
    if (isSimulating) {
      // Simulation mode: advance 10 minutes every 200ms (10 min in 2 seconds)
      const timer = setInterval(() => {
        setSimulationTime(prev => {
          const newTime = new Date(prev)
          newTime.setMinutes(newTime.getMinutes() + 10)
          return newTime
        })
      }, 200)

      return () => clearInterval(timer)
    } else {
      // Normal mode: update every second
      const timer = setInterval(() => {
        setTime(new Date())
      }, 1000)

      return () => clearInterval(timer)
    }
  }, [isSimulating])

  const displayTime = isSimulating ? simulationTime : time

  const toggleSimulation = () => {
    if (!isSimulating) {
      setSimulationTime(new Date()) // Reset simulation to current time
    }
    setIsSimulating(!isSimulating)
  }

  return (
    <div className="flex items-start gap-4 overflow-visible max-w-full relative" style={{ minHeight: '40px' }}>
      <div className="flex-1 min-w-0 relative">
        {/* Time text positioned at very top of page */}
        <div className="relative overflow-visible" style={{ marginTop: '-60px', marginLeft: '-2px', height: '200px' }}>
          <svg className="absolute inset-0 overflow-visible" style={{ width: '600px', height: '200px', zIndex: 1 }}>
            <defs>
              <linearGradient id="hoursGradient" x1="0%" y1="0%" x2="94%" y2="34%" gradientUnits="objectBoundingBox">
                <stop offset="0%" stopColor="#8b5cf6" />
                <stop offset="100%" stopColor="#8824c7" />
              </linearGradient>
              <linearGradient id="minutesGradient" x1="0%" y1="0%" x2="94%" y2="34%" gradientUnits="objectBoundingBox">
                <stop offset="0%" stopColor="#8b5cf6" />
                <stop offset="100%" stopColor="#451a8b" />
              </linearGradient>
              <linearGradient id="colonGradient" x1="0%" y1="0%" x2="94%" y2="34%" gradientUnits="objectBoundingBox">
                <stop offset="0%" stopColor="#7c3aed" stopOpacity="0.4" />
                <stop offset="100%" stopColor="#5b21b6" stopOpacity="0.4" />
              </linearGradient>
            </defs>
            <text
              x="0"
              y="90"
              textAnchor="start"
              dominantBaseline="middle"
              className="font-[Horsemen] tracking-wide"
              style={{ fontSize: '14rem', lineHeight: '1.1' }}
            >
              <tspan fill="url(#hoursGradient)">{displayTime.getHours().toString().padStart(2, '0')}</tspan>
              <tspan fill="url(#colonGradient)">:</tspan>
              <tspan fill="url(#minutesGradient)">{displayTime.getMinutes().toString().padStart(2, '0')}</tspan>
            </text>
          </svg>
        </div>

        {/* Date text with proper spacing below time */}
        <div className={`text-2xl ${neonTheme.text.secondary} capitalize`} style={{ marginTop: '290px'}}>
          {formatSwedishDate(displayTime)}
        </div>

        <p style={{ fontWeight: 'bold', marginTop: '14px' }}>Lägga upp annons är prio!</p>

        {/* Time simulation toggle button */}
        <button
          onClick={toggleSimulation}
          className={`mt-4 px-4 py-2 text-sm rounded-lg font-medium transition-colors ${
            isSimulating
              ? 'bg-purple-600 text-white hover:bg-purple-700'
              : 'bg-purple-200 text-purple-800 hover:bg-purple-300'
          }`}
        >
          {isSimulating ? 'Stop Time Simulation' : 'Start Time Simulation'}
        </button>
      </div>

      {/* Logo positioned within widget boundaries */}
      <div className="flex-shrink-0 w-3/5 max-w-full flex items-end justify-end relative" style={{ zIndex: 10, marginTop: '300px' }}>
        <img
          src="/logo.png"
          alt="Kimonokittens"
          className="w-full h-auto object-contain transform translate-x-20 translate-y-16"
          style={{ zIndex: 10 }}
        />
      </div>
    </div>
  )
}

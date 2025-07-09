import React, { useState, useEffect } from 'react'

export function ClockWidget() {
  const [time, setTime] = useState(new Date())

  useEffect(() => {
    const timer = setInterval(() => {
      setTime(new Date())
    }, 1000)

    return () => clearInterval(timer)
  }, [])

  const formatTime = (date: Date) => {
    return date.toLocaleTimeString('sv-SE', {
      hour: '2-digit',
      minute: '2-digit',
      second: '2-digit'
    })
  }

  const formatDate = (date: Date) => {
    return date.toLocaleDateString('sv-SE', {
      weekday: 'long',
      year: 'numeric',
      month: 'long',
      day: 'numeric'
    })
  }

  const getGreeting = () => {
    const hour = time.getHours()
    if (hour < 6) return 'God natt'
    if (hour < 12) return 'God morgon'
    if (hour < 17) return 'God dag'
    if (hour < 22) return 'God kväll'
    return 'God natt'
  }

  return (
    <div className="widget">
      <div className="widget-title">Tid</div>
      <div className="widget-content">
        <div className="text-6xl font-bold mb-2 font-mono tracking-tight">
          {formatTime(time)}
        </div>
        <div className="text-lg text-gray-300 mb-3 capitalize">
          {formatDate(time)}
        </div>
        <div className="text-sm text-gray-400 italic">
          {getGreeting()} 🌸
        </div>
      </div>
    </div>
  )
} 
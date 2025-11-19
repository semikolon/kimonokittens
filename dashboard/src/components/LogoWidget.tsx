import { useState, useEffect } from 'react'

export function LogoWidget() {
  const [offset, setOffset] = useState({ x: 0, y: 0 })

  useEffect(() => {
    // Prevent LCD burn-in: shift logo by 2-4px every 15 minutes
    const interval = setInterval(() => {
      const randomOffset = () => Math.floor(Math.random() * 5) - 2 // -2 to +2 pixels
      setOffset({ x: randomOffset(), y: randomOffset() })
    }, 15 * 60 * 1000) // 15 minutes

    return () => clearInterval(interval)
  }, [])

  return (
    <img
      src="/logo.png"
      alt="Kimonokittens"
      className="w-full h-full object-contain max-w-none transition-transform duration-1000"
      style={{ transform: `translate(${offset.x}px, ${offset.y}px)` }}
    />
  )
} 

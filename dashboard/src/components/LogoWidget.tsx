import { useState, useEffect } from 'react'

export function LogoWidget() {
  const [offset, setOffset] = useState({ x: 0, y: 0 })

  useEffect(() => {
    // Prevent LCD burn-in: shift logo by 25-40px every 15 minutes
    // Larger shifts clear bright orange outlines (30-50px wide) to prevent image persistence
    const interval = setInterval(() => {
      const randomOffset = () => Math.floor(Math.random() * 16) + 25 // 25 to 40 pixels
      setOffset({ x: randomOffset(), y: randomOffset() })
    }, 15 * 60 * 1000) // 15 minutes

    return () => clearInterval(interval)
  }, [])

  return (
    <img
      src="/logo.png"
      alt="Kimonokittens"
      className="w-full h-full object-contain max-w-none transition-transform duration-2000 ease-in-out"
      style={{ transform: `translate(${offset.x}px, ${offset.y}px)` }}
    />
  )
} 

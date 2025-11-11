// useKeyboardNav - Global keyboard navigation (Tab + ESC)
import { useState, useEffect } from 'react'

type ViewMode = 'public' | 'admin'

export const useKeyboardNav = () => {
  const [viewMode, setViewMode] = useState<ViewMode>('public')

  useEffect(() => {
    const handleKeyDown = (e: KeyboardEvent) => {
      // Tab key: toggle between public and admin view
      if (e.key === 'Tab' && !e.shiftKey && !e.ctrlKey && !e.metaKey) {
        e.preventDefault()
        setViewMode(prev => prev === 'public' ? 'admin' : 'public')
      }

      // ESC key: return to public view
      if (e.key === 'Escape') {
        setViewMode('public')
      }
    }

    window.addEventListener('keydown', handleKeyDown)
    return () => window.removeEventListener('keydown', handleKeyDown)
  }, [])

  return { viewMode, setViewMode }
}

// useKeyboardNav - Global keyboard navigation (Tab + ESC) with URL routing
import { useState, useEffect } from 'react'

type ViewMode = 'public' | 'admin'

export const useKeyboardNav = () => {
  // Initialize from URL: /admin → admin view, otherwise public view
  const [viewMode, setViewMode] = useState<ViewMode>(() => {
    return window.location.pathname === '/admin' ? 'admin' : 'public'
  })

  // Update view mode and sync URL
  const updateViewMode = (newMode: ViewMode) => {
    setViewMode(newMode)
    const newPath = newMode === 'admin' ? '/admin' : '/'
    window.history.pushState({ viewMode: newMode }, '', newPath)
  }

  useEffect(() => {
    const handleKeyDown = (e: KeyboardEvent) => {
      // Tab key: toggle between public and admin view
      if (e.key === 'Tab' && !e.shiftKey && !e.ctrlKey && !e.metaKey) {
        e.preventDefault()
        updateViewMode(viewMode === 'public' ? 'admin' : 'public')
      }

      // ESC key: return to public view
      if (e.key === 'Escape') {
        updateViewMode('public')
      }
    }

    // Handle browser back/forward buttons
    const handlePopState = () => {
      const newMode = window.location.pathname === '/admin' ? 'admin' : 'public'
      setViewMode(newMode)
    }

    window.addEventListener('keydown', handleKeyDown)
    window.addEventListener('popstate', handlePopState)

    return () => {
      window.removeEventListener('keydown', handleKeyDown)
      window.removeEventListener('popstate', handlePopState)
    }
  }, [viewMode])

  return { viewMode, setViewMode }
}

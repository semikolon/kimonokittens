import React, { useState, useEffect } from 'react'

interface CalendarEvent {
  id: string
  title: string
  start: Date
  end: Date
  allDay?: boolean
  location?: string
}

export function CalendarWidget() {
  const [events, setEvents] = useState<CalendarEvent[]>([])
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)

  // Mock data for demonstration
  const mockEvents: CalendarEvent[] = [
    {
      id: '1',
      title: 'Kollektivmöte',
      start: new Date(2025, 6, 10, 19, 0),
      end: new Date(2025, 6, 10, 20, 30),
      location: 'Köket'
    },
    {
      id: '2',
      title: 'Städdag',
      start: new Date(2025, 6, 12, 10, 0),
      end: new Date(2025, 6, 12, 12, 0),
      allDay: false
    },
    {
      id: '3',
      title: 'Fest på Noden',
      start: new Date(2025, 6, 13, 20, 0),
      end: new Date(2025, 6, 13, 23, 59),
      location: 'Noden'
    },
  ]

  useEffect(() => {
    // For now, use mock data
    // TODO: Replace with actual Google Calendar API call when API key is available
    setEvents(mockEvents)
  }, [])

  const formatEventTime = (start: Date, end: Date, allDay?: boolean) => {
    if (allDay) return 'Heldag'
    
    const startTime = start.toLocaleTimeString('sv-SE', { 
      hour: '2-digit', 
      minute: '2-digit' 
    })
    const endTime = end.toLocaleTimeString('sv-SE', { 
      hour: '2-digit', 
      minute: '2-digit' 
    })
    
    return `${startTime} - ${endTime}`
  }

  const formatEventDate = (date: Date) => {
    const today = new Date()
    const tomorrow = new Date(today)
    tomorrow.setDate(today.getDate() + 1)
    
    if (date.toDateString() === today.toDateString()) {
      return 'Idag'
    } else if (date.toDateString() === tomorrow.toDateString()) {
      return 'Imorgon'
    } else {
      return date.toLocaleDateString('sv-SE', { 
        weekday: 'short', 
        month: 'short', 
        day: 'numeric' 
      })
    }
  }

  const getEventIcon = (title: string) => {
    const titleLower = title.toLowerCase()
    if (titleLower.includes('möte')) return '🤝'
    if (titleLower.includes('städ')) return '🧹'
    if (titleLower.includes('fest') || titleLower.includes('party')) return '🎉'
    if (titleLower.includes('mat') || titleLower.includes('middag')) return '🍽️'
    if (titleLower.includes('träning') || titleLower.includes('sport')) return '🏃‍♂️'
    return '📅'
  }

  // Sort events by start time and filter upcoming events
  const upcomingEvents = events
    .filter(event => event.start >= new Date())
    .sort((a, b) => a.start.getTime() - b.start.getTime())
    .slice(0, 4)

  return (
    <div className="widget">
      <div className="widget-title">Kalendar</div>
      <div className="widget-content">
        {upcomingEvents.length === 0 ? (
          <div className="text-center text-purple-300 py-4">
            <div className="text-2xl mb-2">🗓️</div>
            <div className="text-sm">Inga kommande händelser</div>
          </div>
        ) : (
          <div className="space-y-3">
            {upcomingEvents.map((event) => (
              <div key={event.id} className="p-3 rounded bg-gray-800/30 border-l-2 border-blue-400">
                <div className="flex items-start space-x-2">
                  <span className="text-lg mt-0.5">{getEventIcon(event.title)}</span>
                  <div className="flex-1 min-w-0">
                    <div className="text-sm font-medium truncate">{event.title}</div>
                    <div className="text-xs text-purple-200 mt-1">
                      {formatEventDate(event.start)}
                    </div>
                    <div className="text-xs text-purple-200">
                      {formatEventTime(event.start, event.end, event.allDay)}
                    </div>
                    {event.location && (
                      <div className="text-xs text-purple-300 mt-1">
                        📍 {event.location}
                      </div>
                    )}
                  </div>
                </div>
              </div>
            ))}
          </div>
        )}

        <div className="mt-4 text-xs text-purple-200 text-center">
          <div className="bg-yellow-400/10 text-yellow-400 px-2 py-1 rounded">
            📅 Google Calendar API kommer snart
          </div>
        </div>
      </div>
    </div>
  )
} 
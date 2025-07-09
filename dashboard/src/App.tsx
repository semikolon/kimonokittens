import React, { useEffect } from 'react'
import useWebSocket from 'react-use-websocket'
import { ClockWidget } from './components/ClockWidget'
import { LogoWidget } from './components/LogoWidget'
import { WeatherWidget } from './components/WeatherWidget'
import { TemperatureWidget } from './components/TemperatureWidget'
import { TrainWidget } from './components/TrainWidget'
import { StravaWidget } from './components/StravaWidget'
import { TodoWidget } from './components/TodoWidget'
import { CalendarWidget } from './components/CalendarWidget'

function App() {
  // WebSocket connection for real-time updates
  const socketUrl = `/dashboard/ws`

  const { lastMessage, sendMessage } = useWebSocket(socketUrl, {
    onOpen: () => {
      console.log('Dashboard WebSocket connection established.')
      sendMessage('Hello Dashboard Server!')
    },
    onClose: () => console.log('Dashboard WebSocket connection closed.'),
    shouldReconnect: (closeEvent) => true,
  })

  // Effect to handle incoming messages
  useEffect(() => {
    if (lastMessage !== null) {
      console.log('Received WebSocket message:', lastMessage.data)
      if (lastMessage.data === 'data_updated' || lastMessage.data === 'dashboard_refresh') {
        console.log('Dashboard data updated on server. Refreshing widgets...')
        // In the future, we could trigger specific widget refreshes here
        // For now, we'll let the individual widgets handle their own polling
      }
    }
  }, [lastMessage])

  return (
    <div className="dashboard-grid">
      {/* Left Column - "At a Glance" */}
      <div className="flex flex-col space-y-8">
        <ClockWidget />
        <WeatherWidget />
        <TrainWidget />
        <TemperatureWidget />
      </div>

      {/* Center Column - "The Vibe" */}
      <div className="flex flex-col items-center justify-center">
        <LogoWidget />
      </div>

      {/* Right Column - "Our Life" */}
      <div className="flex flex-col space-y-8">
        <TodoWidget />
        <CalendarWidget />
        <StravaWidget />
      </div>
    </div>
  )
}

export default App

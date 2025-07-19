import React from 'react'
import { DataProvider, useData } from './context/DataContext'
import { ClockWidget } from './components/ClockWidget'
import { LogoWidget } from './components/LogoWidget'
import { WeatherWidget } from './components/WeatherWidget'
import { TemperatureWidget } from './components/TemperatureWidget'
import { TrainWidget } from './components/TrainWidget'
import { StravaWidget } from './components/StravaWidget'
import { TodoWidget } from './components/TodoWidget'
import { CalendarWidget } from './components/CalendarWidget'

function ConnectionStatus() {
  const { state } = useData()
  const { connectionStatus } = state

  const getStatusColor = () => {
    switch (connectionStatus) {
      case 'open': return 'bg-green-500'
      case 'connecting': return 'bg-yellow-500'
      case 'closed': return 'bg-red-500'
      default: return 'bg-gray-500'
    }
  }

  const getStatusText = () => {
    switch (connectionStatus) {
      case 'open': return 'Ansluten'
      case 'connecting': return 'Ansluter...'
      case 'closed': return 'Frånkopplad'
      default: return 'Okänd status'
    }
  }

  return (
    <div className="fixed top-4 right-4 flex items-center space-x-2 text-xs z-50">
      <div className={`w-2 h-2 rounded-full ${getStatusColor()}`}></div>
      <span className="text-gray-400">{getStatusText()}</span>
    </div>
  )
}

function DashboardContent() {
  return (
    <>
      <ConnectionStatus />
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
    </>
  )
}

function App() {
  return (
    <DataProvider>
      <DashboardContent />
    </DataProvider>
  )
}

export default App

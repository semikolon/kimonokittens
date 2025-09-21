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
      case 'connecting': return 'bg-yellow-500 animate-pulse'
      case 'closed': return 'bg-red-500'
      default: return 'bg-gray-500'
    }
  }

  const getStatusText = () => {
    switch (connectionStatus) {
      case 'open': return 'Ansluten'
      case 'connecting': return 'Återansluter...'
      case 'closed': return 'Återansluter automatiskt...'
      default: return 'Okänd status'
    }
  }

  return (
    <div className="fixed top-5 right-5 flex items-center space-x-3 text-sm z-50 backdrop-blur-sm bg-black/20 px-3 py-2 rounded-full border border-fuchsia-300/20">
      <div className={`w-3 h-3 rounded-full ${getStatusColor()}`}></div>
      <span className="text-purple-200 font-medium">{getStatusText()}</span>
    </div>
  )
}

function DashboardContent() {
  return (
    <>
      <ConnectionStatus />

      {/* Background decorations */}
      <div className="cyber-bg"></div>
      <div className="grid-overlay"></div>

      {/* Natural Flow Dashboard Grid */}
      <div className="dashboard-grid">
        {/* Hero clock - will auto-size */}
        <div className="widget-hero-size">
          <ClockWidget />
        </div>

        {/* Weather widget */}
        <div className="widget-standard-size">
          <WeatherWidget />
        </div>

        {/* Transport widget */}
        <div className="widget-wide-size">
          <TrainWidget />
        </div>

        {/* Strava widget */}
        <div className="widget-standard-size">
          <StravaWidget />
        </div>

        {/* Temperature widget */}
        <div className="widget-standard-size">
          <TemperatureWidget />
        </div>


        {/* Logo widget */}
        <div className="widget-small-size">
          <LogoWidget />
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

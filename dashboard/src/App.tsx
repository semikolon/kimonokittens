import React from 'react'
import { DataProvider } from './context/DataContext'
import { ClockWidget } from './components/ClockWidget'
import { LogoWidget } from './components/LogoWidget'
import { WeatherWidget } from './components/WeatherWidget'
import { TemperatureWidget } from './components/TemperatureWidget'
import { TrainWidget } from './components/TrainWidget'
import { StravaWidget } from './components/StravaWidget'
import { TodoWidget } from './components/TodoWidget'
import { CalendarWidget } from './components/CalendarWidget'

function App() {

  return (
    <DataProvider>
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
    </DataProvider>
  )
}

export default App

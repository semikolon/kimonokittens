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
import { Wifi, WifiOff } from 'lucide-react'

// Refined widget component with organic, magazine-style design
const Widget = ({
  children,
  title,
  className = "",
  accent = false,
  large = false,
  horsemenFont = false
}: {
  children: React.ReactNode,
  title?: string,
  className?: string,
  accent?: boolean,
  large?: boolean,
  horsemenFont?: boolean
}) => {
  return (
    <div
      className={`overflow-hidden backdrop-blur-sm ${accent ? 'bg-purple-900/30' : 'bg-slate-900/40'}
      rounded-2xl shadow-md border border-purple-900/10 ${className}`}
    >
      <div className={`p-6 ${large ? 'p-8' : ''}`}>
        {title && (
          <h3 className={`text-sm font-medium ${accent ? 'text-purple-200' : 'text-purple-100'}
          mb-4 tracking-wide uppercase ${horsemenFont ? 'font-[Horsemen]' : ''}`}>
            {title}
          </h3>
        )}
        <div>{children}</div>
      </div>
    </div>
  )
}

function ConnectionStatus() {
  const { state } = useData()
  const { connectionStatus } = state

  const getStatusIcon = () => {
    switch (connectionStatus) {
      case 'open': return <Wifi className="h-4 w-4 text-emerald-500" />
      case 'connecting': return <Wifi className="h-4 w-4 text-amber-500 animate-pulse" />
      case 'closed': return <WifiOff className="h-4 w-4 text-rose-500" />
      default: return <WifiOff className="h-4 w-4 text-gray-400" />
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
    <div className="fixed top-6 right-6 flex items-center space-x-3 text-xs z-50 backdrop-blur-md bg-slate-900/60 px-4 py-2 rounded-full shadow-sm border border-purple-800/30">
      {getStatusIcon()}
      <span className="text-purple-100 font-medium tracking-wide">{getStatusText()}</span>
    </div>
  )
}

function DashboardContent() {
  return (
    <div className="min-h-screen bg-black">
      <ConnectionStatus />

      {/* Dark purple overlay */}
      <div className="absolute inset-0 bg-gradient-to-br from-purple-950/[0.04] via-purple-950/[0.06] to-purple-950/[0.08] pointer-events-none" />


      {/* Main content */}
      <div className="container mx-auto px-6 py-12">

        {/* Featured section - Full width Clock with integrated logo */}
        <div className="mb-12">
          <Widget large={true} accent={true} className="min-h-[220px] w-full">
            <ClockWidget />
          </Widget>
        </div>

        {/* Secondary content in organic layout */}
        <div className="grid grid-cols-1 md:grid-cols-3 gap-6 mb-12">
          <div className="md:col-span-1">
            <Widget title="Hem" accent={true} horsemenFont={true}>
              <TemperatureWidget />
            </Widget>
          </div>
          <div className="md:col-span-1">
            <Widget title="Fredriks spring" horsemenFont={true}>
              <StravaWidget />
            </Widget>
          </div>
          <div className="md:col-span-1">
            <Widget title="Klimat" horsemenFont={true}>
              <WeatherWidget />
            </Widget>
          </div>
        </div>

        {/* Full-width transport section */}
        <div className="mb-12">
          <Widget title="Resor" horsemenFont={true} accent={true} className="w-full">
            <TrainWidget />
          </Widget>
        </div>

      </div>
    </div>
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
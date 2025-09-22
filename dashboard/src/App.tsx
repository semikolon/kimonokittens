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
  horsemenFont = false,
  allowOverflow = false
}: {
  children: React.ReactNode,
  title?: string,
  className?: string,
  accent?: boolean,
  large?: boolean,
  horsemenFont?: boolean,
  allowOverflow?: boolean
}) => {
  return (
    <div
      className={`${allowOverflow ? 'overflow-visible' : 'overflow-hidden'} backdrop-blur-sm ${accent ? 'bg-purple-900/30' : 'bg-slate-900/40'}
      rounded-2xl shadow-md border border-purple-900/10 ${className}`}
    >
      <div className={`p-8 ${large ? 'p-8' : ''}`}>
        {title && (
          <h3 className={`text-xl font-medium ${accent ? 'text-purple-200' : 'text-purple-100'}
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
    <div className="min-h-screen w-full bg-black overflow-x-clip relative">
      {/* Magic animated background */}
      <div className="gradients-container fixed inset-0 h-full w-full opacity-20 blur-[60px]">
        <div className="absolute w-[120%] h-[120%] top-[calc(50%-60%)] left-[calc(50%-60%)] bg-[radial-gradient(circle_at_center,_rgba(88,28,135,0.15)_0%,_rgba(88,28,135,0)_70%)] mix-blend-multiply animate-dashboard-first" />
        <div className="absolute w-[120%] h-[120%] top-[calc(50%-60%)] left-[calc(50%-60%)] bg-[radial-gradient(circle_at_center,_rgba(124,58,237,0.12)_0%,_rgba(124,58,237,0)_70%)] mix-blend-multiply animate-dashboard-second transform-origin-[calc(50%-300px)]" />
        <div className="absolute w-[120%] h-[120%] top-[calc(50%-60%)] left-[calc(50%-60%)] bg-[radial-gradient(circle_at_center,_rgba(139,92,246,0.1)_0%,_rgba(139,92,246,0)_70%)] mix-blend-multiply animate-dashboard-third transform-origin-[calc(50%+300px)]" />
        <div className="absolute w-[120%] h-[120%] top-[calc(50%-60%)] left-[calc(50%-60%)] bg-[radial-gradient(circle_at_center,_rgba(168,85,247,0.08)_0%,_rgba(168,85,247,0)_70%)] mix-blend-multiply animate-dashboard-fourth transform-origin-[calc(50%-150px)]" />
        <div className="absolute w-[120%] h-[120%] top-[calc(50%-60%)] left-[calc(50%-60%)] bg-[radial-gradient(circle_at_center,_rgba(196,181,253,0.06)_0%,_rgba(196,181,253,0)_70%)] mix-blend-multiply animate-dashboard-fifth transform-origin-[calc(50%-600px)_calc(50%+600px)]" />
      </div>


      {/* Main content */}
      <div className="w-full px-4 py-12 min-w-0">

        {/* Featured section - Full width Clock with integrated logo */}
        <div className="mb-12">
          <Widget large={true} accent={true} allowOverflow={true} className="min-h-[260px] w-full">
            <ClockWidget />
          </Widget>
        </div>

        {/* Secondary content in organic layout */}
        <div className="grid grid-cols-1 md:grid-cols-4 gap-6 mb-12">
          <div className="md:col-span-2">
            <Widget title="Hem" accent={true} horsemenFont={true}>
              <TemperatureWidget />
            </Widget>
          </div>
          <div className="md:col-span-2">
            <Widget title="Klimat" accent={true} horsemenFont={true}>
              <WeatherWidget />
            </Widget>
          </div>
        </div>

        {/* Full-width transport section */}
        <div className="mb-12">
          <Widget accent={true} className="w-full">
            <TrainWidget />
          </Widget>
        </div>

        {/* Full-width Strava section */}
        <div className="mb-12">
          <Widget title="Fredriks spring" horsemenFont={true} className="w-full">
            <StravaWidget />
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
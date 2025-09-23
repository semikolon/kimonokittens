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
import { RentWidget } from './components/RentWidget'
import { Wifi, WifiOff } from 'lucide-react'
import AnoAI from './components/ui/animated-shader-background'

// Refined widget component with organic, magazine-style design
const Widget = ({
  children,
  title,
  className = "",
  accent = false,
  large = false,
  horsemenFont = false,
  allowOverflow = false,
  innerClassName
}: {
  children: React.ReactNode,
  title?: string,
  className?: string,
  accent?: boolean,
  large?: boolean,
  horsemenFont?: boolean,
  allowOverflow?: boolean,
  innerClassName?: string
}) => {
  return (
    <div
      className={`${allowOverflow ? 'overflow-visible' : 'overflow-hidden'} backdrop-blur-sm ${accent ? 'bg-purple-900/30' : 'bg-slate-900/40'}
      rounded-2xl shadow-md border border-purple-900/10 ${className}`}
    >
      <div className={innerClassName ?? 'p-8'}>
        {title && (
          <h3 className={`text-2xl font-medium ${accent ? 'text-purple-200' : 'text-purple-100'}
          mb-6 tracking-wide uppercase ${horsemenFont ? 'font-[Horsemen]' : ''}`}>
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
    <div className="min-h-screen w-full bg-[radial-gradient(circle_at_center,_rgb(25,20,30)_0%,_rgb(25,18,32)_100%)] overflow-x-clip relative">
      {/* Animated shader background */}
      <div className="fixed inset-0 w-full h-full opacity-30 mix-blend-screen" style={{ zIndex: 1 }}>
        <AnoAI />
      </div>

      {/* Magic animated background */}
      <div className="gradients-container fixed inset-0 h-full w-full opacity-20 blur-[60px]" style={{ zIndex: 2 }}>
        <div className="absolute w-[120%] h-[120%] top-[calc(50%-60%)] left-[calc(50%-60%)] bg-[radial-gradient(circle_at_center,_rgba(48,12,80,0.18)_0%,_rgba(48,12,80,0)_65%)] mix-blend-multiply animate-dashboard-first" />
        <div className="absolute w-[120%] h-[120%] top-[calc(50%-60%)] left-[calc(50%-60%)] bg-[radial-gradient(circle_at_center,_rgba(68,25,150,0.15)_0%,_rgba(68,25,150,0)_65%)] mix-blend-multiply animate-dashboard-second transform-origin-[calc(50%-300px)]" />
        <div className="absolute w-[120%] h-[120%] top-[calc(50%-60%)] left-[calc(50%-60%)] bg-[radial-gradient(circle_at_center,_rgba(89,45,170,0.13)_0%,_rgba(89,45,170,0)_65%)] mix-blend-multiply animate-dashboard-third transform-origin-[calc(50%+300px)]" />
        <div className="absolute w-[120%] h-[120%] top-[calc(50%-60%)] left-[calc(50%-60%)] bg-[radial-gradient(circle_at_center,_rgba(110,35,160,0.11)_0%,_rgba(110,35,160,0)_65%)] mix-blend-multiply animate-dashboard-fourth transform-origin-[calc(50%-150px)]" />
        <div className="absolute w-[120%] h-[120%] top-[calc(50%-60%)] left-[calc(50%-60%)] bg-[radial-gradient(circle_at_center,_rgba(130,90,200,0.09)_0%,_rgba(130,90,200,0)_65%)] mix-blend-multiply animate-dashboard-fifth transform-origin-[calc(50%-600px)_calc(50%+600px)]" />
      </div>


      {/* Main content */}
      <div className="w-full px-4 py-12 min-w-0">

        {/* Featured section - Full width Clock with integrated logo */}
        <div className="mb-12">
          <Widget large={true} accent={true} allowOverflow={true} className="min-h-[260px] w-full" innerClassName="px-6 pt-4 pb-2 md:px-8">
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

        {/* Full-width rent section */}
        <div className="mb-12">
          <Widget title="Hyran" horsemenFont={true} accent={true} className="w-full">
            <RentWidget />
          </Widget>
        </div>

        {/* Full-width Strava section */}
        <div className="mb-12">
          <Widget title="Fredriks skogsturer" horsemenFont={true} className="w-full bg-purple-900/15">
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

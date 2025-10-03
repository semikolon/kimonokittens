import React from 'react'
import { DataProvider, useData } from './context/DataContext' // WebSocket data provider
import { SleepScheduleProvider, useSleepSchedule } from './contexts/SleepScheduleContext'
// Test deployment verification
import { FadeOverlay } from './components/SleepSchedule/FadeOverlay'
import { ClockWidget } from './components/ClockWidget'
import { WeatherWidget } from './components/WeatherWidget'
import { TemperatureWidget } from './components/TemperatureWidget'
import { TrainWidget } from './components/TrainWidget'
import { StravaWidget } from './components/StravaWidget'
import { RentWidget } from './components/RentWidget'
import { DeploymentBanner } from './components/DeploymentBanner'
import { ErrorBoundary } from './components/ErrorBoundary'
import AnoAI from './components/ui/animated-shader-background'

// Refined widget component with organic, magazine-style design
const Widget = ({
  children,
  title,
  className = "",
  accent = false,
  horsemenFont = false,
  allowOverflow = false,
  innerClassName
}: {
  children: React.ReactNode,
  title?: string,
  className?: string,
  accent?: boolean,
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


function BackendErrorMessage() {
  const { state } = useData()
  const { connectionStatus, trainData, temperatureData, weatherData, stravaData, rentData, todoData } = state

  const hasAnyData = trainData || temperatureData || weatherData || stravaData || rentData || todoData
  const isConnected = connectionStatus === 'open'

  if (isConnected && hasAnyData) {
    return null
  }

  return (
    <div className="mb-8 flex justify-center">
      <div className="bg-rose-900/20 border border-rose-500/30 rounded-lg px-6 py-3 text-center">
        <p className="text-rose-200 text-sm font-medium">
          {!isConnected ? 'Ingen anslutning till servern' : 'Ingen data tillgänglig'}
        </p>
      </div>
    </div>
  )
}

function BackendDataWidgets() {
  const { state } = useData()
  const { connectionStatus, trainData, temperatureData, weatherData, stravaData, rentData, todoData } = state

  const isConnected = connectionStatus === 'open'
  const hasAnyData = trainData || temperatureData || weatherData || stravaData || rentData || todoData

  // Only show widgets when connected and have data
  if (!isConnected || !hasAnyData) {
    return null
  }

  return (
    <>
      {/* Secondary content in organic layout */}
      <div className="grid grid-cols-1 md:grid-cols-4 gap-6 mb-12">
        <div className="md:col-span-2">
          <Widget title="Huset" accent={true} horsemenFont={true}>
            <ErrorBoundary resetKeys={[temperatureData?.last_updated_time]}>
              <TemperatureWidget />
            </ErrorBoundary>
          </Widget>
        </div>
        <div className="md:col-span-2">
          <Widget title="Klimat" accent={true} horsemenFont={true}>
            <ErrorBoundary resetKeys={[weatherData?.generated_at]}>
              <WeatherWidget />
            </ErrorBoundary>
          </Widget>
        </div>
      </div>

      {/* Full-width transport section */}
      <div className="mb-12">
        <Widget accent={true} className="w-full">
          <ErrorBoundary resetKeys={[trainData?.generated_at, connectionStatus]}>
            <TrainWidget />
          </ErrorBoundary>
        </Widget>
      </div>

      {/* Full-width rent section */}
      <div className="mb-12">
        <Widget title="Hyran" horsemenFont={true} accent={true} className="w-full">
          <ErrorBoundary resetKeys={[rentData?.generated_at]}>
            <RentWidget />
          </ErrorBoundary>
        </Widget>
      </div>

      {/* Full-width Strava section */}
      <div className="mb-12">
        <Widget title="Fredriks skogsturer" horsemenFont={true} className="w-full !bg-purple-900/15">
          <ErrorBoundary resetKeys={[stravaData?.generated_at]}>
            <StravaWidget />
          </ErrorBoundary>
        </Widget>
      </div>

    </>
  )
}

function DashboardContent() {
  const { state: sleepState } = useSleepSchedule();

  // Pause CSS animations ONLY when fully asleep
  const shouldPauseAnimations = sleepState.currentState === 'sleeping';

  return (
    <div className="min-h-screen w-full bg-[radial-gradient(circle_at_center,_rgb(25,20,30)_0%,_rgb(25,18,32)_100%)] overflow-x-clip relative">
      <DeploymentBanner />

      {/* Sleep overlay - highest z-index */}
      <FadeOverlay />

      {/* Animated shader background */}
      <div className="fixed inset-0 w-full h-full opacity-30 mix-blend-screen" style={{ zIndex: 1 }}>
        <AnoAI />
      </div>

      {/* Magic animated background */}
      <div
        className="gradients-container fixed inset-0 h-full w-full opacity-20 blur-[60px]"
        style={{
          zIndex: 2,
          animationPlayState: shouldPauseAnimations ? 'paused' : 'running'
        }}
      >
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
          <Widget accent={true} allowOverflow={true} className="min-h-[260px] w-full" innerClassName="px-6 pt-4 pb-2 md:px-8">
            <ErrorBoundary>
              <ClockWidget />
            </ErrorBoundary>
          </Widget>
        </div>

        {/* Backend error message */}
        <BackendErrorMessage />

        <BackendDataWidgets />

      </div>
    </div>
  )
}

function App() {
  return (
    <SleepScheduleProvider>
      <DataProvider>
        <DashboardContent />
      </DataProvider>
    </SleepScheduleProvider>
  )
}

export default App

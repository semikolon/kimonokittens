// Dashboard main application component (Oct 26, 2025 - triggering rebuild for daily costs bar)
import React from 'react'
import { DataProvider, useData } from './context/DataContext' // WebSocket data provider
import { SleepScheduleProvider, useSleepSchedule } from './contexts/SleepScheduleContext'
import { AdminAuthProvider } from './contexts/AdminAuthContext'
import { FadeOverlay } from './components/SleepSchedule/FadeOverlay'
import { ClockWidget } from './components/ClockWidget'
import { WeatherWidget } from './components/WeatherWidget'
import { TemperatureWidget } from './components/TemperatureWidget'
import { TrainWidget } from './components/TrainWidget'
import { StravaWidget } from './components/StravaWidget'
import { RentWidget, AnomalySparklineBar } from './components/RentWidget'
import { ErrorBoundary } from './components/ErrorBoundary'
import AnoAI from './components/ui/animated-shader-background'
import { AdminDashboard } from './views/AdminDashboard'
import { useKeyboardNav } from './hooks/useKeyboardNav'
import { AdminStatusStack } from './components/AdminStatusStack'

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
  const { connectionStatus, trainData, temperatureData, weatherData, stravaData, rentData, todoData, electricityDailyCostsData } = state

  const isConnected = connectionStatus === 'open'
  const hasAnyData = trainData || temperatureData || weatherData || stravaData || rentData || todoData

  // Only show widgets when connected and have data
  if (!isConnected || !hasAnyData) {
    return null
  }

  return (
    <>
      {/* Secondary content in organic layout */}
      <div className="grid grid-cols-1 md:grid-cols-4 gap-6 mb-6">
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

      {/* Electricity anomaly bar - positioned above rent widget */}
      {electricityDailyCostsData?.summary?.anomaly_summary && (
        <div className="mb-6 overflow-hidden backdrop-blur-sm bg-purple-900/15 rounded-2xl shadow-md">
          <ErrorBoundary resetKeys={[electricityDailyCostsData?.generated_at]}>
            <AnomalySparklineBar
              anomalySummary={electricityDailyCostsData.summary.anomaly_summary}
              regressionData={electricityDailyCostsData.summary.regression_data}
            />
          </ErrorBoundary>
        </div>
      )}

      {/* Full-width rent section */}
      <div className="mb-6">
        <Widget title="Hyran" horsemenFont={true} accent={true} className="w-full">
          <ErrorBoundary resetKeys={[rentData?.generated_at]}>
            <RentWidget />
          </ErrorBoundary>
        </Widget>
      </div>

      {/* Full-width transport section */}
      <div className="mb-6">
        <Widget accent={true} className="w-full">
          <ErrorBoundary resetKeys={[trainData?.generated_at, connectionStatus]}>
            <TrainWidget />
          </ErrorBoundary>
        </Widget>
      </div>

      {/* Full-width Strava section */}
      <div className="mb-6">
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
  const { viewMode } = useKeyboardNav();

  // Pause CSS animations ONLY when fully asleep
  const shouldPauseAnimations = sleepState.currentState === 'sleeping';

  // Show admin view if Tab key toggled
  if (viewMode === 'admin') {
    return (
      <div className="min-h-screen w-full bg-[radial-gradient(circle_at_center,_rgb(28,22,35)_0%,_rgb(25,18,32)_100%)] overflow-x-clip relative">
        <AdminStatusStack />
        <FadeOverlay />

        {/* Same animated background as public view */}
        <div
          className="gradients-container fixed inset-0 h-full w-full opacity-35 blur-[50px]"
          style={{
            zIndex: 2,
            animationPlayState: shouldPauseAnimations ? 'paused' : 'running'
          }}
        >
          <div className="absolute w-[60%] h-[60%] top-[10%] left-[10%] bg-[radial-gradient(ellipse_at_center,_rgba(68,25,150,0.38)_0%,_rgba(68,25,150,0)_70%)] mix-blend-screen animate-dashboard-first" />
          <div className="absolute w-[50%] h-[70%] top-[15%] right-[5%] bg-[radial-gradient(ellipse_at_center,_rgba(89,45,170,0.33)_0%,_rgba(89,45,170,0)_70%)] mix-blend-screen animate-dashboard-second" />
          <div className="absolute w-[70%] h-[50%] top-[35%] left-[20%] bg-[radial-gradient(ellipse_at_center,_rgba(110,35,160,0.30)_0%,_rgba(110,35,160,0)_70%)] mix-blend-screen animate-dashboard-third" />
          <div className="absolute w-[55%] h-[65%] bottom-[10%] left-[15%] bg-[radial-gradient(ellipse_at_center,_rgba(48,12,80,0.33)_0%,_rgba(48,12,80,0)_70%)] mix-blend-screen animate-dashboard-fourth" />
          <div className="absolute w-[65%] h-[55%] bottom-[15%] right-[10%] bg-[radial-gradient(ellipse_at_center,_rgba(130,90,200,0.26)_0%,_rgba(130,90,200,0)_70%)] mix-blend-screen animate-dashboard-fifth" />
        </div>

        {/* Admin dashboard content */}
        <div className="w-full px-4 py-12 min-w-0 relative z-10">
          {/* Featured section - Full width Clock with integrated logo */}
          <div className="mb-6 relative z-50">
            <Widget accent={true} allowOverflow={true} className="min-h-[260px] w-full" innerClassName="px-6 pt-4 pb-2 md:px-8">
              <ErrorBoundary>
                <ClockWidget />
              </ErrorBoundary>
            </Widget>
          </div>

          <ErrorBoundary>
            <AdminDashboard />
          </ErrorBoundary>
        </div>

      </div>
    )
  }

  // Public dashboard view (default)
  return (
    <div className="min-h-screen w-full bg-[radial-gradient(circle_at_center,_rgb(28,22,35)_0%,_rgb(25,18,32)_100%)] overflow-x-clip relative">
      <DeploymentBanner />

      {/* Sleep overlay - highest z-index */}
      <FadeOverlay />

      {/* Animated shader background - DISABLED for 24/7 operation (reduces GPU wear/power/noise) */}
      {/* <div className="fixed inset-0 w-full h-full opacity-30 mix-blend-screen" style={{ zIndex: 1 }}>
        <AnoAI />
      </div> */}

      {/* Magic animated background - elliptical gradients that move around */}
      <div
        className="gradients-container fixed inset-0 h-full w-full opacity-35 blur-[50px]"
        style={{
          zIndex: 2,
          animationPlayState: shouldPauseAnimations ? 'paused' : 'running'
        }}
      >
        {/* Top-left blob - moves in circular orbit */}
        <div className="absolute w-[60%] h-[60%] top-[10%] left-[10%] bg-[radial-gradient(ellipse_at_center,_rgba(68,25,150,0.38)_0%,_rgba(68,25,150,0)_70%)] mix-blend-screen animate-dashboard-first" />
        {/* Top-right blob - drifts horizontally */}
        <div className="absolute w-[50%] h-[70%] top-[15%] right-[5%] bg-[radial-gradient(ellipse_at_center,_rgba(89,45,170,0.33)_0%,_rgba(89,45,170,0)_70%)] mix-blend-screen animate-dashboard-second" />
        {/* Center blob - pulses and rotates */}
        <div className="absolute w-[70%] h-[50%] top-[35%] left-[20%] bg-[radial-gradient(ellipse_at_center,_rgba(110,35,160,0.30)_0%,_rgba(110,35,160,0)_70%)] mix-blend-screen animate-dashboard-third" />
        {/* Bottom-left blob - diagonal movement */}
        <div className="absolute w-[55%] h-[65%] bottom-[10%] left-[15%] bg-[radial-gradient(ellipse_at_center,_rgba(48,12,80,0.33)_0%,_rgba(48,12,80,0)_70%)] mix-blend-screen animate-dashboard-fourth" />
        {/* Bottom-right blob - slow orbit */}
        <div className="absolute w-[65%] h-[55%] bottom-[15%] right-[10%] bg-[radial-gradient(ellipse_at_center,_rgba(130,90,200,0.26)_0%,_rgba(130,90,200,0)_70%)] mix-blend-screen animate-dashboard-fifth" />
      </div>


      {/* Main content */}
      <div className="w-full px-4 py-12 min-w-0">

        {/* Featured section - Full width Clock with integrated logo */}
        <div className="mb-6 relative z-50">
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
        <AdminAuthProvider>
          <DashboardContent />
          <AdminStatusStack />
        </AdminAuthProvider>
      </DataProvider>
    </SleepScheduleProvider>
  )
}

export default App

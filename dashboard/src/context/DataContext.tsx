import React, { createContext, useContext, useReducer, useEffect } from 'react'
import useWebSocket from 'react-use-websocket'

// Define the data types
interface TrainData {
  summary: string
  deviation_summary: string
}

interface TemperatureData {
  indoor_temperature: string
  target_temperature: string
  supplyline_temperature: string
  hotwater_temperature: string
  indoor_humidity: string
  heatpump_disabled: number
  heating_demand: string
  current_schedule: string
  last_updated_time: string
  last_updated_date: string
  offline_percentage: string
  outages: number[]
}

interface WeatherData {
  current: {
    temp_c: number | null
    condition: {
      text: string
      icon: string
    }
    humidity: number | null
    wind_kph: number | null
    wind_dir: string | null
  }
  forecast: {
    forecastday: Array<{
      date: string
      day: {
        maxtemp_c: number
        mintemp_c: number
        condition: {
          text: string
          icon: string
        }
        chance_of_rain: number
      }
    }>
  }
  location: {
    name: string
    country: string
  }
  error?: string
}

interface StravaData {
  runs: string
}

// Define the state shape
interface DashboardState {
  trainData: TrainData | null
  temperatureData: TemperatureData | null
  weatherData: WeatherData | null
  stravaData: StravaData | null
  connectionStatus: 'connecting' | 'open' | 'closed'
  lastUpdated: {
    train: number | null
    temperature: number | null
    weather: number | null
    strava: number | null
  }
}

// Define action types
type DashboardAction =
  | { type: 'SET_TRAIN_DATA'; payload: TrainData }
  | { type: 'SET_TEMPERATURE_DATA'; payload: TemperatureData }
  | { type: 'SET_WEATHER_DATA'; payload: WeatherData }
  | { type: 'SET_STRAVA_DATA'; payload: StravaData }
  | { type: 'SET_CONNECTION_STATUS'; payload: 'connecting' | 'open' | 'closed' }

// Initial state
const initialState: DashboardState = {
  trainData: null,
  temperatureData: null,
  weatherData: null,
  stravaData: null,
  connectionStatus: 'connecting',
  lastUpdated: {
    train: null,
    temperature: null,
    weather: null,
    strava: null
  }
}

// Reducer function
function dashboardReducer(state: DashboardState, action: DashboardAction): DashboardState {
  switch (action.type) {
    case 'SET_TRAIN_DATA':
      return {
        ...state,
        trainData: action.payload,
        lastUpdated: { ...state.lastUpdated, train: Date.now() }
      }
    case 'SET_TEMPERATURE_DATA':
      return {
        ...state,
        temperatureData: action.payload,
        lastUpdated: { ...state.lastUpdated, temperature: Date.now() }
      }
    case 'SET_WEATHER_DATA':
      return {
        ...state,
        weatherData: action.payload,
        lastUpdated: { ...state.lastUpdated, weather: Date.now() }
      }
    case 'SET_STRAVA_DATA':
      return {
        ...state,
        stravaData: action.payload,
        lastUpdated: { ...state.lastUpdated, strava: Date.now() }
      }
    case 'SET_CONNECTION_STATUS':
      return {
        ...state,
        connectionStatus: action.payload
      }
    default:
      return state
  }
}

// Create the context
const DataContext = createContext<{
  state: DashboardState
  dispatch: React.Dispatch<DashboardAction>
} | null>(null)

// Provider component
export function DataProvider({ children }: { children: React.ReactNode }) {
  const [state, dispatch] = useReducer(dashboardReducer, initialState)
  
  const socketUrl = '/dashboard/ws'

  const { lastMessage } = useWebSocket(socketUrl, {
    onOpen: () => {
      console.log('Dashboard WebSocket connection established.')
      dispatch({ type: 'SET_CONNECTION_STATUS', payload: 'open' })
    },
    onClose: () => {
      console.log('Dashboard WebSocket connection closed.')
      dispatch({ type: 'SET_CONNECTION_STATUS', payload: 'closed' })
    },
    onError: (event) => {
      console.error('Dashboard WebSocket error:', event)
      dispatch({ type: 'SET_CONNECTION_STATUS', payload: 'closed' })
    },
    shouldReconnect: (closeEvent) => true,
  })

  // Handle incoming WebSocket messages
  useEffect(() => {
    if (lastMessage !== null) {
      try {
        const message = JSON.parse(lastMessage.data)
        console.log('Received WebSocket message:', message)
        
        switch (message.type) {
          case 'train_data':
            dispatch({ type: 'SET_TRAIN_DATA', payload: message.payload })
            break
          case 'temperature_data':
            dispatch({ type: 'SET_TEMPERATURE_DATA', payload: message.payload })
            break
          case 'weather_data':
            dispatch({ type: 'SET_WEATHER_DATA', payload: message.payload })
            break
          case 'strava_data':
            dispatch({ type: 'SET_STRAVA_DATA', payload: message.payload })
            break
          default:
            console.log('Unknown message type:', message.type)
        }
      } catch (error) {
        console.error('Error parsing WebSocket message:', error)
      }
    }
  }, [lastMessage])

  return (
    <DataContext.Provider value={{ state, dispatch }}>
      {children}
    </DataContext.Provider>
  )
}

// Custom hook to use the data context
export function useData() {
  const context = useContext(DataContext)
  if (!context) {
    throw new Error('useData must be used within a DataProvider')
  }
  return context
} 
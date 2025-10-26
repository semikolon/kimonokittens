import React, { createContext, useContext, useReducer, useEffect } from 'react'
import useWebSocket from 'react-use-websocket'

// Define the data types
interface TrainData {
  summary: string
  deviation_summary: string
  generated_at?: string
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
    air_quality?: {
      co: number
      no2: number
      o3: number
      so2: number
      pm2_5: number
      pm10: number
      us_epa_index: number
      gb_defra_index: number
    }
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
  generated_at?: string
}

interface StravaData {
  runs: string
  generated_at?: string
}

interface RentData {
  message: string
  year: number
  month: number
  generated_at: string
  electricity_amount?: number
  electricity_month?: string
  heating_cost_line?: string
  data_source?: {
    type: 'actual' | 'historical' | 'defaults'
    electricity_source: 'current_bills' | 'historical_lookup' | 'fallback_defaults'
    description_sv: string
  }
}

interface TodoData {
  text: string
  id: string
}

interface ElectricityPriceData {
  region: string
  prices: Array<{
    time_start: string
    time_end: string
    price_sek: number
    price_eur: number
  }>
  generated_at?: string
}

interface ElectricityDailyCost {
  date: string
  weekday: string
  price: number
  consumption: number
  long_title?: string
  avg_temp_c?: number
  anomalous_usage_pct?: number  // Percentage excess (e.g., 25.3 for +25.3%)
}

interface ElectricityDailyCostsData {
  summary: {
    price_so_far: number
    projected_total: number
    average_hour: number
    anomaly_summary?: {
      total_anomalies: number
      anomalous_days: Array<{
        date: string
        consumption: number
        expected: number
        temp_c: number
        excess_pct: number
        price_per_kwh: number
        cost_impact: number  // In SEK, positive = cost, negative = savings
      }>
    }
    regression_data?: Array<{
      date: string
      excess_pct: number
    }>
  }
  daily_costs: ElectricityDailyCost[]
  generated_at?: string
}

// Define the state shape
interface DeploymentStatus {
  pending: boolean
  time_remaining?: number
  commit_sha?: string
}

interface DashboardState {
  trainData: TrainData | null
  temperatureData: TemperatureData | null
  weatherData: WeatherData | null
  stravaData: StravaData | null
  rentData: RentData | null
  todoData: TodoData[] | null
  electricityPriceData: ElectricityPriceData | null
  electricityDailyCostsData: ElectricityDailyCostsData | null
  deploymentStatus: DeploymentStatus | null
  connectionStatus: 'connecting' | 'open' | 'closed'
  lastUpdated: {
    train: number | null
    temperature: number | null
    weather: number | null
    strava: number | null
    rent: number | null
    todo: number | null
    electricity: number | null
    electricityDailyCosts: number | null
  }
}

// Define action types
type DashboardAction =
  | { type: 'SET_TRAIN_DATA'; payload: TrainData }
  | { type: 'SET_TEMPERATURE_DATA'; payload: TemperatureData }
  | { type: 'SET_WEATHER_DATA'; payload: WeatherData }
  | { type: 'SET_STRAVA_DATA'; payload: StravaData }
  | { type: 'SET_RENT_DATA'; payload: RentData }
  | { type: 'SET_TODO_DATA'; payload: TodoData[] }
  | { type: 'SET_ELECTRICITY_PRICE_DATA'; payload: ElectricityPriceData }
  | { type: 'SET_ELECTRICITY_DAILY_COSTS_DATA'; payload: ElectricityDailyCostsData }
  | { type: 'SET_DEPLOYMENT_STATUS'; payload: DeploymentStatus }
  | { type: 'SET_CONNECTION_STATUS'; payload: 'connecting' | 'open' | 'closed' }

// Initial state
const initialState: DashboardState = {
  trainData: null,
  temperatureData: null,
  weatherData: null,
  stravaData: null,
  rentData: null,
  todoData: null,
  electricityPriceData: null,
  electricityDailyCostsData: null,
  deploymentStatus: null,
  connectionStatus: 'connecting',
  lastUpdated: {
    train: null,
    temperature: null,
    weather: null,
    strava: null,
    rent: null,
    todo: null,
    electricity: null,
    electricityDailyCosts: null
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
    case 'SET_RENT_DATA':
      return {
        ...state,
        rentData: action.payload,
        lastUpdated: { ...state.lastUpdated, rent: Date.now() }
      }
    case 'SET_TODO_DATA':
      return {
        ...state,
        todoData: action.payload,
        lastUpdated: { ...state.lastUpdated, todo: Date.now() }
      }
    case 'SET_ELECTRICITY_PRICE_DATA':
      return {
        ...state,
        electricityPriceData: action.payload,
        lastUpdated: { ...state.lastUpdated, electricity: Date.now() }
      }
    case 'SET_ELECTRICITY_DAILY_COSTS_DATA':
      return {
        ...state,
        electricityDailyCostsData: action.payload,
        lastUpdated: { ...state.lastUpdated, electricityDailyCosts: Date.now() }
      }
    case 'SET_DEPLOYMENT_STATUS':
      return {
        ...state,
        deploymentStatus: action.payload
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

  const { lastMessage, connectionStatus, readyState } = useWebSocket(socketUrl, {
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
    shouldReconnect: () => true,
    reconnectAttempts: 10,
    reconnectInterval: (attemptNumber) => {
      // Exponential backoff: 500ms, 1s, 2s, 4s, 8s, 16s, 30s (max)
      const baseDelay = 500
      const exponentialDelay = Math.min(baseDelay * Math.pow(2, attemptNumber), 30000)
      // Add jitter to prevent thundering herd
      const jitter = Math.random() * 1000
      const delay = exponentialDelay + jitter
      console.log(`WebSocket reconnection attempt ${attemptNumber + 1} in ${Math.round(delay)}ms`)
      return delay
    },
    onReconnectStop: (numAttempts) => {
      console.log(`WebSocket reconnection stopped after ${numAttempts} attempts`)
    },
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
          case 'rent_data':
            dispatch({ type: 'SET_RENT_DATA', payload: message.payload })
            break
          case 'todo_data':
            dispatch({ type: 'SET_TODO_DATA', payload: message.payload })
            break
          case 'electricity_price_data':
            dispatch({ type: 'SET_ELECTRICITY_PRICE_DATA', payload: message.payload })
            break
          case 'electricity_daily_costs_data':
            // Transform backend format: { electricity_stats: [summary, ...daily_costs] }
            // to frontend format: { summary: {...}, daily_costs: [...] }
            const stats = message.payload.electricity_stats || []
            const summary = stats[0] || { price_so_far: 0, projected_total: 0, average_hour: 0 }
            const daily_costs = stats.slice(1).map((day: any) => ({
              date: day.date,
              weekday: day.weekday,
              price: day.price,
              consumption: day.consumption,
              long_title: day.long_title,
              avg_temp_c: day.avg_temp_c,
              anomalous_usage_pct: day.anomalous_usage_pct
            }))

            dispatch({
              type: 'SET_ELECTRICITY_DAILY_COSTS_DATA',
              payload: {
                summary: {
                  price_so_far: summary.price_so_far,
                  projected_total: summary.projected_total,
                  average_hour: summary.average_hour,
                  anomaly_summary: summary.anomaly_summary,
                  regression_data: summary.regression_data
                },
                daily_costs,
                generated_at: message.timestamp?.toString()
              }
            })
            break
          case 'reload':
            console.log('Reload message received from server')

            // Check if we just reloaded recently (deduplication)
            const LAST_RELOAD_KEY = 'kiosk_last_reload_time'
            const MIN_RELOAD_INTERVAL = 120000 // 2 minutes (matches webhook debounce)

            const lastReload = localStorage.getItem(LAST_RELOAD_KEY)
            const now = Date.now()

            if (lastReload && (now - parseInt(lastReload)) < MIN_RELOAD_INTERVAL) {
              const secondsSince = Math.floor((now - parseInt(lastReload)) / 1000)
              console.warn(`Reload blocked - last reload was ${secondsSince}s ago (minimum ${MIN_RELOAD_INTERVAL/1000}s)`)
              break
            }

            // Record this reload
            localStorage.setItem(LAST_RELOAD_KEY, now.toString())

            console.log('Reloading page...')
            window.location.reload()
            break
          case 'deployment_status':
            dispatch({ type: 'SET_DEPLOYMENT_STATUS', payload: message.payload })
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
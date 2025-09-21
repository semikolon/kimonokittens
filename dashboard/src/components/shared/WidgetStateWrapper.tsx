import React from 'react'
import { neonTheme } from '../../utils/theme'

export interface WidgetStateWrapperProps<T> {
  data: T | undefined
  connectionStatus: 'connecting' | 'open' | 'closed' | 'error'
  loadingMessage?: string
  errorMessage?: string
  children: (data: T) => React.ReactNode
}

export function WidgetStateWrapper<T>({
  data,
  connectionStatus,
  loadingMessage = 'Hämtar data...',
  errorMessage = 'WebSocket-anslutning avbruten',
  children
}: WidgetStateWrapperProps<T>) {
  const loading = connectionStatus === 'connecting' && !data
  const error = connectionStatus === 'closed' ? errorMessage : null

  if (loading) {
    return (
      <div className={`${neonTheme.text.muted} text-sm italic animate-pulse`}>
        {loadingMessage}
      </div>
    )
  }

  if (error) {
    return (
      <div className={`${neonTheme.status.error} text-sm`}>
        Fel: {error}
      </div>
    )
  }

  if (!data) {
    return (
      <div className={`${neonTheme.text.muted} text-sm italic`}>
        Ingen data tillgänglig
      </div>
    )
  }

  return <>{children(data)}</>
}
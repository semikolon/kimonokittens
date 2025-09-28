import React, { Component, ErrorInfo, ReactNode } from 'react'

interface Props {
  children: ReactNode
  fallback?: ReactNode
  resetKeys?: Array<string | number>
}

interface State {
  hasError: boolean
  error?: Error
  errorInfo?: ErrorInfo
}

export class ErrorBoundary extends Component<Props, State> {
  constructor(props: Props) {
    super(props)
    this.state = { hasError: false }
  }

  static getDerivedStateFromError(error: Error): State {
    // Update state so the next render will show the fallback UI
    return { hasError: true, error }
  }

  componentDidCatch(error: Error, errorInfo: ErrorInfo) {
    console.error('ErrorBoundary caught an error:', error, errorInfo)
    this.setState({ error, errorInfo })
  }

  componentDidUpdate(prevProps: Props) {
    const { resetKeys } = this.props
    const { hasError } = this.state

    // Reset error boundary when resetKeys change
    if (hasError && prevProps.resetKeys !== resetKeys) {
      if (resetKeys?.some((key, idx) => prevProps.resetKeys?.[idx] !== key)) {
        this.setState({ hasError: false, error: undefined, errorInfo: undefined })
      }
    }
  }

  render() {
    if (this.state.hasError) {
      // Custom fallback UI or default error message
      return this.props.fallback || (
        <div className="error-boundary bg-red-900/20 border border-red-500 rounded-lg p-4 m-4">
          <h3 className="text-red-400 font-semibold mb-2">
            🚨 Component Error
          </h3>
          <p className="text-red-200 text-sm mb-3">
            Something went wrong with this widget. This is a defensive error boundary preventing the entire app from crashing.
          </p>
          <details className="text-xs text-red-300">
            <summary className="cursor-pointer hover:text-red-200">
              Technical Details
            </summary>
            <pre className="mt-2 bg-red-950/30 p-2 rounded text-xs overflow-auto">
              {this.state.error?.toString()}
              {this.state.errorInfo?.componentStack}
            </pre>
          </details>
          <button
            onClick={() => this.setState({ hasError: false, error: undefined, errorInfo: undefined })}
            className="mt-3 px-3 py-1 bg-red-600 hover:bg-red-500 text-white text-xs rounded transition-colors"
          >
            Retry Component
          </button>
        </div>
      )
    }

    return this.props.children
  }
}

// Higher-order component for easier usage
export function withErrorBoundary<P extends object>(
  Component: React.ComponentType<P>,
  fallback?: ReactNode
) {
  return function WrappedComponent(props: P) {
    return (
      <ErrorBoundary fallback={fallback}>
        <Component {...props} />
      </ErrorBoundary>
    )
  }
}

// Hook for error handling in functional components
export function useErrorHandler() {
  return (error: Error, errorInfo?: string) => {
    console.error('Manual error reported:', error, errorInfo)
    // Could integrate with error reporting service here
    throw error // Re-throw to be caught by ErrorBoundary
  }
}
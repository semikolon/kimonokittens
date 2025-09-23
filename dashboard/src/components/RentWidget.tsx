import React, { useState, useEffect } from 'react'

interface RentMessageData {
  message: string
  year: number
  month: number
  generated_at: string
}

export function RentWidget() {
  const [rentData, setRentData] = useState<RentMessageData | null>(null)
  const [isLoading, setIsLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    const fetchRentMessage = async () => {
      try {
        const response = await fetch('/api/rent/friendly_message')
        if (response.ok) {
          const data = await response.json()
          setRentData(data)
        } else {
          throw new Error(`HTTP ${response.status}`)
        }
      } catch (err) {
        console.error('Failed to fetch rent message:', err)
        setError(err instanceof Error ? err.message : 'Failed to load rent data')
      } finally {
        setIsLoading(false)
      }
    }

    fetchRentMessage()
  }, [])

  if (isLoading) {
    return (
      <div className="flex items-center justify-center p-6">
        <div className="text-purple-300">Loading rent info...</div>
      </div>
    )
  }

  if (error) {
    return (
      <div className="p-6 text-red-400">
        <div className="text-sm">Error loading rent data</div>
        <div className="text-xs text-red-300 mt-1">{error}</div>
      </div>
    )
  }

  if (!rentData) {
    return (
      <div className="p-6 text-purple-300">
        <div className="text-sm">No rent data available</div>
      </div>
    )
  }

  // Parse the friendly message to extract the header and amount(s)
  if (!rentData.message) {
    return (
      <div className="p-6 text-purple-300">
        <div className="text-sm">Invalid rent data format</div>
      </div>
    )
  }

  const lines = rentData.message.split('\n').filter(line => line.trim())

  // Function to convert markdown-style bold (*text*) to React elements
  const parseMarkdown = (text: string) => {
    const parts = text.split(/(\*[^*]+\*)/)
    return parts.map((part, index) => {
      if (part.startsWith('*') && part.endsWith('*')) {
        // Remove asterisks and make bold
        const boldText = part.slice(1, -1)
        return <strong key={index} className="font-bold">{boldText}</strong>
      }
      return part
    })
  }

  const header = lines[0]
  const amounts = lines.slice(1) // Everything after header

  return (
    <div>
      {header && (
        <div className="text-purple-200 mb-3 leading-relaxed">
          {parseMarkdown(header)}
        </div>
      )}

      <div className="space-y-2">
        {amounts.map((line, index) => {
          // Parse individual rent lines - look for bold amounts (marked with *)
          const cleanLine = line.replace(/\*/g, '') // Remove all asterisks

          // Split on "kr" to separate amount from description
          const parts = cleanLine.split(' kr')
          if (parts.length >= 2) {
            const beforeKr = parts[0]
            const afterKr = parts.slice(1).join(' kr') // In case there are multiple "kr" instances

            return (
              <div key={index} className="flex items-baseline gap-2">
                <span className="text-2xl font-bold text-purple-100">
                  {beforeKr.trim()} kr
                </span>
                <span className="text-purple-300">
                  {afterKr.trim()}
                </span>
              </div>
            )
          } else {
            // Fallback for lines that don't follow expected format
            return (
              <div key={index} className="text-purple-200">
                {parseMarkdown(cleanLine)}
              </div>
            )
          }
        })}
      </div>
    </div>
  )
}
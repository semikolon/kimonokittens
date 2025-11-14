import { useData } from '../context/DataContext'

export function TodoWidget() {
  const { state } = useData()
  const { todoData, connectionStatus } = state

  if (connectionStatus !== 'open' || !todoData) {
    return null
  }

  return (
    <div className="mt-4">
      <ul className="space-y-2">
        {todoData.map((todo) => (
          <li key={todo.id} className="flex items-center">
            {/* Glowing orange bullet point */}
            <div className="relative mr-3">
              <div
                className="w-3 h-3 bg-orange-500 rounded-full"
                style={{
                  boxShadow: '0 0 10px #f97316, 0 0 12px #f97316, 0 0 26px #f97316',
                  filter: 'brightness(1.1)'
                }}
              />
              {/* Additional glow layer for more intensity */}
              <div
                className="absolute inset-0 w-2 h-2 bg-orange-400 rounded-full animate-pulse"
                style={{
                  boxShadow: '0 0 4px #fb923c',
                  opacity: 0.8
                }}
              />
            </div>
            <span style={{ fontWeight: 'bold' }}>{todo.text}</span>
          </li>
        ))}
      </ul>
    </div>
  )
}

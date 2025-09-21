import React, { useState, useEffect } from 'react'

interface TodoItem {
  id: string
  content: string
  completed: boolean
  priority: number
  due?: string
}

export function TodoWidget() {
  const [todos, setTodos] = useState<TodoItem[]>([])
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)

  // Mock data for demonstration
  const mockTodos: TodoItem[] = [
    { id: '1', content: 'Handla mat', completed: false, priority: 2 },
    { id: '2', content: 'Städa köket', completed: false, priority: 1 },
    { id: '3', content: 'Betala hyra', completed: true, priority: 3 },
    { id: '4', content: 'Tvätta kläder', completed: false, priority: 1 },
  ]

  useEffect(() => {
    // For now, use mock data
    // TODO: Replace with actual Todoist API call when API key is available
    setTodos(mockTodos)
  }, [])

  const getPriorityIcon = (priority: number) => {
    switch (priority) {
      case 3: return '🔴' // High priority
      case 2: return '🟡' // Medium priority
      case 1: return '🟢' // Low priority
      default: return '⚪' // No priority
    }
  }

  const incompleteTodos = todos.filter(todo => !todo.completed)
  const completedTodos = todos.filter(todo => todo.completed)

  return (
    <div className="widget">
      <div className="widget-title">Visa vårt hem kärlek</div>
      <div className="widget-content">
        <div className="mb-4">
          <div className="text-sm text-purple-200 mb-2">
            Att göra ({incompleteTodos.length})
          </div>
          
          {incompleteTodos.length === 0 ? (
            <div className="text-center text-purple-300 py-4">
              <div className="text-2xl mb-2">✨</div>
              <div className="text-sm">Allt är klart!</div>
            </div>
          ) : (
            <div className="space-y-2">
              {incompleteTodos.slice(0, 4).map((todo) => (
                <div key={todo.id} className="flex items-center space-x-2 p-2 rounded bg-gray-800/30">
                  <span className="text-sm">{getPriorityIcon(todo.priority)}</span>
                  <span className="text-sm flex-1">{todo.content}</span>
                </div>
              ))}
              {incompleteTodos.length > 4 && (
                <div className="text-xs text-purple-200 text-center">
                  +{incompleteTodos.length - 4} fler...
                </div>
              )}
            </div>
          )}
        </div>

        {completedTodos.length > 0 && (
          <div>
            <div className="text-sm text-purple-200 mb-2">
              Klart idag ({completedTodos.length})
            </div>
            <div className="space-y-1">
              {completedTodos.slice(0, 2).map((todo) => (
                <div key={todo.id} className="flex items-center space-x-2 p-1 text-purple-300">
                  <span className="text-sm">✅</span>
                  <span className="text-xs line-through">{todo.content}</span>
                </div>
              ))}
            </div>
          </div>
        )}

        <div className="mt-4 text-xs text-purple-200 text-center">
          <div className="bg-yellow-400/10 text-yellow-400 px-2 py-1 rounded">
            📝 Todoist API kommer snart
          </div>
        </div>
      </div>
    </div>
  )
} 
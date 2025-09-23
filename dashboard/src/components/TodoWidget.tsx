import React, { useState, useEffect } from 'react'

interface TodoItem {
  text: string
  id: string
}

export function TodoWidget() {
  const [todos, setTodos] = useState<TodoItem[]>([])
  const [isLoading, setIsLoading] = useState(true)

  useEffect(() => {
    const fetchTodos = async () => {
      try {
        const response = await fetch('/api/todos')
        if (response.ok) {
          const text = await response.text()
          // Parse markdown list items
          const lines = text.split('\n')
          const todoItems: TodoItem[] = []

          lines.forEach((line, index) => {
            const trimmed = line.trim()
            if (trimmed.startsWith('- ')) {
              todoItems.push({
                text: trimmed.substring(2),
                id: `todo-${index}`
              })
            }
          })

          setTodos(todoItems)
        }
      } catch (error) {
        console.error('Failed to fetch todos:', error)
        // Fallback to hardcoded todos
        setTodos([
          { text: 'Lägga upp annons', id: 'todo-1' },
          { text: 'Klipp gräsmattan', id: 'todo-2' }
        ])
      } finally {
        setIsLoading(false)
      }
    }

    fetchTodos()
  }, [])

  if (isLoading) {
    return <div className="text-purple-300 text-sm">Loading todos...</div>
  }

  return (
    <div className="mt-4">
      <ul className="space-y-2">
        {todos.map((todo) => (
          <li key={todo.id} className="flex items-center">
            {/* Glowing orange bullet point */}
            <div className="relative mr-3">
              <div
                className="w-2 h-2 bg-orange-500 rounded-full"
                style={{
                  boxShadow: '0 0 8px #f97316, 0 0 16px #f97316, 0 0 24px #f97316',
                  filter: 'brightness(1.2)'
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
            {/* Text with same typography as existing */}
            <span style={{ fontWeight: 'bold' }}>{todo.text}</span>
          </li>
        ))}
      </ul>
    </div>
  )
}

import { useState, useEffect, useRef, useCallback } from 'react'
import { useData } from '../context/DataContext'
import { useAdminAuth } from '../contexts/AdminAuthContext'

interface TodoWidgetProps {
  isAdmin?: boolean
}

export function TodoWidget({ isAdmin = false }: TodoWidgetProps) {
  const { state } = useData()
  const { todoData, connectionStatus } = state
  const { ensureAuth, token } = useAdminAuth()

  // Local editing state
  const [editingItems, setEditingItems] = useState<string[]>([])
  const [isSaving, setIsSaving] = useState(false)
  const [saveStatus, setSaveStatus] = useState<'idle' | 'saved' | 'error'>('idle')
  const saveTimeoutRef = useRef<ReturnType<typeof setTimeout> | null>(null)
  const debounceRef = useRef<ReturnType<typeof setTimeout> | null>(null)
  const lastSaveTimeRef = useRef<number>(0)

  // Sync from WebSocket data when not in editing mode
  // Grace period after save prevents stale WebSocket data from overwriting
  useEffect(() => {
    const timeSinceLastSave = Date.now() - lastSaveTimeRef.current
    if (timeSinceLastSave < 2000) {
      return // Wait for WebSocket to catch up with our save
    }
    if (todoData && !isSaving) {
      setEditingItems(todoData.map(t => t.text))
    }
  }, [todoData, isSaving])

  // Clear save status after delay
  useEffect(() => {
    if (saveStatus !== 'idle') {
      saveTimeoutRef.current = setTimeout(() => setSaveStatus('idle'), 2000)
      return () => {
        if (saveTimeoutRef.current) clearTimeout(saveTimeoutRef.current)
      }
    }
  }, [saveStatus])

  const saveTodos = useCallback(async (items: string[]) => {
    // Filter empty items
    const cleanItems = items.map(i => i.trim()).filter(Boolean)

    setIsSaving(true)
    try {
      const authToken = await ensureAuth()
      if (!authToken) {
        setIsSaving(false)
        return
      }

      const response = await fetch('/api/admin/todos', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-Admin-Token': authToken
        },
        body: JSON.stringify({ items: cleanItems })
      })

      if (response.ok) {
        setSaveStatus('saved')
        // Update local state to match what was saved
        setEditingItems(cleanItems)
        // Mark save time so we ignore stale WebSocket data for 2s
        lastSaveTimeRef.current = Date.now()
      } else {
        const data = await response.json()
        console.error('Failed to save todos:', data.error)
        setSaveStatus('error')
      }
    } catch (err) {
      console.error('Error saving todos:', err)
      setSaveStatus('error')
    } finally {
      setIsSaving(false)
    }
  }, [ensureAuth])

  const debouncedSave = useCallback((items: string[]) => {
    if (debounceRef.current) {
      clearTimeout(debounceRef.current)
    }
    debounceRef.current = setTimeout(() => {
      saveTodos(items)
    }, 300)
  }, [saveTodos])

  const handleItemChange = (index: number, value: string) => {
    const newItems = [...editingItems]
    newItems[index] = value
    setEditingItems(newItems)
  }

  // Track original items when editing session starts (for clustering edits)
  const originalItemsRef = useRef<string[] | null>(null)
  const listContainerRef = useRef<HTMLUListElement>(null)
  const blurTimeoutRef = useRef<ReturnType<typeof setTimeout> | null>(null)

  const handleItemFocus = () => {
    // Snapshot items when starting to edit (first focus in the list)
    if (originalItemsRef.current === null) {
      originalItemsRef.current = [...editingItems]
    }
    // Cancel any pending blur-save since we're still in the list
    if (blurTimeoutRef.current) {
      clearTimeout(blurTimeoutRef.current)
      blurTimeoutRef.current = null
    }
  }

  const handleItemBlur = () => {
    // Short delay to let focus settle on next element
    blurTimeoutRef.current = setTimeout(() => {
      // Check if focus moved to another element within the todo list
      const activeEl = document.activeElement
      const stillInList = listContainerRef.current?.contains(activeEl) ||
                          activeEl?.closest('button')?.textContent?.includes('Lägg till')

      if (!stillInList && originalItemsRef.current !== null) {
        // Focus left the todo list - check if anything changed and save
        const hasChanges = JSON.stringify(editingItems) !== JSON.stringify(originalItemsRef.current)
        if (hasChanges) {
          debouncedSave(editingItems)
        }
        // Reset for next editing session
        originalItemsRef.current = null
      }
    }, 100)
  }

  const handleKeyDown = (e: React.KeyboardEvent) => {
    if (e.key === 'Enter') {
      e.preventDefault()
      // Save immediately on Enter and reset tracking
      if (debounceRef.current) clearTimeout(debounceRef.current)
      if (blurTimeoutRef.current) clearTimeout(blurTimeoutRef.current)
      originalItemsRef.current = null
      saveTodos(editingItems)
    }
  }

  const addItem = () => {
    const newItems = [...editingItems, '']
    setEditingItems(newItems)
    // Focus will be handled by the new input appearing
  }

  const removeItem = (index: number) => {
    const newItems = editingItems.filter((_, i) => i !== index)
    setEditingItems(newItems)
    debouncedSave(newItems)
  }

  if (connectionStatus !== 'open' || (!todoData && editingItems.length === 0)) {
    return null
  }

  const items = isAdmin ? editingItems : (todoData?.map(t => t.text) || [])

  return (
    <div className="mt-4">
      {/* Save status indicator for admin */}
      {isAdmin && saveStatus !== 'idle' && (
        <div className={`text-sm mb-2 ${saveStatus === 'saved' ? 'text-cyan-400' : 'text-red-400'}`}>
          {saveStatus === 'saved' ? 'Sparat!' : 'Fel vid sparande'}
        </div>
      )}

      <ul ref={listContainerRef} className="space-y-2">
        {items.map((text, index) => (
          <li key={`todo-${index}`} className="flex items-center group">
            {/* Glowing orange bullet point */}
            <div className="relative mr-3 flex-shrink-0">
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

            {isAdmin ? (
              <div className="flex-1 flex items-center gap-2">
                <input
                  type="text"
                  value={text}
                  onChange={(e) => handleItemChange(index, e.target.value)}
                  onFocus={handleItemFocus}
                  onBlur={handleItemBlur}
                  onKeyDown={handleKeyDown}
                  className="flex-1 bg-transparent border-none focus:outline-none text-white font-bold transition-shadow py-0 leading-normal shadow-[0_1px_0_transparent] hover:shadow-[0_1px_0_rgba(168,85,247,0.3)] focus:shadow-[0_1px_0_#c084fc]"
                  placeholder="Skriv något..."
                  disabled={isSaving}
                />
                <button
                  onClick={() => removeItem(index)}
                  className="opacity-0 group-hover:opacity-100 text-red-400 hover:text-red-300 transition-opacity p-1"
                  title="Ta bort"
                  disabled={isSaving}
                >
                  <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M6 18L18 6M6 6l12 12" />
                  </svg>
                </button>
              </div>
            ) : (
              <span style={{ fontWeight: 'bold' }}>{text}</span>
            )}
          </li>
        ))}
      </ul>

      {/* Add button for admin */}
      {isAdmin && (
        <button
          onClick={addItem}
          className="mt-3 text-sm text-purple-300 hover:text-purple-200 flex items-center gap-1 transition-colors"
          disabled={isSaving}
        >
          <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 4v16m8-8H4" />
          </svg>
          Lägg till rad
        </button>
      )}
    </div>
  )
}

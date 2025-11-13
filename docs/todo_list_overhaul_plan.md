# Todo List Overhaul Plan – Admin Editing & Obsidian Compatibility

## Goals

1. **Editable from the admin dashboard**: When `/admin` view is active and the user unlocks with the existing PIN, the todo list should become editable inline (same typography/margins as kiosk view). Edits auto-save when pressing `Enter` or blurring the field, and changes propagate live to the kiosk view via the existing WebSocket channel.
2. **Keep markdown as source of truth**: Todos continue to live in `household_todos.md` (git-managed) so future Obsidian integration is seamless.
3. **PIN-gated write path**: All mutations require the same `X-Admin-Token` gate we’re already using for contracts/tenant scripts.

## Current Architecture Recap

- `household_todos.md` stores a simple markdown list (e.g., `- Brottas & meditera`).
- `TodosHandler` (`/api/todos`) reads the file and returns plaintext.
- `DataBroadcaster` polls `/api/todos`, splits `- ...` lines into JSON, and publishes `todo_data` via WebSocket every ~5 minutes.
- `TodoWidget` just renders `todoData` from the `DataContext`. No local editing, no state.
- Deploy scripts already know to pull data files like `household_todos.md` before building.

## Proposed Changes

### 1. Backend API for updates

- Add `POST /api/admin/todos` with body:
  ```json
  {
    "items": ["Brottas & meditera", "Hitta vår nya crew", ...]
  }
  ```
- Request must include `X-Admin-Token`; reuse `AdminAuth.authorized?` helper.
- Handler writes a sanitized markdown file:
  ```ruby
  File.write('household_todos.md', "# Household Todos\n\n" + items.map { "- #{text}" }.join("\n"))
  ```
- After write, call `DataBroadcaster.broadcast_todos` immediately so kiosk view refreshes without waiting for the next poll.
- Consider a short file lock (`File.flock`) so two admins don’t clobber each other.

### 2. Frontend admin UX

- When `viewMode === 'admin'` and `ensureAuth()` succeeds, render each todo item as an input (same font-size/weight). Non-admin view remains plain text.
- Editing flow:
  - On focus: show caret but keep layout identical.
  - On blur or `Enter`: call the new endpoint with the full list (we keep local state of all items).
  - Reuse the toast system to show “Sparat” / error messages.
- Add `+ Lägg till rad` and a delete icon per row (both behind the PIN gate). Deletions just drop the item from the list we POST.
- Debounce network saves lightly (e.g., 300ms) so quick edits don’t spam the server, but also allow explicit `Enter` saves.

### 3. Data flow / consistency

- After POST success, optimistically update `todoData` locally to avoid waiting for the broadcast.
- When the WebSocket `todo_data` arrives, it will match what we just saved (since we just triggered a broadcast), keeping kiosk/admin views in sync.
- If the file write fails, return 500 so the admin UI can show an error and revert to the last known state.

### 4. Obsidian-friendly considerations

- Continue to store todos in `household_todos.md` so Obsidian can watch the folder. Editing from Obsidian or git means the broadcaster will pick up changes on the next poll and push them to the kiosk (same as today).
- Document in `TODO.md` which data files are “live-editable” and how to edit them safely.
- Later, when the handbook moves to Obsidian, we can reuse this write-path pattern for other markdown-backed content.

## Implementation Steps

1. **Backend**
   - [ ] Create `AdminTodosHandler` (or extend `TodosHandler`) with POST route under `/api/admin/todos`.
   - [ ] Validate `items` array, sanitize leading/trailing whitespace, reject blank rows.
   - [ ] Write file using `File.write` + `flock`. Include header line so file stays consistent.
   - [ ] Directly call the broadcaster or publish a `todo_data` event to avoid delays.

2. **Frontend**
   - [ ] Extend `TodoWidget` to detect admin mode via `useKeyboardNav` or a prop from `DashboardContent`.
   - [ ] Render editable inputs with identical styling (use `contentEditable` or controlled `<input>`; keep `display: block` + same margins).
   - [ ] Maintain local state array for edits; on save, call `/api/admin/todos` with `ensureAuth()`.
   - [ ] Provide add/remove buttons (icon-only, small, subtle) and confetti-of-sorts with toasts.

3. **Testing**
   - [ ] Verify editing while offline fails gracefully.
   - [ ] Ensure kiosk view updates after admin edit without reload.
   - [ ] Confirm markdown file still works with manual git edits (simulate editing `household_todos.md` and pushing).

Once this is in place we’ll have a blueprint for other markdown-backed admin edits (handbook pages, etc.) while preserving Obsidian compatibility.

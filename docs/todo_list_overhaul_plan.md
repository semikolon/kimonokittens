# Todo List Overhaul Plan – Admin Editing & Git Persistence

## Goals

1. **Editable from the admin dashboard**: When `/admin` view is active and the user unlocks with the existing PIN, the todo list should become editable inline (same typography/margins as kiosk view). Edits auto-save when pressing `Enter` or blurring the field, and changes propagate live to the kiosk view via the existing WebSocket channel.
2. **Git-backed persistence**: Every edit commits directly to main branch using Rugged (same pattern as handbook proposals). This ensures edits survive deployments and provides audit trail.
3. **Future handbook integration**: File located in `handbook/docs/` so tenants can later propose todo changes via handbook's two-approval workflow.
4. **PIN-gated write path**: All mutations require the same `X-Admin-Token` gate we're already using for contracts/tenant scripts.

## File Location

**Path**: `handbook/docs/household_todos.md`

**Rationale**: Moved from project root to enable future handbook proposal integration. When handbook deploys publicly, tenants can suggest todo changes ("Sanna föreslår: Lägg till 'Städa balkongen'") that admins approve/reject via the existing two-approval workflow.

## Current Architecture Recap

- `handbook/docs/household_todos.md` stores a simple markdown list (e.g., `- Brottas & meditera`).
- `TodosHandler` (`/api/todos`) reads the file and returns plaintext.
- `DataBroadcaster` polls `/api/todos`, splits `- ...` lines into JSON, and publishes `todo_data` via WebSocket every ~5 minutes.
- `TodoWidget` just renders `todoData` from the `DataContext`. No local editing, no state.
- Webhook deployments do `git pull` which syncs all committed changes including todo file.

## Proposed Changes

### 1. Backend API for updates (`POST /api/admin/todos`)

Request body:
```json
{
  "items": ["Brottas & meditera", "Hitta vår nya crew", ...]
}
```

**Git-backed persistence using Rugged** (same pattern as `handbook_handler.rb`):

```ruby
require 'rugged'

class AdminTodosHandler
  TODO_PATH = 'handbook/docs/household_todos.md'

  def save_todos(items)
    repo = Rugged::Repository.new('.')

    # Build markdown content
    content = "# Household Todos\n\n" + items.map { |t| "- #{t.strip}" }.join("\n") + "\n"

    # Get current main branch
    main_branch = repo.branches['master'] || repo.branches['main']
    parent_commit = main_branch.target

    # Create new blob with content
    oid = repo.write(content, :blob)

    # Build index from parent tree
    index = repo.index
    index.read_tree(parent_commit.tree)
    index.add(path: TODO_PATH, oid: oid, mode: 0100644)

    # Write tree and create commit
    tree_oid = index.write_tree(repo)
    commit_oid = Rugged::Commit.create(repo,
      tree: tree_oid,
      parents: [parent_commit],
      message: "Update household todos via admin dashboard",
      author: { name: 'Admin Dashboard', email: 'admin@kimonokittens.local', time: Time.now },
      committer: { name: 'Admin Dashboard', email: 'admin@kimonokittens.local', time: Time.now },
      update_ref: 'refs/heads/master'
    )

    # Push to origin (async to avoid blocking UI)
    Thread.new { system('git push origin master') }

    commit_oid
  end
end
```

- Request must include `X-Admin-Token`; reuse `AdminAuth.authorized?` helper.
- After commit, call `DataBroadcaster.broadcast_todos` immediately so kiosk view refreshes.
- Git push runs async so UI doesn't block on network.

### 2. Frontend admin UX

- When `viewMode === 'admin'` and `ensureAuth()` succeeds, render each todo item as an input (same font-size/weight). Non-admin view remains plain text.
- Editing flow:
  - On focus: show caret but keep layout identical.
  - On blur or `Enter`: call the new endpoint with the full list (we keep local state of all items).
  - Reuse the toast system to show "Sparat" / error messages.
- Add `+ Lägg till rad` and a delete icon per row (both behind the PIN gate). Deletions just drop the item from the list we POST.
- Debounce network saves lightly (e.g., 300ms) so quick edits don't spam the server, but also allow explicit `Enter` saves.

### 3. Data flow / consistency

```
Admin Edit → POST /api/admin/todos → Rugged commit → async git push
                                   ↓
                          DataBroadcaster.broadcast_todos
                                   ↓
                          WebSocket → Kiosk view updates
                                   ↓
                          GitHub webhook → Production git pull (already committed)
```

- After POST success, optimistically update `todoData` locally.
- WebSocket `todo_data` arrives and syncs kiosk/admin views.
- If commit fails, return 500 so admin UI can show error and revert.
- Production stays in sync via normal webhook flow (git pull fetches the committed change).

### 4. Security considerations

- **PIN-gated**: Same security as tenant management, contracts
- **Direct commits to main**: Acceptable for household todos (low-stakes content)
- **Audit trail**: Full git history of all todo changes
- **No public exposure**: Endpoint behind admin auth, not accessible without PIN

### 5. Future handbook integration

When handbook deploys publicly, tenants can propose todo changes:

1. Tenant opens handbook → sees todo list → clicks "Föreslå ändring"
2. Creates proposal branch: `proposals/{tenant}/{timestamp}-update-household-todos`
3. Two admins approve → auto-merges to main → webhook deploys
4. Admin dashboard direct edits bypass proposal workflow (PIN = trusted)

This two-track approach: immediate admin edits + reviewed tenant proposals.

## Implementation Steps

### Phase 1: Backend (AdminTodosHandler)

- [x] Move `household_todos.md` to `handbook/docs/` (future handbook compatibility)
- [x] Update `TodosHandler` to read from new path
- [x] Add `rugged` gem to Gemfile (already present from handbook_handler.rb)
- [x] Create `AdminTodosHandler` with POST route under `/api/admin/todos`
- [x] Validate `items` array, sanitize whitespace, reject blank rows
- [x] Implement Rugged git commit (write blob → index → tree → commit)
- [x] Add async git push after commit
- [x] Call `DataBroadcaster.broadcast_todos` after successful commit
- [x] Wire up route in `puma_server.rb`

### Phase 2: Frontend (TodoWidget)

- [x] Extend `TodoWidget` to detect admin mode (`isAdmin` prop)
- [x] Render editable inputs with identical styling
- [x] Maintain local state array for edits
- [x] On save, call `/api/admin/todos` with `ensureAuth()`
- [x] Add/remove buttons (icon-only, subtle)
- [x] Save status indicator ("Sparat!" on success)
- [x] 300ms debounce for rapid edits

### Phase 3: Testing

- [ ] Verify editing while offline fails gracefully
- [ ] Ensure kiosk view updates after admin edit without reload
- [ ] Confirm git commit appears in history
- [ ] Test webhook deployment picks up committed changes
- [ ] Verify concurrent edit handling (file lock or last-write-wins)

## Dependencies

- `rugged` gem (Ruby bindings for libgit2) - same as handbook_handler.rb
- Existing: `AdminAuth`, `DataBroadcaster`, `X-Admin-Token` header pattern

## Status

- **Nov 25, 2025**: File moved to `handbook/docs/`, plan updated with Git persistence
- **Nov 25, 2025**: Backend + Frontend implementation complete, deployed to production
- **Pending**: End-to-end testing

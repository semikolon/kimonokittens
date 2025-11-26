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
# Todo Widget Architecture & Fixes

**Status**: In Progress (Nov 26, 2025)

## Problem Summary

Todo editing from kiosk dashboard caused:
1. Race conditions between blur/removeItem handlers
2. Git staging without commit (dirty prod state)
3. Divergent branches blocking deployments

## Fixes Implemented

### Frontend (`TodoWidget.tsx`)

**Clustered Editing** (commit 7a60b6a):
- `originalItemsRef` snapshots items when editing session starts
- Save triggers only when focus leaves ENTIRE list, not each field
- Enables editing multiple lines before save

**WebSocket Race Fix** (commit 6d30ccd):
- 2-second grace period after save ignores stale WebSocket data
- Prevents saved items from reverting to pre-save state

**Remove-Item Race Fix** (commit 6790934):
- Clicking X cancels pending blur timer
- Saves immediately (like Enter key)
- Prevents blur's stale closure from overwriting filtered items

### Backend (`admin_todos_handler.rb`)

**In-Memory Git Index** (commit 6790934):
- Uses `Rugged::Index.new` instead of `repo.index`
- Prevents dirty staged state if commit fails

**Synchronous Push with Retry** (pending):
- Replaces async `Thread.new` push
- On failure: fetch + rebase + retry (3 attempts)
- Handles divergent branches from concurrent dev pushes

## Architecture: Git-Based Handbook Docs

**Design Decision**: Keep todos in git (not database) because:
- Handbook docs will use same git-commit pattern
- Preserves version history
- "Docs as code" philosophy

**Flow**:
```
User Edit → Local Commit → Push to GitHub → (retry with rebase if needed)
           ↓
Webhook pulls from GitHub → Fast-forward (no divergence)
```

**Key Insight**: Synchronous push with rebase retry ensures local commits reach GitHub before webhook runs, preventing divergent branches.

## Tests Needed

### Frontend (Jest/React Testing Library)
- [ ] removeItem cancels blur timer
- [ ] removeItem saves immediately
- [ ] Multiple edits captured before X click
- [ ] WebSocket doesn't overwrite recent save (grace period)
- [ ] Clustered edits: blur within list doesn't save

### Backend (RSpec)
- [ ] In-memory index doesn't dirty working tree
- [ ] push_with_retry handles non-fast-forward
- [ ] Rebase conflict aborts cleanly

## Related Files

- `dashboard/src/components/TodoWidget.tsx`
- `handlers/admin_todos_handler.rb`
- `lib/data_broadcaster.rb` (broadcast_todos)
- `handbook/docs/household_todos.md` (data file)

---

# Filesystem + Git Consistency Fix

**Status**: Implemented (Nov 26, 2025)

## Problem Discovered

The original git-only approach had a critical timing gap:

1. `git_commit()` creates commit in git object store via Rugged
2. **Working directory file is NOT updated** (Rugged writes to git, not filesystem)
3. `DataBroadcaster` reads from filesystem → broadcasts OLD content
4. After 2-second grace period, user sees edit REVERT
5. Only after webhook `git pull` (up to 2-minute debounce) does filesystem update

## Additional Failure Mode

If push fails after local commit:
- User sees "Sparat!" (success response)
- GitHub doesn't have the commit
- Next dev push could cause divergent branches
- Silent failure - user thinks it saved but it didn't persist

## Solution: Filesystem Write + Fail-Fast Push

**Architecture change**: Write to filesystem FIRST, then git commit, fail if push fails.

```
User Edit → Write to filesystem → Git commit → Push with retry
              ↓ (immediate)         ↓              ↓
         DataBroadcaster        Git history    GitHub/webhook
         sees new content       preserved      deployment
```

**On push failure**: Revert filesystem to match origin/master, return 500 error.

**Benefits**:
1. **Immediate visibility** - DataBroadcaster reads new content instantly
2. **No silent failures** - Push failure = user error, not false success
3. **Consistent state** - Filesystem always matches either local success OR origin/master
4. **Audit trail preserved** - Git history still tracks all changes

## Implementation

```ruby
def update_todos(req)
  # ... validation ...

  # 1. Write to filesystem FIRST (immediate visibility)
  File.write(TODO_PATH, content)

  begin
    # 2. Create git commit
    commit_oid = git_commit(content)

    # 3. Push with retry - MUST succeed
    push_success = push_with_retry
    unless push_success
      # Revert filesystem to match deployed state
      system("git checkout origin/master -- #{TODO_PATH}")
      return json_response(500, { error: "Save failed - could not sync to remote" })
    end

    # 4. Broadcast after confirmed persistence
    $data_broadcaster&.broadcast_todos
    json_response(200, { success: true, ... })

  rescue => e
    # Revert on any error
    system("git checkout origin/master -- #{TODO_PATH}")
    json_response(500, { error: "Failed to save: #{e.message}" })
  end
end
```

## Trade-off Accepted

Failed commits still exist in local git history (orphaned). Could accumulate over time, but:
- Rare edge case (push failures are uncommon)
- Git garbage collection eventually cleans unreferenced objects
- Alternative (`git reset --hard`) is destructive and risky
- Acceptable technical debt for reliability

---

# Webhook Integration: Self-Triggering Scenario

**Status**: Verified working (Nov 26, 2025)

## The Round-Trip Flow

When todos are edited on the production server:

1. **Production** writes file + commits + pushes to GitHub
2. **GitHub** receives push → sends webhook back to production
3. **Production** receives webhook for its *own* push

## Smart Change Detection

The webhook (`deployment/scripts/webhook_puma_server.rb`) explicitly handles this:

```ruby
# If only data files changed (no code), git pull is enough
unless changes[:frontend] || changes[:backend] || changes[:deployment] || changes[:config]
  $logger.info("✅ Data files updated via git pull, no deployment needed")
  return { success: true, message: 'Data files updated (handbook/docs/household_todos.md, ...)' }
end
```

**Change detection patterns** (lines 370+):
- `^dashboard/` → frontend rebuild
- `\.(rb|ru|gemspec)$|^Gemfile$` → backend restart
- `^deployment/` → webhook self-update warning
- Config files → kiosk restart

**Files like `handbook/docs/*.md`** don't match any pattern → no deployment flags → fast path.

## Result: Minimal Overhead

For todo edits originating from production:
- `git pull` is a no-op (already at HEAD)
- No backend restart
- No frontend rebuild
- Just the webhook round-trip (~2 seconds)

For todo edits originating from dev machine (via git push):
- `git pull` updates the file
- DataBroadcaster reads new content on next poll
- No deployment needed

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

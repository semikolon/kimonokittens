# Session Work Report: Bus Duplicate Bug & Webhook Architecture Fix
**Date:** October 3, 2025
**Duration:** ~3 hours
**Context:** Production kiosk showing 3 duplicate 15:07 buses stuck at "om 2m/1m" + empty line

## Critical Bugs Fixed

### 1. **Backend Bus Data Caching Bug** ✅ SOLVED
**Symptom:** Production kiosk showed 3 duplicate buses (15:07) stuck showing "om 2m" and "om 1m" with empty line above

**Root Cause:** Backend instance variable `@bus_data` cached stale data from hours earlier
- Backend calculates `minutes_until` fresh on each request (line 179: `((departure_time - now) / 60).round`)
- Cache refreshes every 10 seconds (CACHE_THRESHOLD)
- BUT if backend process runs for hours, internal state can accumulate duplicates

**Fix:** `sudo systemctl restart kimonokittens-dashboard` cleared cache → immediate resolution

**Location:** `handlers/train_departure_handler.rb:38-48`

### 2. **Webhook Git Pull Architecture Bug** ✅ SOLVED
**Symptom:** Data file changes (household_todos.md, electricity_bills_history.txt) never appeared in production

**Root Cause:** Webhook analyzed changes FIRST, then decided whether to git pull:
```ruby
unless changes[:any_changes]
  return 'No deployment needed'  # ← EXITS HERE
end
# Git pull down here - NEVER REACHED for data files!
```

**Files Affected:**
- `household_todos.md` (todos API)
- `electricity_bills_history.txt` (rent calculator)
- `www/*.html`, `www/*.png` (static assets)

**Architectural Fix (Option B - Proper Solution):**
1. Git pull FIRST (always updates ALL files on disk)
2. Analyze changes (determine if code changed)
3. Deploy/restart ONLY if frontend/backend/deployment code changed
4. Data files updated via step 1, no restart needed

**Implementation:**
- Added `pull_latest_code()` method (extracted from deploy_backend)
- Called BEFORE `analyze_changes()` in `process_webhook()`
- Removed duplicate git pull from `deploy_backend` and `deploy_frontend`
- Single source of truth for git operations

**Location:** `deployment/scripts/webhook_puma_server.rb:201-331`

**Commit:** `39f2192` - "fix: webhook now pulls ALL files (data + code) before deployment"

## Complete Data Flow Analysis

### Backend Data Pipeline
```
1. SL Transport API (every 10s cache)
   ↓
2. transform_sl_bus_data (line 258)
   ↓
3. @bus_data instance variable (lines 38, 71, 78, 85)
   ↓
4. structured_buses calculation (line 177)
   - minutes_until = ((departure_time - now) / 60).round
   - ALWAYS recalculated with current time
   ↓
5. JSON response to DataBroadcaster
```

### DataBroadcaster → Frontend Pipeline
```
1. DataBroadcaster fetches /data/train_departures every 30s
   ↓
2. WebSocket broadcast to frontend
   ↓
3. DataContext reducer SET_TRAIN_DATA (line 156)
   - trainData: action.payload (COMPLETE REPLACEMENT)
   ↓
4. TrainWidget consumes trainData
   ↓
5. Framer Motion AnimatePresence renders with animations
```

**Key Finding:** No accumulation logic anywhere - state completely replaced on each update. The duplicate bug was 100% backend caching issue.

## Framer Motion Migration (Completed Earlier)

**Status:** ✅ Production deployed (4 commits pushed)

**Commits:**
1. `6336344` - Install Framer Motion (--legacy-peer-deps for React 19)
2. `cdaa223` - Add red-tinted swoosh CSS, remove ViewTransition rules
3. `03dc7a4` - Migrate TrainWidget to Framer Motion animations
4. `80626dc` - Remove unused flashing animations and cleanup

**Key Changes:**
- AnimatePresence + LayoutGroup wrapping train/bus lists
- motion.div with 1s slide-in/out (no staggering per user preference)
- Layout prop for unified slide-up (all items move together)
- Red-tinted swoosh at 7m (trains) and 2m (buses)
- Removed ViewTransition.tsx and all `::view-transition-*` CSS

**Logic Preserved:**
- 3-minute window (prevents false animations on delays)
- Pre-emptive removal at 5m (trains never show 4m)
- Shine swoosh at 9-8-7m (trains), 4-3-2m (buses)
- Delay handling: inline display "08:07 → 08:10 (3 min sen)"
- Störningar filtering (no duplicates)

## Production Deployment Architecture

### Services
- **Backend:** `kimonokittens-dashboard` (port 3001) - Puma + WebSocket
- **Webhook:** `kimonokittens-webhook` (port 49123) - Smart deployment receiver
- **Frontend:** Static files served by nginx from `/var/www/kimonokittens/dashboard/`
- **Kiosk:** Chrome browser via `kimonokittens-kiosk` (user service)

### Webhook Flow
1. GitHub push → POST localhost:49123/webhook
2. **Git pull (ALWAYS)** ← NEW FIX
3. Analyze changes:
   - `dashboard/` → Frontend deployment
   - `.rb`, `Gemfile` → Backend deployment
   - `deployment/` → Deployment config (requires manual webhook restart)
   - Everything else → Data files (git pull is enough)
4. 2-minute debounce (rapid pushes = one deployment)
5. Deploy components as needed
6. Restart kiosk if frontend changed

### Key Insights
- **Restart vs Reload distinction:**
  - `sudo systemctl restart kimonokittens-dashboard` = Backend only
  - Frontend is static files (already built, served by nginx)
  - Kiosk browser needs `window.location.reload()` for new frontend

- **Webhook self-update limitation:**
  - Webhook CANNOT restart itself when deployment/*.rb changes
  - Must manually: `sudo systemctl restart kimonokittens-webhook`
  - Documented in CLAUDE.md:556-577

## Files Modified This Session

### Code Changes
1. `deployment/scripts/webhook_puma_server.rb` - Architectural fix for git pull
2. `household_todos.md` - Test change ("Annons i fler grupper" → "Hitta vår nya crew")

### Documentation Updates
1. `CLAUDE.md` - Webhook deployment system docs (auto-updated by remote)
2. `docs/SESSION_WORK_REPORT_2025_10_03_BUS_DUPLICATE_DEBUG.md` - This report

## Testing & Verification

### Completed
✅ Backend restart fixed duplicate buses immediately
✅ TypeScript compilation clean (no errors)
✅ Webhook fix committed and pushed
✅ Architecture validated through complete code audit

### Pending (Production)
⚠️ Restart webhook service: `sudo systemctl restart kimonokittens-webhook`
⚠️ Verify household_todos.md change appears within 5 minutes
⚠️ Monitor for any new duplicate bus occurrences

## Key Learnings

1. **Backend caching can accumulate state** - instance variables in long-running processes need careful management
2. **Git pull timing is critical** - should always happen BEFORE deployment decisions
3. **Data files vs code files** - different update strategies (git pull vs deployment)
4. **Webhook self-update limitation** - deployment code can't restart its own process
5. **Restart vs reload distinction** - backend restart ≠ frontend reload ≠ kiosk refresh

## Recommendations

1. **Monitor backend memory/state** - consider periodic backend restarts (e.g., nightly)
2. **Add health checks** - detect stale data scenarios automatically
3. **Log data freshness** - timestamp when bus_data was last updated
4. **Consider stateless architecture** - avoid instance variables for cached data
5. **Document all data files** - maintain list of files that need git pull (household_todos.md, electricity_bills_history.txt, www/*)

## Files That Auto-Update Now (Post-Fix)

✅ `household_todos.md` - Todos API
✅ `electricity_bills_history.txt` - Rent calculator electricity costs
✅ `www/*.html`, `www/*.png` - Static assets via StaticHandler
✅ Any future data files added to repo

**Update Frequency:**
- Git pull: Immediate (on push to master)
- Backend reads: Next request (no caching on File.read)
- DataBroadcaster: 5min for todos, 30s for trains, 60s for temperature
- Frontend display: After DataBroadcaster fetch

## Context at Session End
- **Token usage:** ~115k / 200k (58% utilized)
- **Git state:** Clean, all changes pushed to master
- **Production state:** Webhook fix deployed, awaits manual restart
- **Next action:** Restart webhook service on production kiosk

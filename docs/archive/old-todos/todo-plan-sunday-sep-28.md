# Todo Plan - Sunday September 28, 2025

## Completed Today ✅

### Process Management System Implementation
- ✅ **Fixed process management bugs**: Socket path issues in bin/dev status/stop commands
- ✅ **Added foreman to Gemfile**: Proper dependency management for development
- ✅ **Tested all process commands**: start, stop, restart, status, logs all working
- ✅ **Created npm script aliases**: `npm run dev`, `dev:stop`, `dev:status`, `dev:restart`, `dev:logs`
- ✅ **Updated CLAUDE.md**: Added comprehensive development workflow documentation
- ✅ **Clean process state**: Eliminated straggling processes from previous sessions

**Impact**: Prevents cache-related bugs like the 7,492 kr rent calculation error caused by stale server processes.

## Pending Tasks 🚧

### 1. Temperature Schedule Bar Enhancement ✅
**Priority**: Medium → **COMPLETED**
**Description**: Upgrade temperature schedule visualization to use complete 24-hour schedule data

**Implementation Summary**:
- ✅ **Upgraded from simple string parsing** ("15-21") to **full schedule_data array parsing**
- ✅ **Added multi-day support** - each schedule entry has full ISO timestamp with date
- ✅ **Enhanced precision** - hour-by-hour on/off periods instead of simple ranges
- ✅ **Preserved timezone handling** - applies same -1 hour Thermiq offset to schedule data
- ✅ **Date-aware mapping** - uses `YYYY-M-D-H` keys for precise lookups across multiple days
- ✅ **No midnight-spanning quirks** - each time period explicitly dated in ISO format
- ✅ **Maintained existing visualization** - same 16-hour timeline and heating state logic

**Technical Achievement**:
- Enhanced accuracy from simplified range display to hour-by-hour schedule precision
- Preserved all existing staleness detection, heating states, and visual animations
- Schedule bar now displays actual heating schedule with granular on/off periods

### 2. Bus Departure Visibility Investigation
**Priority**: High
**Description**: Bus departure list appearing empty despite valid data being sent from server

**Current State**:
- Server logs show buses with valid `minutes_until` values (3, 3, 7, 15 minutes)
- Frontend filtering logic appears correct (`isFeasibleBusDeparture >= 0`)
- User reports seeing empty bus list

**Next Steps**:
- Inspect browser console for frontend debug logs
- Check if frontend state management is filtering buses incorrectly
- Verify WebSocket data reception in browser
- Test with different time periods to isolate timing issues

**Latest Data Example**:
```json
"buses": [
  {"departure_time":"18:44", "minutes_until":3, "line_number":"709"},
  {"departure_time":"18:45", "minutes_until":3, "line_number":"705"},
  {"departure_time":"18:48", "minutes_until":7, "line_number":"705"},
  {"departure_time":"18:56", "minutes_until":15, "line_number":"865"}
]
```

## Process Management Note 📝

**About "Overmind not running" errors**: This is normal and expected behavior, not an error to avoid. It appears when:
1. No development processes are currently running (which is correct)
2. You run `bin/dev status` or `npm run dev:status` when processes are stopped

This message indicates the system is working correctly - it's checking for running processes and accurately reporting none are found. It's only followed by helpful fallback commands for manual cleanup if needed.

## Development Workflow Reminder 🔧

Always use these commands for development:
```bash
npm run dev          # Start all processes
npm run dev:restart  # Clean restart (prevents cache issues)
npm run dev:stop     # Stop all processes
npm run dev:status   # Check what's running
```

## Files Modified Today 📁

- `bin/dev` - Fixed socket path and overmind flags
- `Gemfile` - Added foreman dependency
- `package.json` - Added npm script aliases
- `CLAUDE.md` - Added development workflow documentation
- `Procfile.dev` - Process definitions
- `.claude/settings.local.json` - Added command permissions
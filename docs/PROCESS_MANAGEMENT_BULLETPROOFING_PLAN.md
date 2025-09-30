# Process Management Bulletproofing Plan
## Preventing Zombie Overmind/Tmux Sessions Forever

**Date**: September 30, 2025
**Status**: ✅ FULLY IMPLEMENTED & PRODUCTION READY
**Priority**: 🔥 CRITICAL - This MUST work every single time

**UPDATE**: All planned changes implemented and battle-tested. See `PROCESS_MANAGEMENT_DEEP_DIVE.md` for:
- Complete root cause analysis (3 cascading failures)
- Implementation details and testing results
- Troubleshooting guide
- Lessons learned

**Key Achievements**:
- ✅ Three-tier cleanup strategy implemented
- ✅ Critical lsof syntax bug fixed (commit `4f72e62`)
- ✅ Pre-flight checks in start command
- ✅ Enhanced status command with zombie detection
- ✅ Nuclear cleanup option (`bin/dev nuke`)
- ✅ Comprehensive documentation

---

## Executive Summary

The current `bin/dev` script has a critical flaw: it can leave zombie tmux sessions and stale socket files when processes terminate unexpectedly (terminal closure, system crashes, force-quit). This creates a cascading failure where:

1. Socket file `.overmind.sock` exists but points to a dead session
2. `overmind status` fails silently
3. `bin/dev restart` thinks Overmind is running
4. New start attempts fail with "already running" error
5. Manual intervention required to clean up

**This must NEVER happen again.**

---

## Research Findings

### Known Overmind Issues

**Issue #164**: "How to clear our tmux if overmind thinks its already running?"
- **Root cause**: Stale `.overmind.sock` file after unexpected termination
- **Official solution**: `rm ./.overmind.sock` and restart
- **Problem**: Doesn't handle orphaned tmux sessions

**Issue #50**: "Better way to deal with unexpected termination"
- **Finding**: Closing terminal leaves processes running in tmux session
- **Impact**: Orphan processes + stale socket = broken state

### Overmind Architecture

**How it works:**
- Creates a tmux session with name pattern: `overmind-{project}-{random}`
- Creates socket file: `.overmind.sock`
- Manages processes via tmux panes

**Commands:**
- `overmind quit` - Gracefully stops all processes AND shuts down Overmind (cleans up tmux)
- `overmind stop` - Stops processes but leaves Overmind/tmux running
- `overmind restart` - Restarts processes within existing session

**Current `bin/dev` flaw:** Uses `overmind quit` in `stop` command, but if Overmind is already dead, the socket remains and orphaned tmux sessions persist.

### Claude Code Background Task Limitations

**From research:**
> "Claude Code isn't able to properly handle [long-running background tasks] yet - when a job is forced to the background, CC doesn't know how to get the job's logs, so while the flags work, the implementation isn't quite there."

**Implication:** We can't rely on Claude Code to manage long-lived processes gracefully. The `bin/dev` script must be 100% bulletproof and idempotent.

---

## Current State Analysis

### What We Found

**Zombie tmux sessions:**
```bash
$ ps aux | grep overmind | grep -v grep
fredrikbranstrom 99741  ... tmux -C -L overmind-kimonokittens-ixYQL3A5fHj2QChSIEIEX ...
fredrikbranstrom 95036  ... tmux -C -L overmind-kimonokittens-nCeRxyAIg-DKd3ePhlwpo ...
fredrikbranstrom 81434  ... tmux -C -L overmind-kimonokittens-X4xn0b5It75gVDlLRVFWC ...
fredrikbranstrom 26409  ... tmux -C -L overmind-kimonokittens-5dQcaOetZeFzpW5gx1hR0 ...
```

**4 orphaned sessions** from different times:
- Sunday 7PM
- Monday 1AM
- Monday 3PM (2 sessions)

**Stale socket:** `.overmind.sock` exists, points to dead session

**Port occupied:** Backend (PID 99747) running standalone, not via Overmind

### Why Current Script Fails

**Lines 38-40 in `bin/dev` stop command:**
```bash
if have_overmind && running_overmind; then
  overmind quit
fi
```

**Problem:** `running_overmind()` (line 11) checks:
```bash
running_overmind() { [ -S "$SOCKET" ] && overmind status >/dev/null 2>&1; }
```

**Failure scenario:**
1. Socket file exists (returns true for `[ -S "$SOCKET" ]`)
2. But session is dead, so `overmind status` fails (returns false)
3. Combined check fails, `overmind quit` never runs
4. Cleanup code (lines 43-47) runs, but only kills ports/processes
5. **Socket and tmux sessions remain!**

**Next `bin/dev start` attempt:**
- Line 25: `running_overmind` check passes because socket exists
- Line 26: "dev already running – attaching"
- Line 27: `overmind connect` fails because session is dead
- **User is stuck**

---

## The Bulletproof Solution

### Design Principles

1. **Nuclear cleanup**: Kill everything with extreme prejudice
2. **Idempotent operations**: Can run 100 times, always works
3. **Zero trust**: Never trust socket/process state
4. **Defense in depth**: Multiple cleanup strategies (session → socket → port → process)
5. **Clear communication**: Tell user exactly what's happening

### New Architecture

**Three cleanup levels:**

1. **LEVEL 1: Graceful** (`bin/dev stop`)
   - Try `overmind quit` if session is healthy
   - Then proceed to aggressive cleanup

2. **LEVEL 2: Aggressive** (`bin/dev stop` fallback)
   - Kill all tmux sessions matching project pattern
   - Remove socket file unconditionally
   - Kill processes by port
   - Kill processes by name pattern

3. **LEVEL 3: Nuclear** (`bin/dev nuke` - new command)
   - Kill ALL tmux sessions (not just project)
   - Remove all tmux sockets for user
   - Kill ALL Ruby/Node processes
   - Clear all possible state

### Implementation Plan

#### Phase 1: Fix `bin/dev stop` Command ✅

**Replace lines 37-49 with:**

```bash
stop)
  echo "🛑 Stopping all development processes..."

  # LEVEL 1: Try graceful shutdown if Overmind is actually running
  if have_overmind; then
    if overmind status >/dev/null 2>&1; then
      echo "   Graceful Overmind shutdown..."
      overmind quit 2>/dev/null || true
      sleep 0.5
    fi
  fi

  # LEVEL 2: Aggressive cleanup (ALWAYS runs, regardless of Level 1 result)
  echo "   Aggressive cleanup..."

  # Kill ALL tmux sessions matching our project pattern
  tmux_sessions=$(tmux list-sessions -F "#{session_name}" 2>/dev/null | grep "^kimonokittens" || true)
  if [ -n "$tmux_sessions" ]; then
    echo "   Killing tmux sessions: $tmux_sessions"
    echo "$tmux_sessions" | xargs -I {} tmux kill-session -t {} 2>/dev/null || true
  fi

  # Kill ALL orphaned tmux processes with our project in the name
  pkill -f 'tmux.*overmind-kimonokittens' 2>/dev/null || true

  # Remove socket file unconditionally
  if [ -e "$SOCKET" ]; then
    echo "   Removing socket: $SOCKET"
    rm -f "$SOCKET"
  fi

  # Remove any tmux temporary directories for this project
  rm -rf /tmp/tmux-$(id -u)/overmind-kimonokittens-* 2>/dev/null || true
  rm -rf /var/folders/*/T/overmind-kimonokittens-* 2>/dev/null || true

  # Kill processes by port (existing logic)
  ports_to_kill=$(lsof -ti :3001,:5175 2>/dev/null || true)
  if [ -n "$ports_to_kill" ]; then
    echo "   Killing processes on ports 3001, 5175: $ports_to_kill"
    echo "$ports_to_kill" | xargs kill -9 2>/dev/null || true
  fi

  # Kill processes by name pattern
  pkill -f 'ruby.*puma_server.rb' 2>/dev/null || true
  pkill -f 'vite.*--port 5175' 2>/dev/null || true

  sleep 1
  echo "✅ All processes stopped and cleaned up."
  ;;
```

#### Phase 2: Add `bin/dev nuke` Command ✅

**Add new case before the default `*` case:**

```bash
nuke)
  echo "☢️  NUCLEAR CLEANUP - Killing ALL tmux sessions and processes"
  echo ""
  read -p "This will kill ALL tmux sessions and Ruby/Node processes. Continue? [y/N] " -n 1 -r
  echo
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 1
  fi

  echo "🧨 Proceeding with nuclear cleanup..."

  # Kill ALL tmux sessions
  tmux_sessions=$(tmux list-sessions -F "#{session_name}" 2>/dev/null || true)
  if [ -n "$tmux_sessions" ]; then
    echo "   Killing all tmux sessions"
    tmux kill-server 2>/dev/null || true
  fi

  # Remove ALL tmux sockets for current user
  rm -rf /tmp/tmux-$(id -u)/* 2>/dev/null || true
  rm -rf /var/folders/*/T/tmux-$(id -u)/* 2>/dev/null || true

  # Remove project socket
  rm -f "$SOCKET" 2>/dev/null || true

  # Kill ALL Ruby processes
  pkill -9 ruby 2>/dev/null || true

  # Kill ALL Node processes
  pkill -9 node 2>/dev/null || true

  # Kill ALL processes on development ports
  lsof -ti :3001,:5175,:8080,:3000,:5000 2>/dev/null | xargs -r kill -9 2>/dev/null || true

  sleep 2
  echo "☢️  Nuclear cleanup complete. All clear."
  echo ""
  echo "You can now run: bin/dev start"
  ;;
```

#### Phase 3: Improve `bin/dev restart` Command ✅

**Replace lines 100-109 with:**

```bash
restart)
  echo "🔄 Restarting development environment..."

  # NEVER trust Overmind's restart - always do stop → start
  # This ensures clean state every time
  "$0" stop
  sleep 2
  exec "$0" start
  ;;
```

**Reasoning:** Overmind's `restart` command only works if the session is healthy. If it's in a broken state, it fails silently. Always do nuclear stop → clean start.

#### Phase 4: Improve `bin/dev start` Command ✅

**Replace lines 16-36 with:**

```bash
start)
  ensure_tmp

  echo "🚀 Starting development environment..."

  # Pre-flight check: Ensure we're in clean state
  if [ -S "$SOCKET" ]; then
    echo "⚠️  Socket file exists, verifying session..."
    if ! overmind status >/dev/null 2>&1; then
      echo "⚠️  Stale socket detected. Running cleanup..."
      "$0" stop
      sleep 1
    fi
  fi

  # Aggressive port cleanup to handle straggling processes
  ports_to_kill=$(lsof -ti :3001,:5175 2>/dev/null || true)
  if [ -n "$ports_to_kill" ]; then
    echo "⚠️  Ports occupied, cleaning up: $ports_to_kill"
    echo "$ports_to_kill" | xargs kill -9 2>/dev/null || true
    sleep 1
  fi

  if have_overmind; then
    if running_overmind; then
      echo "✅ Dev already running – attaching"
      exec overmind connect
    else
      echo "✨ Starting fresh Overmind session..."
      exec overmind start -f "$PROCFILE" -p "$PORT_BASE"
    fi
  else
    echo "⚠️  Overmind not found; using foreman via Bundler"
    echo "    (Install with: brew install tmux overmind)"
    exec bundle exec foreman start -f "$PROCFILE" -p "$PORT_BASE"
  fi
  ;;
```

#### Phase 5: Add Health Check Command ✅

**Update `status` command (lines 50-99) to include cleanup recommendations:**

```bash
status)
  echo "🔍 Development Environment Status"
  echo "================================="

  # Check Overmind status
  overmind_healthy=false
  if have_overmind; then
    if overmind status >/dev/null 2>&1; then
      echo "✅ Overmind: RUNNING"
      overmind status 2>/dev/null || echo "   (Status details unavailable)"
      overmind_healthy=true
    else
      echo "❌ Overmind: NOT RUNNING"
      if [ -S "$SOCKET" ]; then
        echo "⚠️  WARNING: Stale socket detected at $SOCKET"
      fi
    fi
  else
    echo "⚠️  Overmind: NOT INSTALLED"
  fi

  # Check for zombie tmux sessions
  zombie_sessions=$(tmux list-sessions -F "#{session_name}" 2>/dev/null | grep "^kimonokittens" || true)
  if [ -n "$zombie_sessions" ]; then
    echo "⚠️  WARNING: Zombie tmux sessions detected:"
    echo "$zombie_sessions" | sed 's/^/      /'
  fi

  # Check for orphaned tmux processes
  orphan_count=$(pgrep -f 'tmux.*overmind-kimonokittens' 2>/dev/null | wc -l | tr -d ' ')
  if [ "$orphan_count" -gt 0 ]; then
    echo "⚠️  WARNING: $orphan_count orphaned tmux processes detected"
  fi

  echo ""
  echo "📊 Port Analysis:"

  # Check port 3001 (backend)
  backend_proc=$(lsof -ti :3001 2>/dev/null || true)
  if [ -n "$backend_proc" ]; then
    backend_cmd=$(ps -p "$backend_proc" -o comm= 2>/dev/null || echo "unknown")
    echo "✅ Port 3001 (Backend): OCCUPIED by PID $backend_proc ($backend_cmd)"
  else
    echo "❌ Port 3001 (Backend): FREE"
  fi

  # Check port 5175 (frontend)
  frontend_proc=$(lsof -ti :5175 2>/dev/null || true)
  if [ -n "$frontend_proc" ]; then
    frontend_cmd=$(ps -p "$frontend_proc" -o comm= 2>/dev/null || echo "unknown")
    echo "✅ Port 5175 (Frontend): OCCUPIED by PID $frontend_proc ($frontend_cmd)"
  else
    echo "❌ Port 5175 (Frontend): FREE"
  fi

  echo ""
  echo "🔧 Process Summary:"
  ruby_procs=$(pgrep -f 'ruby.*puma_server.rb' 2>/dev/null | wc -l | tr -d ' ')
  vite_procs=$(pgrep -f 'vite.*--port 5175' 2>/dev/null | wc -l | tr -d ' ')
  echo "   Ruby processes: $ruby_procs"
  echo "   Vite processes: $vite_procs"

  # Overall health check
  echo ""
  if [ "$overmind_healthy" = true ] && [ -n "$backend_proc" ] && [ -n "$frontend_proc" ]; then
    echo "🟢 Status: HEALTHY - All systems operational"
  elif [ -n "$backend_proc" ] || [ -n "$frontend_proc" ]; then
    echo "🟡 Status: PARTIAL - Some services running"
    echo ""
    echo "💡 Recommendation: Run 'bin/dev restart' for clean state"
  else
    echo "🔴 Status: STOPPED - No services running"
    if [ -S "$SOCKET" ] || [ -n "$zombie_sessions" ] || [ "$orphan_count" -gt 0 ]; then
      echo ""
      echo "⚠️  CLEANUP NEEDED:"
      [ -S "$SOCKET" ] && echo "   • Stale socket file"
      [ -n "$zombie_sessions" ] && echo "   • Zombie tmux sessions"
      [ "$orphan_count" -gt 0 ] && echo "   • Orphaned tmux processes"
      echo ""
      echo "💡 Run: bin/dev stop    # Aggressive cleanup"
      echo "💡 Or:  bin/dev nuke    # Nuclear cleanup (last resort)"
    fi
  fi
  ;;
```

#### Phase 6: Update Help Text ✅

**Update the `*` case (lines 118-129) to include new `nuke` command:**

```bash
*)
  echo "Usage: bin/dev [start|stop|restart|status|logs|nuke]"
  echo ""
  echo "  start   - Start all dev processes (backend + frontend)"
  echo "  stop    - Stop all dev processes (aggressive cleanup)"
  echo "  restart - Restart all dev processes (stop + start)"
  echo "  status  - Show process status and health check"
  echo "  logs    - View/attach to process logs"
  echo "  nuke    - Nuclear cleanup (kills ALL tmux and Ruby/Node)"
  echo ""
  echo "Processes: Ruby backend (port 3001), Vite frontend (port 5175)"
  echo ""
  echo "🔧 Troubleshooting:"
  echo "   If 'start' fails with 'already running', run: bin/dev stop"
  echo "   If 'stop' doesn't fix it, run: bin/dev nuke"
  exit 1
  ;;
```

---

## Testing Plan

### Manual Testing Scenarios

**Scenario 1: Normal operation**
```bash
bin/dev start      # Should start cleanly
bin/dev status     # Should show healthy
bin/dev restart    # Should restart cleanly
bin/dev stop       # Should stop cleanly
```

**Scenario 2: Terminal force-close**
```bash
bin/dev start      # Start services
# Force-close terminal (Cmd+Q or kill Terminal.app)
# Open new terminal
bin/dev status     # Should detect zombies
bin/dev stop       # Should clean up everything
bin/dev start      # Should start fresh
```

**Scenario 3: System crash simulation**
```bash
bin/dev start      # Start services
rm .overmind.sock  # Simulate socket loss
# Kill tmux processes but leave Ruby/Vite running
kill <tmux_pid>
bin/dev status     # Should detect broken state
bin/dev restart    # Should recover
```

**Scenario 4: Multiple zombie sessions**
```bash
# Manually create 4+ zombie sessions
# Leave stale socket
bin/dev status     # Should list all zombies
bin/dev stop       # Should kill all
bin/dev start      # Should start fresh
```

**Scenario 5: Nuclear option**
```bash
# Create absolute chaos (multiple sessions, stale sockets, orphaned processes)
bin/dev nuke       # Should prompt for confirmation
# Answer 'y'
bin/dev status     # Should show clean slate
bin/dev start      # Should start fresh
```

### Automated Testing

**Create test script: `test/bin_dev_test.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail

echo "Testing bin/dev script robustness..."

# Test 1: Clean start/stop
echo "Test 1: Clean start/stop"
bin/dev start &
sleep 5
bin/dev stop
sleep 2
if bin/dev status | grep -q "STOPPED"; then
  echo "✅ Test 1 passed"
else
  echo "❌ Test 1 failed"
  exit 1
fi

# Test 2: Stale socket handling
echo "Test 2: Stale socket handling"
bin/dev start &
sleep 5
# Simulate stale socket
mv .overmind.sock .overmind.sock.old
touch .overmind.sock
bin/dev restart
sleep 5
if bin/dev status | grep -q "HEALTHY"; then
  echo "✅ Test 2 passed"
else
  echo "❌ Test 2 failed"
  exit 1
fi
bin/dev stop

echo "All tests passed!"
```

---

## Migration Strategy

### Step 1: Backup Current Script ✅

```bash
cp bin/dev bin/dev.backup.20250930
git add bin/dev.backup.20250930
git commit -m "backup: Save current bin/dev before bulletproofing"
```

### Step 2: Implement Changes ✅

Apply all changes from Implementation Plan phases 1-6 to `bin/dev`.

### Step 3: Test in Isolation ✅

```bash
# Test the new script without committing
chmod +x bin/dev
./test/bin_dev_test.sh
```

### Step 4: Manual Verification ✅

Run through all testing scenarios manually.

### Step 5: Update Documentation ✅

Update `CLAUDE.md` with new commands and troubleshooting guide.

### Step 6: Commit & Deploy ✅

```bash
git add bin/dev CLAUDE.md
git commit -m "fix: bulletproof bin/dev process management

- Aggressive cleanup in stop command (kills zombie tmux sessions)
- Pre-flight checks in start command (detects stale state)
- Nuclear cleanup option (bin/dev nuke)
- Enhanced status command (detects zombies and recommends fixes)
- Improved restart (always stop → start, never trust overmind restart)

This prevents zombie Overmind/tmux sessions from EVER breaking the
development environment again."
```

---

## Rollback Plan

If the new script causes issues:

```bash
# Restore backup
cp bin/dev.backup.20250930 bin/dev
chmod +x bin/dev

# Clean up current mess
bin/dev nuke  # Using the old backup script

# Restart
bin/dev start
```

---

## Future Enhancements

### Phase 7: Process Monitoring (Optional)

Add a background watchdog that monitors for zombie sessions:

```bash
# bin/dev-watchdog
#!/usr/bin/env bash
while true; do
  if zombie_count=$(pgrep -f 'tmux.*overmind-kimonokittens' | wc -l); then
    if [ "$zombie_count" -gt 1 ]; then
      echo "⚠️  Detected $zombie_count zombie tmux processes"
      echo "💡 Run: bin/dev stop"
    fi
  fi
  sleep 300  # Check every 5 minutes
done
```

### Phase 8: Integration with Claude Code (Future)

When Claude Code's background task support matures, create a hook:

```bash
# .claude/hooks/on-session-start.sh
#!/usr/bin/env bash
# Automatically check for zombies when Claude Code session starts
bin/dev status
```

---

## Success Criteria

✅ **bin/dev stop** kills everything, every time, no exceptions
✅ **bin/dev start** always works after stop, no manual cleanup needed
✅ **bin/dev restart** is 100% reliable
✅ **bin/dev nuke** provides nuclear option for worst-case scenarios
✅ **bin/dev status** accurately detects broken states and recommends fixes
✅ Terminal force-close doesn't break the environment
✅ System crashes don't require manual tmux cleanup
✅ Multiple Claude Code sessions can safely run bin/dev commands
✅ Zero manual `rm .overmind.sock` commands needed ever again

---

## Lessons Learned

1. **Never trust process state** - Always verify with multiple checks
2. **Socket existence ≠ session alive** - Check `overmind status` return code
3. **Cleanup must be aggressive** - Pattern matching and unconditional removal
4. **Idempotency is key** - Operations must work 100 times in a row
5. **Defense in depth** - Multiple cleanup strategies (session → socket → port → process)
6. **Clear user communication** - Tell user what's happening and why
7. **Provide escape hatch** - Nuclear option for when everything else fails

---

**Document Status:** ✅ Ready for Implementation
**Last Updated:** September 30, 2025
**Review Required:** Yes - User approval before modifying bin/dev
**Estimated Time:** 1-2 hours implementation + testing

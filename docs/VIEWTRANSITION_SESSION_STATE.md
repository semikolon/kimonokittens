# ViewTransition Migration - Session State (Oct 1, 2025)

**Status**: ✅ Phase 1 COMPLETE - Ready for Phase 2 Integration

## Current State Summary

### Phase 1 Completed (5/5 tasks)
1. ✅ Reverted to React 19.1.0 stable (commit `be5a865`)
2. ✅ Created native ViewTransition wrapper at `dashboard/src/components/ViewTransition.tsx` (commit `6884894`)
3. ✅ Structural change detection built into `startListTransition()` function
4. ✅ Performance instrumentation with PerformanceObserver + marks (lines 29-55)
5. ✅ Dev server verified working (PIDs: 95649 ruby, 95692 vite)

### Files Created/Modified

**New Files:**
- `dashboard/src/components/ViewTransition.tsx` (116 lines) - Native API wrapper
- `docs/VIEWTRANSITION_IMPLEMENTATION_NOTES.md` (309 lines) - Complete implementation plan

**Modified Files:**
- `dashboard/package.json` - React 19.1.0 exact version
- `dashboard/src/App.tsx` - Removed unused imports, fixed Widget props
- `bin/dev` - Reverted timeout changes, added `|| true` for set -e compatibility
- `CLAUDE.md` - Added Claude Code background process bug documentation + Vite cache cleanup section

### Key Decisions Made

**React Component Not Available:**
- `unstable_ViewTransition` exists in code but not exported (behind `enableViewTransition` flag)
- Facebook-internal only ("dynamic for www")
- Unknown public availability timeline
- Decision: Use native `document.startViewTransition()` with abstraction layer

**Performance Analysis:**
- flushSync penalty: 4-25ms typical (acceptable at 1-3 transitions/min)
- View Transitions overhead: ~70ms LCP (separate from flushSync)
- Kiosk context (low interactivity) makes penalty acceptable
- Auto-disable safety net: >80ms 3 times = disabled for session

**Discovered Bugs:**
1. **Claude Code**: Background process status tracking unreliable (system reminders lag behind BashOutput)
2. **bin/dev**: timeout in command substitution with `set -euo pipefail` caused instant failures
3. **Vite**: Cache corruption after React version changes (fixed: `rm -rf dashboard/node_modules/.vite`)

### Next: Phase 2 Implementation

**Goal**: Integrate ViewTransition in TrainWidget while keeping old system (dual system testing)

**Phase 2 Tasks (5 total):**
1. Import `startListTransition` helper in TrainWidget
2. Add `style={{ viewTransitionName: generateTrainId(train) }}` to train items
3. Add `style={{ viewTransitionName: generateBusId(bus) }}` to bus items
4. Wrap `setFeasibleTrains(...)` calls with `startListTransition(setFeasibleTrains, newTrains, hasStructuralChange)`
5. Test both animation systems work simultaneously

**Critical Implementation Details:**

**TrainWidget.tsx Structure:**
- Line 170-174: `generateTrainId()` - KEEP (becomes view-transition-name)
- Line 176-259: `useTrainListChanges()` - KEEP for Phase 2 (remove in Phase 4)
- Line 263-347: `useDepartureSequence()` - KEEP warning/critical, simplify departing in Phase 4
- Line 349-407: `useUrgentBusFlashing()` - KEEP (time-triggered, not list-triggered)
- Line 415-417: `isFeasibleTrainDeparture()` - KEEP (business logic)

**Structural Change Detection:**
```typescript
// Phase 2: Add this logic to detect when list membership changes
const hasStructuralChange = (oldList: T[], newList: T[]) => {
  // Compare IDs, not entire objects (avoid false positives from time updates)
  const oldIds = new Set(oldList.map(generateId));
  const newIds = new Set(newList.map(generateId));
  return oldIds.size !== newIds.size ||
         ![...oldIds].every(id => newIds.has(id));
};
```

**CSS Timing Requirements:**
- Entry animations: 5s slide-in (match current `.introducing` class)
- Exit animations: 400ms fade-out (match current `.departing` class)
- GPU acceleration: Use `transform` and `opacity` only

### Documentation Cross-References

**Implementation Details:**
- `VIEWTRANSITION_IMPLEMENTATION_NOTES.md` - Complete 7-phase plan (28 tasks)
- `VIEWTRANSITION_LOGIC_PRESERVATION_AUDIT.md` - Line-by-line analysis (1,160 lines)
- `VIEWTRANSITION_STRATEGY_COMPARISON.md` - Imperative vs declarative comparison

**Process Management:**
- `CLAUDE.md` lines 3-46 - Critical bug documentation + validation commands
- `CLAUDE.md` lines 45-61 - Vite cache cleanup after React version changes
- `docs/PROCESS_MANAGEMENT_DEEP_DIVE.md` - Complete technical analysis

### Commits This Session (5 total)

1. `6884894` - ViewTransition infrastructure + native API strategy
2. `be5a865` - React 19.1.0 stable revert (from canary)
3. `684f101` - App.tsx TypeScript fixes
4. `407028e` - Timeout handling attempt (later reverted)
5. `203618e` - Revert timeouts + document CC bug comprehensively

### Context for Next Session

**Where We Are:**
- Native ViewTransition wrapper ready at `dashboard/src/components/ViewTransition.tsx`
- Export: `startListTransition(setState, newState, isStructural)`
- Dev server running and verified with `ps` (React 19.1.0 stable)
- Full implementation plan documented in `VIEWTRANSITION_IMPLEMENTATION_NOTES.md`

**What to Do Next:**
1. Read `VIEWTRANSITION_IMPLEMENTATION_NOTES.md` Phase 2 section
2. Import `startListTransition` in TrainWidget.tsx
3. Add view-transition-name to train/bus items using existing generateTrainId/generateBusId
4. Wrap setState calls with structural change detection
5. Test dual animation system

**Critical Reminders:**
- ⚠️ Always verify background process status with `ps` or `BashOutput` tool
- ⚠️ Don't trust system reminder "status: running" messages
- ⚠️ After React version changes, clear Vite cache: `rm -rf dashboard/node_modules/.vite`
- ✅ bin/dev commands are solid (use `|| true` pattern for set -e compatibility)
- ✅ Structural change detection prevents false animations on time updates
- ✅ Performance instrumentation will auto-disable if >80ms 3 times

**Code Locations:**
- ViewTransition wrapper: `dashboard/src/components/ViewTransition.tsx`
- Integration target: `dashboard/src/components/TrainWidget.tsx` (873 lines)
- CSS will go in: TrainWidget.tsx `<style>` tag or separate CSS file
- Documentation: `docs/VIEWTRANSITION_*.md` (3 files)

---

**Session End Context**: 11% context remaining, Phase 1 complete, ready for Phase 2 integration with complete implementation plan on disk.

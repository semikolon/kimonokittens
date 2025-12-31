# Dashboard Frontend Instructions

**Parent context:** See `/CLAUDE.md` for monorepo architecture, critical protocols, and deployment workflows.

---

## 🎨 UI COLOR SCHEME

**CRITICAL: Never use green or emerald colors for success states, buttons, or positive indicators.**

**Approved Color Palette:**
- **Primary**: Purple (`purple-100` through `purple-900`) - Main brand color, headings, accents
- **Background**: Slate (`slate-700` through `slate-900`) - Dark backgrounds, surfaces
- **Success/Positive**: Cyan (`cyan-300` through `cyan-600`) - Turquoise/aqua tone, NOT green/emerald
- **Warning/Pending**: Yellow (`yellow-300` through `yellow-600`) - Pending states, warnings
- **Error/Negative**: Red (`red-300` through `red-600`) - Errors, failures, negative adjustments
- **Info/Secondary**: Blue (`blue-300` through `blue-600`) - Informational states
- **Neutral**: Slate (`slate-300` through `slate-600`) - Neutral/inactive states
- **Alert**: Orange (`orange-300` through `orange-600`) - Alerts, expirations

**Forbidden Colors:**
- ❌ **Green** (`green-*`) - Never use for any purpose
- ❌ **Emerald** (`emerald-*`) - Never use for any purpose
- ❌ **Lime** (`lime-*`) - Never use for any purpose

**Examples:**
- ✅ Completed status: `text-cyan-400`, `bg-cyan-400/20 border-cyan-400/30`
- ✅ Action button: `bg-cyan-600/80 hover:bg-cyan-600`
- ✅ Room discount: `text-cyan-400` (negative adjustment = discount)
- ❌ Never: `text-green-400`, `bg-emerald-600`, etc.

---

## Frontend Development

### Environment & Workflow

**SSH port forwarding** (Mac → Linux dev machine):
```bash
# ~/.ssh/config on Mac
Host kimonokittens
  HostName <linux-ip>
  User fredrik
  LocalForward 5175 localhost:5175  # Vite dev server
  LocalForward 3001 localhost:3001  # Ruby backend API
```

**Development loop:**
1. SSH with forwarding: `ssh kimonokittens`
2. Start dev servers: `cd ~/Projects/kimonokittens && bin/dev start`
3. Open browser on Mac: `http://localhost:5175`
4. Edit code → Vite HMR auto-reloads → push → webhook deploys to production

**Dependencies** (fredrik dev checkout): Ruby (rbenv), Bundle (`bundle install`), Node/npm (`npm install` in dashboard/)

### Implementation Patterns

**Animation** - Stable identity keys prevent false re-renders:
```typescript
// ✅ Good: const id = `${departure_time}-${line_number}-${destination}`
// ❌ Bad:  const id = `${adjusted_time}-${line_number}-${destination}` // Changes on delays
```

**CSS gotchas** (`TrainWidget.tsx`): `background` shorthand resets all → use `background-image` with `background-clip: text`; add `animation-fill-mode: forwards`; interval ≠ duration (race condition); use `background-repeat: repeat-x` for gradients.

**Performance**: `transform`/`opacity` for GPU acceleration, respect `prefers-reduced-motion`, clean up in useEffect.

**Form Editing Patterns:**

**Inline forms** (faster, maintains context):
- Text/date field edits in expanded detail views
- Multi-field sequences with tab navigation
- Pattern: Button → input reveals inline + Save/Cancel buttons
- Examples: `TenantDetails.tsx` departure date, contact fields
- Use when: User already viewing/editing the entity

**Modal dialogs** (demands attention, isolates action):
- Authentication gates (PIN entry)
- Destructive actions (delete confirmation)
- Multi-step flows (wizards, onboarding)
- Creating new entities (separate from existing data)
- Examples: `AdminAuthContext.tsx` PIN gate, `ContractDetails.tsx` cancel confirmation

**Decision guide**: User already editing an existing item → inline keeps flow. Need user focus/confirmation or creating something new → modal provides isolation.

---

## Kiosk Display Optimization

**WebGL Shader Impact** (`animated-shader-background.tsx`):
- +7-8% GPU, +16-21°C temp, +23-24W power, increased fan noise
- **Recommendation**: Disable for 24/7 use (reduces wear, ~200 kWh/year saved, quieter)
- To disable: Comment out `<AnoAI />` in `App.tsx`

**Thermal History & Cabinet Ventilation:**
- **Oct 6, 2025** (baseline with cabinet door ajar after shader thermal issues):
  - GPU: 54°C (shader off), 75°C (shader on, +21°C)
  - Power: 19W (shader off), 43W (shader on, +24W)
  - **Context**: Door ajar for cooling, not closed-cabinet baseline
- **Dec 31, 2025** (cabinet closed with ventilation holes cut in back panel):
  - GPU: 59°C @ 37% utilization, CPU: 60-62°C
  - **Result**: Only +5°C vs door-ajar despite closed cabinet - ventilation holes working excellently
  - 45+ days uptime, no thermal throttling, 34°C margin to GPU critical temp (93°C)

**Note**: Hardware specs and Chrome GPU flags are in `~/.claude/CLAUDE.md` (global, machine-specific)

---

## WebSocket Integration

**Data flow:** See `/CLAUDE.md` for architecture overview.

**Frontend integration:**

**React Context** (`dashboard/src/context/DataContext.tsx`):
- Manages centralized state with useReducer
- Subscribes to WebSocket connection
- Receives broadcasts from backend DataBroadcaster
- Auto-reconnects on disconnect

**Consuming data in widgets:**
```typescript
import { useData } from '../context/DataContext';

function MyWidget() {
  const { temperature, rent, electricity } = useData();

  // Data updates automatically when WebSocket broadcasts
  return <div>{temperature.indoor}°C</div>;
}
```

**Widget patterns:**
- Widgets consume via `useData()` hook
- No manual polling - data pushed from backend
- React rerenders automatically on state updates

---

## 📝 Contract Signing (Admin UI)

**Backend integration:** See `/lib/CLAUDE.md` for Zigned API details.

**Creating contracts via admin UI:**

**Required tenant fields:**
- `name`
- `email`
- `personnummer` ← **MOST COMMON MISSING FIELD** (legally required for Swedish rental contracts)
- `start_date`

If any field missing: `400 Bad Request` with error identifying missing field.

**Contract creation flow:**
1. Admin clicks "Create Contract" in `TenantDetails.tsx`
2. Frontend validates required fields
3. POST to `/api/admin/contracts` with tenant data
4. Backend generates PDF → sends to Zigned → returns signing URL
5. Admin shares signing URL with tenant
6. Tenant signs → Zigned webhook → backend updates status → WebSocket broadcast → UI refreshes

**Contract status display:**
- **Pending**: Yellow badge, shows signing URL
- **Completed**: Cyan badge, shows signed date
- **Failed**: Red badge, shows error details

**Real-time updates:**
- WebSocket broadcasts contract status changes
- Admin UI updates automatically without refresh
- See `ContractDetails.tsx` for implementation

---

## Cache Cleanup After Major Changes

**CRITICAL: After major dependency changes (React version jumps, etc.), always clean build caches:**

```bash
# Clear Vite cache (fixes module resolution errors after React updates)
rm -rf dashboard/node_modules/.vite

# If problems persist, nuclear node_modules cleanup:
cd dashboard && rm -rf node_modules && npm install && cd ..
```

**Why this matters:**
- Vite caches React's internal dependency graph
- Version mismatches cause "Cannot find module" errors (e.g., `dep-BO5GbxpL.js`)
- Restart commands DON'T fix corrupted caches - manual cleanup required

---

## Frontend Testing

**Philosophy:** See `/CLAUDE.md` for universal testing principles.

**Frontend testing patterns:** (To be documented - Jest/React Testing Library)
- Component testing
- Mock WebSocket connections
- Accessibility testing

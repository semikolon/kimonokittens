# Kimonokittens Project Instructions

## ⚠️ CRITICAL: PROCESS MANAGEMENT PROTOCOL

**🔥 MANDATORY RULES FOR ALL CLAUDE CODE SESSIONS - NEVER DEVIATE! 🔥**

### ✅ ALWAYS DO:
- **ONLY** use these exact commands for ALL process management:
  ```bash
  npm run dev          # Start all processes (calls bin/dev start)
  npm run dev:stop     # Stop all processes (calls bin/dev stop)
  npm run dev:restart  # Clean restart (calls bin/dev restart)
  npm run dev:status   # Check status (calls bin/dev status)
  ```
- **ALWAYS** use `run_in_background=true` - commands are designed for background execution
- **ALWAYS** check status before starting to verify clean state

### ❌ NEVER DO:
- **NEVER** use direct commands like `ruby puma_server.rb` or `PORT=3001 ENABLE_BROADCASTER=1 ruby puma_server.rb`
- **NEVER** use `cd dashboard && npm run dev` directly
- **NEVER** spawn processes outside bin/dev control
- **NEVER** mix Claude Code background calls with direct process spawning

### 🚨 WHY THIS MATTERS:
**Orphaned processes cause:**
- Port conflicts ("Address already in use" errors)
- Stale data caching (7,492 kr rent bug was caused by old server running since Saturday)
- Development workflow chaos
- Hours of debugging pain

**The bin/dev commands include aggressive cleanup that handles orphaned processes from ANY source.**

---

**CRITICAL: Read this file completely before working on rent calculations or database operations.**

## Rent Calculation Timing Quirks ⚠️

### The Core Confusion: September Config → October Rent
**The dashboard calls for current month config but shows NEXT month's rent.**

- **Today: September 27, 2025**
- **Dashboard requests: September 2025 config** (`/api/rent/friendly_message` with no params)
- **Actually shows: October 2025 rent** ("Hyran för oktober 2025 ska betalas innan 27 sep")

**WHY:** Rent is paid **in advance** for the upcoming month, but operational costs (electricity) are paid **in arrears** for the previous month.

### Database Period Logic
```ruby
# To show October 2025 rent on September 27:
db.set_config('el', 2424, Time.new(2025, 9, 1))  # September period
# NOT: Time.new(2025, 10, 1)  # This would be wrong!
```

### Payment Structure & Quarterly Savings Mechanism

**Regular Monthly Payments (Advance)**:
- **Base rent** (`kallhyra`): October housing
- **Internet** (`bredband`): October service
- **Utilities** (`vattenavgift`, `va`, `larm`): Building up savings for quarterly bills

**Arrears Payments**:
- **Electricity** (`el`): September consumption bills

**Quarterly Bill Savings System**:
- **Monthly utilities**: 375 + 300 + 150 = **825 kr/month**
- **Purpose**: Internal "savings account" for quarterly building costs
- **Quarterly invoice**: ~2,600 kr (property tax, maintenance, building utilities)
- **Logic**: 825 kr × 3 months = 2,475 kr ≈ quarterly invoice amount
- **When quarterly arrives**: Replaces monthly utilities for that month

**Example:** September 27 payment covers:
- October base rent (advance) + October utilities (savings) + September electricity (arrears)
- OR October base rent (advance) + Q4 quarterly invoice (if it arrives) + September electricity (arrears)

## Database Safety Rules ⚠️

### Test Contamination Prevention
**NEVER let integration tests write to production database!**

**Problem:** `/spec/rent_calculator/integration_spec.rb` wrote `drift_rakning: 2612` to production DB, causing 7,492 kr instead of 7,045 kr rent calculations.

**Solutions:**
1. Use `test_mode: true` in all test scenarios
2. Use separate test database for integration tests
3. Clean up test data immediately after tests
4. Verify test isolation before running specs

### Database Configuration Keys
- **`el`**: Electricity cost (most frequently updated)
- **`drift_rakning`**: Quarterly invoice (replaces monthly fees when present)
- **Monthly fees**: `vattenavgift` + `va` + `larm` (used when no quarterly invoice)

## Documentation Locations

### Already Documented:
- **`rent.rb:12-17`**: Payment structure comments
- **`DEVELOPMENT.md:84-94`**: Electricity bill handling timeline
- **`RENT_DATA_SOURCE_TRANSPARENCY.md`**: Data source indicators

### Why This Wasn't Clear:
1. **Scattered documentation** across multiple files
2. **No central project-specific instructions** (this file fixes that)
3. **Timing logic buried in code comments** rather than prominent docs

## Quick Reference Commands

### Check Current Database Config:
```bash
ruby -e "require 'dotenv/load'; require_relative 'lib/rent_db'; db = RentDb.instance; db.get_rent_config(year: 2025, month: 9).each { |r| puts '  ' + r['key'] + ': ' + r['value'] }"
```

### Set October 2025 Rent Config:
```bash
# IMPORTANT: Use September period for October rent!
ruby -e "require 'dotenv/load'; require_relative 'lib/rent_db'; db = RentDb.instance; db.set_config('el', 2424, Time.new(2025, 9, 1))"
```

### Test API Response:
```bash
curl -s http://localhost:3001/api/rent/friendly_message | jq .message
```

## Expected Behavior

### Correct October 2025 Rent:
- **Individual rent**: 7,045 kr per person
- **Total apartment**: 28,179 kr
- **Data source**: "Baserad på aktuella elräkningar"
- **Electricity**: 2,424 kr total (Fortum 792 + Vattenfall 1632)

### Red Flags:
- **7,492 kr**: Usually indicates quarterly invoice contamination
- **7,286 kr**: Usually indicates historical/default data instead of actual bills
- **"Baserad på uppskattade elkostnader"**: Projection mode, not actual bills

## Development Workflow

### Process Management Protocol 🔧
**The bin/dev system provides foolproof process lifecycle management with aggressive cleanup.**

**Core Features**:
- **Aggressive port cleanup**: Kills ALL processes on ports 3001/5175 before starting
- **Background-friendly**: Designed to work perfectly with Claude Code's `run_in_background=true`
- **Idempotent operations**: Safe to run multiple times, always works
- **Comprehensive status**: Shows ports, processes, and Overmind state

**Commands**:
```bash
# Start all dev processes (backend + frontend)
npm run dev          # PREFERRED: Always use this

# Check comprehensive status
npm run dev:status   # Shows ports, processes, Overmind state

# Clean restart (most important for preventing bugs)
npm run dev:restart  # Kills everything, then starts fresh

# Stop all processes thoroughly
npm run dev:stop     # Aggressive cleanup of all processes

# View process logs
npm run dev:logs     # Attach to live process logs
```

**Architecture**:
- **Backend**: 3001 (Ruby Puma + WebSocket broadcaster)
- **Frontend**: 5175 (Vite dev server)
- **Process manager**: Overmind (preferred) or Foreman (fallback)
- **Definition**: `Procfile.dev` defines all development processes

**Critical Features for Claude Code**:
- Commands work perfectly with background execution
- Aggressive cleanup handles orphaned processes from ANY source
- Comprehensive error reporting guides correct usage
- All operations are idempotent and safe

### Code Change Workflow

1. **Before making rent changes**: Read this file
2. **Check database state**: Use quick reference commands above
3. **Update configs**: Use correct timing (current month period for next month rent)
4. **Restart processes**: `npm run dev:restart` to ensure fresh backend
5. **Verify results**: Test API and check dashboard
6. **Clean up**: Remove any test data from production DB

## Train/Bus Animation System 🚂 **COMPLETED ✅**

### Smart Identity Tracking for Sliding Animations
**Location**: `dashboard/src/components/TrainWidget.tsx:129-130`

The animation system uses **original departure times** for train/bus identity, not adjusted-if-late times:

```typescript
const generateTrainId = (train: TrainDeparture): string =>
  `${train.departure_time}-${train.line_number}-${train.destination}`
```

**Why this works**: Delayed trains maintain their identity and don't trigger unnecessary animations when delay info updates.

### Complete Animation System ✅ (September 29, 2025)
**Major breakthrough**: Fully implemented comprehensive animation system addressing all edge cases:

1. **Introduction Animations**: Both trains and buses slide in when becoming feasible (`introducing` class, 5s duration)
2. **Departure Animations**: Smooth removal animations when becoming infeasible (400ms slide out)
3. **Feasibility Transition Support**: Fixed core bug - trains transitioning infeasible→feasible now animate properly
4. **Smart List Change Detection**: Compare previous feasible vs current feasible (not raw API vs feasible)
5. **Bus Glow Timing**: Optimized from 4-3min to 2-1min to prevent slide-in glow
6. **Terminology Fix**: "introducing" (not "arriving" - trains arrive at platforms, not departure lists)

### Critical Bug Fixes Implemented ✅
- **Missing train introduction animations**: Trains had zero slide-in animations vs buses
- **Feasibility transition detection**: List change hooks compared wrong datasets causing missed transitions
- **False animation prevention**: 5-minute time window prevents API time updates from triggering animations
- **Animation simplification**: Removed blur/scale effects, reduced 10s→5s for cleaner experience
- **Störningar filtering**: Delayed trains in disruption box now respect adjusted feasibility times

### Performance & Architecture
- **GPU acceleration**: `transform` and `opacity` for 60fps animations
- **Accessibility**: Respects `prefers-reduced-motion` media query
- **Consistent timing**: 5s introduction, 400ms departure, 0.1s stagger per item
- **Memory management**: Proper cleanup of animation states and timeouts

## WebSocket Architecture ⚡

### DataBroadcaster URLs - FIXED ✅
**Environment variable solution implemented**: `lib/data_broadcaster.rb` now uses `ENV['API_BASE_URL']`

**Production ready**: Set `API_BASE_URL=https://your-domain.com` in production environment

### Data Flow
1. **Ruby DataBroadcaster** fetches from HTTP endpoints every 30-600s
2. **Custom WebSocket** (`puma_server.rb`) publishes to frontend via raw socket handling
3. **React Context** manages centralized state with useReducer
4. **Widgets** consume via `useData()` hook

## Project Quirks & Technical Debt 🔧

### Test Database Contamination
**Never let integration tests write to production DB!** Previous issue: `drift_rakning: 2612` written by specs, causing incorrect 7,492 kr calculations.

### Electricity Bill Timeline Complexity
**3-month lag**: January consumption → February bills arrive → March rent includes January costs (due Feb 27)

### SL Transport API - WORKING ✅
Train departures use **keyless SL Transport API** (`transport.integration.sl.se`) - no access tokens needed. Previous "fallback mode" references are outdated from old ResRobot migration.

---

**Remember: When in doubt about rent timing, the dashboard request month determines the config period, not the rent month shown in the message.**

## 🔄 SMART WEBHOOK DEPLOYMENT SYSTEM

### Overview: Modern Event-Driven Deployment

The kimonokittens project uses a **smart webhook system** with Puma architecture for automated deployments. The system analyzes changed files and only deploys what's necessary, with intelligent debouncing for rapid development workflows.

**Architecture**: Unified Puma + Rack across all services (dashboard port 3001, webhook port 9001)

### Key Features

#### 🎯 **Smart Change Analysis**
- **Frontend changes** (`dashboard/`) → Frontend rebuild + kiosk refresh only
- **Backend changes** (`.rb`, `.ru`, `Gemfile`) → Backend restart only
- **Docs/config only** → No deployment (zero disruption)
- **Mixed changes** → Deploy both components

#### ⏱️ **Deployment Debouncing (Anti-Spam)**
- **Problem**: Rapid git pushes (3-7 commits in 5 minutes) cause deployment spam
- **Solution**: 2-minute debounce timer (configurable via `WEBHOOK_DEBOUNCE_SECONDS`)
- **Behavior**: New push cancels previous timer, always deploys latest code
- **Guarantee**: `git pull origin master` ensures latest HEAD deployment

#### 🔒 **Database Safety**
- **Webhook never touches database** - deployments are code-only
- **Migrations are manual** - run `production_migration.rb` deliberately
- **Zero database risk** from automated deployments

### Deployment Scenarios

#### **Scenario A: Frontend Development**
```
You edit: dashboard/src/components/Widget.tsx
Webhook: Detects frontend change → npm run build → deploy to nginx → refresh kiosk
Result: New UI appears on kiosk, backend keeps running
```

#### **Scenario B: Backend Development**
```
You edit: handlers/rent_calculator_handler.rb
Webhook: Detects backend change → git pull → bundle install → restart service
Result: New API behavior, frontend stays cached
```

#### **Scenario C: Documentation**
```
You edit: README.md, docs/architecture.md
Webhook: No relevant changes detected → "No deployment needed"
Result: Zero disruption, zero resources wasted
```

#### **Scenario D: Rapid Development (Debouncing)**
```
10:01 - Push typo fix → "Deployment queued (2min debounce)"
10:02 - Push another fix → "Previous cancelled, new deployment queued"
10:03 - Push final fix → "Previous cancelled, new deployment queued"
10:05 - Timer fires → Deploys latest code only (all 3 fixes included)
Result: One deployment with all changes, not three separate deployments
```

### Webhook Endpoints

- **`POST /webhook`** - GitHub webhook receiver (signature verified)
- **`GET /health`** - Simple health check
- **`GET /status`** - Detailed status including pending deployments

### Monitoring Deployments

```bash
# Check if deployment is pending
curl http://localhost:9001/status | jq .deployment

# View webhook logs
journalctl -u kimonokittens-webhook -f

# View deployment timer status
curl http://localhost:9001/status | jq '{pending: .deployment.pending, time_remaining: .deployment.time_remaining}'
```

### Future-Proofing

The Puma architecture is designed for:
- **Multiple projects** - easily add new webhook endpoints
- **Concurrent requests** - multi-threaded webhook handling
- **Scalability** - same battle-tested server as dashboard
- **Cognitive ease** - unified Rack patterns across services

---

## 🚨 PRODUCTION DEPLOYMENT & HISTORICAL DATA MIGRATION

### CRITICAL: Historical Data Migration Protocol
**COMPLETED September 28, 2025** - All production deployments MUST include historical data migration.

#### Migration Components:
- **`deployment/production_migration.rb`**: Enhanced with historical JSON processing
- **`data/rent_history/`**: Required directory containing 14+ JSON files
- **Tenant Mapping**: Automatic name-to-ID conversion for foreign keys
- **Semantic Conversion**: CONFIG PERIOD MONTH → rent period month (month 7 → August rent)
- **Result**: 58 historical RentLedger records from corrected JSON data

#### Database State After Migration:
```
RentConfig: 7 records (electricity, base rent, utilities, quarterly invoice)
Tenants: 8 records (Adam, Amanda, Astrid, Elvira, Frans-Lukas, Fredrik, Malin, Rasmus)
RentLedger: 58 records (complete historical rent payments)
```

#### Migration Verification Commands:
```bash
# Verify RentLedger record count
ruby -e "require 'dotenv/load'; require_relative 'lib/rent_db'; puts RentDb.instance.class.rent_ledger.count"

# Check historical coverage
ruby -e "require 'dotenv/load'; require_relative 'lib/rent_db'; puts RentDb.instance.class.rent_ledger.group(:period).count"
```

### Production Deployment Files Checklist:
```
deployment/production_database_20250928.json    ✅ Core data export
deployment/production_migration.rb              ✅ WITH HISTORICAL DATA PROCESSING
deployment/export_production_data.rb            ✅ Backup script
deployment/DEPLOYMENT_CHECKLIST.md              ✅ Step-by-step guide
DELL_OPTIPLEX_KIOSK_DEPLOYMENT.md               ✅ Hardware setup
data/rent_history/                               ✅ REQUIRED FOR MIGRATION
```

### ⚠️ IMPORTANT MIGRATION REMINDERS:

1. **Never deploy without `data/rent_history/` directory** - Historical data won't migrate
2. **CONFIG PERIOD MONTH semantics are corrected** - Files already fixed (month 7 = August rent)
3. **Tenant mapping is automatic** - Script handles name-to-ID conversion
4. **One-time operation** - Historical migration only runs during initial deployment
5. **Backup exists** - Original JSON files preserved at `data/rent_history_original_backup_20250928/`

### Production Health Checks:
```bash
# Ruby dependencies
bundle install --deployment --without development test assets

# Database connectivity
ruby -e "require 'dotenv/load'; require_relative 'lib/rent_db'; puts RentDb.instance.get_tenants.length"

# API endpoints
curl http://localhost:3001/api/rent/friendly_message

# WebSocket connection
# Check browser console for WebSocket at ws://localhost:3001
```
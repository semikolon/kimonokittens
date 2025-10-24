# Kimonokittens Project Instructions

## ⚠️ CRITICAL: PROCESS MANAGEMENT PROTOCOL

**🔥 MANDATORY RULES FOR ALL CLAUDE CODE SESSIONS - NEVER DEVIATE! 🔥**

**Status**: ✅ PRODUCTION - with Claude Code Background Caveats (Oct 1, 2025)
**Deep Dive**: See `docs/PROCESS_MANAGEMENT_DEEP_DIVE.md` for complete technical analysis

### 🐛 CLAUDE CODE BACKGROUND PROCESS BUG - CRITICAL AWARENESS

**Claude Code has a systemic background process status tracking bug:**

1. **Status in system reminders is UNRELIABLE** - may show "status: running" when process died instantly
2. **BashOutput tool shows CORRECT status** - always cross-verify with `BashOutput` tool
3. **Always verify with ps/pgrep** - don't trust system reminder status alone

**Validation commands** (run these to verify actual process state):
```bash
# Check if processes actually exist:
ps aux | grep -E "(npm run dev|ruby.*puma|vite.*5175)" | grep -v grep

# Check if ports are actually occupied:
lsof -ti :3001 :5175

# Use BashOutput tool to see real status, not system reminders
```

**Related GitHub Issues:**
- [#7838](https://github.com/anthropics/claude-code/issues/7838) - No process health monitoring, text-based polling unreliable
- [#1481](https://github.com/anthropics/claude-code/issues/1481) - Background processes still wait for child processes
- [#759](https://github.com/anthropics/claude-code/issues/759) - CLI hanging and background behavior issues

**Discovered**: Oct 1, 2025 - Commands appeared to "hang for 26 minutes" but actually failed instantly. System reminders showed "running" while BashOutput showed "failed". Cross-verification with `ps` confirmed no processes existed.

### ⚠️ SUDO COMMANDS - CANNOT RUN INTERACTIVELY

**Claude Code cannot run `sudo` commands that require password input.**

**NEVER attempt to run sudo commands directly** - instead:
- ✅ **Tell the user what to run** - Provide the exact sudo command for them to copy/paste
- ✅ **Explain what it does** - Brief description of why the command is needed
- ❌ **Don't try to run it yourself** - Will fail with "a terminal is required to read the password"

**Example:**
```
User needs: Restart webhook service
Wrong: Run sudo systemctl restart kimonokittens-webhook
Right: "Please run: sudo systemctl restart kimonokittens-webhook"
```

### 🚨 NEVER MANUALLY DEPLOY TO PRODUCTION

**CRITICAL RULE: Webhook deployments are MANDATORY - never work around them!**

- ❌ **NEVER** run `git pull` in `/home/kimonokittens/Projects/kimonokittens`
- ❌ **NEVER** manually copy files to production
- ❌ **NEVER** edit files directly in production checkout
- ✅ **ALWAYS** commit changes to dev checkout and push to trigger webhook
- ✅ **IF webhook doesn't deploy** → Fix the webhook, don't work around it

**Why this matters:**
1. Manual deploys bypass the smart debouncing and change detection
2. They create inconsistencies between git state and deployed state
3. They hide webhook configuration problems that need to be fixed
4. The webhook is the single source of truth for production state

**If webhook isn't working:**
1. Check GitHub webhook configuration at repository settings
2. Verify webhook secret matches `WEBHOOK_SECRET` in `.env`
3. Check webhook service logs: `journalctl -u kimonokittens-webhook -f`
4. **Fix the root cause** - don't bypass with manual git pull

### ✅ ALWAYS DO:
- **ONLY** use these exact commands for ALL process management:
  ```bash
  npm run dev          # Start all processes (calls bin/dev start)
  npm run dev:stop     # Stop all processes (calls bin/dev stop)
  npm run dev:restart  # Clean restart (calls bin/dev restart)
  npm run dev:status   # Check status (calls bin/dev status)
  bin/dev nuke         # Nuclear cleanup (only if above fails)
  ```
- **VERIFY status after background commands** using `ps` or `BashOutput` tool
- **Check status before starting** to verify clean state

### ❌ NEVER DO:
- **NEVER** use direct commands like `ruby puma_server.rb` or `PORT=3001 ENABLE_BROADCASTER=1 ruby puma_server.rb`
- **NEVER** use `cd dashboard && npm run dev` directly
- **NEVER** spawn processes outside bin/dev control
- **NEVER** mix Claude Code background calls with direct process spawning

### 🚨 WHY THIS MATTERS:
**Orphaned processes cause:**
- Port conflicts ("Address already in use" errors)
- Stale data caching (7,492 kr rent bug was caused by old server running since Saturday)
- Cross-session zombie persistence (processes from old CC sessions surviving)
- Development workflow chaos
- Hours of debugging pain

**The bin/dev commands include multi-layered cleanup that handles:**
- ✅ Claude Code's known orphan bug ([GitHub #5545](https://github.com/anthropics/claude-code/issues/5545))
- ✅ Zombie tmux sessions across CC session boundaries
- ✅ Stale socket files from abnormal termination
- ✅ Port-based cleanup (fixed lsof syntax bug - commit `4f72e62`)
- ✅ Process name pattern matching

**Defense in depth**: Graceful → Aggressive → Nuclear cleanup strategies ensure processes NEVER survive.

---

## ⚠️ CRITICAL: GIT SAFETY PROTOCOL

**🔥 NEVER AMEND OR FORCE PUSH - THESE DESTROY HISTORY! 🔥**

### ❌ FORBIDDEN OPERATIONS:
- **NEVER** use `git commit --amend` unless **explicitly requested by user**
- **NEVER** use `git push --force` or `git push -f` (especially to main/master)
- **NEVER** use `git reset --hard` on shared branches

### ✅ CORRECT WORKFLOW:
- **Always create new commits** for changes, even small config tweaks
- **Always use normal push**: `git push origin master`
- **If you need to change something after commit**: Make a NEW commit, don't amend

### 🚨 WHY THIS MATTERS:
- **Amending pushed commits** creates divergent branches → deployment failures
- **Force push** can destroy other developers' work → data loss
- **Linear history** is sacred → webhook relies on fast-forward pulls

**Lesson learned**: Oct 4, 2025 - Force push caused "divergent branches" error, breaking webhook deployment. Always use new commits.

---

### 🧹 Cache Cleanup After Major Changes

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

## 🚨 RELOAD LOOP PROTECTION (Oct 2, 2025)

**Multi-layer defense system prevents infinite reload loops that crashed the kiosk.**

### Protection Layers (All Implemented ✅)

1. **Server throttling**: `handlers/reload_handler.rb` - Max 1 reload broadcast per 2 minutes
2. **Client deduplication**: `dashboard/src/context/DataContext.tsx` - Blocks reloads within 2 minutes
3. **Systemd restart limits**: Kiosk service only restarts 3× in 60s, then stops trying
4. **Emergency stop**: `bin/emergency-kiosk-stop` script for manual recovery

### Emergency Stop (Run as your user, not kimonokittens)

**⚠️ REQUIRES TTY/SUDO PASSWORD - Run as fredrik, not kimonokittens:**

```bash
# Emergency kiosk stop (uses machinectl which needs sudo)
./bin/emergency-kiosk-stop
```

**Why machinectl?** `sudo systemctl stop kimonokittens-kiosk` FAILS because it's a user service. Only `machinectl shell kimonokittens@.host /usr/bin/systemctl --user stop kimonokittens-kiosk` works from root.

**Full incident analysis**: See `docs/archive/RELOAD_LOOP_INCIDENT.md`

---

## 🏗️ Repository Architecture Pattern

**Status**: ✅ **PRODUCTION READY** (October 2025) - Full domain model migration complete

### Current Architecture

The codebase uses **clean architecture** with domain models, repositories, and services:

```
Handlers → Services → Domain Models + Repositories → Database
         ↓
    Persistence (centralized access)
```

### Quick Reference

**Access repositories:**
```ruby
require_relative 'lib/persistence'

Persistence.tenants           # TenantRepository
Persistence.rent_configs      # RentConfigRepository
Persistence.rent_ledger       # RentLedgerRepository
Persistence.electricity_bills # ElectricityBillRepository
```

**Domain model methods:**
```ruby
# Electricity billing period calculation:
ElectricityBill.calculate_bill_period(due_date)  # → consumption period Date

# Rent configuration with carry-forward logic:
RentConfig.for_period(year: 2025, month: 10, repository: Persistence.rent_configs)

# Tenant days stayed calculation:
tenant.days_stayed_in_period(period_start, period_end)
```

**Services for transactions:**
```ruby
# Store electricity bill + auto-aggregate + update RentConfig:
ApplyElectricityBill.call(
  provider: 'Vattenfall',
  amount: 1685.69,
  due_date: Date.new(2025, 11, 3)
)
# Automatically: stores bill → aggregates period → updates RentConfig → notifies WebSocket
```

### Architecture Layers

1. **Domain Models** (`lib/models/`) - Business logic, NO database access
2. **Repositories** (`lib/repositories/`) - Persistence only, NO business rules
3. **Services** (`lib/services/`) - Multi-table transactions
4. **Persistence** (`lib/persistence.rb`) - Singleton repository access
5. **RentDb** (`lib/rent_db.rb`) - Thin compatibility wrapper (deprecated for new code)

### Documentation

For LLM assistants and future developers:
- **Complete API guide**: `docs/MODEL_ARCHITECTURE.md` (800+ lines)
- **Migration commits**: d96d76f (models), d7b75ec (handlers), 7df8296 (tests)
- **Business logic preservation**: Verified in test suite (spec/models/, spec/repositories/, spec/services/)
- **Test coverage**: 37 tests for domain layer (all passing)

---

## 🔐 Environment Variables

**Production `.env` file synced with development** - The `/home/kimonokittens/.env` file contains all API keys and secrets from the Mac development environment for smooth deployment across all monorepo features (weather, Strava, bank integration, handbook, etc.).

**Symlink strategy (no duplication)**: `/home/kimonokittens/Projects/kimonokittens/.env` → `/home/kimonokittens/.env` (source of truth). Services use `EnvironmentFile=-/home/kimonokittens/.env`, Prisma/dotenv follow symlink.

**Development environment on kiosk** - `/home/fredrik/Projects/kimonokittens/.env` configured with `DATABASE_URL` pointing to `_development` database and `NODE_ENV=development`. Allows independent local dev/test on kiosk hardware without affecting production.

---

## 🚀 DEPLOYMENT ARCHITECTURE

> **✅ KIOSK DEPLOYED**: Dell Optiplex 7010 live in hallway (October 6, 2025)
> - Dashboard display operational 24/7
> - GPU acceleration + webhook auto-deployment active
> - Migration from Pi 3B+ ongoing (Node-RED, MQTT, cron jobs)

### 🔄 Pi Migration Strategy (October 6, 2025)

**Network**: `kimonokittens.com` bound to home IP via DDClient dynamic DNS

**Services Staying on Pi** (infrastructure/automation):
- **DDClient**: Dynamic DNS updates for kimonokittens.com
- **Pycalima**: Bluetooth-based bathroom fan control (hardware proximity required)
- **Node-RED**: Temperature sensor aggregation, heatpump schedule generation (port 1880)
- **Mosquitto MQTT**: Message broker for ThermIQ heatpump data (port 1883)

**Services Migrating to Dell** (dashboard-relevant data):
- **Electricity data cron jobs**: `vattenfall.rb` + `tibber.rb` (every 2 hours)
- **Electricity JSON files**: `electricity_usage.json`, `tibber_price_data.json`
- **Dashboard data generation**: All data consumed by widgets or useful for online handbook

**Services to Sunset** (after BRF-Auto income secured):
- **Pi Agoo server** (`json_server.rb`):
  - Currently hosts simple public homepage at kimonokittens.com
  - Dell has own handlers - no functional dependency
  - Will be replaced by nginx on Dell serving handbook + dashboard publicly

**Rationale**: Keep infrastructure services (DNS, MQTT, sensors) on Pi where hardware lives. Migrate dashboard-related data generation to Dell for consolidation and future handbook features (which is part of monorepo but not yet deployed).

**Public Deployment Postponed**: Domain migration + handbook public hosting delayed until BRF-Auto project income secured (~1-2 weeks).

**Documentation**: See `docs/PI_MIGRATION_MAP.md`, `docs/PI_VS_DELL_ELECTRICITY_ANALYSIS.md`, and `docs/ELECTRICITY_PRICE_DATA_ANALYSIS.md` for complete analysis.

### Production Paths & Services
```
/home/kimonokittens/                          # Service user home
├── .env                                       # Production secrets (source of truth)
└── Projects/kimonokittens/                    # Git checkout
    ├── .env → /home/kimonokittens/.env        # Symlink (no duplication)
    ├── puma_server.rb                         # Backend API + WebSocket
    ├── dashboard/                             # Frontend source
    │   └── dist/                              # Built frontend (rsync'd to nginx)
    └── deployment/scripts/
        ├── setup_production.sh                # Initial deployment script
        ├── configure_chrome_kiosk.sh          # GPU acceleration config
        └── webhook_puma_server.rb             # Smart webhook receiver

/var/www/kimonokittens/dashboard/              # Nginx serves from here
/home/kimonokittens/.config/systemd/user/      # User services
├── kimonokittens-kiosk.service                # Chrome kiosk (port localhost)
└── (dashboard managed by root systemd)
```

### System Services
```bash
# Backend API + WebSocket (root systemd)
sudo systemctl status kimonokittens-dashboard  # Runs: puma_server.rb on port 3001

# Webhook receiver (root systemd)
sudo systemctl status kimonokittens-webhook    # Runs: webhook_puma_server.rb on port 49123

# Chrome kiosk (user systemd via kimonokittens user)
sudo -u kimonokittens systemctl --user status kimonokittens-kiosk
# Or via machinectl:
machinectl shell kimonokittens@ /usr/bin/systemctl --user status kimonokittens-kiosk
```

### Webhook Deployment Flow
**Smart change detection + 2-minute debounce + component-specific deployment**

1. **Push to master** → GitHub webhook → `POST localhost:49123/webhook`
2. **Analyze changes**:
   - `dashboard/` → Frontend deployment
   - `*.rb`, `Gemfile` → Backend deployment
   - `docs/`, `README.md` → No deployment
3. **Debounce (120s)**: Rapid pushes cancel previous timer, always deploy latest
4. **Deploy components**:
   ```bash
   # Frontend: npm ci → npx vite build → rsync to nginx → restart kiosk
   # Backend: git pull → bundle install → systemctl restart dashboard
   ```
5. **Monitor**: `journalctl -u kimonokittens-webhook -f`

**Webhook endpoints**: `/webhook` (GitHub), `/health`, `/status` (deployment queue info)

### Frontend Build & Deploy
```bash
# Development build (localhost:5175)
cd dashboard && npm run dev

# Production build
cd dashboard && npx vite build  # Outputs to dist/

# Deploy to nginx
sudo rsync -av --delete dashboard/dist/ /var/www/kimonokittens/dashboard/

# Restart kiosk to reload
sudo -u kimonokittens systemctl --user restart kimonokittens-kiosk
```

### Backend Deploy
```bash
# Pull latest code
git pull origin master

# Install dependencies
bundle install --deployment

# Restart service
sudo systemctl restart kimonokittens-dashboard
```

### Port Architecture
- **3001**: Backend API + WebSocket (Puma)
- **5175**: Frontend dev server (Vite, dev only)
- **49123**: Webhook receiver (Puma, obscure port for security)
- **80/443**: Nginx → serves `/var/www/kimonokittens/dashboard/`
- **localhost**: Kiosk Chrome points here (nginx proxy)

### Key Deployment Insights
- **⚠️ NPM WORKSPACES CRITICAL** - ALWAYS run `npm ci` from **project root**, never from `dashboard/` subdirectory
  - Monorepo uses npm workspaces (`dashboard`, `handbook/frontend`, `packages/*`)
  - Running npm in subdirectory silently skips devDependencies like vite
  - Correct: `cd /home/kimonokittens/Projects/kimonokittens && npm ci`
  - Wrong: `cd dashboard && npm ci` (will break builds)
- **Symlink .env, don't duplicate** - Single source of truth in `/home/kimonokittens/.env`
- **Kiosk auto-refresh on frontend deploy** - Webhook restarts kiosk service after rsync
- **2-minute debounce prevents spam** - Rapid development pushes = one deployment with all changes
- **No database schema changes via webhook** - Prisma migrations are manual (run `npx prisma migrate deploy`)

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

### Electricity Bill Due Date Timing ⚡

**CRITICAL: Bills have variable due dates that determine WHICH CONFIG PERIOD uses them.**

The key question is: **When did the bill ARRIVE and become available for rent calculation?**

**Two patterns based on due date day:**

1. **End-of-month bills** (day 25-31):
   - Due: Sept 30 → Bill arrived **September** → **Config period: September**
   - Example: Due July 31 → arrived July → July config → August rent

2. **Start-of-month bills** (day 1-10):
   - Due: Oct 1 → Bill arrived **September** (late Sept) → **Config period: September**
   - Example: Due Aug 1 → arrived July → July config → August rent

**Concrete example: August 2025 consumption**
- Bills arrive mid-September
- **Vattenfall** due Sept 30 (day 30): Config = **Sept** (due month)
- **Fortum** due Oct 1 (day 1): Config = **Sept** (due month - 1)
- Both bills total 2424 kr in **September config** → Used for **October rent**

**The rule (for migration scripts):**
```ruby
if due_day >= 25
  config_month = due_month        # Bill arrived same month as due
else
  config_month = due_month - 1    # Bill arrived month before due
end
```

**Why this matters:**
- **Don't think "consumption month"** - think "when did bill arrive?"
- **Config period** = month when bills became available
- **Complete flow**: Aug consumption → Sept bills arrive → Sept config → Oct rent

**Historical data files:**
- `electricity_bills_history.txt` contains actual due dates
- Must interpret day-of-month (25-31 vs 1-10) to determine consumption period
- See `deployment/historical_config_migration.rb` for implementation

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

## Testing Best Practices 🧪

**Status**: ✅ PRODUCTION READY (October 4, 2025) - 39/39 tests passing
**Documentation**: `docs/TESTING_GUIDE.md` (complete reference)

### Critical Rules

1. **Test database isolation** - Tests ALWAYS use `kimonokittens_test` database (4-layer defense in depth)
2. **spec_helper.rb MUST be first require** - Loads `.env.test` before any code
3. **Sequel API**: Use `db.class.db.run()` not `db.conn.exec()` (pre-2025 upgrade)
4. **Default utilities**: Calculator adds 825 kr when utilities not provided
5. **Rounding tolerance**: Use `be_within(1).of(...)` for financial totals
6. **Timestamp comparison**: Compare `.to_date` not full timestamps (timezone differences)

### Quick Commands

```bash
# Run tests (one file at a time for easier fixes)
bundle exec rspec spec/rent_calculator/calculator_spec.rb

# Verify dev database untouched after tests
ruby -e "require 'dotenv/load'; require_relative 'lib/rent_db'; puts RentDb.instance.get_tenants.length"  # Should show 8

# Full test suite
bundle exec rspec
```

### When Tests Fail

**Code behavior likely evolved legitimately** - update test expectations, not implementation:
- Message format changes → Update regex/string matchers
- Rounding differences → Add tolerance
- Default values → Accept calculator's defaults
- Timezone handling → Compare dates not timestamps

**See**: `docs/TESTING_GUIDE.md` for complete patterns, setup, and troubleshooting

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
**The bin/dev system provides robust process lifecycle management with aggressive cleanup.**

**Core Features**:
- **Aggressive port cleanup**: Kills ALL processes on ports 3001/5175 before starting
- **Idempotent operations**: Safe to run multiple times
- **Comprehensive status**: Shows ports, processes, and Overmind state
- **Handles Claude Code orphans**: Works around CC's known orphan bug ([#5545](https://github.com/anthropics/claude-code/issues/5545))

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

**Important for Claude Code Users**:
- ⚠️ **Status tracking unreliable**: Always verify with `ps` or `BashOutput` after background commands
- ✅ **Cleanup logic is solid**: Aggressive cleanup handles orphaned processes from ANY source
- ✅ **Commands are idempotent**: Safe to run multiple times, won't break on re-run
- ⚠️ **Error output may be hidden**: Check `BashOutput` tool, not just system reminders

### Code Change Workflow

1. **Before making rent changes**: Read this file
2. **Check database state**: Use quick reference commands above
3. **Update configs**: Use correct timing (current month period for next month rent)
4. **Restart processes**: `npm run dev:restart` to ensure fresh backend
5. **Verify results**: Test API and check dashboard
6. **Clean up**: Remove any test data from production DB

## 🖥️ Kiosk GPU Acceleration (Oct 2, 2025) **DEPLOYED ✅**

**Status**: Live - Dell Optiplex in hallway (Oct 6, 2025), NVIDIA GTX 1650

### Achievement Summary
Successfully configured hardware GPU acceleration for WebGL shader animations on Dell Optiplex 7010 kiosk after resolving crash-loop issues caused by outdated Chrome flags.

**Problem Solved**: Initial GPU flags (`--enable-gpu-rasterization`, `--enable-zero-copy`, `--use-gl=desktop`) caused Chrome to crash every 60 seconds, spawning 9+ renderer processes and consuming 737.5% CPU. System was unusable.

**Solution**: 2024 NVIDIA-specific flags that properly enable GPU acceleration without conflicts:
```bash
--ignore-gpu-blocklist
--enable-features=AcceleratedVideoDecodeLinuxZeroCopyGL,AcceleratedVideoDecodeLinuxGL,VaapiIgnoreDriverChecks,VaapiOnNvidiaGPUs
--force-gpu-mem-available-mb=4096  # Matched to actual GTX 1650 VRAM
--force-device-scale-factor=1.15   # 115% zoom for readability
```

**Performance Results**:
- ✅ GPU: 52% utilization (WebGL shader running on hardware)
- ✅ VRAM: 1.2GB / 4GB (well within limits)
- ✅ CPU: 275% total (normal for shader coordination)
- ✅ Smooth 60fps animations, no crashes
- ✅ Fan noise acceptable, display stays cool

**WebGL Shader Background Impact** (Oct 6, 2025):
The `animated-shader-background.tsx` component adds visual appeal but can increase resource usage. Testing showed approximately **+7-8% GPU utilization, +16-21°C temperature increase (typically 54°C → 70-75°C), +23-24W power draw (19W → 42-43W), with increased fan activity**. Actual impact varies by time of day and ambient temperature. Disabling the shader (comment out `<AnoAI />` in `App.tsx`) reduces GPU load while maintaining smooth UI. Optional tradeoff between aesthetics and efficiency.

**Recommendation for 24/7 hallway display**: Disable shader to reduce GPU wear, power consumption (~200 kWh/year), and fan noise. While 70°C is safe for continuous operation, the decorative animation provides minimal utility for a passive display. GPU lifespan at constant 70°C: 5-8+ years vs 10+ years at lower temps.

**Architecture**: DRY pattern - `setup_production.sh` creates basic service, then calls `configure_chrome_kiosk.sh` to apply optimized flags. Single source of truth for Chrome configuration.

**Documentation**: `DELL_OPTIPLEX_KIOSK_DEPLOYMENT.md` section "Browser Performance" documents flag choices and VRAM verification.

---

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

### CSS Gradient Animation Gotchas (Oct 3, 2025)
**Hard-won lessons from shine swoosh implementation:**
- **`background` shorthand resets all properties** → Use `background-image` when composing with `background-clip: text`
- **Animations snap back by default** → Always add `animation-fill-mode: forwards` to prevent color flash at end
- **Test intervals matching animation duration = race conditions** → Add gap (e.g., 4s animation + 8s interval)
- **`background-repeat: repeat-x` solves transparency bugs** → Gradient tiles infinitely, prevents gaps during animation
- **Background-position math**: `offset = (container_width - gradient_width) × position%` (200% gradient needs careful positioning)

## WebSocket Architecture ⚡

### DataBroadcaster URLs - FIXED ✅
**Environment variable solution implemented**: `lib/data_broadcaster.rb` now uses `ENV['API_BASE_URL']`

**Production ready**: Set `API_BASE_URL=https://your-domain.com` in production environment

### Data Flow
1. **Ruby DataBroadcaster** fetches from HTTP endpoints every 30-600s
2. **Custom WebSocket** (`puma_server.rb`) publishes to frontend via raw socket handling
3. **React Context** manages centralized state with useReducer
4. **Widgets** consume via `useData()` hook

### Heating Cost Display (RentWidget) 🌡️
**Location**: Displayed below electricity source line in RentWidget

**Calculation**: Uses ElectricityProjector (trailing 12-month baseline + seasonal patterns)
- **Current (Oct 2025)**: "2 °C varmare skulle kosta 143 kr/mån (36 kr/person); 2 °C kallare skulle spara 130 kr/mån (33 kr/person)"
- **February 2026 (predicted)**: "2 °C varmare skulle kosta 451 kr/mån (113 kr/person); 2 °C kallare skulle spara 409 kr/mån (102 kr/person)"

**Why February costs 3.5× more**:
- Seasonal multiplier: Feb = 2.04x vs Sep = 0.56x (winter vs fall)
- More heating usage = larger impact per degree adjustment

**Architecture**:
- Shared module: `lib/heating_cost_calculator.rb`
- Sent via `/api/rent/friendly_message` in `heating_cost_line` field
- Auto-updates monthly as ElectricityProjector recalculates

## Project Quirks & Technical Debt 🔧

### Test Database Contamination
**Never let integration tests write to production DB!** Previous issue: `drift_rakning: 2612` written by specs, causing incorrect 7,492 kr calculations.

### Electricity Bill Timeline Complexity
**2-month lag**: January consumption → bills arrive mid-February → February config → March rent (due Feb 27)

**Important:** The config month represents when bills became available, not when electricity was consumed. See "Electricity Bill Due Date Timing" section above for complete details.

### SL Transport API - WORKING ✅
Train departures use **keyless SL Transport API** (`transport.integration.sl.se`) - no access tokens needed. Previous "fallback mode" references are outdated from old ResRobot migration.

---

**Remember: When in doubt about rent timing, the dashboard request month determines the config period, not the rent month shown in the message.**

---

## 🖥️ DEVELOPMENT WORKFLOW & ENVIRONMENT

### Checkout Structure

**Production Checkout**: `/home/kimonokittens/Projects/kimonokittens/`
- Runs as `kimonokittens` user
- Physical display (Dell OptiPlex kiosk) in hallway downstairs
- Backend: Port 3001 (puma_server.rb)
- Frontend: Served via nginx at production URL
- **Not for development** - deploy-only via webhook

**Development Checkout**: `/home/fredrik/Projects/kimonokittens/`
- Where code changes are made and pushed to GitHub
- Runs as `fredrik` user (you are here when using Claude Code)
- **No direct browser access** - display is in hallway, not visible from desk
- Backend: Port 3001 (when running locally)
- Frontend: Port 5175 (Vite dev server when running)

### SSH Access to Kiosk

**IMPORTANT**: The kiosk hostname is `pop` (not `kimonokittens.com` - that points to Pi)

**SSH Commands**:
```bash
# Connect as fredrik user (default)
ssh pop

# Connect as kimonokittens user
ssh kimonokittens@pop
# or
ssh pop -l kimonokittens
```

**Key Facts**:
- `kimonokittens.com` DNS points to home WAN IP (via DDClient on Pi)
- **Pi Agoo server** hosts simple public homepage at that domain:
  - Port 6464 (HTTP), 6465 (HTTPS)
  - Static landing page: logo + Swish donation message
  - Proxies some endpoints to Node-RED (temperature, etc.)
  - **NOT needed by Dell dashboard** (Dell has own handlers)
- **Dell dashboard** only serves on localhost (not publicly accessible yet)
  - Production deployment via webhook (port 3001)
  - Backend handlers: rent, weather, temperature, electricity prices
  - No dependency on Pi Agoo server for functionality
- **Public migration postponed** until BRF-Auto income secured:
  - Move kimonokittens.com → Dell nginx
  - Deploy handbook publicly under domain
  - Sunset Pi Agoo server (keep Node-RED/MQTT)

### Frontend Development Workflow

**Problem**: Can't see frontend changes visually - display is downstairs, SSH session has no browser.

**Solution**: SSH port forwarding from Mac (where user types) to Linux dev machine.

**Setup** (one-time, user does this on Mac):
```bash
# ~/.ssh/config on Mac
Host kimonokittens
  HostName <linux-ip>
  User fredrik
  LocalForward 5175 localhost:5175  # Vite dev server
  LocalForward 3001 localhost:3001  # Ruby backend API
```

**Workflow**:
1. SSH from Mac with forwarding: `ssh kimonokittens` (or manual: `ssh -L 5175:localhost:5175 -L 3001:localhost:3001 fredrik@<ip>`)
2. Start dev servers in Linux terminal: `cd ~/Projects/kimonokittens && bin/dev start`
3. Open browser on Mac: `http://localhost:5175`
4. Edit code in Claude Code (Linux side)
5. Vite HMR auto-reloads browser on Mac
6. Push changes when ready → webhook deploys to production

**Dependencies** (in fredrik dev checkout):
- Ruby: Via rbenv (same as kimonokittens user)
- Bundle: `bundle install` in project root
- Node/npm: `npm install` in dashboard/ subdirectory
- Verify: `bin/dev status` should show clean state

**Production Deployment**:
- Push to GitHub → webhook auto-deploys → production kiosk updates
- Never edit production checkout directly
- Always develop in fredrik checkout, deploy via git

## 🔄 SMART WEBHOOK DEPLOYMENT SYSTEM

### Overview: Modern Event-Driven Deployment

The kimonokittens project uses a **smart webhook system** with Puma architecture for automated deployments. The system analyzes changed files and only deploys what's necessary, with intelligent debouncing for rapid development workflows.

**Status**: ✅ **WORKING** (Oct 2, 2025) - Core pipeline functional: git pull → npm ci --legacy-peer-deps → vite build → rsync deploy
**Known Issue**: Kiosk reload trigger logs stop after rsync (deployment succeeds, reload uncertain)
**Architecture**: Unified Puma + Rack across all services (dashboard port 3001, webhook port 49123)

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
- **Schema migrations are manual** - run `npx prisma migrate deploy` deliberately in production
- **Zero database risk** from automated code deployments

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

### ⚠️ CRITICAL: Webhook Self-Update Limitation

**The webhook service CANNOT automatically restart itself when its own code changes.**

**Why:** Chicken-and-egg problem - the deployment thread runs inside the process that needs to restart. Ruby can't restart a process from within while maintaining active HTTP connections.

**When webhook code changes (`deployment/scripts/*.rb`):**
1. Webhook pulls latest code to disk ✅
2. Webhook deployment runs with OLD code in memory ❌
3. **Manual restart required:** `sudo systemctl restart kimonokittens-webhook`
4. Next deployment uses new code ✅

**Quick check if restart needed:**
```bash
# Compare running code vs on-disk code
journalctl -u kimonokittens-webhook --since "5 minutes ago" | grep "Backend change detected: deployment"
# If found → restart webhook to load new code
```

**Services restart behavior:**
- `kimonokittens-dashboard`: Auto-reloads via USR1 signal ✅
- `kimonokittens-webhook`: **Manual restart required** ⚠️

### ⚠️ CRITICAL: Ruby Logger Buffering Mystery

**The deployment logs would appear to "stop" after rsync, but execution continued successfully.**

**What happened (Oct 2-3, 2025 debugging marathon):**
- Logs showed deployment starting, git pull, npm ci, vite build, rsync output
- Then **complete silence** - no "✅ Frontend files deployed", no completion message
- Looked like the thread died after rsync
- Actually: **logs were buffered for 60 seconds** before appearing in journald

**Root cause:** Ruby `Logger.new(STDOUT)` buffers output. rsync generates lots of output (filling buffer → flush), then subsequent log lines sit in buffer until it fills again or something forces flush.

**Fix applied (commit `4a458ca`):**
```ruby
$stdout.sync = true
$stderr.sync = true
```

**Now logs appear instantly** - no more phantom "deployment hangs" that were actually just buffered logs.

**Never debug without checking wider time windows** - if logs "stop", check if they appear 30-120 seconds later.

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

## 📚 HISTORICAL: Initial Production Deployment (September-October 2025)

**Status**: ✅ COMPLETED - Database fully operational in production since October 6, 2025

### What Was Done (Historical Context):
- **Sep 28-30, 2025**: Created Prisma schema + initial migrations
  - `20250930000000_initial_schema` - All tables (ElectricityBill, RentConfig, RentLedger, Tenants)
  - `20251004112744_remove_generated_column_extend_ledger` - Schema fixes
- **Sep 28, 2025**: Created `production_migration.rb` for initial data population
  - Migrated 58 historical RentLedger records from JSON files
  - Populated 8 Tenants, 7 RentConfig records
- **Oct 6, 2025**: Dell kiosk deployed with database fully operational

### Current Production Database State:
```
✅ Schema: 2 Prisma migrations applied
✅ Data: RentConfig, Tenants, RentLedger, ElectricityBill tables populated
✅ Location: kimonokittens_production database on Dell kiosk
```

### Recent Work (October 21-23, 2025):
**Model architecture refactoring** - Pure code changes, no database migrations:
- Created domain models in `lib/models/` (ElectricityBill, RentConfig, Tenant, RentLedger)
- Created repositories in `lib/repositories/`
- Created services in `lib/services/` (ApplyElectricityBill)
- Created persistence module `lib/persistence.rb`
- **Deployment**: Code-only via webhook (no manual database steps needed)

### Complete Deployment Documentation:
**All initial deployment procedures have been completed (Oct 6, 2025).** Documentation preserved for:
- Future server migrations (e.g., new production environment)
- Reference when considering deployment automation tools (Capistrano, Mina, etc.)

**Available documentation:**
- **`deployment/DEPLOYMENT_CHECKLIST.md`** - Complete step-by-step initial deployment
- **`DELL_OPTIPLEX_KIOSK_DEPLOYMENT.md`** - Hardware setup + database migration procedures
- **`deployment/production_migration.rb`** - Historical data migration script (already run)
- **`deployment/scripts/setup_production.sh`** - Automated setup script
- **`docs/PRODUCTION_CRON_DEPLOYMENT.md`** - Cron job setup for electricity automation

**Note on Capistrano:** Current deployment uses webhook-based automation. If migrating to Capistrano or similar tools in the future, above docs provide the baseline deployment procedure to automate.

### For Future Deployments:
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

## 🔧 System Upgrade History

**Oct 9, 2025**: Pop!_OS 22.04 system upgrade completed successfully - PostgreSQL 14→18, NVIDIA 550→580, kernel 6.16.3, 552 packages total. Database schema intact (kimonokittens_production), all DKMS modules compiled.
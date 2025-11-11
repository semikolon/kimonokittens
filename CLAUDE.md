# Kimonokittens Project Instructions

## ⚠️ CRITICAL: PROCESS MANAGEMENT PROTOCOL

**Status**: ✅ PRODUCTION (Oct 26, 2025) | **Deep Dive**: `docs/PROCESS_MANAGEMENT_DEEP_DIVE.md`

### 🐛 Claude Code Background Process Bug

**System reminders show unreliable status** - always verify with `ps` or `BashOutput` tool:
```bash
ps aux | grep -E "(npm run dev|ruby.*puma|vite.*5175)" | grep -v grep
lsof -ti :3001 :5175
```

**Issues**: [#7838](https://github.com/anthropics/claude-code/issues/7838), [#1481](https://github.com/anthropics/claude-code/issues/1481), [#759](https://github.com/anthropics/claude-code/issues/759)

### ⚠️ Sudo Commands - Tell User to Run

**Claude Code cannot run `sudo` commands requiring password input.** Always tell user the exact command, never attempt to run directly.

**Dell Production Server - User Permissions:**
- **fredrik user**: Has sudo access ✅
- **kimonokittens user**: NOT in sudoers ❌
- **All sudo commands must run as fredrik user**, not kimonokittens

### 🔒 Public API Security

**CRITICAL: Most endpoints MUST NOT be exposed to public internet via nginx.**

**Safe to expose (authenticated):**
- `/api/webhooks/deploy` - GitHub signature verification protects against unauthorized deployments
- `/api/webhooks/zigned` - Zigned webhook secret verification ensures only legitimate contract status updates
- `/api/contracts/:id/pdf` - Serves signed contract PDFs via HTTP (required because browsers block file:// URLs from HTTP pages for security)

**DANGEROUS to expose (unauthenticated):**
- `PUT /api/rent/config` - Anyone could modify rent amounts, electricity costs, utilities (financial fraud risk)
- `GET /api/rent/friendly_message` - Exposes tenant names, rent amounts, personal financial data (GDPR violation)
- `/dashboard/*` static files - Exposes internal kiosk UI not designed for public access (information disclosure)
- `/data/*` endpoints - Temperature, weather, etc. - less critical but still internal-only data

**Nginx rule:** Public domain server block should ONLY serve homepage files + authenticated webhooks. All other endpoints restricted to localhost.

**Future public signup endpoint (`/api/signup`):**
- Enabled in nginx config for future tenant signup form at `/meow`, `/curious`, or `/signup`
- ⚠️ **MUST implement rate limiting** when building backend handler (prevent signup spam)
- ⚠️ **MUST implement CAPTCHA** or similar bot prevention (hCaptcha, Cloudflare Turnstile, etc.)
- Creates pending tenant record → admin approval → contract generation → Zigned e-signing flow

### 🚨 Production Deployment

**🔴 CRITICAL: NEVER PUSH WITHOUT EXPLICIT USER AUTHORIZATION 🔴**
- **ALWAYS ask "Ready to push to production?" before `git push`**
- **User must explicitly say "yes" or "push it" or similar**
- **"Looks good" or "that's fine" is NOT authorization to push**
- Pushing = Immediate production deployment via webhook
- User may want to review changes locally before production rollout

**Webhook deployments MANDATORY** - never edit production checkout directly:
- ❌ **NEVER** run `git pull` in `/home/kimonokittens/Projects/kimonokittens/`
- ❌ **NEVER** edit files in `/home/kimonokittens/Projects/kimonokittens/` directly
- ✅ **ALWAYS** edit in dev checkout: `/home/fredrik/Projects/kimonokittens/`
- ✅ **ALWAYS** commit to dev → push to trigger webhook (ONLY after user authorization)
- Webhook broken? Fix webhook, don't work around
- Check: `journalctl -u kimonokittens-webhook -f`

**🔴 STAY IN DEV DIRECTORY - NEVER `cd` TO PRODUCTION:**
- ❌ **NEVER** `cd /home/kimonokittens/Projects/kimonokittens/` except for read-only verification
- ✅ **ALWAYS** work from `/home/fredrik/Projects/kimonokittens/` (dev checkout)
- ✅ **If you need to check production state**: Use full paths or `cd` temporarily then immediately return to dev
- **Why**: Easy to accidentally edit production files when in prod directory, breaking webhook deployments

### ✅ Process Management Commands (ONLY Use These)

```bash
npm run dev          # Start (calls bin/dev start)
npm run dev:stop     # Stop with aggressive cleanup
npm run dev:restart  # Clean restart
npm run dev:status   # Comprehensive status check
bin/dev nuke         # Nuclear cleanup (last resort)
```

**NEVER** use direct commands (`ruby puma_server.rb`, `cd dashboard && npm run dev`, etc.)

**Why:** Orphaned processes cause port conflicts, stale data (7,492 kr rent bug), zombie persistence. bin/dev handles Claude Code orphan bug ([#5545](https://github.com/anthropics/claude-code/issues/5545)) with multi-layered cleanup (ports, tmux sessions, stale sockets, process patterns).

### 📋 Non-TTY Environment (Oct 26, 2025)

**Procfile auto-detection:**
- **TTY**: `Procfile.dev` (tmux pipe-pane logs)
- **Non-TTY**: `Procfile.dev.nontty` (direct `>> log/*.log` redirection)

**Critical for Claude Code:**
- Verification commands (`overmind status`, `tmux list-windows`) **HANG indefinitely** in non-TTY
- Trust Overmind daemon starts successfully (`-D` flag returns immediately)
- Log access: `npm run dev:logs` or `tail -f log/*.log`
- Status: Run `npm run dev:status` separately AFTER startup, not inline

**Oct 26 simplification**: Removed verification loops that caused hanging - restored pre-Oct 26 reliability.

---

## 📚 ZIGNED E-SIGNATURE API

**Status**: v3 API (Nov 11, 2025) | **Docs**: Use REF read_url for lookups

**CRITICAL: Always use REF read_url tool for Zigned API documentation:**
- Start with: `mcp__REF__ref_read_url "https://docs.zigned.se/"`
- Navigate to specific sections via links in the response
- Base URL: `https://api.zigned.se/rest/v3`
- OAuth: `https://api.zigned.se/oauth/token` (client credentials flow)
- Primary resource: `/agreements` (NOT `/cases` - that's deprecated v1)
- File uploads: `POST /files` with multipart/form-data (15MB limit)
- **OpenAPI spec**: `docs/zigned-api-spec.yaml` (authoritative source for endpoints, schemas, authentication)

**Authentication**: v3 uses OAuth 2.0 with client credentials
```ruby
# Exchange client_id + client_secret for access_token
POST https://api.zigned.se/oauth/token
  grant_type=client_credentials
  client_id=YOUR_CLIENT_ID
  client_secret=YOUR_CLIENT_SECRET

# Use access_token as Bearer token in API requests
Authorization: Bearer <access_token>
```

**Implementation**: `lib/zigned_client_v3.rb` - v3 API client with OAuth + multipart upload

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

## ⚠️ CRITICAL: DATABASE AND DATA OPERATIONS

**Query Before Scripting**: When writing scripts that depend on specific records:

1. **First query to understand actual data state**:
   - What IDs exist in the database?
   - What schema/fields are actually used?
   - Never assume IDs from filenames match database records

2. **Read repository/API documentation** before using methods:
   - Check what methods exist (don't assume `find_all()` exists)
   - Verify method signatures and return types
   - Read the actual code if documentation is missing

3. **Then write scripts based on verified reality**:
   - Use actual IDs discovered from queries
   - Handle missing data gracefully
   - Either discover IDs programmatically or accept parameters

4. **For database operations**:
   - Always check .env for actual `DATABASE_URL` before assuming database names
   - Never connect to `*_development` without verifying it exists
   - Use the database name from .env configuration

**Example - WRONG approach**:
```ruby
# Assumes IDs without verification
sanna = repo.find_by_id('sanna-juni-benemar-8706220020')  # FAILS: ID doesn't exist
```

**Example - CORRECT approach**:
```bash
# First query to discover actual IDs
psql -d kimonokittens -c "SELECT id, name FROM \"Tenant\" WHERE name = 'Sanna Juni Benemar';"
# Returns: cmhqe9enc0000wopipuxgc3kw

# Then use verified ID in script
sanna = repo.find_by_id('cmhqe9enc0000wopipuxgc3kw')  # SUCCESS
```

**Lesson learned**: Nov 8, 2025 - Hardcoded IDs from JSON filenames didn't match database UUIDs, causing export script to fail. Always query first.

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

## ⚡ Electricity Invoice Automation

**Status**: ✅ **PRODUCTION** (Oct 24, 2025) - Dual-scraper system with daily cron
**Documentation**: `docs/ELECTRICITY_AUTOMATION_COMPLETION_SUMMARY.md`, `docs/PRODUCTION_CRON_DEPLOYMENT.md`
**Testing Verified**: Oct 26, 2025 - End-to-end deletion test confirmed 2,581 kr aggregation (see docs)

**Architecture**: Vattenfall (3am) + Fortum (4am) scrapers → `ApplyElectricityBill` service → auto-update RentConfig
**Features**: Peak/off-peak pricing, smart adaptive projection, automatic bill deduplication, timezone-normalized storage
**Cron**: `/home/kimonokittens/Projects/kimonokittens/bin/fetch_vattenfall_data.sh` + `fetch_fortum_data.sh`

---

## 📊 Quarterly Invoice Auto-Projection System

**Status**: ✅ **PRODUCTION** (Oct 25, 2025) - Proactive growth-adjusted projections
**Documentation**: `docs/QUARTERLY_INVOICE_RECURRENCE_PLAN.md`

**Architecture**: RentConfig.for_period → QuarterlyInvoiceProjector → Auto-populate when missing
**Pattern**: Quarterly months (Apr/Jul/Oct) = 3× yearly building operations invoices
**Growth Rate**: 8.7% annual (2024 → 2025: 7,689 kr → 8,361 kr historical trend)
**Base Amount**: 2,787 kr (2025 average of all drifträkningar)

**Key Features**:
- **Proactive auto-population**: Dashboard requests auto-create projections when drift_rakning missing
- **Growth-adjusted formula**: `2,787 × (1.087 ^ years_forward)` → Apr 2026 = 3,030 kr, Apr 2027 = 3,294 kr
- **Projection tracking**: Database `isProjection` flag distinguishes actual vs projected invoices
- **Manual override**: PUT /api/rent/config automatically clears projection flag on updates
- **API transparency**: `quarterly_invoice_projection` boolean + Swedish disclaimer in messages

**Implementation**:
- **Service**: `lib/services/quarterly_invoice_projector.rb` (projection calculations)
- **Model**: `lib/models/rent_config.rb` (auto-population logic in `for_period`)
- **Repository**: `lib/repositories/rent_config_repository.rb` (`save_with_projection_flag` method)
- **Handler**: `handlers/rent_calculator_handler.rb` (API response includes projection status)

**Production Data**:
- Oct 2025: 2,797 kr (actual invoice, isProjection=false) → Nov rent: 7,577 kr/person
- Apr 2026: 3,029 kr (auto-projected, isProjection=true) → May rent shows disclaimer

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
> - **Production IP**: `192.168.4.84` (SSH hostname: `pop` via ~/.ssh/config)
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

**ThermIQ-MQTT Manual**: `docs/ThermIQ_MQTT_Installation_Presentation.pdf` - Complete reference for Thermia heatpump control via MQTT. Contains register reference (pages 12-13), EVU switch control, hot water production status (r10:3), and all telemetry/control registers exposed through the temperature data endpoint.

**Heatpump Control Hierarchy** (highest to lowest priority):
1. **EVU (Hardware Lockout)** - Terminal 307/308 on Thermia heatpump
   - Blocks compressor at permission level, preventing **ALL heat production** (both space heating and hot water)
   - MQTT: `{"EVU":1}` = blocked, `{"EVU":0}` = allowed
   - Cannot be overridden by software - operates upstream of all internal logic
2. **Temperature Override** (Node-RED function: "turn heat ON IF temp too low")
   - Triggers when: `indoor ≤ target` OR `hotwater < 40°C`
   - Forces heatpump ON regardless of schedule when conditions met
   - Only effective when EVU allows compressor operation
   - Location: Pi Node-RED flow at `192.168.4.66:1880`
3. **Tibber Schedule** (Node-RED price optimization)
   - Generates schedule from electricity prices (13h/day, maxPrice 2.2kr/kWh)
   - Optimizes runtime for cheapest hours
   - Subordinate to temperature override

**Critical**: Hot water "priority" logic operates AFTER these three layers. EVU blocking occurs at the compressor (shared heat source), preventing the reversing valve from ever switching heat destination. Temperature override explains why `heatpump_disabled=0` even when schedule shows OFF - the system stays enabled to maintain comfort, but only when EVU permits operation.

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

**Current routing (Nov 2025):** GitHub webhooks bypass nginx, hitting port 49123 directly via home IP
**After domain migration:** Webhooks will route through nginx at `https://kimonokittens.com/api/webhooks/deploy`

1. **Push to master** → GitHub webhook → `POST localhost:49123/webhook` (direct) or `POST https://kimonokittens.com/api/webhooks/deploy` (via nginx after migration)
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
- **⚠️ GEMFILE.LOCK MUST BE COMMITTED** - Industry standard (Capistrano/Heroku) workflow:
  - Development: `bundle install` after Gemfile changes → commit BOTH Gemfile + Gemfile.lock
  - Production: `bundle install --deployment` (frozen mode - lockfile must match exactly)
  - If deployment fails: Fix in development, update lockfile, commit both files
  - No self-healing - deployment only succeeds if lockfile is correct (Oct 24, 2025)
- **pdf-reader removed** - Scrapers use Ferrum browser automation, not PDF parsing (Oct 25, 2025)
- **No database changes via webhook** - Migrations are manual (run `production_migration.rb`)

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

### Electricity Automation Status ⚡

**Status**: ✅ **FULLY AUTOMATED** (Oct 24, 2025) - No manual entry required for rent calculations

- **Peak/off-peak pricing**: Implemented with 0.6-4.3% winter accuracy (exceeds 5-6% target) - see `docs/ELECTRICITY_AUTOMATION_COMPLETION_SUMMARY.md`
- **Dual-scraper system**: Vattenfall (3am) + Fortum (4am) cron jobs auto-fetch invoices, aggregate totals, update RentConfig - see `docs/PRODUCTION_CRON_DEPLOYMENT.md`
- **Rent calculation**: Fully automated from bill arrival through WebSocket broadcast - zero manual intervention needed
- **Quarterly invoice auto-projection**: Growth-adjusted projections (8.7% YoY) for Apr/Jul/Oct when actual invoices not yet received - see `docs/QUARTERLY_INVOICE_RECURRENCE_PLAN.md`

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

**Alarm System (Larm)**: Verisure pre-installed system in building, mandatory cost, cannot be removed. Household doesn't use it, but equipment remains installed. Initially separate billing (597 kr/quarter early 2023), now consolidated into Bostadsagenturen quarterly invoice.

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

### Check Temperature Data:
```bash
curl -s http://localhost:3001/data/temperature | jq '{temp: .supplyline_temperature, disabled: .heatpump_disabled, demand: .heating_demand}'
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
- **Definition**: `Procfile.dev` (TTY) or `Procfile.dev.nontty` (non-TTY) - auto-detected by bin/dev

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

### Performance Caching
**Electricity regression** (90-day linear model) cached until midnight - deterministic daily calculation runs once/day instead of every 5min broadcast (99.65% reduction, ~90% CPU savings for handler). Cache invalidates when `Date.today` changes.

### Data Refresh Flow
**Backend**: DataBroadcaster fetches handlers every 5-600s → checks cache → computes if needed → broadcasts via WebSocket. **Frontend**: Receives updates → React rerenders widgets. **Key**: Regression data changes once daily (midnight cache invalidation), but frontend receives WebSocket updates every 5min regardless.

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
curl http://localhost:49123/status | jq .deployment

# View webhook application logs (deployment details, bundle install, etc)
tail -f /var/log/kimonokittens/webhook.log

# View webhook service status (systemd start/stop only)
journalctl -u kimonokittens-webhook -f

# View deployment timer status
curl http://localhost:49123/status | jq '{pending: .deployment.pending, time_remaining: .deployment.time_remaining}'
```

**Note**: Webhook logs application output to `/var/log/kimonokittens/webhook.log`, not systemd journal. Use `tail -f` on the log file to see deployment progress, bundle install status, and errors.

### GitHub Webhook Debugging (gh CLI)

**Check webhook status and recent deliveries:**
```bash
# List all webhooks with status
gh api repos/:owner/:repo/hooks | jq '.[] | {id, active, url: .config.url, last_response}'

# Check specific webhook status (ID: 572892196)
gh api repos/:owner/:repo/hooks/572892196 | jq '{id, active, last_response, events}'

# View recent webhook deliveries (last 20)
gh api repos/:owner/:repo/hooks/572892196/deliveries | jq '.[] | {delivered_at, status_code, status, event}' | head -20

# Get detailed error from specific delivery
gh api repos/:owner/:repo/hooks/572892196/deliveries/DELIVERY_ID | jq '{status: .status_code, request: .request.headers, response: .response}'

# Latest delivery summary
gh api repos/:owner/:repo/hooks/572892196/deliveries | jq -r '.[0] | "Latest: \(.delivered_at) - Status: \(.status_code) - \(.status)"'
```

**Common webhook issues:**
- **500 errors**: Git pull failed (check file ownership, untracked files, or dirty git state)
- **502 errors**: Webhook service down or network unreachable
- **No deliveries**: GitHub may have disabled webhook after repeated failures

**Recovery steps** (Oct 26, 2025 incident):
1. **Check git ownership**: `ls -l /home/kimonokittens/Projects/kimonokittens/.git/index` (should be kimonokittens:kimonokittens)
2. **Fix ownership**: `sudo chown -R kimonokittens:kimonokittens /home/kimonokittens/Projects/kimonokittens/.git`
3. **Check untracked files**: `cd /home/kimonokittens/Projects/kimonokittens && git status --porcelain` (should be empty or only ignored files)
4. **Test git pull**: `cd /home/kimonokittens/Projects/kimonokittens && git pull origin master`
5. **Monitor next push**: `tail -f /var/log/kimonokittens/webhook.log` while pushing from dev machine

### Why Deploy Webhook MUST Stay Separate

**Deploy and Zigned webhooks serve different services and cannot be unified.**

1. **Self-Restart Impossibility** - Deploy webhook updates its own code; can't restart from within while serving HTTP
2. **Fault Isolation** - Git pull/npm failures shouldn't crash live contract signing webhooks
3. **Security Through Obscurity** - Deploy on port 49123 (GitHub only), API on port 3001 (public-facing)
4. **Operational Simplicity** - Independent restart/recovery without affecting business logic

**Architecture (intentional, not technical debt):**
- Port 49123: Deploy webhook only (kimonokittens-webhook.service)
- Port 3001: Main API + Zigned webhooks (kimonokittens-dashboard.service)

### Future-Proofing

The Puma architecture is designed for:
- **Multiple projects** - easily add new webhook endpoints
- **Concurrent requests** - multi-threaded webhook handling
- **Scalability** - same battle-tested server as dashboard
- **Cognitive ease** - unified Rack patterns across services

---

## 📝 CONTRACT SIGNING SYSTEM (Zigned Integration)

**Status**: ✅ **PRODUCTION READY** (Nov 11, 2025) - Complete webhook handler with all 14 event types

### Architecture Overview

**Contract Lifecycle**:
1. **Creation** (`lib/contract_signer.rb`) → Generate PDF + Send to Zigned API v3
2. **Webhooks** (`handlers/zigned_webhook_handler.rb`) → Receive 14 event types from Zigned
3. **Storage** (`lib/models/`, `lib/repositories/`) → Track contracts + participants in database
4. **Completion** → Auto-download signed PDF + Update records

### Key Files & Components

**Core Implementation**:
- `handlers/zigned_webhook_handler.rb` - Complete event handler (14 event types, personal_number lookup, signature verification)
- `lib/contract_signer.rb` - PDF generation + Zigned API client integration
- `lib/models/signed_contract.rb` - Contract domain model with lifecycle tracking
- `lib/models/contract_participant.rb` - Per-participant tracking (email, signatures, identity verification)
- `lib/repositories/signed_contract_repository.rb` - Contract persistence with `update()` and `save()` methods
- `lib/repositories/contract_participant_repository.rb` - Participant persistence
- `lib/persistence.rb` - Centralized repository access (`Persistence.contract_participants`, etc.)

**Database Schema** (Prisma):
- `SignedContract` - Main contract record (test mode, lifecycle status, timestamps, email delivery)
- `ContractParticipant` - Per-signer tracking (signing URLs, email delivery, identity enforcement, personal numbers)

**Documentation** (all in `docs/`):
- `ZIGNED_WEBHOOK_FIELD_MAPPING.md` - Real payload analysis mapping webhook events → database fields
- `ZIGNED_WEBHOOK_TESTING_STATUS.md` - Bug fixes log (Nov 11: repository.update + personal_number lookup)
- `ZIGNED_V3_MIGRATION_PLAN.md` - Migration from v1 → v3 API
- `zigned-api-spec.yaml` - Complete OpenAPI 3.0 spec (21,571 lines)

### Webhook Events (Complete Coverage ✅)

**Lifecycle Events** (6):
- `agreement.lifecycle.pending` - Contract ready for signing
- `participant.lifecycle.fulfilled` - Individual signer completed
- `agreement.lifecycle.fulfilled` - All parties signed
- `agreement.lifecycle.finalized` - Signed PDF ready (auto-downloads)
- `agreement.lifecycle.expired` - Contract expired
- `agreement.lifecycle.cancelled` - Contract cancelled

**Tracking Events** (8):
- `participant.identity_enforcement.passed` - Swedish personnummer verified
- `participant.identity_enforcement.failed` - Identity check failed
- `agreement.pdf_verification.completed` - PDF validation passed
- `agreement.pdf_verification.failed` - PDF validation failed
- `email_event.agreement_invitation.delivered` - Per-participant email confirmation
- `email_event.agreement_invitation.all_delivered` - All invitation emails sent
- `email_event.agreement_invitation.delivery_failed` - Email bounce detection
- `email_event.agreement_finalized.delivered` - Final PDF email delivered

### Critical Implementation Details

**Personal Number Lookup** (Bug #2 fix - Nov 11):
- Zigned webhooks **don't send personal_number** field
- Handler implements fallback: landlord email match + tenant database query
- Location: `handlers/zigned_webhook_handler.rb:682-708`

**Signing URL Field Variants** (commit 25be98d):
- Zigned API uses both `signing_url` AND `signing_room_url` in different endpoints
- Handler checks both with `||` fallback operator
- Location: `handlers/zigned_webhook_handler.rb:661`

**Signature Verification** (Stripe-style HMAC-SHA256):
- Validates `x-zigned-request-signature` header format: `t={timestamp},v1={signature}`
- Uses timestamped payload to prevent replay attacks
- Location: `handlers/zigned_webhook_handler.rb:137-163`

### Logging & Monitoring

**All webhook events logged to systemd journal:**
```bash
# Real-time Zigned events
journalctl -u kimonokittens-dashboard -f | grep -E "(📝|✍️|🎉|📥|❌|⚠️)"

# All contract events
journalctl -u kimonokittens-dashboard | grep -E "(agreement|participant|email_event)"

# Specific event type
journalctl -u kimonokittens-dashboard | grep "participant.lifecycle.fulfilled"

# Webhook errors
journalctl -u kimonokittens-dashboard | grep "❌ Webhook error"
```

**Event indicators**:
- 📝 Agreement activated
- ✍️ Signature received
- 🎉 Contract fully signed
- 📥 Contract finalized (PDF ready)
- 📧 Email delivered
- 🔐 Identity verified
- ❌ Errors (identity/PDF/email failures)
- ⚠️ Warnings (missing records, unknown events)

### Production Requirements

**Environment variables** (already configured in `/home/kimonokittens/.env`):
```bash
ZIGNED_API_KEY='{production_api_key}'
ZIGNED_WEBHOOK_SECRET_REAL='{production_webhook_secret}'
ZIGNED_WEBHOOK_SECRET_TEST='{test_webhook_secret}'
```

**Webhook endpoint**: `POST /api/webhooks/zigned` (port 3001, handled by puma_server.rb)

### Recent Work (Nov 11, 2025)

**Bug Fixes**:
- eff6ccf - Complete webhook handler (all 14 events, signing URL fallback, failure handlers)
- 1a1d4de - Personal number lookup (email matching + tenant query)
- 281c137 - Add `update()` method to SignedContractRepository

**Features**:
- 7261f44 - All tracking events (identity, PDF verification, email delivery)
- 3d11c95 - Adapt to real Zigned payloads (not docs - actual webhook data)
- b98a41c - Field mapping document (comprehensive payload analysis)

**Testing** (Nov 11):
- Test contract `cmhuyr9pt010x4cqk5tova6bd` revealed both critical bugs
- Both fixed and deployed within hours
- Ready for webhook replay testing in Zigned dashboard

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
# Kimonokittens Project Instructions

## 📖 DOCUMENTATION PHILOSOPHY

**See global `~/.claude/CLAUDE.md` for universal documentation principles.**

**This project's application**:
- **Subdirectory organization**: `/dashboard/CLAUDE.md` (frontend), `/lib/CLAUDE.md` (backend), root CLAUDE.md (cross-cutting)
- **Cross-machine context**: Dell Optiplex 7010 (production), Mac Mini M2 (development), Raspberry Pi 3B+ (infrastructure)

---

## 💻 Production Environment (Dell Optiplex 7010)

**Hardware:**
- Dell Optiplex 7010
- GPU: NVIDIA GTX 1650 (4GB VRAM)
- Display: Physical monitor in hallway (24/7 kiosk)

**System:**
- OS: Pop!_OS 22.04 (Linux kernel 6.16.3)
- PostgreSQL: 18
- NVIDIA Driver: 580
- Last system upgrade: Oct 9, 2025

**Chrome Kiosk GPU Flags:**
```bash
--ignore-gpu-blocklist
--enable-features=AcceleratedVideoDecodeLinuxZeroCopyGL,AcceleratedVideoDecodeLinuxGL,VaapiIgnoreDriverChecks,VaapiOnNvidiaGPUs
--force-gpu-mem-available-mb=4096
--force-device-scale-factor=1.15
```

**Display Rotation:** Monitor physically rotated 90° clockwise (portrait). Software compensates with 90° counter-clockwise (`<rotation>left</rotation>`). **Critical:** GNOME ignores `/var/lib/gdm3/.config/monitors.xml` on modern systems - use `/etc/xdg/monitors.xml` (global Mutter config) to persist rotation across reboots/power outages. Wayland disabled (`WaylandEnable=false` in `/etc/gdm3/custom.conf`).

**UPS Needed:** Power outages cause config resets (rotation, possibly brightness schedule). UPS recommended (650-900 kr) to protect production server from outage-related configuration drift.

**Services:**
- Backend API: Puma on port 3001
- Frontend: Nginx serving built dashboard
- WebSocket: Integrated with Puma backend
- Webhook receiver: Port 49123
- Production database: `kimonokittens_production`

---

## 👤 SESSION CONTEXT & PERMISSIONS

**This Claude Code session runs as the `fredrik` user** (development environment)

### User & Checkout Matrix

| User | Sudo Access | Checkout Location | Purpose |
|------|-------------|-------------------|---------|
| **fredrik** | ✅ Yes (TTY required) | `/home/fredrik/Projects/kimonokittens/` | Development & git operations |
| **kimonokittens** | ❌ No | `/home/kimonokittens/Projects/kimonokittens/` | Production services only |

### Claude Code Capabilities & Limitations

**What Claude Code CAN do:**
- ✅ Access production database via `DATABASE_URL` environment variable
- ✅ Read files from both checkouts (dev and prod)
- ✅ Run non-privileged commands as fredrik user
- ✅ Git operations (commit, push) in dev checkout

**What Claude Code CANNOT do:**
- ❌ Run `sudo` commands - requires TTY for password input
- ❌ Access kimonokittens user directly - session runs as fredrik
- ❌ Restart systemd services - requires sudo (tell user the command instead)

### Working Directory Protocol

**🔒 PRODUCTION CHECKOUT IS READ-ONLY (Filesystem Protection Active)**

As of Nov 24, 2025, production checkout has filesystem permissions that **prevent fredrik user from writing**:
```bash
# Permissions: chmod g-w (group write removed)
# Files owned by: kimonokittens:kimonokittens
# fredrik user: read-only access (group member, no write permission)
```

**Development workflow (ALWAYS follow):**
```bash
# ✅ CORRECT: Work in dev checkout
cd /home/fredrik/Projects/kimonokittens/
# Edit files, commit, push to trigger webhook deployment

# ✅ SAFE: Production checkout is READ-ONLY
cd /home/kimonokittens/Projects/kimonokittens/  # Can read, CANNOT write
# Any Edit/Write attempts will fail with "Permission denied"
```

**Why this matters:**
- Webhook deployments ensure consistent deployment process
- Filesystem protection prevents accidental production edits
- All changes MUST go through git → webhook flow
- Direct production edits contaminate ownership and block deployments

**Deployment flow:** Edit in dev → commit → push → webhook auto-deploys to prod

**If you need to verify production state:** Read files only, never edit. Use dev checkout for all modifications.

---

## ⚠️ CRITICAL: PROCESS MANAGEMENT PROTOCOL

**Status**: ✅ PRODUCTION (Oct 26, 2025) | **Deep Dive**: `docs/PROCESS_MANAGEMENT_DEEP_DIVE.md`

### 🐛 Claude Code Background Process Bug

**System reminders show unreliable status** - always verify with `ps` or `BashOutput` tool:
```bash
ps aux | grep -E "(npm run dev|ruby.*puma|vite.*5175)" | grep -v grep
lsof -ti :3001 :5175
```

**BashOutput for background commands may be stale** - System reminders about "new output available" can refer to hours-old processes. Always verify process is actually running before trusting output.

**Issues**: [#7838](https://github.com/anthropics/claude-code/issues/7838), [#1481](https://github.com/anthropics/claude-code/issues/1481), [#759](https://github.com/anthropics/claude-code/issues/759)

### ⚠️ Sudo Commands - Tell User to Run

**Claude Code cannot run `sudo` commands** (requires TTY for password input). Always tell user the exact command instead of attempting to run it.

**See**: 👤 SESSION CONTEXT & PERMISSIONS section above for complete user/permission details.

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

## 🎨 UI COLOR SCHEME

**For complete color palette and usage guidelines:** See `/dashboard/CLAUDE.md`

**Critical rule**: Never use green/emerald for success states - use cyan instead.

### 🚨 Production Deployment

**🔴 CRITICAL: NEVER PUSH WITHOUT EXPLICIT USER AUTHORIZATION 🔴**
- **ALWAYS ask "Ready to push to production?" before `git push`**
- **User must explicitly say "yes" or "push it" or similar**
- **"Looks good" or "that's fine" is NOT authorization to push**
- Pushing = Immediate production deployment via webhook
- User may want to review changes locally before production rollout

**Webhook deployments MANDATORY** - never edit production checkout directly:
- All changes MUST go through: dev checkout → git push → webhook → production
- See 👤 SESSION CONTEXT & PERMISSIONS for complete checkout/workflow details
- Webhook broken? Fix webhook, don't work around
- Monitor: `journalctl -u kimonokittens-webhook -f`

**⚠️ SYSTEMD ENVIRONMENTFILE REMOVED (Nov 12, 2025):**
Systemd's `EnvironmentFile` doesn't support `${VAR}` expansion - it loads literal strings. Services now use `require 'dotenv/load'` exclusively for .env loading. This enables variable substitution (`ZIGNED_WEBHOOK_SECRET=${ZIGNED_WEBHOOK_SECRET_REAL}`) and prevents systemd from overriding dotenv values. **Never re-add EnvironmentFile to service files.**

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

## 🗄️ PRISMA DATABASE MIGRATION PROTOCOL

**Status**: ✅ CRITICAL WORKFLOW - Development shortcuts become production disasters

### Core Principle: Schema and Database Must Always Match

**Development discipline directly determines production reliability.** Careless migration practices in development create technical debt that manifests as data corruption, deployment failures, and emergency incidents in production.

### ✅ The Correct Prisma Migration Workflow

**Always follow this sequence for schema changes:**

1. **Edit `schema.prisma`** - Make your model changes
2. **Create migration** - `npx prisma migrate dev --name descriptive_name`
3. **Verify migration** - Review generated SQL in `prisma/migrations/`
4. **Commit both files** - Schema + migration together, always

**Why this matters:** Prisma migrations are immutable records. Once applied, they become the source of truth. Schema file must reflect what migrations create.

### ❌ What NEVER To Do

**NEVER modify migrations after they're applied** - Creates irreversible drift between migration history and database state. Like editing git commits after pushing - breaks everyone downstream.

**NEVER use `db push` except for rapid prototyping** - Bypasses migration history entirely. Fine for throwaway experiments, dangerous for any code that will be committed.

**NEVER leave schema.prisma out of sync with migrations** - When you create a migration SQL file, you MUST update schema.prisma to match. This is not optional. Drift between schema and database breaks:
- Future migrations (Prisma can't calculate correct diffs)
- CI/CD pipelines (fresh database builds fail)
- Team collaboration (others pull your migrations but schema doesn't match)
- Production deployments (migration applies but schema expectations differ)

### 🔧 Resolving Migration Drift (When You Discover Mismatch)

**If you discover schema.prisma is out of sync with applied migrations:**

1. **Add missing fields to schema.prisma** - Match what's actually in the database
2. **Verify with `npx prisma db pull`** - This introspects database and shows what schema SHOULD be
3. **Create new migration for your actual change** - `npx prisma migrate dev --name your_feature`

**Never use `--skip-generate` or `--accept-data-loss` flags without understanding WHY Prisma is warning you.**

**Manual migration fixes (Nov 20, 2025):** If you manually apply a migration's SQL to fix drift, you MUST run `npx prisma migrate resolve --applied "migration_name"` to reconcile Prisma's migration history. Just applying SQL isn't enough - Prisma needs to know the migration is resolved.

### 📋 Migration Best Practices

**Descriptive migration names** - Use present tense verbs: `add_room_to_tenant`, `add_contract_lifecycle_tracking`, `remove_deprecated_status_field`

**Review generated SQL** - Always read what Prisma created. Catch mistakes before they reach the database.

**Commit migrations immediately** - Don't accumulate uncommitted migrations. Each logical change = one migration = one commit.

**Test migrations locally first** - Run `npx prisma migrate dev` in development before pushing to production.

**Production migrations are manual** - Never auto-migrate in production. Webhook deploys code only. Run `npx prisma migrate deploy` deliberately after reviewing changes.

### 🎯 Development vs Production Commands

**Development** (creates migrations):
```bash
npx prisma migrate dev --name descriptive_name  # Create + apply migration
npx prisma db push                              # Prototype only (no migration files)
npx prisma db pull                              # Introspect database → update schema
```

**Production** (applies existing migrations):
```bash
npx prisma migrate deploy     # Apply pending migrations (never creates new ones)
npx prisma migrate status     # Check which migrations need to run
```

**Never run `migrate dev` in production.** It tries to create migrations, which should only happen in development with developer oversight.

**Claude Code limitation**: `npx prisma migrate dev` requires interactive environment - Claude Code will error. User must run the command manually in their terminal after schema changes are committed.

**Community vs Prisma team (Nov 2025):** GitHub issues #7113, #4669 requested `--allow-non-interactive` flag for CI/CD workflows. Prisma team **intentionally rejected** this to prevent misuse of `migrate dev` in production. The team's stance: development migrations should always be interactive, production should use `migrate deploy`. This means AI coding tools will never be able to run `migrate dev` - by design.

### 💡 Key Insight: Shortcuts Compound

Taking shortcuts in development doesn't save time - it creates time bombs:
- Skip updating schema.prisma → drift warnings on next migration
- Ignore drift warnings → migration fails in CI
- Force through with `db push` → production migration fails
- Emergency hotfix required → downtime for users

**Sustainable development means:** Every change is done correctly the first time. The "careful way" in development IS the fast way to production.

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

## ⚠️ CRITICAL: RUBY SCRIPT EXECUTION PROTOCOL

**For complete Ruby execution guidelines:** See `/lib/CLAUDE.md`

**Critical rule**: ALWAYS use `bundle exec` for Ruby scripts - this project uses `--deployment` mode with `vendor/bundle`.

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

**Status**: ✅ **PRODUCTION** (Oct 24, 2025) - Fully automated, zero manual intervention
**Cron**: `bin/fetch_vattenfall_data.sh` (3am) + `bin/fetch_fortum_data.sh` (4am)
**Flow**: Scrapers → `ApplyElectricityBill` → RentConfig update → WebSocket broadcast
**Docs**: `docs/ELECTRICITY_AUTOMATION_COMPLETION_SUMMARY.md`

### Data Source Clarification (Nov 20, 2025)

**CRITICAL: Consumption data comes from Vattenfall scraper, NOT Tibber!**

**Actual Data Sources:**
- **Consumption data**: `vattenfall.rb` → `electricity_usage.json` (Vattenfall Eldistribution API, hourly kWh)
- **Spot price data**: `lib/electricity_projector.rb` → elprisetjustnu.se API (SE3 Stockholm, live API calls)
- **Fixed service fees** (constants in ElectricityProjector):
  - Vattenfall: 590 kr/month (grid connection base fee)
  - Fortum: 88 kr/month (trading service 39 kr + Priskollen 49 kr)
  - Total: 678 kr/month (added to consumption costs in projections)

**"Tibber" References in Codebase (Historical Context):**
- **Legacy files DELETED Nov 20, 2025**: `tibber.rb`, `tibber_price_data.json` - Used 1+ years ago for Dakboard dashboard
- **Node-RED heatpump integration**: Uses "Tibber-compatible" API format (`heatpump_price_handler.rb`) for backwards compatibility
- **Migration completed Nov 19, 2025**: Node-RED switched from Tibber demo API key to Dell API endpoint

**Key Insight**: "Tibber-compatible" means API response format matching for Node-RED MQTT heatpump commands, NOT actual Tibber data usage. The dashboard electricity projection system (ElectricityProjector) has NEVER used Tibber - it always used elprisetjustnu.se for spot prices and Vattenfall scraper for consumption data.

---


## 🏗️ Repository Architecture Pattern

**Status**: ✅ **PRODUCTION READY** (October 2025) - Full domain model migration complete

**For complete Ruby implementation guide:** See `/lib/CLAUDE.md`

### Architecture Overview

Clean architecture with domain models, repositories, and services:

```
Handlers → Services → Domain Models + Repositories → Database
         ↓
    Persistence (centralized access)
```

**Architecture layers:**
1. **Domain Models** (`lib/models/`) - Business logic, NO database access
2. **Repositories** (`lib/repositories/`) - Persistence only, NO business rules
3. **Services** (`lib/services/`) - Multi-table transactions
4. **Persistence** (`lib/persistence.rb`) - Singleton repository access

**Single Source of Truth (SSoT):** Tenant is the master data source - all handlers fetch tenant data live from database via repository. No duplication, no cache. Changes to tenant records immediately reflect in all views.

**Repository SELECT Pattern:** Never enumerate fields in `.select()` - schema changes cause silent bugs (hydrate() expects new field, SELECT omits it → nil). Model `.to_h()` whitelists API exposure, making unrestricted fetch safe.

**Documentation**: `docs/MODEL_ARCHITECTURE.md` (800+ lines), test coverage: 37 tests for domain layer (all passing)

---

## 🔐 Environment Variables

**Production `.env` file synced with development** - The `/home/kimonokittens/.env` file contains all API keys and secrets from the Mac development environment for smooth deployment across all monorepo features (weather, Strava, bank integration, handbook, etc.).

**Symlink strategy (no duplication)**: `/home/kimonokittens/Projects/kimonokittens/.env` → `/home/kimonokittens/.env` (source of truth). Services use `EnvironmentFile=-/home/kimonokittens/.env`, Prisma/dotenv follow symlink.

**Development environment on kiosk** - `/home/fredrik/Projects/kimonokittens/.env` configured with `DATABASE_URL` pointing to `_development` database and `NODE_ENV=development`. Allows independent local dev/test on kiosk hardware without affecting production.

---

## 🚀 DEPLOYMENT ARCHITECTURE

> **✅ KIOSK DEPLOYED**: Dell Optiplex 7010 live in hallway (October 6, 2025)
> - **Production IP**: `192.168.4.84` (SSH hostname: `pop` via ~/.ssh/config). From any device on the LAN you can hit the dashboard UI directly at `http://pop-os.local/` (nginx on port 80 proxies everything), so no special tunneling is required. The SPA only makes same-origin requests (`/api/*`, `/dashboard/ws` etc.), so browsing from another machine never tries to call its own localhost.
> - Dashboard display operational 24/7
> - GPU acceleration + webhook auto-deployment active
> - Migration from Pi 3B+ ongoing (Node-RED, MQTT, cron jobs)

### 🔄 Pi Migration Strategy (October 6, 2025)

**Network**: `kimonokittens.com` bound to home IP via DDClient dynamic DNS

**Services Staying on Pi** (infrastructure/automation):
- **DDClient**: Dynamic DNS updates for kimonokittens.com
- **Pycalima**: Bluetooth-based bathroom fan control (hardware proximity required)
- **Node-RED**: Temperature sensor aggregation, Dell API integration for heatpump control (port 1880)
  - **Nov 20, 2025 migration**: Removed Tibber integration + ps-strategy logic → now calls Dell `/api/heatpump/schedule` endpoint
  - Serves as transport layer: fetches schedule from Dell → sends EVU commands via MQTT
- **Mosquitto MQTT**: Message broker for ThermIQ heatpump data (port 1883)

**Services Migrating to Dell** (dashboard-relevant data):
- **Electricity data cron jobs**: `vattenfall.rb` + `tibber.rb` (every 2 hours)
- **Electricity JSON files**: `electricity_usage.json`, `tibber_price_data.json`
- **Dashboard data generation**: All data consumed by widgets or useful for online handbook
- **Heatpump schedule generation** (Nov 20, 2025): Moved from Pi Tibber/ps-strategy → Dell Ruby backend
  - ps-strategy algorithm now in `/api/heatpump/schedule` handler
  - Configurable parameters via database (HeatpumpConfig table) - UI in progress
  - Temperature override logic will also move to Dell (currently broken on Pi)

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
2. **Temperature Override** (⚠️ **BROKEN as of Nov 20, 2025** - pending migration to Dell backend)
   - Previous implementation: Node-RED function checking `indoor ≤ target` OR `hotwater < 40°C`
   - Broken: Depends on removed Tibber data flow
   - **Migration plan**: Override logic moving to Dell backend in `/api/heatpump/schedule` handler
   - See `docs/HEATPUMP_CONFIG_UI_PLAN.md` for implementation details
3. **Dell API Schedule** (price-optimized ps-strategy, Nov 20, 2025)
   - **Replaced** Tibber/Node-RED ps-strategy with Ruby backend implementation
   - Generates schedule from electricity prices (configurable: hours_on 9-14, maxPrice 1.5-3.0 kr/kWh)
   - Optimizes runtime for cheapest hours using ps-strategy algorithm
   - Node-RED calls `/api/heatpump/schedule?hours_on=12&max_price=2.2` every 20 minutes
   - Returns JSON with EVU state, schedule applies to MQTT

**Critical**: Hot water "priority" logic operates AFTER these three layers. EVU blocking occurs at the compressor (shared heat source), preventing the reversing valve from ever switching heat destination. Temperature override (when working) explains why `heatpump_disabled=0` even when schedule shows OFF - system stays enabled to maintain comfort, but only when EVU permits operation.

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

/etc/nginx/
├── sites-available/
│   └── kimonokittens.conf                     # Main nginx config (source of truth)
└── sites-enabled/
    └── default → ../sites-available/kimonokittens.conf  # Active config (symlink)

/home/kimonokittens/.config/systemd/user/      # User services
├── kimonokittens-kiosk.service                # Chrome kiosk (port localhost)
└── (dashboard managed by root systemd)
```

**Nginx Configuration:**
- **Config file**: `/etc/nginx/sites-available/kimonokittens.conf`
- **Active symlink**: `/etc/nginx/sites-enabled/default` → `kimonokittens.conf`
- **Non-standard naming**: Symlink is called "default" instead of matching filename
- **Structure**: Two server blocks (public HTTPS for kimonokittens.com + localhost for kiosk/LAN)
- **Reload after changes**: `sudo nginx -t && sudo systemctl reload nginx`

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

### Verification Commands
```bash
# Database connectivity
ruby -e "require 'dotenv/load'; require_relative 'lib/rent_db'; puts RentDb.instance.get_tenants.length"

# API health
curl http://localhost:3001/api/rent/friendly_message

# WebSocket (check browser console)
ws://localhost:3001
```

---

**CRITICAL: Read this file completely before working on rent calculations or database operations.**

## Rent Calculation Timing & Business Logic

**For complete rent calculation details:** See `/lib/CLAUDE.md`

**Critical concept**: Config month = rent month - 1 (Sept config → Oct rent). Rent paid in advance, electricity in arrears. See `/lib/CLAUDE.md` for payment structure, virtual pot system, electricity automation, and bill timing details.

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
- **`drift_rakning`**: Quarterly invoice (logged for audit only, **not used in calculations**)
- **Monthly accruals**: Always 837 kr (754 building + 83 gas), regardless of quarterly invoices

### Debugging Structural Issues
When rent calculations seem wrong, check these patterns:
- **Config timing**: Verify `period` month = rent display month - 1 (Sept config → Oct rent)
- **Test contamination**: Production DB has unexpected `drift_rakning` values from specs
- **Message indicator**: API shows "uppskattade elkostnader" = projection mode (bills not arrived yet)

## Testing Best Practices 🧪

**For complete backend testing guide:** See `/lib/CLAUDE.md`

**Status**: ✅ 39/39 tests passing | **Documentation**: `docs/TESTING_GUIDE.md`

**Core philosophy**: Test database isolation (use `kimonokittens_test` database), spec_helper.rb must be first require, update test expectations when code evolves legitimately.

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

### Rent Config Change Workflow:
1. **Before making rent changes**: Read this file (timing quirks above)
2. **Check database state**: Use quick reference commands above
3. **Update configs**: Use correct timing (current month period for next month rent)
4. **Restart processes**: `npm run dev:restart` to ensure fresh backend
5. **Verify results**: Test API and check dashboard
6. **Clean up**: Remove any test data from production DB

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

## Kiosk Display Optimization

**For WebGL shader performance impact and optimization recommendations:** See `/dashboard/CLAUDE.md`

**Note**: Hardware specs and Chrome GPU flags are in `~/.claude/CLAUDE.md` (global, machine-specific)

---

## Frontend Development

**For complete frontend development guide:** See `/dashboard/CLAUDE.md`

**Key topics covered:**
- SSH port forwarding setup (Mac → Linux dev machine)
- Vite development workflow and HMR
- Animation patterns, CSS gotchas, performance optimization
- Form editing patterns (inline vs modal dialogs)

---

## WebSocket Architecture ⚡

**For backend implementation:** See `/lib/CLAUDE.md` (DataBroadcaster, refresh intervals, performance caching)
**For frontend integration:** See `/dashboard/CLAUDE.md` (React Context, widget patterns)

### Data Flow Overview

```
Backend (Ruby) → WebSocket → Frontend (React)
DataBroadcaster → puma_server.rb → React Context → Widgets
```

1. **Ruby DataBroadcaster** fetches from HTTP endpoints every 30-600s
2. **Custom WebSocket** (`puma_server.rb`) publishes to frontend via raw socket handling
3. **React Context** manages centralized state with useReducer
4. **Widgets** consume via `useData()` hook

**Performance**: Electricity anomaly regression (90-day model) cached until midnight - runs once/day instead of every 5min (99.65% reduction, ~90% CPU savings).

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

### Monitoring Production Kiosk Display 📸

**Problem**: The production kiosk display is physically located in the hallway downstairs - not visible from SSH sessions.

**Solution**: Screenshot API for remote monitoring

**Usage**:
```bash
# Capture new screenshot of kiosk display
curl -s http://localhost:3001/api/screenshot/capture | jq .

# Download the screenshot
curl -s http://localhost:3001/api/screenshot/latest > /tmp/dashboard.png

# View with image viewer or Read tool
# The screenshot shows exactly what's on the physical display
```

**API Endpoints**:
- `GET /api/screenshot/capture` - Takes new screenshot, returns metadata
- `GET /api/screenshot/latest` - Returns the most recent screenshot image (PNG)

**Storage**: Screenshots saved to `/tmp/kimonokittens-screenshots/`, last 10 kept automatically

**Requirements**:
- Runs as `kimonokittens` user with `DISPLAY=:0` access
- Uses `scrot` command (pre-installed on production)
- Works from any SSH session without sudo/authentication

**Use cases**:
- Verify frontend deployments loaded correctly
- Check WebSocket connection status
- Debug visual issues without walking downstairs
- Monitor kiosk health remotely

## 🔄 SMART WEBHOOK DEPLOYMENT SYSTEM

**Smart change detection** + **2-min debounce** + **component-specific deployment** (Puma + Rack architecture)

**Status**: ✅ **WORKING** (Oct 2, 2025) - Core pipeline: git pull → npm ci → vite build → rsync deploy
**Architecture**: Unified Puma + Rack (dashboard port 3001, webhook port 49123)

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

### ⚠️ CRITICAL: Ruby Logger Buffering

**Problem**: Deployment logs appeared to "stop" after rsync, but execution actually continued (logs buffered 60+ seconds).

**Root cause**: Ruby `Logger.new(STDOUT)` buffers output. rsync output fills buffer → flush, then subsequent logs sit buffered.

**Fix** (commit `4a458ca`): `$stdout.sync = true` forces immediate flush.

**Debugging lesson**: If logs "stop", check wider time windows (30-120s later) before assuming hang.

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

## 📝 Contract Signing & Admin UI

**For backend implementation:** See `/lib/CLAUDE.md` (Zigned webhooks, API endpoints, validation)
**For frontend admin UI:** See `/dashboard/CLAUDE.md` (contract creation flow, status display)

**Status**: ✅ **PRODUCTION READY** (Nov 11-14, 2025) - Zigned integration + admin contact management

**Critical requirement**: Tenant must have `personnummer` before contract creation (legally required for Swedish rental contracts)


## ⚠️ REPOSITORY PATTERN GOTCHA

**Critical bug discovered Nov 14, 2025** - `lib/repositories/tenant_repository.rb`

### The Problem

Repository `.all()` method was using `.select()` but **missing fields**:
```ruby
# WRONG - fields not in SELECT returned as nil!
.select(:id, :name, :email, :startDate, :departureDate, :roomAdjustment, :room, :status)
```

**Impact**: Admin UI showed "—" for personnummer even though database had data!

### The Lesson

**Always include all model fields in SELECT statements** or use `select_all`:
```ruby
# CORRECT - include all fields model needs
.select(:id, :name, :email, :personnummer, :phone, :facebookId, ...)
```

**When debugging "missing data"**: Verify database state FIRST before concluding data doesn't exist.

---


## 💸 PAYMENT DETECTION & RENT REMINDERS

**Status**: ✅ **PRODUCTION** (Nov 2025) - All 5 phases complete

**Payment Detection** (Lunchflow bank sync - ⏸️ Temporarily disabled, re-enabling Nov 27):
- Monitors house bank account (tied to Swish) for incoming transactions
- 4-tier matching: reference code → phone number → amount+timing → fuzzy name
- Syncs 3x daily (8:05, 14:05, 20:05) when active
- Automatically updates RentLedger payment status
- Cron disabled until subscription renewed

**Rent Reminders** (SMS via 46elks - ✅ Production, Nov 24 2025):
- Automated SMS reminders (4 tones: heads_up day 24, first_reminder payday, urgent day 27, overdue 28+)
- Idempotency checking prevents duplicate sends
- Separate WEBHOOK_BASE_URL for external 46elks callbacks (public URL required)
- Tested successfully: 5 SMS sent with correct amounts
- Cron: daily 9:45am

**Architecture**:
- Backend: `lib/sms/gateway.rb` (46elks integration)
- Ledger: `lib/models/rent_ledger.rb`, `bin/populate_monthly_ledger`
- Matching: 4-tier payment detection in Lunchflow webhook handler

**Docs**: `docs/RENT_REMINDERS_IMPLEMENTATION_PLAN.md`, `docs/CODE_REVIEW_RENT_REMINDERS_REWORK.md`

---

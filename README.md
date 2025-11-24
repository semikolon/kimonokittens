# Kimonokittens – Rental Management & Home Automation Platform

> **Note:** For all recent technical decisions, see [DEVELOPMENT.md](DEVELOPMENT.md).

This repo is a **production monorepo** for managing a shared rental property (kollektiv) and home automation. The system runs on a **Dell Optiplex 7010 kiosk** (hallway display) with **automated rent calculations, contract management, and real-time monitoring**.

**Core Systems:**

| Component | Purpose | Status |
|-----------|---------|--------|
| **Rent Management** | Automated rent calculation with electricity bill scraping (Vattenfall + Fortum), time-of-use pricing, quarterly projections | ✅ **Production** |
| **Contract System** | Tenant signup (`/meow`), BankID e-signing (Zigned), admin dashboard with real-time contract tracking | ✅ **Production** |
| **Rent Reminders** | SMS automation (46elks) active, payment detection (Lunchflow) re-enabling Nov 27 | ✅ **Production** (SMS) |
| **Dashboard** | Real-time kiosk display: weather, transit (SL), Strava, temperature, rent, todo, heatpump schedule | ✅ **Production** |
| `handbook/` | Live wiki & handbook with planned git-backed proposal workflow (branch-per-proposal, approval merges to master) | 🟡 **Partial** |
| `bankbuster/` | Automated Bankgirot camt.054 parser (Ruby + Vue) | ⏸️ **Legacy** |


## Development Workflow

**Process Management** (see `CLAUDE.md` for full protocol):

```bash
npm run dev          # Start all development processes (frontend + backend)
npm run dev:stop     # Stop all processes
npm run dev:restart  # Clean restart (prevents cache/stale process issues)
npm run dev:status   # Check what's running
```

**Architecture:**

```bash
├── puma_server.rb        # Ruby backend (Puma + WebSocket, port 3001)
├── dashboard/            # React frontend (Vite, port 5175)
├── handlers/             # API endpoints (30+ handlers for rent, contracts, weather, transit, etc.)
├── lib/                  # Core domain models & services (rent calculator, contract generator, etc.)
├── prisma/               # Database schema & migrations (PostgreSQL)
├── bin/                  # CLI scripts (rent_reminders, bank_sync, etc.)
├── contracts/            # Contract templates & signed PDFs
└── deployment/           # Production deployment scripts & docs
```

**Tech Stack:** Ruby 3.3.8 • PostgreSQL 18 • React 19 • Vite • Prisma • Puma • Nginx

---

## Dashboard System

The **hallway kiosk** (`dashboard/`) displays real-time data via WebSocket updates on a portrait-oriented 24" monitor. Features include:

**Widgets:**
- **Weather** - Current conditions + forecast (WeatherAPI with AQI)
- **Transit** - Live SL train/bus departures with urgency animations (Framer Motion)
- **Temperature** - Heatpump schedule visualization (16-hour bar with supply line glow + time cursor)
- **Strava** - Recent activity stats
- **Rent** - Current month's rent calculation with electricity projections
- **Todo** - Household tasks from `household_todos.md`
- **Clock** - Gradient-animated time display with Three.js aurora shader background

**Key Features:**
- **Sleep Schedule** - Adaptive brightness (0.7-1.5) + fade-out/wake transitions (configurable via `config/sleep_schedule.json`)
- **Admin View** - Tab-key access to contract management, tenant leads, signing progress (PIN-protected)
- **Auto-reload** - WebSocket-triggered refresh after GitHub webhook deployments
- **GPU-accelerated** - NVIDIA GTX 1650 with WebGL shaders + CSS animations

**Thermiq Heatpump Time Offset**: Device clock is -1 hour off. Dashboard auto-compensates in `TemperatureWidget.tsx:THERMIQ_TIME_OFFSET_HOURS`. Remove when device is corrected.

---

## Rent Management System

**Automated rent calculation** with fair distribution among active tenants, prorated stays, room adjustments, and real-time electricity cost tracking.

**Key Features:**
- **Automated Bill Scraping** - Daily cron jobs fetch Vattenfall (3am) + Fortum (4am) invoices via browser automation
- **Time-of-Use Pricing** - Peak/off-peak grid rates (53.60 vs 21.40 öre/kWh) for winter months
- **Quarterly Projections** - Growth-adjusted estimates (8.7% YoY) when drift_rakning not yet available
- **Real-time API** - `/api/rent/friendly_message` for voice assistants + WebSocket broadcast to dashboard
- **Contract Management** - Tenant signup (`/meow`), BankID e-signing (Zigned), admin dashboard with signing progress
- **Payment Automation** *(ready, not deployed)* - Bank sync (Lunchflow), SMS reminders (46elks), GPT-5-mini message composer

**Database:** PostgreSQL with Prisma (models: Tenant, RentConfig, ElectricityBill, SignedContract, BankTransaction, RentReceipt, SmsEvent)

**CLI Tools:**
```bash
bin/rent_reminders       # Check overdue payments + send SMS reminders
bin/bank_sync            # Sync bank transactions from Lunchflow API
```

For implementation details, see [**DEVELOPMENT.md**](DEVELOPMENT.md) and [**TODO.md**](TODO.md).

---

## Production Deployment

**Environment:** Dell Optiplex 7010 running Pop!_OS 22.04 with NVIDIA GTX 1650

**Services:**
- `kimonokittens-dashboard` - Puma server (port 3001) via systemd user service
- `kimonokittens-kiosk` - Chrome kiosk mode (fullscreen, GPU-accelerated)
- `kimonokittens-webhook` - GitHub webhook receiver (port 49123, auto-deploy on push)
- `nginx` - Reverse proxy + static file serving

**Automation:**
- Push to `master` → webhook → `npm ci` + `vite build` + `rsync` → browser auto-reload
- Database migrations: Manual via `npx prisma migrate deploy` (safety measure)
- Cron jobs: Electricity bill scraping (3am, 4am daily)

**Key Files:**
- `.env` - Environment variables (not committed)
- `config/sleep_schedule.json` - Display sleep/wake schedule
- `deployment/` - Deployment scripts & documentation

See [**DELL_OPTIPLEX_KIOSK_DEPLOYMENT.md**](DELL_OPTIPLEX_KIOSK_DEPLOYMENT.md) for full setup guide.

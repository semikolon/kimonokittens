# Kimonokittens – Meta Repository

> **Note:** For all recent technical decisions, see [DEVELOPMENT.md](DEVELOPMENT.md).

This repo is a **multi-project monorepo** for various home-automation and finance tools running on the Raspberry Pi at _kimonokittens.com_.

Active sub-projects:

| Path | Purpose |
|------|---------|
| `dashboard/` | Real-time home automation dashboard (React + TypeScript) |
| `handbook/` | Live wiki & handbook for the kollektiv (React + Ruby) |
| `bankbuster/`| Automated downloader & parser for Bankgirot camt.054 reports (Ruby + Vue dashboard) |
| `rent.rb`   | Core logic for the rent calculation system, integrated with the backend. |


## Development Workflow

**IMPORTANT**: Use the foolproof process management protocol documented in `CLAUDE.md`:

```bash
npm run dev          # Start all development processes (frontend + backend)
npm run dev:stop     # Stop all processes
npm run dev:restart  # Clean restart (prevents cache/stale process issues)
npm run dev:status   # Check what's running
```

Architecture:

```bash
├── bin/dev               # Development orchestration script (Overmind/Foreman)
├── puma_server.rb        # Ruby backend server (WebSocket + REST APIs)
├── dashboard/            # React frontend (Vite dev server)
├── handlers/             # API endpoints (weather, transit, temperature, etc.)
├── bankbuster/           # Bank scraper
├── handbook/             # Wiki SPA & API
└── legacy/               # Deprecated Agoo server files
```

---

## Dashboard System

The dashboard (`dashboard/`) is a React frontend that displays real-time home automation data including temperature, weather, transit, and Strava activity information.

### Known Issues & Workarounds

**Thermiq Heatpump Time Offset**: The Thermiq smart heatpump device clock is currently misconfigured by exactly -1 hour. The dashboard automatically compensates for this in `TemperatureWidget.tsx` with a fixed offset:

```typescript
const THERMIQ_TIME_OFFSET_HOURS = -1
```

This ensures the heatpump schedule visualization displays correctly relative to the device's actual operational state. Remove this offset when the device clock is corrected.

**Schedule Bar Time Cursor**: The 16-hour schedule bar features a sliding time cursor that moves from left (18% at 7am) to right (81% at 11pm) throughout the day, providing a visual sense of day progression. At night (midnight-6am), it resets to the morning view showing future heating schedules.

---

## Rent Calculator System

A Ruby system for calculating rent distribution among roommates and maintaining historical records of rent payments.

For detailed technical implementation guides, testing strategies, and recent architectural decisions, please see [**DEVELOPMENT.md**](DEVELOPMENT.md).

For a log of major accomplishments and project milestones, see [**DONE.md**](DONE.md).

> For Agoo WebSocket integration details (status code 101, con_id gotcha), see DEVELOPMENT.md.

> For handler/server stability patterns and the upcoming Git-backed proposal workflow, see [DEVELOPMENT.md](DEVELOPMENT.md).

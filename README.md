# Kimonokittens – Meta Repository

This repo is a **multi-project monorepo** for various home-automation and finance tools running on the Raspberry Pi at _kimonokittens.com_.

Active sub-projects:

| Path | Purpose |
|------|---------|
| `handbook/` | Live wiki & handbook for the kollektiv (React + Ruby Agoo) |
| `bankbuster/`| Automated downloader & parser for Bankgirot camt.054 reports (Ruby + Vue dashboard) |
| `rent.rb`   | Core logic for the rent calculation system, integrated with the `handbook` backend. |


When working in Cursor:

* Open the sub-folder you're focused on (`handbook/` or `bankbuster/`) as a **separate workspace** so the AI context stays tight.
* Each sub-project has its own README, TODO backlog and `.cursor/rules` directory.

The scripts for the rent calculation system also live at the repo root and `handlers/`. They share gems and the same Agoo server.

```bash
├── json_server.rb         # Boots Agoo, mounts sub-apps
├── handlers/              # Misc JSON endpoints (electricity, trains, rent, etc.)
├── bankbuster/            # Bank scraper
└── handbook/              # Wiki SPA & API
```

---

## Rent Calculator System

A Ruby system for calculating rent distribution among roommates and maintaining historical records of rent payments.

For detailed technical implementation guides, testing strategies, and recent architectural decisions, please see [**DEVELOPMENT.md**](DEVELOPMENT.md).

For a log of major accomplishments and project milestones, see [**DONE.md**](DONE.md).

> For Agoo WebSocket integration details (status code 101, con_id gotcha), see DEVELOPMENT.md.

# Kimonokittens – Meta Repository

This repo is a **multi-project monorepo** for various home-automation and finance tools running on the Raspberry Pi at _kimonokittens.com_.

Active sub-projects:

| Path | Purpose |
|------|---------|
| `handbook/` | Live wiki & handbook for the kollektiv (React + Ruby Agoo) |
| `bankbuster/` | Automated downloader & parser for Bankgirot camt.054 reports (Ruby + Vue dashboard) |

When working in Cursor:

* Open the sub-folder you're focused on (`handbook/` or `bankbuster/`) as a **separate workspace** so the AI context stays tight.
* Each sub-project has its own README, TODO backlog and `.cursor/rules` directory.

Legacy / utility scripts (energy stats, rent maths, misc handlers) live at the repo root and `handlers/`. They share gems and the same Agoo server, but aren't actively developed right now.

```bash
├── json_server.rb         # Boots Agoo, mounts sub-apps
├── handlers/              # Misc JSON endpoints (electricity, trains, etc.)
├── bankbuster/            # Bank scraper
└── handbook/              # Wiki SPA & API
```

For details jump into the respective sub-folder. 
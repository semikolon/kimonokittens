# Kimonokittens – Live Handbook & Wiki

A self-hosted, edit-in-place knowledge base for the Kimonokittens collective.
It combines:

* **Vue/React front-end** with Tailwind v4 & Radix primitives
* **Markdown-first authoring** backed by Git
* **Two–step review workflow** (draft → approve ×2 → merge)
* **Ruby Agoo API** that stores pages in the same repo
* **Facebook OAuth** so house-mates log in with one click
* **Postgres ledger** to surface dynamic rent & economy data
* **Obsidian-Git** for anyone who prefers a local vault

> "The goal is no-friction updates, full transparency and beautiful typography."

---

## Table of contents
1. [Why this project?](#why-this-project)
2. [High-level architecture](#high-level-architecture)
3. [Directory layout](#directory-layout)
4. [Quick start (development)](#quick-start-development)
5. [Authentication](#authentication)
6. [Content workflow](#content-workflow)
7. [Database model](#database-model)
8. [Running in production](#running-in-production)
9. [Roadmap](#roadmap)
10. [License](#license)

---

## Why this project?
* Written meeting notes & agreements live in too many places: Messenger, Google Docs, printed A4s on the fridge.
* People hesitate to edit because "what if I break it?"
* New members need a **single URL** that explains everything, from chores to rent algorithm.

We solve it with a **Git-backed wiki** that renders Markdown to a modern SPA, but still lets non-techies click ✏️ Edit, type, and submit a proposal.

---

## High-level architecture
```mermaid
flowchart TD
  subgraph Client
    A[React SPA] -- REST / WS --> B[Agoo API]
    A <-- HTML/JS/CSS -- B
  end
  subgraph Server
    B --> C[(Git repo)]
    B --> D[(Postgres)]
  end
  C <--> E[Obsidian Git]
```

Layer breakdown:

1. **Front-end (`frontend/`)**  
   • Vite + React 18 + TypeScript  
   • Tailwind v4 utilities; Radix UI for accessible primitives  
   • TipTap editor extension for in-place Markdown editing  
   • jsdiff + react-diff-viewer for word-level diffs  

2. **API (`server/agoo`)**  
   • Ruby Agoo HTTP & WebSocket server  
   • Rugged (libgit2) for writing/merging wiki files  
   • JSON API endpoints:  
     • `GET /raw/:slug.md` – raw Markdown  
     • `POST /api/propose` – create draft  
     • `PATCH /api/approve/:id` – add approval & merge when ≥2  
     • `GET /api/rent/current` – current user's ledger  

3. **Database**  
   • Postgres 16, accessed via Prisma ORM  
   • `Tenant`, `RentLedger`, `PurchasePool` tables  

4. **Auth**  
   • Next-Auth with Facebook provider → JWT session  
   • Name & avatar injected into UI ("Hej Malin 👋")  

5. **Desktop vault**  
   • Obsidian-Git in pull-only mode keeps personal notes up-to-date without pushing accidental changes.

---

## Directory layout
```
wiki/                 Approved live Markdown pages
proposals/            Drafts awaiting ≥2 approvals
frontend/             React SPA source (Vite)
server/agoo/          Ruby API (mounts into existing json_server.rb)
prisma/               Schema & migrations for Postgres
.cursor/rules/        Cursor IDE project rules (auto-attached)
```

*The legacy `json_server.rb` stays the public entry-point; it now `require_relative "server/agoo/handbook_api"` to plug in the new routes.*

---

## Quick start (development)
Prerequisites: Ruby 3.2, Node ≥20 with pnpm, and either a local Postgres service **or** Docker.

```bash
# 1. clone & install
pnpm install
bundle install

# 2. start Postgres (choose one)
#    a) system-wide service already running → skip
#    b) disposable container
docker run --name handbook-pg -e POSTGRES_PASSWORD=wiki -p5432:5432 -d postgres:16

# 3. initialise DB
cp .env.example .env          # fill in FACEBOOK_* & DATABASE_URL
pnpm prisma migrate dev

# 4. run everything
pnpm dev            # Vite + Tailwind HMR on :5173
ruby ../../json_server.rb # Run from repo root; Agoo on :6464 / :6465 (SSL)
```
Visit https://localhost:6465/wiki/handbok to test.

---

## Authentication
1. Create a Facebook App → *Meta for Developers* → obtain `APP_ID` & `APP_SECRET`.
2. Add `FACEBOOK_CLIENT_ID` and `FACEBOOK_CLIENT_SECRET` to `.env`.
3. First-time visitors click **Logga in med Facebook**; session cookie stores JWT.

---

## Content workflow
1. User reads `/wiki/stad-schema`.
2. Clicks ✏️ → TipTap opens in the same place.
3. Press **Skicka förslag** → `POST /api/propose` saves draft in `proposals/slug-123456.md` with `approvals: []` front-matter.
4. Banner appears: "Din ändring väntar på 2 godkännanden."
5. Two peers click ✓ in the side-panel → API merges file into `wiki/`, pushes commit, broadcasts WS event.
6. All open browsers hot-reload the page; Obsidian pulls next time it syncs.

---

## Database model
```prisma
model Tenant {
  id        Int     @id @default(autoincrement())
  fbId      String  @unique   // Facebook UID
  name      String
  avatarUrl String
  rents     RentLedger[]
}

model RentLedger {
  id        Int      @id @default(autoincrement())
  tenant    Tenant   @relation(fields: [tenantId], references: [id])
  tenantId  Int
  month     DateTime
  base      Decimal(10,2)
  extras    Decimal(10,2)
  total     Decimal(10,2)
}
```
`GET /api/rent/current` returns the last 12 months for the logged-in user; `<RentPanel/>` renders it inside any Markdown page via MDX.

---

## Running in production
1. Build static assets → `pnpm build` → output to `frontend/dist/`.
2. `json_server.rb` already serves static files via Agoo's `root` option.
3. Use systemd service files (`systemd/wiki.service`, `postgres.service`) with automatic restart.
4. SSL: follow existing Let's Encrypt path used by kimonokittens.com.

Optional: run Postgres via Docker Compose (`docker compose -f infra/compose.yml up -d`) to keep the rest of the server clean.

---

## Roadmap
* Diff-per-word accept/reject each hunk (à la GitHub review)
* Stripe webhook → mark rent as paid automatically
* Mobile PWA & offline cache
* Matrix / Signal bot that posts "New proposal awaiting review"
* Dark-mode & custom font pairings

---

## License
MIT for code; handbook content CC BY-SA 4.0. 
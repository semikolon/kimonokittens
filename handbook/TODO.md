# TODO – Handbook / Wiki

### Milestone 0 – Walking skeleton
- [ ] `handbook/server/agoo/handbook_api.rb` with GET /raw, POST /propose, PATCH /approve
- [ ] Vite React scaffold in `handbook/frontend/` (Tailwind + Radix)
- [ ] TipTap editor + word-diff viewer
- [ ] WebSocket broadcast on merge

### Milestone 1 – Auth & DB
- [ ] Next-Auth setup (Facebook provider) – `.env` vars + `/api/auth/*` routes
- [x] Prisma schema + first migration (moved to /prisma)
- [ ] `<RentPanel/>` component showing logged-in user's ledger

### Milestone 2 – Review flow polish
- [ ] Banner "Waiting for approvals" with avatars of approvers
- [ ] Diff per hunk accept/reject (client only)
- [ ] E-mail or Matrix push when new proposal created

### Milestone 3 – Docs & styling
- [ ] MDX support to embed React components in pages
- [ ] Tailwind theme matching Kimonokittens colours & font stack
- [ ] Dark mode toggle + prefers-color-scheme

### Milestone 4 – Deployment
- [ ] `infra/compose.yml` for Postgres + Watchtower upgrade
- [ ] systemd unit `handbook.service` to start Agoo with `bundle exec`
- [ ] CI: Vite build + rspec + prisma validate (from root)

### Stretch ideas
- [ ] Stripe webhook to auto-mark rent paid, update ledger
- [ ] Mobile PWA (service worker + offline page cache)
- [ ] Sync proposals with local Obsidian via Git hooks
- [ ] Sync /api rent calculator from Mac Mini and integrate
- [ ] Research and implement contract management for tenants, including e-signing via a BankID provider (e.g., Scrive, DocuSign).
- [ ] Plan House AI integration for querying handbook docs (See: `docs/house-ai-integration.md`)
- [ ] Implement WebSocket push for real-time page updates after merges.

### Financials & Contracts
- [x] Define Prisma schema for `Tenant` and `RentLedger` (moved to /prisma).
- [ ] Implement `<RentPanel/>` component to display data from the API.
- [ ] Research and integrate a third-party e-signing service (DocuSign, Scrive) for contracts.

### House AI Integration
- [ ] **Hardware:** Research and acquire necessary components for retrofitting Google Home units to support the Wyoming Protocol.
- [ ] **Hardware:** Flash Google Home units with custom firmware and configure `whisper-satellite`.
- [ ] **Server Setup:** Configure the Docker environment on the Dell Optiplex.
- [ ] **Server Setup:** Install and configure Whisper (STT) and Piper (TTS) Docker containers.
- [ ] **RAG Backend:** Set up a local vector database (e.g., ChromaDB).
- [ ] **RAG Backend:** Create the indexing script to process Markdown files and update the vector DB.
- [ ] **RAG Backend:** Implement the `post-commit` Git hook to trigger the indexing script automatically.
- [ ] **RAG Backend:** Build the query endpoint that takes a user question, performs the retrieval and generation steps, and returns an answer. 
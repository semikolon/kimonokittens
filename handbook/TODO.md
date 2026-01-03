# TODO – Handbook / Wiki

**Last updated**: Dec 21, 2025

### Milestone 0 – Walking skeleton ✅ COMPLETE
- [x] Backend handler with GET /pages, GET/POST /proposals, POST /approve (`handlers/handbook_handler.rb`, 388 lines)
- [x] Mounted in main puma_server.rb at `/api/handbook/*`
- [x] Vite React scaffold in `handbook/frontend/` (Tailwind + Radix)
- [x] TipTap editor + word-diff viewer (in frontend scaffold)
- [ ] WebSocket broadcast on merge (deferred - using polling for now)

### Milestone 1 – Auth & DB ✅ MOSTLY COMPLETE
- [x] Facebook OAuth implementation (`handbook/authentication_plan.md` - marked complete)
- [x] Prisma schema + migrations (moved to /prisma - shared with dashboard)
- [ ] `<RentPanel/>` component showing logged-in user's ledger

### Milestone 1.5 – AI Query System ✅ COMPLETE (Added Dec 2025)
- [x] OpenAI embeddings integration (`text-embedding-3-small`)
- [x] Pinecone vector database client
- [x] RAG query endpoint (`POST /api/handbook/query`)
- [x] Indexing script (`handbook/scripts/index_documents.rb`)
- [ ] Run indexing script to populate Pinecone index
- [ ] Post-commit hook for automatic re-indexing

### Milestone 2 – Review flow polish
- [x] Git-based proposal branches with approval tracking
- [x] Auto-merge on 2 approvals with conflict detection
- [ ] Banner "Waiting for approvals" with avatars of approvers
- [ ] Diff per hunk accept/reject (client only)
- [ ] E-mail or Matrix push when new proposal created

### Milestone 3 – Docs & styling
- [ ] MDX support to embed React components in pages
- [ ] Tailwind theme matching Kimonokittens colours & font stack
- [ ] Dark mode toggle + prefers-color-scheme

### Milestone 4 – Deployment
- [x] Backend integrated into main dashboard puma_server.rb (no separate service needed)
- [ ] `infra/compose.yml` for Postgres + Watchtower upgrade
- [ ] CI: Vite build + rspec + prisma validate (from root)

### NEW: Milestone 5 – Dashboard Integration (Dec 2025)
- [ ] Add handbook as third dashboard view (Tab cycling: public → admin → handbook)
- [ ] Create `HandbookDashboard.tsx` with AI query widget
- [ ] Quick links to key handbook pages
- [ ] Pending proposals display
- [ ] See: `docs/HANDBOOK_DASHBOARD_VIEW_PLAN.md`

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
# Kimonokittens Master Plan

This document tracks the high-level implementation plan for the Kimonokittens monorepo projects.

## Phase 1: Foundational Setup (In Progress)

- [x] **(AI)** Create this master plan `TODO.md` to track high-level progress.
- [ ] **(AI)** Solidify data structures and legal/agreement documents.
    - [ ] Update `handbook/docs/agreements.md` with co-ownership details.
    - [ ] Define initial Prisma schema (`Tenant`, `CoOwnedItem`).
- [ ] **(USER)** Locate existing rent API implementation notes from Mac Mini.
- [ ] **(BLOCKED)** Define Prisma schema for `RentLedger` and other financial models.

## Phase 2: Handbook Scaffolding

- [ ] **(AI)** Scaffold the React frontend in `handbook/frontend/`.
    - [ ] Initialize Vite project with React + TS.
    - [ ] Install and configure Tailwind, Radix UI, TipTap.
    - [ ] Create placeholder components (`WikiPage`, `EditToolbar`, etc.).
- [ ] **(BLOCKED)** Create `<RentPanel/>` component.

## Phase 3: Backend & AI Pipeline Scaffolding

- [ ] **(AI)** Scaffold the Ruby backend API endpoints (non-financial).
    - [ ] Add mock routes for handbook pages and proposals to `json_server.rb`.
- [ ] **(AI)** Implement the RAG pipeline indexing script (`handbook/scripts/index_documents.rb`).
    - [ ] Read from `/docs`.
    - [ ] Chunk text.
    - [ ] Connect to Pinecone and index documents.
- [ ] **(BLOCKED)** Implement financial API endpoints.

## Phase 4: Core Logic Implementation

- [ ] **(USER)** Set up voice assistant hardware (Dell Optiplex, Google Homes).
- [ ] Implement handbook approval workflow (proposals -> merge).
- [ ] Implement financial calculations and link `RentLedger` to UI.
- [ ] Implement live AI queries against the RAG pipeline. 
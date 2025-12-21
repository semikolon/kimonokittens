# Handbook Dashboard View Implementation Plan

**Status**: 📋 PLANNING (Dec 21, 2025)
**Priority**: High - Internal visibility for household members
**Prerequisite**: Backend already exists and is mounted

## Overview

Add the handbook as a third view in the existing dashboard SPA, accessible via Tab key cycling (public → admin → handbook). This provides internal visibility to all household members before considering public deployment.

## Current State Assessment

### What Already Exists (Backend) ✅

| Component | Location | Status |
|-----------|----------|--------|
| HandbookHandler | `handlers/handbook_handler.rb` | ✅ 388 lines, mounted in puma_server.rb |
| API Endpoints | `/api/handbook/*` | ✅ 5 endpoint groups implemented |
| AI Query (RAG) | `/api/handbook/query` | ✅ OpenAI + Pinecone integration |
| Git Collaboration | Proposals/approvals | ✅ Branch-based workflow |
| HandbookParser | `lib/handbook_parser.rb` | ✅ Section extraction |
| Indexing Script | `handbook/scripts/index_documents.rb` | ✅ Ready to run |
| Test Suite | `spec/handbook_handler_spec.rb` | ✅ Full coverage |

### What Needs Work

| Component | Status | Effort |
|-----------|--------|--------|
| Pinecone Index | 🔧 Needs population | 5 min (run script) |
| Dashboard View | 📋 New component | 2-3 hours |
| View Mode Extension | 📋 Modify hook | 30 min |
| Styling Consistency | 📋 Match existing | Included above |

## Implementation Plan

### Phase 1: Pinecone Index Population (5 minutes)

**Run the indexing script to populate the vector database:**

```bash
cd /Users/fredrikbranstrom/Projects/kimonokittens
bundle exec ruby handbook/scripts/index_documents.rb
```

**What it does:**
- Creates `kimonokittens-handbook` index in Pinecone (if not exists)
- Reads all `.md` files from `handbook/docs/`
- Chunks by paragraph (skips <50 char chunks)
- Generates embeddings via OpenAI `text-embedding-3-small`
- Upserts vectors with file/text metadata

**Prerequisites:**
- `OPENAI_API_KEY` in environment ✅ (confirmed available)
- `PINECONE_API_KEY` in environment (need to verify)
- `PINECONE_ENVIRONMENT` (defaults to `gcp-starter`)

### Phase 2: Extend View Mode System (30 minutes)

**File: `dashboard/src/hooks/useKeyboardNav.tsx`**

Current:
```typescript
type ViewMode = 'public' | 'admin'
```

Change to:
```typescript
type ViewMode = 'public' | 'admin' | 'handbook'
```

Update Tab key handler to cycle through 3 views:
```typescript
// Current: toggles public ↔ admin
// New: cycles public → admin → handbook → public
const nextMode = {
  'public': 'admin',
  'admin': 'handbook',
  'handbook': 'public'
} as const
updateViewMode(nextMode[viewMode])
```

Update URL routing:
- `/` → public
- `/admin` → admin
- `/handbook` → handbook

### Phase 3: Create HandbookDashboard View (2-3 hours)

**File: `dashboard/src/views/HandbookDashboard.tsx`**

**Layout matching existing dashboard style:**

```
┌─────────────────────────────────────────────┐
│  ClockWidget (same as other views)          │
├─────────────────────────────────────────────┤
│  ┌─────────────────────────────────────────┐│
│  │ AI Query Widget                         ││
│  │ ┌─────────────────────────────────────┐ ││
│  │ │ "Fråga handboken..."               │ ││
│  │ └─────────────────────────────────────┘ ││
│  │ [AI response area]                      ││
│  └─────────────────────────────────────────┘│
├─────────────────────────────────────────────┤
│  ┌─────────────────────────────────────────┐│
│  │ Quick Links                             ││
│  │ • Husregler • Avtal • Städschema       ││
│  └─────────────────────────────────────────┘│
├─────────────────────────────────────────────┤
│  ┌─────────────────────────────────────────┐│
│  │ Pending Proposals (if any)              ││
│  │ [List with approve buttons]             ││
│  └─────────────────────────────────────────┘│
└─────────────────────────────────────────────┘
```

**Key Components:**

1. **AI Query Widget** (primary feature)
   - Input field for natural language questions
   - Calls `POST /api/handbook/query`
   - Displays grounded answers from handbook content
   - Swedish UI labels ("Fråga handboken", "Svar:")

2. **Quick Links Section**
   - Direct links to key handbook pages
   - Uses existing `GET /api/handbook/pages/{slug}` endpoint
   - Styled as cards matching dashboard aesthetic

3. **Pending Proposals** (if logged in)
   - Shows proposals needing approval
   - Uses `GET /api/handbook/proposals`
   - Approve buttons for authenticated users

**Styling Requirements:**
- Same purple/slate color scheme
- Same Widget component wrapper
- Same gradient background
- Same font stack (Horsemen headers)
- Cyan for success states (not green)

### Phase 4: Update App.tsx (30 minutes)

Add conditional render for handbook view:

```typescript
if (viewMode === 'handbook') {
  return (
    <div className="min-h-screen...">
      <FadeOverlay />
      {/* Same gradient blobs */}
      <div className="w-full px-4 py-12...">
        <Widget accent={true} allowOverflow={true}>
          <ClockWidget isHandbook={true} />
        </Widget>
        <HandbookDashboard />
      </div>
    </div>
  )
}
```

### Phase 5: Document Updates (30 minutes)

**Update these files:**

1. **`handbook/TODO.md`** - Mark completed items, add new milestones
2. **`dashboard/CLAUDE.md`** - Add handbook view documentation
3. **`CLAUDE.md`** (root) - Update deployment section with handbook status

## Pinecone Details

**Index Configuration:**
- Name: `kimonokittens-handbook`
- Dimension: 1536 (OpenAI text-embedding-3-small)
- Metric: cosine similarity
- Environment: `gcp-starter` (or configured via `PINECONE_ENVIRONMENT`)

**Content Indexed:**
- `handbook/docs/agreements.md` - Rental agreements, house rules
- `handbook/docs/house-rules.md` - Community guidelines
- `handbook/docs/household_todos.md` - Shared tasks
- `handbook/docs/house-ai-integration.md` - AI vision doc
- Any additional `.md` files in `handbook/docs/`

**Query Flow:**
1. User types question in UI
2. Frontend POSTs to `/api/handbook/query`
3. HandbookHandler embeds question via OpenAI
4. Queries Pinecone for top-5 similar chunks
5. Constructs prompt with retrieved context
6. GPT-4o-mini generates grounded answer
7. Returns answer to frontend

## Future Considerations

### Authentication (Deferred)
- Facebook OAuth already implemented in handbook frontend
- Could integrate with dashboard's AdminAuthContext
- For now: read-only access for all, proposals require auth

### Public Deployment (Later Priority)
- Requires nginx config changes
- Add `/handbook` location block
- Consider rate limiting for AI queries (cost control)

### Voice Interface (Long-term)
- Wyoming Protocol satellite mics
- Whisper STT + Piper TTS
- Docker containers on Dell Optiplex
- See `handbook/docs/house-ai-integration.md`

## Success Criteria

1. ✅ Tab cycles through 3 views smoothly
2. ✅ Handbook view matches dashboard styling
3. ✅ AI query returns relevant answers from handbook content
4. ✅ Quick links navigate to handbook pages
5. ✅ URL routing works (`/handbook` loads handbook view)
6. ✅ Production deployment via existing webhook

## Effort Estimate

| Phase | Effort | Dependencies |
|-------|--------|--------------|
| 1. Pinecone population | 5 min | API keys |
| 2. View mode extension | 30 min | None |
| 3. HandbookDashboard | 2-3 hours | Phase 2 |
| 4. App.tsx integration | 30 min | Phase 3 |
| 5. Documentation | 30 min | Phase 4 |
| **Total** | **~4 hours** | |

## Related Documentation

- `handbook/README.md` - Architecture overview
- `handbook/CLAUDE.md` - Prisma schema migration notes
- `handbook/TODO.md` - Feature roadmap
- `handbook/docs/house-ai-integration.md` - Voice AI vision
- `handbook/authentication_plan.md` - OAuth implementation (complete)
- `handlers/handbook_handler.rb` - Backend implementation
- `spec/handbook_handler_spec.rb` - Test coverage

---

**Created**: Dec 21, 2025
**Author**: Claude + Fredrik

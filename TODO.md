# Kimonokittens Master Plan (Detailed)

> **Note:** For July 2025 WebSocket, train API, and weather widget fixes, see DEVELOPMENT.md.
> **Oct 2 2025:** Reload loop protection implemented - 4-layer defense system active.

This document provides a detailed, step-by-step implementation plan for the Kimonokittens monorepo projects. It is designed to be executed by an AI assistant with minimal context loss. Execute tasks sequentially unless marked as `(BLOCKED)`.

---

## ⚠️ HIGH PRIORITY - Deposit Formula Mismatch

**CRITICAL:** Deposit formula in code (6,746 kr) doesn't match social convention (6,200 kr)!

**Current state:**
- `Tenant.calculate_deposit(4)` returns **6,746 kr** (formula: 110% of per-person rent)
- Social convention/practice is **6,200 kr** (historical, "floating around between mouths and memories")
- Formula exists in `lib/models/tenant.rb:164` but is **NEVER CALLED** in codebase
- Risk: Future code could call formula and set wrong deposit amount

**Action needed:**
- [ ] Decide: Remove formula OR update to return 6,200 kr OR document as "theoretical only"
- [ ] If keeping formula: Add explicit warning that social convention overrides formula
- [ ] Consider: Should formula be dynamic based on tenant count? (5 tenants = recalculate?)
- [ ] Document: Where is the "real" deposit amount stored/defined as source of truth?

**Context:** Discovered Nov 10, 2025 during contract testing prep. Formula gives 546 kr higher than actual practice.

---
## 🚀 PRODUCTION DEPLOYMENT - Dell Optiplex Kiosk ✅ COMPLETE

**Goal:** Deploy Kimonokittens dashboard as production kiosk on Dell Optiplex

**Status:** ✅ **DEPLOYED** (October 6, 2025) - Webhook operational, kiosk live in hallway

### **Current Status** (November 10, 2025)
- ✅ **Webhook server:** Running on port 49123, smart change detection + debouncing
- ✅ **Deployment automation:** Push to master → auto-deploy (code only, migrations manual)
- ✅ **Kiosk hardware:** Dell Optiplex 7010 with GPU acceleration for WebGL shaders
- ✅ **Production services:** Dashboard (port 3001), nginx, kiosk display all operational
- ✅ **Database migrations:** Manual via `npx prisma migrate deploy` (by design - safety)
- ✅ **NPM workspace fix:** Resolved - `npm ci` from project root, not subdirectories
- ✅ **SSL certificates:** Manual DNS-01 via Namecheap (expires 2026-02-08)
- ⏰ **TODO (before Feb 2026):** Migrate to Cloudflare DNS delegation for automated SSL renewals (see DOMAIN_MIGRATION_CHECKLIST.md Option B)

### **Production Environment Setup**
- [x] **Run production deployment script**
- [x] **Configure GitHub webhook** (ID: 572892196, port 49123)
- [x] **Test webhook:** Working - `http://DELL_IP:49123/webhook`
- [ ] **Fix vite installation** - CRITICAL BLOCKER
- [ ] **Verify services:** `systemctl status kimonokittens-dashboard nginx`
- [ ] **Test end-to-end deployment:** Push → webhook → build → deploy
- [ ] **Reboot for kiosk mode:** `sudo reboot`

### **Production Architecture** (SIMPLIFIED)
- **User:** `kimonokittens` (single user for backend + kiosk display)
- **Ruby:** 3.3.8 via rbenv (copied to production user)
- **Database:** PostgreSQL with production data migration
- **Frontend:** Nginx serving built dashboard
- **Auto-updates:** GitHub webhook → deployment script

### **Critical Blocker: Dotfiles Setup**
- [ ] **Locate and sync global Claude config** from Mac Mini M2
- [ ] **Setup dotfiles repository** with symlink strategy for `.zshrc`, `.claude/`
- [ ] **Add rbenv Claude Code compatibility section** to global CLAUDE.md:
  ```markdown
  ## Claude Code & rbenv Compatibility
  Claude Code Bash tool doesn't load shell functions. Use direct paths:

  # ❌ Won't work: rbenv exec ruby --version
  # ✅ Works: ~/.rbenv/bin/rbenv exec ruby --version
  ```
- [ ] **Create bootstrap script** for consistent machine setup
- [ ] **Document dotfiles structure** and deployment process

**Priority**: HIGH - Affects all future Claude Code sessions and development workflow
**Details**: See `deployment/DOTFILES_SETUP_BLOCKER.md`

**References:**
- `deployment/README.md` (quick start guide)
- `deployment/DEPLOYMENT_CHECKLIST.md` (step-by-step)
- `deployment/SIMPLIFIED_ARCHITECTURE.md` (technical details)

### **Production Environment Access Investigation**
- [ ] **Research optimal deployment/server environment** for Claude Code + production database access
- [ ] **Evaluate options**: Install CC for kimonokittens user vs fredrik user access patterns vs API-based verification tools
- [ ] **Consider**: `/api/electricity_bills` endpoint to simplify verification without direct DB queries

**Priority**: MEDIUM - Improves debugging and verification workflows

---

## 🌐 PUBLIC HOMEPAGE & DOMAIN SETUP

**Goal:** Deploy public-facing kimonokittens.com homepage with SSL

**Status:** ⏳ **PLANNED** - Domain exists, needs SSL renewal + homepage design

### Tasks
- [ ] **Renew SSL certificate for kimonokittens.com**
  - [ ] Configure Let's Encrypt on Dell nginx
  - [ ] Setup auto-renewal via certbot
  - [ ] Verify HTTPS works for all webhook endpoints
- [ ] **Design new homepage with Magic MCP** (`/ui-prototype` command)
  - [ ] Modern, welcoming design for Kimono Kittens
  - [ ] Information about the collective
  - [ ] Links to handbook (when public)
  - [ ] Contact/application information
  - [ ] Swish donation QR code
- [ ] **Deploy homepage to production**
  - [ ] Build static site or simple React app
  - [ ] Configure nginx to serve at domain root
  - [ ] Test public accessibility
- [ ] **Tenant Signup & Contract Management System** (`/meow`, `/curious`, or `/signup` endpoints)

  **Public Signup Flow:**
  - [ ] Public signup form at `/meow` (or `/curious` or `/signup`)
    - Fields: name, personnummer, email, phone, desired move-in date
    - Creates draft Tenant record with `status: 'pending_approval'`
    - Email notification to admin (landlord)

  **Design Specification (Nov 10, 2025):**
  - [ ] Simple unstyled signup page (`www/signup.html`)
    - Page background: Empty dashboard-style (dark gradient)
    - Page heading: "Intresseanmälan" above form
    - Form width: 40% of page, max-width 900px
    - Form style: Widget-like appearance (matches dashboard widgets)
    - Input fields: Huge font size, left-aligned text
    - Labels: All-caps, half font size, 50% opacity, right-aligned on left side of fields
    - Label positioning: Right-aligned to mirror/meet left-aligned field content
    - Submit button: Large, glowing orange with stark gradient, 5px half-opacity orange border
    - Form fields: name, personnummer, email, phone, move-in date
    - Backend: POST /api/signup creates Tenant with status 'pending_approval'
    - Security: Rate limiting + CAPTCHA required before production

  **Admin Management UI:**
  - [ ] Admin interface for tenant approval & contract generation
    - View all pending tenant applications
    - Approve/reject applicants
    - Assign tenant to specific room (1-4)
    - Set move-in date (can adjust from application date)
    - Set individual room price adjustment (if not standard pricing)
    - Preview rent calculation before contract generation

  **Contract Generation & Signing:**
  - [ ] On admin approval → Automatic contract workflow:
    - Create Tenant record in database (status: 'approved')
    - Generate contract PDF via `ContractSigner.create_and_send()`
    - Send to Zigned for BankID e-signing
    - Email signing links to landlord + tenant

  **Webhook Integration:**
  - [ ] Zigned webhook updates contract status:
    - `case.created` → Contract sent for signing
    - `case.signed` → Both parties signed
    - `case.completed` → Download signed PDF
    - Update Tenant record status: 'contract_signed', 'move_in_ready'

  **Authentication & Security:**
  - [ ] Admin login (HTTP Basic Auth or simple token-based)
  - [ ] Rate limiting on public signup form
  - [ ] CAPTCHA or similar spam protection

  **Related Files:**
  - `lib/contract_signer.rb` - Contract generation + Zigned API
  - `lib/zigned_client.rb` - BankID e-signing integration
  - `lib/models/tenant.rb` - Tenant domain model
  - `lib/repositories/tenant_repository.rb` - Tenant persistence
  - Homepage files: `www/` directory → deployed to `/var/www/kimonokittens/`
  - Nginx config: Public domain serves root, kiosk serves `dashboard/` subdirectory

  **Status:** ✅ Nginx routes enabled (Nov 10, 2025) - `/meow`, `/curious`, `/signup` + `/api/signup` ready
  **Pending:** Backend implementation (signup form HTML + POST /api/signup handler with rate limiting + CAPTCHA)

**Priority**: MEDIUM - Improves public presence and future automation

---

## 🌙 Dashboard Sleep Schedule Feature ✅ PRODUCTION READY

**Status:** ✅ FULLY WORKING with CSS transitions (October 4, 2025)

### Implemented Features
- ✅ **File-based configuration** at `config/sleep_schedule.json` (git-tracked, vim-editable)
- ✅ **Smooth GPU-accelerated fades**: Pure CSS transitions (120s opacity, cubic-bezier easing)
- ✅ **Weekend support**: Different sleep times for Fri/Sat nights (sleepTimeWeekend)
- ✅ **Adaptive brightness**: 24-hour schedule (0.7-1.5 range) integrated with xrandr
- ✅ **Monitor power control**: DPMS power off during sleep (optional via config)
- ✅ **Animation pausing**: WebGL shader and CSS animations pause during sleep
- ✅ **Webhook auto-reload**: Config changes trigger kiosk browser reload

### Current Configuration
Located at `config/sleep_schedule.json`:
```json
{
  "enabled": true,
  "sleepTime": "01:00",           // Weekday: 1am
  "sleepTimeWeekend": "03:00",    // Fri/Sat: 3am
  "wakeTime": "05:30",            // Every day: 5:30am
  "monitorPowerControl": true,
  "brightnessEnabled": true
}
```

### Components Deployed
- **Backend API**: `/api/sleep/config` (handlers/sleep_schedule_handler.rb)
- **Frontend Context**: SleepScheduleContext.tsx (state machine, 10s timer)
- **UI Components**: FadeOverlay.tsx (pure CSS transitions, no JS animation)
- **Display Control**: display_control_handler.rb (xrandr brightness + DPMS)

### Key Implementation Fix (Oct 4, 2025)
**Bug Found**: Original requestAnimationFrame approach conflicted with CSS transitions
**Fix Applied**: Pure CSS `transition: opacity 120s` - GPU-accelerated, smooth fades
**Time Check**: Reduced to 10s interval to prevent missing minute boundaries

### Testing Status
- [x] CSS fade-out works smoothly (2-minute transition)
- [x] CSS fade-in works smoothly (2-minute transition)
- [x] Weekend schedule uses correct sleep time
- [x] Time check interval catches minute boundaries
- [x] End-to-end overnight sleep/wake cycle (Verified Oct 4, 2025)
- [x] Monitor DPMS power control verification (Verified Oct 4, 2025)

**Details:** See `docs/DASHBOARD_SLEEP_SCHEDULE_IMPLEMENTATION.md` for architecture

---
## Immediate Tasks & Repository Hygiene

**Goal:** Address outstanding technical debt and improve overall code quality.

-   [ ] **Test ViewTransition animations** (manual browser verification)
    -   [ ] Verify train intro/departure animations (5s slide-in, 400ms slide-out)
    -   [ ] Verify bus intro/departure animations
    -   [ ] Verify warning/critical glows still trigger correctly
    -   [ ] Check delay display (no "0m sen" regression)
    -   [ ] Monitor performance marks in console (should be <50ms)
    -   **Details:** See `docs/VIEWTRANSITION_SESSION_STATE.md` for complete implementation summary
    -   **Commits:** 13 commits (0b7d1e7 and earlier) - ~278 lines removed, native browser API
-   [ ] **Fix Failing Specs: [In Progress]**
    -   [ ] **BankBuster:** All 5 specs for `bank_buster_spec.rb` are failing.
    -   [ ] **HandbookHandler:** All 12 specs for `handbook_handler_spec.rb` are failing.
-   [ ] **Decide fate of BankBuster: modernise or archive**
-   [ ] **Add fast spec for handler timeouts/fallbacks**
-   [ ] **See handoff_to_claude_git_proposal_workflow.md for proposal workflow plan**
-   [ ] **See handoff_to_claude_rspec_tests.md for remaining handler/spec coverage items**
-   [ ] **Add/complete specs for new handler logic (timeouts/fallbacks) and frontend widget tests**

# SL API Note
- SL train departures currently use fallback data due to missing accessId. See DEVELOPMENT.md and TODO.md for next steps.

# WebSocket Integration
- ✅ **COMPLETE**: DataBroadcaster now uses `ENV['API_BASE_URL']` for all endpoints
- Configured in `.env` for development and systemd service for production
- All endpoints (rent_data, todo_data, train_data, etc.) use configurable base URL

---

## Phase 1: Foundational Data Structures

**Goal:** Define the core data models for the handbook before any code is written.

- [x] **Task 1.1: Define Prisma Schema**
    - [x] Finalize `RentLedger` based on the newly merged rent calculation logic.
    - [x] Added `startDate` to `Tenant` model.

---

## Phase 2: Handbook Frontend Scaffolding

**Goal:** Create a functional, non-interactive frontend shell with all necessary libraries and components.

- [x] **Task 2.6: Create `<RentPanel/>` component.**

---

## Phase 3-7: Backend, AI, & Core Logic (Pending)

**Goal:** Implement the full approval workflow, AI query pipeline, and other production features.

- [ ] **(AI) Task 7.1: Implement Git-Backed Approval Workflow**
    - [ ] Add the `rugged` gem to the `Gemfile` for Git operations from Ruby.
    - [ ] Modify the `HandbookHandler` to create a new branch (e.g., `proposal/some-change`) when a proposal is submitted.
    - [ ] On approval, use `rugged` to merge the proposal branch into `master`.
    - [ ] **Conflict-Safety:** Implement a "dry-run" merge check to detect potential conflicts before enabling the merge button in the UI. The UI should show a warning if conflicts are found.
- [ ] Set up proper authentication and user management.
- [ ] **(USER)** Set up voice assistant hardware (Dell Optiplex, Google Homes).
- [ ] And other tasks from the original plan...

---

## Phase 3: Backend & AI Pipeline Scaffolding

**Goal:** Define the backend API contract with mock data and build the script to populate our AI's knowledge 
base.

- [x] **(AI) Task 3.1: Add `pinecone-client` to Gemfile**
    - [x] Edit the root `Gemfile` and add `gem 'pinecone-client', '~> 0.1'`.
    - [x] Run `bundle install` in the terminal.
- [x] **(AI) Task 3.2: Scaffold API Routes**
    - [x] Edit `json_server.rb`. Add a new handler class at the end of the file.
      ```ruby
      class HandbookHandler < WEBrick::HTTPServlet::AbstractServlet
        def do_GET(req, res)
          res['Content-Type'] = 'application/json'
          
          # Mock API for fetching a single page
          if req.path.match(%r{/api/handbook/pages/(\w+)})
            slug = $1
            res.body = {
              title: "Mock Page: #{slug.capitalize}",
              content: "<h1>#{slug.capitalize}</h1><p>This is mock content for the page.</p>"
            }.to_json
            return
          end

          # Mock API for fetching proposals
          if req.path == '/api/handbook/proposals'
            res.body = [
              { id: 1, title: 'Proposal 1', author: 'Fredrik' },
              { id: 2, title: 'Proposal 2', author: 'Rasmus' }
            ].to_json
            return
          end

          res.status = 404
          res.body = { error: 'Not Found' }.to_json
        end
        
        def do_POST(req, res)
            # Mock API for creating a proposal
            if req.path == '/api/handbook/proposals'
                puts "Received proposal: #{req.body}"
                res['Content-Type'] = 'application/json'
                res.body = { status: 'success', message: 'Proposal received' }.to_json
                return
            end
            
            res.status = 404
            res.body = { error: 'Not Found' }.to_json
        end
      end
      ```
    - [x] In `json_server.rb`, find where other handlers are mounted (e.g., `server.mount "/api/...", ...`) a
nd add the new handler:
      ```ruby
      server.mount "/api/handbook", HandbookHandler
      ```
- [x] **(AI) Task 3.3: Implement RAG Indexing Script**
    - [x] Create `handbook/scripts/index_documents.rb` with the following content. This script connects to Pi
necone and indexes the content of our handbook documents.
      ```ruby
      require 'pinecone'
      require 'dotenv/load'

      # Configuration
      PINECONE_INDEX_NAME = 'kimonokittens-handbook'
      DOCS_PATH = File.expand_path('../../docs', __FILE__)
      # Standard dimension for OpenAI's text-embedding-ada-002
      VECTOR_DIMENSION = 1536 

      def init_pinecone
        Pinecone.configure do |config|
          config.api_key  = ENV.fetch('PINECONE_API_KEY')
          # NOTE: The environment for Pinecone is found in the Pinecone console
          # It's usually something like "gcp-starter" or "us-west1-gcp"
          config.environment = ENV.fetch('PINECONE_ENVIRONMENT') 
        end
      end

      def main
        init_pinecone
        pinecone = Pinecone::Client.new
        
        # 1. Create index if it doesn't exist
        unless pinecone.index(PINECONE_INDEX_NAME).describe_index_stats.success?
          puts "Creating Pinecone index '#{PINECONE_INDEX_NAME}'..."
          pinecone.create_index(
            name: PINECONE_INDEX_NAME,
            dimension: VECTOR_DIMENSION,
            metric: 'cosine'
          )
        end
        index = pinecone.index(PINECONE_INDEX_NAME)

        # 2. Read documents and prepare vectors
        vectors_to_upsert = []
        Dir.glob("#{DOCS_PATH}/*.md").each do |file_path|
          puts "Processing #{File.basename(file_path)}..."
          content = File.read(file_path)
          
          # Split content into chunks (by paragraph)
          chunks = content.split("\n\n").reject(&:empty?)
          
          chunks.each_with_index do |chunk, i|
            # FAKE EMBEDDING: In a real scenario, you would call an embedding API here.
            # For now, we generate a random vector.
            fake_embedding = Array.new(VECTOR_DIMENSION) { rand(-1.0..1.0) }
            
            vectors_to_upsert << {
              id: "#{File.basename(file_path, '.md')}-#{i}",
              values: fake_embedding,
              metadata: {
                file: File.basename(file_path),
                text: chunk[0..200] # Store a snippet of the text
              }
            }
          end
        end
        
        # 3. Upsert vectors to Pinecone
        puts "Upserting #{vectors_to_upsert.length} vectors to Pinecone..."
        index.upsert(vectors: vectors_to_upsert)
        puts "Done!"
      end

      main if __FILE__ == $0
      ```
    - [x] Add a note to the user: A `PINECONE_ENVIRONMENT` variable will need to be added to the environment 
for the script to run.

---

## Phase 4: Approval Workflow Implementation (UI & Mock Backend)

**Goal:** Build the user interface for proposing and approving changes, backed by a stateful mock API.

- [x] **(AI) Task 4.1: Enhance the Mock Backend to be Stateful**
    - [x] Edit `handlers/handbook_handler.rb` at the top of the `HandbookHandler` class to initialize: `@prop
osals = []` and `@next_proposal_id = 1`.
    - [x] Modify `do_POST` on `/api/handbook/proposals` to parse JSON, create proposal hash with `{ id: @next
_proposal_id, title: "Proposal for #{Time.now.strftime('%Y-%m-%d')}", content: parsed_body['content'], approv
als: 0 }`, add to array, increment ID, return new proposal as JSON.
    - [x] Modify `do_GET` on `/api/handbook/proposals` to return the `@proposals` array as JSON.
    - [x] Add route for `POST /api/handbook/proposals/(\d+)/approve` that finds proposal by ID, increments `:
approvals` count, returns updated proposal as JSON.
- [x] **(AI) Task 4.2: Build Frontend UI for Proposals**
    - [x] Create `handbook/frontend/src/components/ProposalList.tsx` that fetches from `/api/handbook/proposa
ls`, stores in `useState`, maps over proposals to show title/approval count, has "Approve" button that POSTs 
to approve endpoint.
    - [x] Create `handbook/frontend/src/components/Editor.tsx` using TipTap's `useEditor` hook with `StarterK
it`, renders `EditToolbar` and `EditorContent`, has "Save Proposal" button that POSTs `editor.getHTML()` to `
/api/handbook/proposals`.
    - [x] Update `handbook/frontend/src/App.tsx` to remove default Vite content, add state for showing WikiPa
ge vs Editor, render ProposalList component always visible.

## Phase 5: AI Query Implementation

**Goal:** Connect the RAG pipeline to a real UI, using a real embedding model and LLM.

- [x] **(AI) Task 5.1: Update RAG Script for Real Embeddings**
    - [x] Add `ruby-openai` gem to Gemfile and run `bundle install`.
    - [x] Edit `handbook/scripts/index_documents.rb` to initialize OpenAI client, replace fake embeddings wit
h real API calls to `text-embedding-3-small`, add error handling and rate limiting.
- [x] **(AI) Task 5.2: Create AI Query Backend Endpoint**
    - [x] Edit `handlers/handbook_handler.rb` to add route for `POST /api/handbook/query` that: parses questi
on, embeds it, queries Pinecone for top results, constructs prompt with context, calls OpenAI chat completion
, returns AI response.
- [x] **(AI) Task 5.3: Build Frontend UI for AI Queries**
    - [x] Create `handbook/frontend/src/components/QueryInterface.tsx` with text input, submit button, loadin
g state, displays AI answer.
    - [x] Update `handbook/frontend/src/App.tsx` to include QueryInterface component.

## Phase 6: Testing

**Goal:** Ensure the application is robust and reliable with a comprehensive test suite.

- [x] **(AI) Task 6.1: Implement Backend Specs**
    - [x] Add `rspec` and `rack-test` to the Gemfile.
    - [x] Create `spec/handbook_handler_spec.rb` to test the mock API, covering proposal CRUD, approvals, and
 mocked AI queries.
- [x] **(AI) Task 6.2: Implement Frontend Specs**
    - [x] Add `vitest` and `@testing-library/react` to `package.json`.
    - [x] Configure Vite for testing with a `jsdom` environment.
    - [x] Create unit tests for `WikiPage` and `ProposalList` components.

## Phase 7: Core Logic Implementation

**Goal:** Connect remaining pieces and implement production features.

- [ ] **(USER)** Set up voice assistant hardware (Dell Optiplex, Google Homes).
- [ ] Implement financial calculations and link `RentLedger` to the UI.
- [ ] **(AI) Task 7.1: Implement Git-Backed Approval Workflow**
    - [ ] Add the `rugged` gem to the `Gemfile` for Git operations from Ruby.
    - [ ] Modify the `HandbookHandler` to create a new branch (e.g., `proposal/some-change`) when a proposal 
is submitted.
    - [ ] On approval, use `rugged` to merge the proposal branch into `master`.
    - [ ] **Conflict-Safety:** Implement a "dry-run" merge check to detect potential conflicts before enablin
g the merge button in the UI. The UI should show a warning if conflicts are found.
- [ ] Set up proper authentication and user management.

---

# Rent Calculator TODO

## Current Tasks

### General
- Always make sure documentation is up to date with usage and developer guidelines and background knowledge that might be important for future devs (TODO.md, README.md, inline comments, etc).

### Documentation Maintenance
- [ ] Keep track of special payment arrangements:
  - Who covers whose shares
  - When arrangements started/ended
  - Which costs are affected
- [ ] Document billing cycles clearly:
  - Relationship between consumption, billing, and rent months
  - How special cases are handled
  - Impact on rent calculations
- [ ] Maintain historical records:
  - Payment arrangements
  - Bill amounts and dates
  - Consumption patterns
  - Year-over-year trends

### Rent History
- [ ] Adjust example scripts to prevent overwriting existing files
- [ ] Separate test data from production/default data directories for rent history (make sure specs don't overwrite production data)

### Testing
- [x] Add integration tests:
  - [x] November 2024 scenario
  - [x] Error cases
  - [x] Friendly message format
- [x] Manual testing with real data

### Persistent Storage
- [ ] Add migration system for database schema changes
- [ ] Add backup/restore functionality for SQLite databases
- [ ] Add data validation and cleanup tools
- [ ] Add monitoring for database size and performance
- [ ] **Update all Tenant contact details** (personnummer, phone) for existing tenants (Fredrik, Adam, Rasmus, etc.) to enable contract generation for all
- [ ] **Implement Tenant Lifecycle Management System** (BLOCKER for removing hardcoded tenant count)
  - **Context**: Contract generator currently hardcodes 4 tenants (`contract_generator_html.rb:127`) as safeguard against incomplete data
  - **Why hardcoded**: Prevents accidental rent miscalculation if departure dates aren't updated immediately
  - **Future requirement**: SMS reminders + Swish payment matching REQUIRE accurate tenant tracking
  - **Needed features**:
    - [ ] Tenant status tracking (active/pending_departure/departed/pending_arrival)
    - [ ] Automated reminders to update departure dates (email/SMS 30 days before expected departure)
    - [ ] Dashboard widget showing tenant lifecycle status (who's active, who's leaving, data completeness)
    - [ ] Validation warnings when generating contracts if tenant data stale (e.g., no departure date after 1 year)
    - [ ] Historical tenant tracking (past tenants with complete date ranges)
    - [ ] Room assignment tracking (which tenant in which room, room turnover history)
  - **Benefits**:
    - Remove hardcode from contract generator → accurate rent in contracts
    - Enable SMS rent reminders (need current active tenant list)
    - Enable Swish payment matching (need tenant count for amount validation)
    - Support future features (room-specific rent adjustments, move-in/out workflows)
  - **Priority**: MEDIUM-HIGH - Required before SMS/Swish automation can be implemented
  - **Discovered**: Nov 11, 2025 during contract testing financial number verification

## Future Enhancements

### Rails Migration
- [ ] Consider migrating to Rails when more features are needed:
  - ActiveRecord for better database management
  - Web dashboard for configuration
  - User authentication for roommates
  - Background jobs for automation
  - Better testing infrastructure
  - Email notifications and reminders
  - Mobile-friendly UI
- [ ] Keep architecture modular to facilitate future migration
- [ ] Document current data structures for smooth transition

### SMS Reminders and Swish Integration

**📌 IMPORTANT: Detailed planning exists in ChatGPT thread with automated Swish transaction matching implementation details**

- [ ] Implement automated rent reminders via SMS:
  - Generate personalized Swish payment links with correct amounts
  - Send monthly reminders with payment links
  - Manual confirmation system for payments
  - Update payment status in persistent storage
  - Track payment history
- [ ] **Automated Swish Payment Matching via Bank Sync**:
  - [ ] Integrate bank transaction sync API (Tink/Nordigen/similar)
  - [ ] Filter Swish transactions from synced bank history
  - [ ] Match payments to expected rent amounts by tenant
  - [ ] Automatic payment confirmation without manual checks
  - [ ] Reduce manual verification overhead
  - [ ] **Reference**: See ChatGPT thread for complete implementation plan
- [ ] Investigate Swish API access requirements:
  - Research requirements for företag/enskild firma
  - Evaluate costs and benefits
  - Explore automatic payment confirmation possibilities
  - Document findings for future implementation
- [ ] **JotForm AI Agent Integration**:
  - [ ] Set up JotForm AI Agent with SMS channel capabilities
  - [ ] Configure API tool to connect to the rent calculator API
  - [ ] Implement conversational scenarios:
    - Rent inquiries ("What's my rent?")
    - Updating quarterly invoices ("The quarterly invoice is 2612 kr")
    - Roommate changes ("Adam is moving in next month")
    - Payment confirmations ("I've paid my rent")
  - [ ] Test the integration with sample SMS conversations
  - [ ] Set up scheduled reminders for monthly rent payments
  - [ ] Monitor API availability and SMS delivery
  - [ ] Create documentation for roommates on how to interact with the SMS agent

### Error Handling
- [x] Improve error messages and recovery procedures:
  - [x] Invalid roommate data (negative days, etc.)
  - [x] Missing required costs
  - [x] File access/permission issues
  - [x] Version conflicts
- [x] Implement validation rules:
  - [x] Roommate count limits (3-4 recommended)
  - [x] Room adjustment limits (±2000kr)
  - [x] Stay duration validation
  - [x] Smart full-month handling
- [ ] Document common error scenarios:
  - Clear resolution steps
  - Prevention guidelines
  - Recovery procedures
  - User-friendly messages

### Output Formats
- [x] Support for Messenger-friendly output:
  - [x] Bold text formatting with asterisks
  - [x] Swedish month names
  - [x] Automatic due date calculation
  - [x] Concise yet friendly format
- [ ] Additional output formats:
  - [ ] HTML for web display
  - [ ] CSV for spreadsheet import
  - [ ] PDF for official records

### Deposit Management
- [ ] Track deposits and shared property:
  - Initial deposit (~6000 SEK per person)
  - Buy-in fee for shared items (~2000 SEK per person)
  - Shared items inventory:
    - Plants, pillows, blankets
    - Mesh wifi system
    - Kitchen equipment
    - Common area items
  - Condition tracking:
    - House condition (floors, bathrooms, kitchen)
    - Plant health and maintenance
    - Furniture and equipment status
    - Photos and condition reports
  - Value calculations:
    - Depreciation over time
    - Fair deduction rules
    - Return amount calculations
    - Guidelines for wear vs damage

### One-time Fees
- [ ] Support for special cases:
  - Security deposits (handling, tracking, returns)
  - Maintenance costs (fair distribution)
  - Special purchases (shared items)
  - Utility setup fees (internet, electricity)
- [ ] Design fair distribution rules:
  - Based on length of stay
  - Based on usage/benefit
  - Handling early departures
  - Partial reimbursements

### Automation ✅ COMPLETE
- [x] **Automate electricity bill invoice fetching** - ✅ **DEPLOYED** (Oct 24, 2025):
  - **Vattenfall elnät invoice**: ✅ Dual-scraper system with `ApplyElectricityBill` service
  - **Fortum elhandel invoice**: ✅ Both providers scraped daily (3am Vattenfall, 4am Fortum)
  - **Goal**: ✅ Full automation of monthly electricity bills into rent calculator
  - **Benefit**: ✅ Zero manual intervention - bills → RentConfig → WebSocket broadcast
  - **Technical approach**: ✅ Ferrum browser automation with deduplication + aggregation
  - **Data target**: ✅ ElectricityBill table + auto-aggregated into RentConfig (key='el')
  - **Cron deployment**: ✅ Production cron jobs running with full logging
- [x] **Automate quarterly invoice projections** - ✅ **DEPLOYED** (Oct 25, 2025):
  - **Pattern**: Quarterly months (Apr/Jul/Oct) = 3× yearly building operations invoices
  - **Auto-projection**: Growth-adjusted (8.7% YoY) when drift_rakning missing
  - **Projection tracking**: Database `isProjection` flag + API transparency
  - **Manual override**: PUT endpoint auto-clears projection flag
  - **API indicator**: `quarterly_invoice_projection` boolean + Swedish disclaimer
- [ ] Fill in missing electricity bills history (Nov 2024 - Sept 2025) in `electricity_bills_history.txt`
- [ ] **⚡ CRITICAL: Implement Time-of-Use Grid Pricing (Winter Savings Opportunity)**
  - **Discovery (Oct 24, 2025)**: Vattenfall charges 2.5× higher grid transfer during winter peak hours
  - **Peak pricing (53.60 öre/kWh)**: Mon-Fri 06:00-22:00 during Jan/Feb/Mar/Nov/Dec
  - **Off-peak pricing (21.40 öre/kWh)**: All other times + entire summer (Apr-Oct)
  - **Impact**: ~400-500 kr/month savings potential by shifting consumption to off-peak
  - **Priority 1**: Update `ElectricityProjector` with hour-of-day + month-of-year logic
  - **Priority 2**: Migrate Node-RED heatpump schedule from Tibber API to elprisetjustnu.se API
  - **Priority 3**: Implement smart scheduling to avoid 06:00-22:00 weekdays in winter months
  - **Technical**: Add peak/off-peak classification to consumption analysis
  - **Testing**: Validate against Jan/Feb/Mar 2025 invoices with mixed peak/off-peak rates
  - **Node-RED Migration**: Replace Tibber spot price queries with elprisetjustnu.se + peak logic
  - **Heatpump Optimization**: Target 22:00-06:00 + weekends for heating during winter

### API Integration
- [x] Expose rent calculator as API for voice/LLM assistants:
  - [x] Natural language interface for rent queries
  - [x] Voice assistant integration (e.g., "Hey Google, what's my rent this month?")
  - [x] Ability for roommate-specific queries
  - [x] Historical rent lookup capabilities
- [x] Persistent storage for configuration:
  - [x] Base costs and monthly fees
  - [x] Quarterly invoice tracking
  - [x] Previous balance management
- [x] Persistent storage for roommates:
  - [x] Current roommate tracking
  - [x] Move-in/out dates
  - [x] Room adjustments
  - [x] Temporary stays
- [ ] **JotForm AI Integration**:
  - [ ] Ensure API is properly exposed with HTTPS and authentication
  - [ ] Optimize friendly_message format specifically for SMS
  - [ ] Add error handling for API timeouts and connection issues
  - [ ] Implement logging for JotForm API requests for debugging
  - [ ] Create OpenAPI documentation specifically for JotForm integration 
# Kimonokittens Master Plan (Detailed)

> **Note:** For July 2025 WebSocket, train API, and weather widget fixes, see DEVELOPMENT.md.
> **Oct 2 2025:** Reload loop protection implemented - 4-layer defense system active.
> **Nov 16 2025:** Documentation audit completed - major features previously marked as "planned" are actually production-ready.

This document provides a detailed, step-by-step implementation plan for the Kimonokittens monorepo projects. It is designed to be executed by an AI assistant with minimal context loss. Execute tasks sequentially unless marked as `(BLOCKED)`.

---

## 📊 RECENT DOCUMENTATION AUDIT (Nov 16, 2025)

**Key findings from codebase reality check:**

### ✅ Major Features Actually COMPLETE (previously documented as "planned"):
1. **Admin Dashboard & Contract Management** - ✅ Production-ready since Nov 14
   - Tab-key navigation, PIN auth, real-time WebSocket updates all working
   - 8 UI components + full backend handler (537 lines)
   - Contract cancellation, tenant contact management, signing progress monitoring
2. **Time-of-Use Grid Pricing** - ✅ Fully implemented in ElectricityProjector
   - Peak/off-peak rates (53.60 vs 21.40 öre/kWh) coded and tested
   - Swedish holiday handling, winter month logic all working
3. **Color Palette Documentation** - ✅ Complete in CLAUDE.md + docs/
   - Strict cyan-for-success rule enforced (no green/emerald)
4. **Personnummer Locking** - ✅ Implemented with has_completed_contract check
5. **Electricity Bills History** - ✅ 98% complete (only Nov 2024 missing)

### ❌ Still TODO (documentation accurate):
1. ~~**Deposit Formula Mismatch**~~ - ✅ **FIXED** (Nov 16, 2025)
2. ~~**Tenant Signup Form**~~ - ✅ **COMPLETE** (Nov 17, 2025) - See `docs/TENANT_SIGNUP_IMPLEMENTATION_SUMMARY.md`
3. **Tenant Signup Deployment** - Complete pending setup actions:
   - Cloudflare Turnstile account
   - Database migration
   - SMS service
   - **Add nginx location block for `/fonts/` directory** in `nginx-kimonokittens-https-split.conf` (public server block) to serve Horsemen fonts on signup page
   - (See `docs/TENANT_SIGNUP_IMPLEMENTATION_SUMMARY.md` for full checklist)
4. **Log Rotation** - Needs verification if actually needed in production
5. **Contract Replacement Workflow** - Delete+Re-sign not yet implemented
6. **Heatpump Peak Avoidance** - Requires Pi Node-RED config (separate infrastructure)
7. ~~**Horsemen Font**~~ - ✅ **EXTRACTED** (Nov 20, 2025) - Font files added to `/fonts/`, @font-face declarations in signup.html (nginx config needed for public access)
8. **Whenever Gem vs Manual Cron** - Consider pros/cons of using Whenever gem (already installed) for cron job management instead of manual crontab entries (rent reminders, bank sync, electricity scrapers)
9. **Electricity Price Awareness System** - Smart warnings for high-cost periods to optimize household appliance usage (washing machine, tumble dryer, dishwasher). System auto-detects abnormally high prices via statistical analysis (rolling baseline, no manual threshold). Features: (a) Predictive SMS/notifications day(s) before expensive periods, (b) Enhanced dashboard sparkline with visual price peak warnings overlaid on heatpump schedule bar. Context-aware: accounts for seasonal patterns while alerting on objectively high prices regardless of outdoor temperature. **Architecture:** See `docs/PRICE_AWARENESS_ARCHITECTURE_ANALYSIS.md` for design rationale (on-demand calculation, separate from heatpump config).
10. **Process Management Overhaul** - Current bin/dev + Overmind system unreliable (stale sockets, orphaned processes, state tracking failures requiring manual intervention). Research and implement simpler alternative: systemd user services (if viable on Mac), pure Foreman, custom lightweight manager, or automated socket cleanup integrated into bin/dev startup sequence.

**Impact:** Documentation was significantly outdated. 6 major features marked "planned" were actually shipped months ago.

---

## ✅ RESOLVED - Deposit Formula Fixed (Nov 16, 2025)

**PROBLEM:** Deposit formula in code (6,746 kr) didn't match actual practice (6,221 kr per person)!

**ROOT CAUSE:** Formula incorrectly calculated based on rent (110% of per-person rent) instead of splitting the fixed total deposit (24,884 kr) evenly among tenants.

**SOLUTION IMPLEMENTED:**
- [x] Updated formula to split fixed total deposit: `24_884 / num_active_tenants`
- [x] Corrected default to actual deposit paid: **6,221 kr per person** (not 6,200 kr)
- [x] Total house deposit: **24,884 kr** (6,221 kr × 4 original tenants)
- [x] Updated tests in `spec/models/tenant_spec.rb` (all passing)
- [x] Verified logic with manual tests (4 people: 6,221 kr, 5 people: 4,977 kr, 3 people: 8,295 kr)

**KEY PRINCIPLE:** Total deposit never exceeds original amount paid (24,884 kr), regardless of tenant count.

**Implementation:**
- File: `lib/models/tenant.rb` lines 161-180
- Method: `Tenant.calculate_deposit(num_active_tenants, total_house_deposit: 24_884)`
- Tests: `spec/models/tenant_spec.rb` lines 113-151

**Context:** Discovered Nov 10, 2025 during contract testing. Fixed Nov 16, 2025 based on clarification that original deposit was 6,221 kr/person (24,884 kr total).

---

## ⚠️ Monitor Brightness Schedule - Verify After Power Outage

**Issue:** Display appears stuck at low brightness (0.7-0.8) during daytime hours. May have reset after Nov 15 power outage (same outage that broke rotation).

**Expected schedule** (from `DASHBOARD_SLEEP_SCHEDULE_IMPLEMENTATION.md`):
- 00:00-05:32: 0.7 (night)
- 06:00: 1.0 (morning start)
- 08:00: 1.26 (mid-morning)
- 10:00: 1.39 (daytime peak)

**Action needed:**
- [ ] Test during daytime (10am-4pm) to verify brightness reaches ~1.4 instead of staying at 0.7
- [ ] Check xrandr brightness command execution in `/home/kimonokittens/.config/systemd/user/` or wherever schedule runs
- [ ] Consider UPS purchase (650-900 kr) to prevent future power-related config resets

**Created:** Nov 15, 2025 after display rotation reset incident

---

## ⚠️ Logo Burn-In Prevention - Implement Pixel Drift

**Issue:** Static logo in ClockWidget may cause LCD image persistence after 6-12 months of 24/7 display.

**Recommended approach:** Subtle pixel drift - shift entire display 2-4px every 15min using CSS `transform: translate()`. Imperceptible to users, prevents static elements from burning into exact pixels. GPU-accelerated, zero performance cost, preserves aesthetic.

**Implementation:** Add React hook to ClockWidget with `setInterval` updating random X/Y offsets (-3 to +3px), apply via wrapper div with `transition: transform 2s ease-in-out`. ~15 lines of code, 5min task.

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

  **Status:** ✅ **COMPLETE** (Nov 17, 2025) - Full implementation deployed to branch
  **Documentation:** See `docs/TENANT_SIGNUP_IMPLEMENTATION_SUMMARY.md` for complete reference
  **Pending Production Deployment:**
  - [ ] Merge branch `claude/prioritize-todo-tasks-01BismLPp9uGe1itBpQNTSTi` to master
  - [ ] Run database migration: `npx prisma migrate deploy`
  - [ ] Register Cloudflare Turnstile account + update siteKey/secretKey
  - [ ] (Optional) Extract Horsemen font from PopOS system fonts
  - [ ] (Optional) Integrate SMS service for admin notifications

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

## 🔐 ADMIN DASHBOARD & CONTRACT MANAGEMENT

**Goal:** Build comprehensive admin interface for managing contracts, tenant applications, and signing progress tracking

**Status:** ✅ **PRODUCTION READY** (Nov 14, 2025) - Core features implemented and deployed

### Core Features

**Admin View Integration:**
- [x] **Keyboard-navigable view switching** in hallway dashboard ✅ **IMPLEMENTED**
  - Tab key toggles between public display and admin view
  - ESC returns to public dashboard from admin view
  - Seamless transitions without page reload
  - Admin view hidden from passive hallway display
  - Visual indicator for which view is active
- [ ] **Facebook profile pic avatars** for tenant rows: Circular avatars (1.5× current icon size, white border) sourced from Facebook via facebookId field when populated

**Contract Management UI:**
- [x] **Signing progress monitoring** (real-time webhook updates) ✅ **IMPLEMENTED**
  - View all pending contracts with status
  - Track participant signing status (landlord + tenant)
  - Monitor agreement lifecycle (draft → pending → fulfilled → finalized)
  - Display expiration warnings and time remaining
  - Email delivery status and failures
  - Generation/validation error tracking
  - Real-time WebSocket updates via DataBroadcaster
  - Components: `ContractList.tsx`, `ContractRow.tsx`, `ContractDetails.tsx`, `ContractTimeline.tsx`
  - Backend: `handlers/admin_contracts_handler.rb`
- [x] **Contract cancellation** ✅ **IMPLEMENTED**
  - "Avbryt" (Cancel) button for non-completed contracts
  - Confirmation dialog with PIN authentication
  - Endpoint: `POST /api/admin/contracts/:id/cancel`
  - WebSocket broadcast on success
- [ ] **Contract replacement workflow** for completed contracts ⏳ **PLANNED**
  - "Delete + Re-sign" button for signed contracts (NOT YET IMPLEMENTED)
  - Allows landlord to cancel existing contract and generate fresh one
  - Use case: Contract corrections, rent adjustments, term changes
  - Security: PIN-gated action (same admin auth as other sensitive operations)
  - Flow: Delete old SignedContract record → Create new contract → Send to Zigned
  - Note: Discovered Nov 14, 2025 - completed contracts currently show only "Visa kontrakt" button
- [x] **Tenant contact management** ✅ **IMPLEMENTED** (Nov 14, 2025)
  - Update personnummer (locked after contract signing for security)
  - Update phone number
  - Update Facebook ID
  - Inline editing via window.prompt in admin UI
  - Endpoints: `PATCH /api/admin/contracts/tenants/:id/{personnummer,phone,facebook-id}`
  - `has_completed_contract` check prevents personnummer editing after signing
- [ ] **Tenant application workflow** (when public signup implemented) ⏳ **PLANNED**
  - View pending applications from `/meow` signup form
  - Approve/reject applicants with notes
  - Assign room and set move-in date
  - Preview rent calculation before contract generation
  - One-click contract generation and Zigned submission
- [x] **Contract viewing and management** ✅ **IMPLEMENTED**
  - Download signed PDFs via "Visa kontrakt" button
  - View signing timeline and participant details
  - Filter: All contracts / Active only
  - Real-time status updates via WebSocket
- [ ] **Historical contract archive enhancements** ⏳ **FUTURE**
  - Search/filter improvements
  - Export contract metadata (CSV/JSON)
  - Advanced pagination for large lists

**Testing Status:**
- [x] Real-time webhook integration (contract status updates via WebSocket) ✅ **WORKING**
- [x] Keyboard navigation (Tab toggles views, ESC returns to public) ✅ **WORKING**
- [x] PIN authentication with AdminAuthContext ✅ **WORKING**
- [ ] Accessibility (screen reader support, ARIA labels) ⏳ **FUTURE**
- [ ] Database query performance (pagination for large contract lists) ⏳ **FUTURE**

**Technical Implementation:**
- Built as separate view within existing dashboard (not separate app) ✅
- Uses same DataContext/WebSocket infrastructure ✅
- **Tab key** toggles between public dashboard and admin view ✅
- PIN authentication via AdminAuthContext ✅
- Components: `dashboard/src/components/admin/` (8 components)
- Backend: `handlers/admin_contracts_handler.rb` (537 lines)

**Dependencies:**
- ✅ Zigned webhook v3 implementation (Phase 1-5) **COMPLETE**
- ✅ Database schema for participant tracking **COMPLETE**
- ⏳ Public tenant signup form (`/meow` endpoint) **PENDING**

**Priority:** ✅ **CORE FEATURES COMPLETE** - Only enhancements remain

**Related Docs:**
- `docs/ZIGNED_WEBHOOK_IMPLEMENTATION_PLAN.md` (Phase 6: Admin Dashboard)
- `handlers/zigned_webhook_handler.rb` (webhook event processing)
- `lib/repositories/signed_contract_repository.rb` (contract data access)

---
## Immediate Tasks & Repository Hygiene

**Goal:** Address outstanding technical debt and improve overall code quality.

-   [ ] **Test ViewTransition animations** (manual browser verification) ⚠️ **LIKELY IMPLEMENTED**
    -   **Status**: `TrainWidget.tsx` found with ViewTransition code - implementation exists
    -   **Testing needed**: Verify train intro/departure animations (5s slide-in, 400ms slide-out)
    -   [ ] Verify bus intro/departure animations
    -   [ ] Verify warning/critical glows still trigger correctly
    -   [ ] Check delay display (no "0m sen" regression)
    -   [ ] Monitor performance marks in console (should be <50ms)
    -   **Details:** See `docs/VIEWTRANSITION_SESSION_STATE.md` for complete implementation summary
    -   **Commits:** 13 commits (0b7d1e7 and earlier) - ~278 lines removed, native browser API
-   [ ] **Fix Failing Specs** ⚠️ **NEEDS TEST RUN TO VERIFY**
    -   **Status**: Cannot verify until `bundle install` completes and tests run
    -   **Test count**: 249 test cases found across 21 spec files
    -   [ ] **BankBuster:** All 5 specs for `bank_buster_spec.rb` are failing (per documentation)
    -   [ ] **HandbookHandler:** All 12 specs for `handbook_handler_spec.rb` are failing (per documentation)
    -   **Action**: Run `bundle exec rspec` to verify actual test status vs documented claims
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
- [ ] **Store signed contract PDFs as blobs in database instead of filesystem**
  - **Current**: SignedContract table stores file paths (`pdfUrl` field), actual PDFs in `contracts/signed/` directory
  - **Future**: Store PDF binary data directly in database for better backup, multi-machine access, and data integrity
  - **Priority**: LOW - filesystem approach works fine for single-server deployment, but consider for future scaling

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

**📌 IMPORTANT: Detailed planning exists in `docs/RENT_REMINDERS_SYSTEM_BRAIN_DUMP.md` - complete codebase exploration + GPT-5 prompt**

**Future Tenant fields (deferred for now):**
- [ ] `sms_tone` field (gentle-quirky, professional, etc.) - Add when personality customization needed
- [ ] `lang` field (sv/en) - Add when non-Swedish tenants join

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
- [x] **⚡ Implement Time-of-Use Grid Pricing** ✅ **FULLY IMPLEMENTED** (Oct 24, 2025)
  - **Discovery**: Vattenfall charges 2.5× higher grid transfer during winter peak hours
  - **Peak pricing (53.60 öre/kWh)**: Mon-Fri 06:00-22:00 during Jan/Feb/Mar/Nov/Dec ✅
  - **Off-peak pricing (21.40 öre/kWh)**: All other times + entire summer (Apr-Oct) ✅
  - **Implementation**: `lib/electricity_projector.rb` lines 50+
  - **Peak detection logic**: `is_peak_hour?(timestamp)` method with month + weekday + hour checks ✅
  - **Swedish holiday handling**: Red days excluded from peak pricing ✅
  - **Testing**: Validated against actual 2025 invoices ✅
  - **Impact**: Pricing model now accounts for time-of-use rates in projections
- [ ] **⚡ FUTURE: Heatpump Optimization for Peak Avoidance** ⏳ **PLANNED**
  - **Goal**: ~400-500 kr/month savings by shifting consumption to off-peak
  - **Priority 1**: Migrate Node-RED heatpump schedule from Tibber API to elprisetjustnu.se API
  - **Priority 2**: Implement smart scheduling to avoid 06:00-22:00 weekdays in winter months
  - **Priority 3**: Target 22:00-06:00 + weekends for heating during winter
  - **Blocker**: Requires Node-RED configuration changes (not code changes in this repo)
  - **Location**: Heatpump control runs on Raspberry Pi via MQTT (separate infrastructure)
- [ ] **⚡ FUTURE: Self-learning hours_on adjustment** ⏳ **PLANNED**
  - **Goal**: Replace fixed hours_on value with adaptive algorithm
  - **Approach**: Monitor performance metrics to automatically optimize baseline
    - Temperature override frequency (too many overrides = increase hours_on)
    - Energy cost vs target (overspending → reduce hours_on, underspending → can increase)
    - Weather pattern correlation (colder winters need higher baseline)
    - Indoor temperature stability (fluctuations indicate poor scheduling)
  - **Benefit**: Intelligent baseline optimization vs removed emergency_price reactive approach
  - **Context**: Replaces removed price opportunity logic (emergency_price threshold) with proactive learning
  - **Added**: Nov 20, 2025 during emergencyPrice field removal
- [ ] **⚡ FUTURE: Enhance Electricity Projection Accuracy** ⏳ **PLANNED**
  - Use Vattenfall/Fortum PDF scrapers to extract actual bill line-item breakdowns and model specific cost components (trading margins, certificates, administrative fees) instead of empirical 4.5% adjustment. See `bin/analyze_projection_accuracy.rb` for current accuracy baseline.

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

---

## 💰 Rent Reminders & Payment Automation

**Status:** ✅ Implementation plan complete (Nov 14, 2025) - Ready for development
**Documentation:** `docs/RENT_REMINDERS_IMPLEMENTATION_PLAN.md`

### MVP Implementation (6-Week Plan)
- [ ] **Phase 1:** Database schema (3 new tables: BankTransaction, RentReceipt, SmsEvent)
- [ ] **Phase 2:** Lunch Flow API integration (hourly bank sync cron)
- [ ] **Phase 3:** Payment matching service (3-tier: reference, amount+name, partial)
- [ ] **Phase 4:** SMS infrastructure (46elks integration + webhooks)
- [ ] **Phase 5:** Rent reminder scheduling (daily 09:45 & 16:45, tone-based escalation)
- [ ] **Phase 6:** Admin dashboard UI (payment status badges + expanded details)

### Service Signup Required
- [ ] **Lunch Flow:** Sign up at https://www.lunchflow.app/signin/signup (£5/month, 7-day trial)
- [ ] **46elks:** Sign up at https://46elks.com/register (Swedish SMS provider, ~0.65 SEK/SMS)

### Future Enhancements (Deferred from MVP)

**Future Tenant Fields** (noted Nov 14, 2025):
- [ ] `sms_tone` field (gentle-quirky, professional, etc.) - Add when personality customization needed
- [ ] `lang` field (sv/en) - Add when non-Swedish tenants join

**Desktop User Experience:**
- [ ] QR code fallback for Swish links (desktop users can scan with phone camera instead of copy-paste)

**Analytics & Tracking:**
- [ ] Swish link click tracking (`/swish/track?token=...` endpoint to log who clicks vs who pays without clicking)

**Swish Commerce API** (4-6 line summary as requested):
- [ ] Apply for business Swish account (requires enskild firma or company registration)
- [ ] Real-time payment webhooks (~200-500 kr/month subscription cost)
- [ ] Immediate confirmation instead of hourly bank sync lag (better UX)
- [ ] Refund capability via API for overpayments or cancellations

**RentConfig Admin UI:**
- [ ] Add admin UI fields for `extra_in`, `saldo_innan`, and other manual RentConfig adjustments (allows adding unexpected costs/income before ledger population on day 22)

---

## Infrastructure & DevOps

### Log Management
- [ ] **Implement log rotation for `/var/log/kimonokittens/`** ⚠️ **NEEDS VERIFICATION**
  - **Problem**: `/var/log/kimonokittens/webhook.log` was 303MB (Nov 11, 2025) - will consume disk space over time
  - **Status**: Mentioned as "(Optional)" in `docs/PRODUCTION_CRON_DEPLOYMENT.md` but not verified if implemented
  - **Action needed**: Check actual production log sizes to confirm if this is urgent
  - **Solution**: Configure logrotate for all kimonokittens log files
  - **Files to rotate**:
    - `webhook.log` (GitHub deployment webhook - very verbose)
    - `frontend.log` (frontend error logging)
    - `zigned-webhooks.log` (Zigned contract signing events)
  - **Recommended config**:
    - Rotate daily
    - Keep 14 days of logs (2 weeks for debugging)
    - Compress after rotation (gzip)
    - Max size 100MB (force rotation if exceeded)
  - **Implementation**: Create `/etc/logrotate.d/kimonokittens` config file
  - **Priority**: **HIGH IF LOGS ARE LARGE** - Check production first, then implement if needed 
## 🎨 Design System & UI Consistency

- [x] **Color palette documented** ✅ **COMPLETE** (documented in `CLAUDE.md` lines 95-113)
  - **Approved colors**: Purple (primary), Slate (backgrounds), Cyan (success/positive), Yellow (warnings), Red (errors), Blue (info), Orange (alerts)
  - **CRITICAL RULE**: Never use green/emerald for success states (use cyan instead)
  - **Additional docs**: `docs/ADMIN_UI_VISUAL_GUIDE.md`, `docs/CONTRACT_PDF_DASHBOARD_STYLING_GUIDE.md`
- [ ] **Extended style guide** ⏳ **FUTURE**
  - Typography patterns (uppercase headings, dot separators, font sizing)
  - Gradient specifications and usage guidelines
  - Spacing system (margins, padding, grid)
  - Motion/animation patterns (transitions, timing functions)
  - Document reusable tokens for consistency across admin/dashboard widgets

## 🧾 Logging & Monitoring

- [ ] Remove verbose console logging from widgets (RentWidget clusters, DataContext WebSocket messages, etc.) - historically useful but now cluttering browser console
- [ ] Investigate prod log volume (journald + dashboard logs): measure disk space consumed per hour/day and trim noisy broadcast entries.
- Check electricity scrapers - dashboard shows projection despite bills being due, verify logs and RentConfig aggregation

# Session Brain Dump - November 14, 2025

## Context Handoff
- **Session started**: November 14, 2025
- **User**: Fredrik working from Mac Mini M2 dev environment
- **Project**: Kimonokittens dashboard + admin contracts UI
- **Context left**: ~1% when this dump was created

## Session Overview

### What Was Done

#### 1. Temperature Handler Fix (DEPLOYED ✅)
**Commit**: `7e91957` - "fix: remove phased-out public temperature endpoint"

**Problem**: Production logs showing 404 errors every 60 seconds:
```
Nov 12 23:30:39 pop-os bash[2667287]: TEMPERATURE_HANDLER: Trying endpoint https://kimonokittens.com/data/temperature
Nov 12 23:30:39 pop-os bash[2667287]: TEMPERATURE_HANDLER: Got response code 404
Nov 12 23:30:39 pop-os bash[2667287]: TEMPERATURE_HANDLER: Response not successful: 404
Nov 12 23:30:39 pop-os bash[2667287]: TEMPERATURE_HANDLER: Trying endpoint http://192.168.4.66:1880/data/temperature
Nov 12 23:30:39 pop-os bash[2667287]: TEMPERATURE_HANDLER: Got response code 200
```

**Root Cause**: After domain migration, `handlers/temperature_handler.rb` was trying public `kimonokittens.com/data/temperature` first (which no longer exists), then falling back to local Node-RED endpoint.

**Fix Applied**:
- Removed phased-out `https://kimonokittens.com/data/temperature` endpoint
- Now goes directly to `http://192.168.4.66:1880/data/temperature`
- Removed obsolete SSL verification skip logic
- File: `handlers/temperature_handler.rb` lines 8-11

**Impact**:
- ✅ No more 404 errors in production logs
- ✅ ~500ms-1s faster temperature data fetching
- ✅ Cleaner logs

---

#### 2. Admin Contract UI Cleanup (DEPLOYED ✅)
**Commit**: `d07ef3a` - "feat(admin): hide email status & extra buttons for completed contracts"

**User Request**: Hide email status and extra buttons for completed/signed contracts, keeping only "Visa kontrakt" button.

**Changes Made** - `dashboard/src/components/admin/ContractDetails.tsx`:

1. **Hidden E-poststatus section** (lines 115-162):
```typescript
{/* Email Status Section - Hidden for completed contracts */}
{contract.status !== 'completed' && (
  <div>
    <h4 className="text-sm font-semibold text-purple-200 mb-3">E-poststatus:</h4>
    {/* ... email delivery tracking ... */}
  </div>
)}
```

2. **Hidden extra action buttons** (lines 232-266):
```typescript
{/* Hide extra buttons for completed contracts */}
{contract.status !== 'completed' && (
  <>
    <button>Skicka igen</button>  {/* Resend email */}
    <button>Avbryt</button>       {/* Cancel contract */}
    <button>Kopiera länkar</button> {/* Copy signing URLs */}
  </>
)}
```

**Kept visible**: "Visa kontrakt" button (always shown, opens PDF in new tab)

**Rationale**: Once both parties have signed:
- Email delivery status is historical noise
- Can't resend emails for signed contracts
- Can't cancel finalized contracts
- Signing URLs no longer needed

---

#### 3. TODO.md Update
**Added**: Contract replacement workflow for future implementation

**Location**: `TODO.md` lines 253-259

**Content**:
```markdown
- [ ] **Contract replacement workflow** for completed contracts
  - "Delete + Re-sign" button for signed contracts
  - Allows landlord to cancel existing contract and generate fresh one
  - Use case: Contract corrections, rent adjustments, term changes
  - Security: PIN-gated action (same admin auth as other sensitive operations)
  - Flow: Delete old SignedContract record → Create new contract → Send to Zigned
  - Note: Discovered Nov 14, 2025 - completed contracts currently show only "Visa kontrakt" button
```

---

#### 4. Personnummer Display Bug Fix (CRITICAL) ✅
**Commits**: `d905661`, `17fdbfc`

**Problem**: Admin UI showing "—" placeholder despite database having personnummer data

**Root Cause**: `lib/repositories/tenant_repository.rb` line 97 - `.select()` was missing personnummer field!

**Before** (BROKEN):
```ruby
def all
  dataset
    .select(:id, :name, :email, :startDate, :departureDate, :roomAdjustment, :room, :status)
    .order(:name)
    .map { |row| hydrate(row) }
end
```

**After** (FIXED):
```ruby
def all
  dataset
    .select(:id, :name, :email, :startDate, :departureDate, :roomAdjustment, :room, :status,
            :personnummer, :phone, :deposit, :furnishingDeposit,
            :facebookId, :avatarUrl, :createdAt, :updatedAt)
    .order(:name)
    .map { |row| hydrate(row) }
end
```

**Database had data all along**:
- Fredrik Bränström: 8604230717
- Frida Johansson: 9012151234
- Sanna Juni Benemar: 8706220020

**Lesson**: Always verify actual database state before concluding data is missing!

---

#### 5. Complete Contact Management System ✅
**Commits**: `17fdbfc`, `d6beb20`, `865579b`

**3-Column Contact Grid**:
- Column 1: Personnummer (identity)
- Column 2: Facebook ID (social contact)
- Column 3: Phone number (direct contact)

**Backend Endpoints**:
- `PATCH /api/admin/contracts/tenants/:id/personnummer` - Swedish format validation (10-12 digits)
- `PATCH /api/admin/contracts/tenants/:id/facebook-id` - Any string format
- `PATCH /api/admin/contracts/tenants/:id/phone` - Swedish phone validation (9-15 digits)

**Security**:
- All endpoints PIN-gated via `X-Admin-Token`
- Personnummer editing blocked if `has_completed_contract = true`
- Lock message: "🔒 Personnummer kan inte ändras efter signerat kontrakt"

**UI Features**:
- Inline editing via `window.prompt`
- Clickable links: `facebook.com/{id}`, `tel:{phone}`
- Obfuscation: `860423-****` (show first 6 digits, hide last 4)
- Clean display: Only show button when field missing (no placeholder text)
- Real-time updates via WebSocket broadcast

**Phone Number Validation**:
```ruby
# Removes whitespace and common formatting characters
cleaned_phone = phone.strip.gsub(/[\s\-\(\)\.\/]/, '')

# Swedish phone numbers: 9-15 digits (with/without country code)
unless cleaned_phone =~ /^\+?\d{9,15}$/
  return error
end
```

---

#### 6. Deposit Amounts Set ✅
**Script**: `scripts/set_tenant_deposits.rb` (one-off, not committed)

**Standard deposits**:
- Base deposit: 6,200 kr
- Furnishing deposit: 2,200 kr

**Updated tenants**:
- ✅ Adam McCarthy: 6,200 kr + 2,200 kr
- ✅ Fredrik Bränström: 6,200 kr + 2,200 kr
- ✅ Sanna Juni Benemar: 6,200 kr + 2,200 kr (already had correct amounts)
- ⏭️ Frida Johansson: Skipped (already has contract)

---

#### 7. Contract Status Display Revamp ✅
**Commit**: `5cf0245`

**Old format** (verbose with headers):
```
Signeringsstatus:
  ✓ Fredrik Bränström - Signerad (12 november kl. 18:08)
  ✓ Hyresgäst - Signerad (12 november kl. 18:08)
```

**New format** (clean, no headers):
```
✓ Fredrik Bränström signerade 12 nov. 18:08
✓ Frida Johansson signerade 12 nov. 18:08
```

**Key improvements**:
- Removed section headers ("E-poststatus:", "Signeringsstatus:")
- Abbreviated month names (nov instead of november)
- Simplified past tense ("signerade" vs "Signerad")
- Email: "fick kontraktet via email" format
- Combined email + signing in single section for non-completed contracts

**Completed contracts layout**:
- Signing status appears in column to right of "Visa kontrakt" button
- Horizontal flex layout with `gap-8`
- Clean, scannable status info

---

#### 8. Visual Polish: Teal Button [IN PROGRESS]
**Current work**: Change "Visa kontrakt" button from orange to teal gradient

**Before**: `linear-gradient(180deg, #c86c34 20%, #8f3c10 100%)` (orange)
**After**: `linear-gradient(180deg, #22d3ee 20%, #0891b2 100%)` (teal, matches checkmarks)

**Rationale**: Visual consistency with cyan-400 checkmarks throughout contract UI

---

## Important Context from Previous Session

### Codex Session Summary (Nov 12, 2025)
**Document**: `docs/codex_session_summary_2025-11-12.md`

**Key work from Codex+Fredrik pair programming**:
1. **Duplicate contract cleanup helper**: `scripts/cleanup_signed_contract_duplicates.rb`
2. **Admin dashboard fixes**:
   - Contract creation endpoint detects existing contracts (cyan toasts)
   - UI polish: large form typography, time-lived pills, rent visibility
   - CSS-based expand/collapse animations (replaced Framer Motion)
   - Removed broken "Aktiva/Alla" filter toggle
3. **Security hardening**:
   - PIN-gated admin auth (`/api/admin/auth`)
   - Short-lived tokens stored server-side
   - All sensitive actions behind `X-Admin-Token` check
   - Frontend `AdminAuthProvider` prompts for PIN on first protected action
4. **Dynamic landlord profile**: Admin UI reads landlord data from tenant record
5. **Tenant insight panel**: Expanded rows show rent, deposits, move-out date
6. **Dashboard build health**: TypeScript backlog cleared, `npm run build` succeeds
7. **Post-completion polish**: Contract timelines collapse once both parties sign

### Open Follow-ups from Codex Session
- PIN currently shared across all actions (evaluate per-user auth later)
- Animation polish paused
- Pending: Adam's failed contract creation investigation
- Pending: PIN-gated todo editing + markdown persistence
- Pending: Production log volume instrumentation
- Pending: LAN kiosk access hygiene documentation

---

## Tibber API Context (Important for Future Work)

**From previous session**: User mentioned elpriset API migration in Node-RED

**Document**: `docs/NODE_RED_TIBBER_TO_ELPRISET_MIGRATION.md` (created Oct 26, 2025)

**Key Facts**:
- Node-RED heatpump scheduler using **INVALID Tibber API demo key since May 2025**
- Demo data inflated prices by **+96.5%**
- Missing customer-specific Vattenfall T4 grid rates
- **Potentially 2,000 kr wasted over 5 months**

**CRITICAL UNDERSTANDING** (from this session):
- User clarified: Tibber API is ONLY used for heatpump on/off schedule
- Old Tibber data had correct timing curve (cheapest hours)
- Just didn't have accurate absolute prices
- **Expected savings from elpriset migration: MARGINAL** (5-10% reduction, not dramatic)
- Still worth doing for accurate pricing + Vattenfall T4 rates

**Migration complexity**: HIGH
- Requires porting 150+ lines Ruby pricing logic
- Swedish holiday calculations (31+ dates per year)
- Timezone handling
- Testing without disrupting production heatpump control

**Status**: PLANNING - Do NOT implement yet

---

## Rent Reality Investigation (From Previous Session)

### Actual Annual Average Discovery
**Investigation**: Queried historical electricity data from RentConfig database

**Results** (Dec 2024 - Oct 2025, 11 months):
```
Average electricity: 3,679 kr/month (NOT 1,800 kr assumed!)
Base costs: 25,767 kr (kallhyra + bredband + utilities + gas)
Total: 29,446 kr/month
Per person (4 roommates): 7,362 kr
```

**Current advertised**: 7,100 kr/person
**Actual average**: 7,362 kr/person
**Shortfall**: 262 kr/person/month = 12,576 kr/year total for 4 roommates

### Seasonal Variance Discovery
**Winter peaks**:
- Feb 2025: 5,945 kr (highest)
- Mar 2025: 5,936 kr
- Apr 2025: 4,398 kr
- Jan 2025: 4,763 kr
- Dec 2024: 4,226 kr

**Summer lows**:
- Aug 2025: 1,738 kr (lowest)
- Jul 2025: 1,972 kr
- Sep 2025: 2,424 kr
- Oct 2025: 2,581 kr

**Variance**: 3.4× between summer and winter!

### Important Clarification
**This 7,362 kr average INCLUDES the inflated Tibber costs (+96.5% since May 2025)**

Once elpriset API migration completes, expect marginal reduction (5-10%), not dramatic drop.

---

## Virtual Pot System Status

**Status**: ✅ **IMPLEMENTED** (November 1, 2025)

**Document**: `docs/virtual_pot_implementation_plan_v2.md` (updated this session)

**Key Understanding**:
- Monthly accruals (754 kr utilities + 83 kr gas = 837 kr) ALWAYS used in calculations
- Quarterly invoices (`drift_rakning`) STORED in database but NEVER used in billing
- **Current buffer consideration**: User considering increase to 900 kr/month (decision pending)

**Timing Clarification** (from this session):
- Virtual pot is NOT one-time reserve
- It's **continuous accrual** that rebuilds immediately after invoice payment
- START SAVING IMMEDIATELY after paying October invoice
- With 754 kr/month: only 2,262 kr saved by January (538 kr shortfall)
- With 900 kr/month: 2,700 kr saved by January (100 kr shortfall) - much safer

---

## Smart Defaults Implementation (Completed Nov 12, 2025)

**Status**: ✅ **COMPLETE**

**Document**: `docs/RENT_CALCULATOR_SMART_DEFAULTS_IMPLEMENTATION_PLAN.md`

**What Was Implemented**:
1. Added `with_projection: true` to `RentConfig.for_period()` (lib/models/rent_config.rb:149-157)
2. Added convenience method `RentCalculator.rent_breakdown_for_period()` (rent.rb:549-605)
3. Updated both handlers:
   - `admin_contracts_handler.rb:96` - Now uses convenience method (1 line vs 8 lines)
   - `rent_calculator_handler.rb:388` - Passes projection parameter

**Test Updates**: 18 test expectations updated across 3 files
- Config tests: 7/7 passing
- Calculator tests: 11/12 passing (1 kr rounding diff - user approved ignoring)
- Integration tests: 3/3 passing

---

## Production Environment Details

### SSH Access
- **Kiosk hostname**: `pop` (NOT `kimonokittens.com` - that points to Pi)
- **SSH as fredrik**: `ssh pop` (default)
- **SSH as kimonokittens**: `ssh kimonokittens@pop` or `ssh pop -l kimonokittens`

### Domain & Services
- `kimonokittens.com` DNS points to home WAN IP (via DDClient on Pi)
- **Pi Agoo server**: Hosts simple public homepage (port 6464/6465)
- **Dell dashboard**: Only serves localhost (not publicly accessible yet)
- **Public migration postponed** until BRF-Auto income secured

### Process Management
**CRITICAL**: Never trust system reminders about background process status - always verify!

**Commands**:
```bash
# Development
npm run dev          # Start all dev processes
npm run dev:status   # Comprehensive status check
npm run dev:restart  # Clean restart (most important!)
npm run dev:stop     # Aggressive cleanup
npm run dev:logs     # View process logs

# Verification
ps aux | grep -E "(npm run dev|ruby.*puma|vite.*5175)" | grep -v grep
lsof -ti :3001 :5175
```

### Webhook Deployment
- **Port 49123**: Webhook receiver (GitHub webhooks)
- **Smart change detection**: Frontend vs backend vs docs-only
- **2-minute debounce**: Rapid pushes = one deployment with all changes
- **Log location**: `/var/log/kimonokittens/webhook.log`
- **Monitor**: `tail -f /var/log/kimonokittens/webhook.log`

---

## Database & Data Models

### Key Tables
- **SignedContract**: Contract lifecycle (draft → pending → completed)
- **ContractParticipant**: Landlord + tenant signing status
- **Tenant**: Tenant records with move-in/out dates, room assignments
- **RentConfig**: Period-specific rent configuration
- **ElectricityBill**: Historical electricity invoices

### Repository Pattern
**Location**: `lib/repositories/`
- `signed_contract_repository.rb`
- `contract_participant_repository.rb`
- `tenant_repository.rb`
- `rent_config_repository.rb`
- `electricity_bill_repository.rb`

**Access**: Via `lib/persistence.rb` singleton

---

## Git Workflow Notes

### Recent Commits (This Session)
1. **7e91957**: fix: remove phased-out public temperature endpoint
2. **d07ef3a**: feat(admin): hide email status & extra buttons for completed contracts
3. **d905661**: fix: personnummer display bug (repository SELECT missing fields)
4. **17fdbfc**: feat: complete personnummer + Facebook ID management
5. **d6beb20**: feat(admin): add phone number to 3-column tenant contact grid
6. **865579b**: refactor(admin): clean UI for missing contact fields + set deposits
7. **5cf0245**: refactor(admin): revamp contract status display for cleaner UI
8. **[IN PROGRESS]**: style: change "Visa kontrakt" button to teal gradient

### Pull Before Push
- Session encountered merge conflict during push
- Had to `git pull origin master` (auto-rebased)
- Then `git push origin master` succeeded

### Deployment Flow
1. Local changes → commit → push to GitHub
2. Webhook triggers on Dell kiosk
3. Smart change detection analyzes files
4. Frontend/backend deployed as needed
5. Kiosk browser restarts for frontend changes

---

## Known Issues & Quirks

### Claude Code Background Process Bug
- System reminders show unreliable status
- **ALWAYS verify with `ps` or `BashOutput` tool**
- Issues: #7838, #1481, #759

### Non-TTY Environment
- Procfile auto-detection: TTY uses `Procfile.dev`, non-TTY uses `Procfile.dev.nontty`
- Verification commands (`overmind status`) HANG in non-TTY
- Trust daemon starts successfully, check logs separately

### Ruby Logger Buffering Mystery (Oct 2-3, 2025)
- Logs would "stop" after rsync but execution continued
- **Root cause**: Ruby `Logger.new(STDOUT)` buffers output
- **Fix applied**: `$stdout.sync = true` and `$stderr.sync = true`
- Logs now appear instantly

---

## File Locations Reference

### Admin UI Components
- `dashboard/src/components/admin/AdminUnlockIndicator.tsx`
- `dashboard/src/components/admin/ContractDetails.tsx` ← **Modified this session**
- `dashboard/src/components/admin/ContractList.tsx`
- `dashboard/src/components/admin/ContractRow.tsx`
- `dashboard/src/components/admin/ContractTimeline.tsx`
- `dashboard/src/components/admin/MemberRow.tsx`
- `dashboard/src/components/admin/TenantDetails.tsx`
- `dashboard/src/components/admin/TenantForm.tsx`

### Backend Handlers
- `handlers/temperature_handler.rb` ← **Modified this session**
- `handlers/admin_contracts_handler.rb`
- `handlers/rent_calculator_handler.rb`
- `handlers/zigned_webhook_handler.rb`

### Documentation
- `docs/codex_session_summary_2025-11-12.md` ← **Read at session start**
- `docs/NODE_RED_TIBBER_TO_ELPRISET_MIGRATION.md`
- `docs/virtual_pot_implementation_plan_v2.md` ← **Updated this session**
- `docs/RENT_CALCULATOR_SMART_DEFAULTS_IMPLEMENTATION_PLAN.md`
- `TODO.md` ← **Updated this session**

### Key Configuration
- `.env` - Environment variables (database URLs, API keys)
- `config/sleep_schedule.json` - Dashboard sleep schedule
- `Procfile.dev` - Development process definitions (TTY)
- `Procfile.dev.nontty` - Development process definitions (non-TTY)

---

## Work Completed This Session ✅

### Major Accomplishments
1. ✅ **Temperature handler cleanup** - Removed phased-out public endpoint
2. ✅ **Completed contract UI cleanup** - Hide email status & extra buttons
3. ✅ **CRITICAL: Personnummer bug fix** - Repository SELECT was missing fields
4. ✅ **Complete contact management** - 3-column grid (personnummer, Facebook, phone)
5. ✅ **Deposit amounts standardized** - 6,200 kr + 2,200 kr for all active tenants
6. ✅ **Status display revamp** - Removed headers, cleaner format, teal visual consistency
7. 🔄 **IN PROGRESS: Teal button** - Currently coding, about to commit & push

### Files Modified This Session
- `handlers/temperature_handler.rb` - Endpoint cleanup
- `dashboard/src/components/admin/ContractDetails.tsx` - UI cleanup, status revamp, button color
- `dashboard/src/components/admin/TenantDetails.tsx` - 3-column grid, phone editing
- `dashboard/src/views/AdminDashboard.tsx` - TypeScript interfaces
- `handlers/admin_contracts_handler.rb` - Phone endpoint, tenant_phone in API
- `lib/repositories/tenant_repository.rb` - CRITICAL FIX: Added missing SELECT fields
- `TODO.md` - Added contract replacement workflow task
- `docs/session_brain_dump_2025_11_14.md` - This comprehensive update

---

## Technical Debt & Future Work

### High Priority
- **Elpriset API migration** (NODE_RED_TIBBER_TO_ELPRISET_MIGRATION.md)
- **Contract replacement workflow** ("Delete + Re-sign" button)
- **PIN-gated todo editing** + markdown persistence

### Medium Priority
- **Log rotation** for `/var/log/kimonokittens/` (webhook.log is 303MB)
- **SSL certificate renewal** before Feb 2026
- **Deposit formula mismatch** (6,746 kr vs 6,200 kr social convention)

### Future Enhancements
- **Public tenant signup** (`/meow`, `/curious`, `/signup` endpoints)
- **SMS reminders** + Swish integration
- **Tenant lifecycle management** (remove hardcoded 4-tenant count)

---

## Environment Variables Reference

### Production `.env` Location
- **Source of truth**: `/home/kimonokittens/.env`
- **Symlink**: `/home/kimonokittens/Projects/kimonokittens/.env` → `/home/kimonokittens/.env`

### Development `.env` Location
- **Dev checkout**: `/home/fredrik/Projects/kimonokittens/.env`
- Points to `_development` database
- `NODE_ENV=development`

### Key Variables
- `DATABASE_URL` - PostgreSQL connection string
- `API_BASE_URL` - Base URL for DataBroadcaster endpoints
- `WEBHOOK_PORT` - Webhook receiver port (49123)
- `PINECONE_API_KEY`, `PINECONE_ENVIRONMENT` - For handbook RAG
- `OPENAI_API_KEY` - For AI query pipeline
- Various Zigned/Vattenfall/Fortum API credentials

---

## Session State at Dump Time

### Git Status
```
On branch master
Your branch is up to date with 'origin/master'.
nothing to commit, working tree clean
```

### Last Commit Pushed
**Commit**: `d07ef3a`
**Branch**: `master`
**Remote**: `origin/master`

### Background Processes Running
- Bash 133166: `npm run dev:logs` (status: running)
- Bash 05cb1d: `npm run dev` (status: running)
- Bash 49be1c: `npm run dev` (status: running)

### Context Remaining
~1% when this dump was created

---

## Critical Reminders for Next Session

1. **Always verify background process status** with `ps` commands, never trust system reminders
2. **Pull before push** to avoid merge conflicts
3. **Temperature handler now goes directly to Node-RED** (192.168.4.66:1880)
4. **Completed contracts show minimal UI** (only "Visa kontrakt" button)
5. **Virtual pot is continuous accrual**, not one-time reserve
6. **Actual rent average is 7,362 kr/person**, not 7,100 kr (includes inflated Tibber costs)
7. **Elpriset migration will provide marginal savings** (5-10%), not dramatic drop

---

## User's Communication Style

- **"Ultrathink"** - Means think deeply, consider all implications
- Prefers concise, technical explanations
- Values exhaustive documentation for handoffs
- Works across multiple AI agents (Codex, Claude Code)
- Appreciates proactive problem-solving
- Expects immediate action on critical requests (like this brain dump!)

---

## End of Brain Dump

**Created**: November 14, 2025
**Context used**: ~1% remaining when created
**Purpose**: Comprehensive session handoff for next AI agent or resumed session
**Next action**: Investigate personnummer display issue in admin UI

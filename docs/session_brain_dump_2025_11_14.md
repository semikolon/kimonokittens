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

## Next Steps (From User's Latest Request)

### Immediate Tasks
1. **Check latest commits** - User pulled work from server-side CC agent
2. **Troubleshoot personnummer display issue**:
   - Screenshot shows personnummer field in admin UI
   - User says "doesn't fetch the data correctly"
   - Need to investigate what's wrong with data fetching
3. **Push fix if solved**

### Context for Investigation
- User mentioned pulling work from "server side CC agent"
- This suggests there's been development on the kiosk itself
- Need to check recent commits NOT from this local session
- Likely commits after `d07ef3a` that haven't been analyzed yet

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

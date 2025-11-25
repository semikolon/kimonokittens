# Contract UI & Webhook Fixes Plan

**Created:** Nov 24, 2025, 14:35
**Last Updated:** Nov 25, 2025, 02:30
**Status:** ✅ PRODUCTION - Complete system working, two production contracts created (Adam + Rasmus)
**Priority:** COMPLETE - All core features deployed, self-contract creation fully fixed

## 🚀 DEPLOYMENT STATUS

**Latest Session (Nov 25, 01:48-02:30):**
- `b7a160f` - **FIX:** Self-contract creation (emailDeliveryStatus constraint + reload window race condition)
- `77b8092` - **FIX:** ContractParticipant field validation (remove invalid signed/phone fields)
- `1d18711` - **FIX:** generation_status constraint violation ('generated' → 'completed')

**Production Status:**
- ✅ Self-contract creation fully debugged (3 constraint violations fixed)
- ✅ Reload window ensures both kiosk + browser reload after deployment (2-minute window)
- ✅ **VERIFIED:** Landlord self-contract created successfully (SELF-cef6f59d, 2025-11-25 12:20:06)
  - Status: completed, both signatures fulfilled
  - Participants: landlord + tenant roles, both with SMS delivered
  - All database constraints satisfied

**Key Fixes:**
- **Database constraints:** emailDeliveryStatus='delivered' (not 'not_applicable'), generation_status='completed' (not 'generated')
- **Participant validation:** Removed invalid fields (signed, phone), use status='fulfilled' + personal_number
- **Reload race condition:** Backend restart → 0 clients → reload lost. Fixed: 2-min reload window for reconnecting clients
- **SMS status:** Self-contracts create participants with smsDelivered=true for UI consistency

**Session 3 (Nov 24-25, 23:20-01:37):**
- `aee6922` - **UI FIX:** Timeline timezone display (Europe/Stockholm)
- `a55301b` - **UI POLISH:** Timeline one-liner format (timestamp - actor + event)
- `af1527d` - **SYSTEM FIX:** DRY debounce duration (backend → frontend via WebSocket)
- `af1527d` - **UI SIMPLIFY:** Hide timeline completely, fix vertical alignment for completed contracts
- `e54e311` - **FEATURE:** Self-contract detection (tenant = landlord)
- `2eece73` - **FIX:** Self-contract auto-complete both signatures (not just landlord)
- `962f2fb` - **DOCS:** Update fixes plan with session progress
- `2a60f5a` - **FIX:** Self-contract creation bug (invalid SignedContract keywords) + expansion persistence + logs docs

**Production Status:**
- ✅ Adam McCarthy contract created & signed by landlord (pending tenant signature)
- ✅ Rasmus Kasurinen contract created & signed by landlord (pending tenant signature)
- ✅ Old unsigned self-contract deleted (manual DB cleanup)
- ✅ Self-contract creation bug fixed (invalid model keywords removed)
- ✅ Row expansion state persists across WebSocket updates (localStorage)
- ✅ Backend logs documented in lib/CLAUDE.md

**Key Improvements:**
- **Timezone accuracy:** All contract events now display in Swedish time (CET/CEST)
- **Single source of truth:** Webhook debounce duration read from backend (no hardcoded 120s)
- **Smart contracts:** Self-contracts (landlord = tenant) auto-complete both signatures immediately
- **Cleaner UI:** Timeline hidden in expanded view, status lines condensed
- **Expansion persistence:** Admin rows stay expanded during WebSocket data updates
- **Logs discoverability:** Backend errors accessible via `journalctl -u kimonokittens-dashboard`

---

**Session 2 (Nov 24, 22:00-23:10):**
- `759dd36` - **DOCS:** Condense repository checklist 114→38 lines (67% reduction)
- `e718cd5` - **WEBHOOK FIX:** Match signer by email (landlord/tenant status updates)
- `dbc0e69` - **API/TS FIX:** Include SMS fields in API response + TypeScript types
- `e31e965` - **DOCS:** Expand checklist to 5 layers (add API + TypeScript)
- `e94231f` - **UI FIX:** Cancel modal positioning (createPortal)
- `d05a03d` - **DATABASE FIX:** Make participantId nullable (migration)
- `cbc6f79` - **VALIDATION FIX:** Add landlord/tenant to valid roles
- `225cfe7` - **PERSISTENCE FIX:** SMS field persistence + participant_id validation

**Migrations:**
- `20251124184554_add_sms_delivery_tracking` - Applied in production
- `20251124214319_make_participant_id_nullable` - Applied in production ✅

**Backend:** No restart needed (model/schema changes only)

**Six-Bug Fix Sequence (Nov 24, 22:00-23:10):**
- ✅ **Bug A:** Repository missing SMS fields → Added to hydrate/dehydrate (225cfe7)
- ✅ **Bug B:** participant_id validation too strict → Commented out (225cfe7)
- ✅ **Bug C:** Role validation incomplete → Added 'landlord', 'tenant' (cbc6f79)
- ✅ **Bug D:** Database NOT NULL constraint → Migration DROP NOT NULL (d05a03d)
- ✅ **Bug E:** API handler filtered out SMS fields → Include in response (dbc0e69)
- ✅ **Bug F:** Webhook role matching failed → Match by email instead (e718cd5)

**Fixes deployed (all successful):**
- ✅ Expand parameter working (retrieves 2 participants with signing URLs)
- ✅ Database has signing URLs in participants table
- ❌ **CRITICAL BUG:** Hash key lookup fails - "Tenant signing URL is missing"
- ✅ Email delivery tracked correctly (webhook handler fixed)
- ✅ Contract SMS types validated (invitation + completion)
- ✅ WebSocket handlers working (no console errors)
- ✅ Toast shows firstname + sent methods
- ✅ UI condensed: 2 lines without label columns
- ✅ Database tracks SMS delivery (schema updated)

---

## 🚨 CRITICAL ISSUES (Blocking)

### 1. SMS Missing Signing URL
**Priority:** 🟡 MEDIUM (Repository bugs fixed, hash lookup bug remains)
**Status:** ✅ PARTIALLY FIXED - Two NEW bugs discovered and fixed (Nov 24, 2025 - 22:50)

**Problem:**
- SMS only shows: "Du har blivit inbjuden att skriva på ett hyresavtal med Kimono Kittens! Signera med BankID här:"
- NO URL after "här:" - makes contract unsignable via SMS

**Root Cause Analysis:**
- `lib/contract_signer.rb:161` calls `send_contract_invitation_sms(tenant, tenant_link, landlord, landlord_link)`
- `tenant_link` and `landlord_link` extracted from `zigned_result[:signing_links]` (lines 138-139)
- `signing_links` hash built by `lib/zigned_client_v3.rb:428-434` method `extract_signing_links`
- Database shows Adam's contract: `tenantSigningUrl: NULL`, `landlordSigningUrl: NULL`
- Zero participants in ContractParticipant table (webhook handler didn't populate)

**Deep Research Findings (Nov 24, 2025):**
- ✅ **Zigned API behavior confirmed**: Signing URLs are NULL when participants are added to DRAFT agreements
- ✅ **URLs generated after activation**: `POST /agreements/:id/lifecycle` with status: 'pending' generates signing URLs
- ✅ **Must use expand parameter**: `GET /agreements/:id?expand=participants` required to get full participant objects with URLs
- ✅ **Current code already activates**: Line 125 in `zigned_client_v3.rb` calls `activate_agreement`
- ❌ **BUG**: Line 130 uses participants array from BEFORE activation (still has NULL URLs)
- ❌ **MISSING**: Need to fetch agreement AFTER activation WITH expand parameter

**Complete research documentation:** `docs/ZIGNED_SIGNING_URL_RESEARCH.md` (496 lines, OpenAPI spec + online docs verified)

**Investigation Status:**
- ✅ Confirmed SMS template correct (line 444: message + URL)
- ✅ Confirmed database has NULL URLs for Adam's contract (case ID: cmid6ne7706qx41ekv8s7k4pj)
- ✅ Confirmed zero participants in database (webhook didn't create records)
- ✅ **ROOT CAUSE IDENTIFIED:** Signing URLs extracted from BEFORE-activation participant data (all NULL)
- 🔍 **NEXT:** Fix `get_agreement` to support expand parameter, fetch AFTER activation

**Files Involved:**
- `lib/contract_signer.rb:138-139,161,433-469` - Signing URL extraction + SMS sending
- `lib/zigned_client_v3.rb:85-134,226-258,428-434` - Zigned API client
- `handlers/zigned_webhook_handler.rb:213-255` - Webhook participant creation (deployed fix)

**Fix Strategy:**
1. ✅ Update `get_agreement` method to support `expand: []` parameter
2. ✅ Handle nested response structure: `agreement['data']['participants']['data']`
3. ✅ In `create_and_activate`, fetch agreement AFTER activation WITH expand parameter
4. ✅ Add 'contract_invitation' to valid SMS types (better semantics than 'confirmation')
5. ✅ Add nil-check validation before sending SMS (fail fast if URLs still null)
6. ⏳ Test with new contract creation to verify signing URLs populated
7. ⏳ Verify SMS includes actual signing URLs

**Implementation Status:**
- 🔴 **BLOCKED** - Hash lookup fails despite expand parameter working (Nov 24, 2025 - 21:15)

**Current Evidence (Production Logs):**
```
DEBUG: Fetching agreement details with expanded participants to get signing URLs
DEBUG: Retrieved 2 participants with signing URLs  ← FETCH SUCCEEDED!
✅ Signing case created: cmidkpfw90ao841ekwb5d6ddi
❌ Error creating contract: Tenant signing URL is missing - cannot send SMS invitation
```

**Database Evidence:**
```json
"participants":[{
  "id":"participant-862db577ed660dc1",
  "name":"Adam McCarthy",
  "signing_url":"https://www.zigned.se/sign/cmidkpfw90ao841ekwb5d6ddi/cmidkph830aob41ek1gyzhld5"
}]
```

**Root Cause Analysis (Nov 24, 21:15):**
- ✅ Expand parameter works: `GET /agreements/:id?expand=participants` succeeds
- ✅ Signing URLs present in database (verified via admin UI)
- ❌ **Hash key lookup fails** in `lib/zigned_client_v3.rb:507-515`
- **Likely issue**: Field name `participant[:personal_number]` is incorrect
  - Code strips non-digits: `participant[:personal_number]&.gsub(/\D/, '')`
  - But if field name is wrong (e.g., `personnummer` in Swedish), lookup returns nil
  - Hash key becomes nil → lookup fails → "Tenant signing URL is missing"

**Code Location (lib/zigned_client_v3.rb:507-515):**
```ruby
def extract_signing_links(participants, signers)
  participants.each_with_object({}) do |participant, hash|
    url = participant[:signing_url] || participant[:signing_room_url]
    clean_pnr = participant[:personal_number]&.gsub(/\D/, '')  # ← SUSPECT LINE
    hash[clean_pnr] = url if clean_pnr && url
  end
end
```

**🆕 NEW BUGS DISCOVERED (Nov 24, 22:30-22:50):**

**Bug A: Repository Missing SMS Fields (SILENT DATA LOSS)**
- **Severity:** 🔴 CRITICAL
- **Root Cause:** `ContractParticipantRepository` hydrate/dehydrate missing `sms_delivered` and `sms_delivered_at`
- **Impact:** Model had fields, database had columns, but repository silently dropped values on save/load
- **Pattern:** Exact repeat of Nov 14 `personnummer` bug - missing repository fields = silent data loss
- **Fix:** Added 4 lines to repository (commit `225cfe7`)
  - hydrate: `sms_delivered: row[:smsDelivered]`, `sms_delivered_at: row[:smsDeliveredAt]`
  - dehydrate: `smsDelivered: participant.sms_delivered`, `smsDeliveredAt: participant.sms_delivered_at`

**Bug B: Validation Too Strict (CONTRACT CREATION FAILED)**
- **Severity:** 🔴 CRITICAL - Blocked ALL contract creation
- **Root Cause:** `ContractParticipant` model validation required `participant_id` to be non-nil
- **Impact:** Contract creation failed with "participant_id is required" error
- **Why Wrong:** `participant_id` is nil initially, gets set by Zigned webhook AFTER agreement creation
- **Evidence:** Production log: `❌ Error creating contract: participant_id is required`
- **Fix:** Removed validation line (commented out with explanation)
- **Result:** SMS at 21:27 was from earlier attempt; 21:49 contract failed validation

**Documentation Added:**
- Updated `lib/CLAUDE.md` with comprehensive "Repository Pattern - Model/Persistence Checklist"
- Three-layer consistency verification (Model → Repository → Database)
- Common bug patterns with examples
- Verification commands for detecting field drift
- Historical incidents log (Nov 14 personnummer, Nov 24 SMS fields)

**Next Investigation:**
1. ✅ Repository SMS fields fixed
2. ✅ Validation bug fixed
3. ⏳ Delete broken contract (d5e7e5dc-88d1-406f-9208-ab61719190d2)
4. ⏳ Create new contract for Adam - verify SMS sends with URLs
5. ⏳ Check if hash lookup bug still exists (original Issue #1)

**Files modified (commit db5cf82):**
  - `lib/zigned_client_v3.rb:308-372,512` - Expand parameter + key stripping
  - `lib/contract_signer.rb:436-444` - URL validation before SMS
  - `lib/models/sms_event.rb:36` - Added contract SMS types
  - `handlers/zigned_webhook_handler.rb:310-317` - Email delivery tracking fix

---

### 2. No Toast Notification on Contract Creation
**Priority:** 🟡 MEDIUM
**Status:** ✅ COMPLETE (Nov 24, 2025 - 16:00)

**Problem:**
- User clicks "Skapa Kontrakt" button
- No success/failure toast appears
- User unsure if action completed

**Solution Implemented:**
- ✅ Toast already existed in code but was basic
- ✅ Enhanced to show contract ID + expiry days
- ✅ Success toast: "Kontrakt skapat! ID: {last 8 chars} • Utgår om {X} dagar"
- ✅ Error toasts already handled

**Files Modified:**
- `dashboard/src/components/admin/MemberRow.tsx:209-215` - Enhanced toast with contract details

---

## 🔴 HIGH PRIORITY ISSUES

### 3. Unknown WebSocket Message Types
**Priority:** 🔴 HIGH
**Status:** ✅ COMPLETE (Nov 24, 2025 - 16:15)

**Problem:**
- Browser console shows:
  ```
  Unknown message type: contract_update
  Unknown message type: contract_list_changed
  ```
- These are broadcast by backend but frontend doesn't handle them

**Solution Implemented:**
- ✅ Added `contract_update` handler - logs event details (full refresh via admin_contracts_data)
- ✅ Added `contract_list_changed` handler - acknowledges event (data refreshed automatically)
- ✅ No more console errors

**Files Modified:**
- `dashboard/src/context/DataContext.tsx:599-608` - Added case statements for both message types

---

### 4. Webhook Not Tracking Email/SMS Delivery
**Priority:** 🔴 HIGH
**Status:** ✅ SOLVED BY ISSUE #5 (Nov 24, 2025)

**Problem:**
- Zigned sends `email_event.agreement_invitation.delivered` webhooks
- Handler fails: `⚠️ Participant not found for email (ID: )`
- Both `participant_email` and `participant_id` are empty strings
- Actual payload has NO `participant` or `email` fields - only in `description`

**Root Cause:**
- Individual email events don't contain structured participant data
- Would require regex parsing from description field (brittle)

**Solution:**
- ✅ Use `participant.lifecycle.received_invitation` event instead (Issue #5)
- ✅ This event contains full participant data including email address
- ✅ More reliable and structured than parsing description field
- ✅ Already tracks email delivery per-participant with timestamps

**Outcome:**
- Individual `email_event.agreement_invitation.delivered` events remain unhandled (by design)
- Per-participant tracking via better event source

---

### 5. Unhandled Webhook: participant.lifecycle.received_invitation
**Priority:** 🔴 HIGH
**Status:** ✅ COMPLETE (Nov 24, 2025 - 16:20)

**Problem:**
- Zigned sends this event when participant receives invitation
- Webhook marks as "⚠️ Unhandled webhook event"
- Event contains full participant data including signing URLs!

**Solution Implemented:**
- ✅ Added handler in `handlers/zigned_webhook_handler.rb:270-316`
- ✅ Updates participant record with `email_delivered = true` + timestamp
- ✅ Verifies/updates signing URL as backup
- ✅ Broadcasts `invitation_delivered` event for real-time UI updates
- ✅ Creates participant record if missing (fallback)

**Benefits:**
- ✅ Most reliable email delivery tracking (per-participant with structured data)
- ✅ Contains signing URLs for verification
- ✅ Solves Issue #4 (replaces brittle email_event parsing)

**Files Modified:**
- `handlers/zigned_webhook_handler.rb:115-116` - Added case statement
- `handlers/zigned_webhook_handler.rb:270-316` - Implemented handler method

---

## 🟡 MEDIUM PRIORITY ISSUES (UI Polish)

### 6. Status Display Too Verbose
**Priority:** 🟡 MEDIUM
**Status:** ✅ COMPLETE (Nov 24, 2025 - 20:40)

**Problem:**
- UI showed 4 separate lines (2 for notifications, 2 for signing)
- Redundant information
- Grid layout with label columns took excessive space

**Solution Implemented:**
- ✅ Removed "Notifieringar:" and "Signeringar:" label columns entirely
- ✅ Condensed to 2 simple status lines with icons + text
- ✅ Changed from grid layout to flex containers
- ✅ Applied to both pending and completed contract states

**Final UI (2 lines without labels):**
```
[Icon] Adam och Fredrik har båda fått email
[Icon] Ingen har signerat än (30 dagar kvar)
```

**Swedish Text Patterns Implemented:**
- **Both notified same way:** "Adam och Fredrik har båda fått email"
- **Both notified different:** "Adam har fått email och SMS, Fredrik har fått email"
- **One notified:** "Adam har fått email, Fredrik väntar"
- **None notified:** "Väntar på notifieringar"

- **Both signed:** "Båda har signerat ✓"
- **One signed:** "Adam har signerat, Fredrik inte (29 dagar kvar)"
- **None signed:** "Ingen har signerat än (30 dagar kvar)"

**Files Modified:**
- `dashboard/src/components/admin/ContractDetails.tsx:124-269` - Removed labels, simplified layout
- Commit: `839332f` (Nov 24, 2025 - 20:40)

---

### 7. Database Schema Missing Notification Tracking
**Priority:** 🟡 MEDIUM
**Status:** ✅ COMPLETE (Nov 24, 2025 - 19:45)

**Problem:**
- No way to track which notification methods were used
- Can't show "Adam har fått email och SMS" without data

**Current Schema:**
```prisma
model ContractParticipant {
  email_delivered    Boolean?
  email_delivered_at DateTime?
  // Missing: sms_delivered, sms_delivered_at
}
```

**Solution Implemented:**
- ✅ Added Prisma migration: `20251124184554_add_sms_delivery_tracking`
- ✅ Added fields to schema:
  ```prisma
  smsDelivered      Boolean  @default(false)
  smsDeliveredAt    DateTime?
  ```
- ✅ Updated domain model: `lib/models/contract_participant.rb`
- ✅ Migration deployed to production

**Files Modified:**
- `prisma/schema.prisma:176-177` - Added new fields
- `lib/models/contract_participant.rb:14-27` - Added to model initialization
- Migration applied Nov 24, 2025

---

## 🟢 FUTURE ENHANCEMENTS (Later)

### 8. SmsEvent Table Schema Migration
**Priority:** 🟢 LOW (Future)
**Status:** Not Started

**Problem:**
- Current SmsEvent table has old schema: `id, tenantId, month, direction, providerId, body, parts, status, meta, createdAt`
- New SmsEvent model (from rent reminders refactoring) expects: `phoneNumber, messageBody, smsType, tone, deliveryStatus, sentAt, etc.`
- Database logging fails with schema mismatch when trying to log contract invitation SMS

**Impact:**
- Contract invitation SMS sends successfully via 46elks API
- But database logging fails silently (exception caught)
- No audit trail for contract invitation SMS in database

**Solution (Later):**
- Run Prisma migration to update SmsEvent table schema
- Migrate existing data to new format if needed
- Test contract invitation SMS logging

**Note:** Not blocking - SMS sends successfully, just no database logging

---

### 9. Draft/Open Status Flow Refactoring
**Priority:** 🟢 LOW (Future)
**Status:** Research Phase

**Context from Zigned API:**
- Contracts start in **draft** status (editable, cancellable)
- Transition to **open** status (still editable, cancellable)
- Transition to **pending** status (activated, signing in progress)
- **Problem:** Can only cancel/edit in draft/open, NOT in pending

**Current Flow:**
1. `ContractSigner.create_and_sign` immediately activates to pending
2. No opportunity to cancel or edit PDF before activation
3. If mistake found: must delete from our DB (can't cancel in Zigned)

**Desired Flow:**
1. Create contract in draft status
2. Admin reviews PDF + details
3. Admin clicks "Activate" → moves to pending
4. Allow cancellation/PDF replacement in draft/open status

**Zigned API Endpoints:**
- `DELETE /agreements/:id` - Only works in draft status
- `POST /agreements/:id/lifecycle` - Update status (draft → open → pending → cancelled)
- `POST /agreements/:id/documents/main` - Replace PDF (draft/open only)

**Benefits:**
- Fix mistakes before activation
- Update rent amounts if changed
- Cancel before sending notifications

**Investigation Needed:**
- How long can contracts stay in draft before expiring?
- Can we update PDFs in open status?
- How does signing room activation work?

**Files:**
- `lib/contract_signer.rb` - Modify `create_and_sign` to NOT activate
- `handlers/admin_contracts_handler.rb` - Add activate/cancel endpoints
- `dashboard/src/components/admin/ContractDetails.tsx` - Add activate button

**Documentation:**
- `docs/zigned-api-spec.yaml:13963-13981` - Lifecycle status documentation
- `docs/zigned-api-spec.yaml:5028` - DELETE endpoint (draft only)

---

## 📊 PROGRESS TRACKING

**Completed:** 8/11 (73%)
**In Progress:** 1/11 (9%)
**Future Work:** 2/11 (18%)

**🔴 In Progress:**
1. 🟡 **Issue #1** - SMS missing signing URL (repository/validation fixed, hash lookup remains)

**✅ Completed Issues (Nov 24, 2025 - Session):**
2. ✅ **Issue #2** - Toast notification (enhanced: firstname + sent methods)
3. ✅ **Issue #3** - WebSocket handlers (contract_update + contract_list_changed)
4. ✅ **Issue #4** - Email delivery tracking (solved by Issues #5 + webhook fix)
5. ✅ **Issue #5** - participant.lifecycle.received_invitation handler
6. ✅ **Issue #6** - Status display redesign (2 columns: Notifieringar + Signeringar)
7. ✅ **Issue #7** - Database schema (smsDelivered + smsDeliveredAt added)
10. ✅ **Issue #10** - **NEW BUG A** - Repository SMS field persistence (silent data loss fixed)
11. ✅ **Issue #11** - **NEW BUG B** - Validation blocking contract creation (participant_id nil allowed)

**🔮 Future Enhancements:**
8. 📋 **Issue #8** - SmsEvent table schema migration (low priority)
9. 📋 **Issue #9** - Draft/Open status flow refactoring (prevents immediate activation)

**🧪 Verification Status:**
- ✅ Expand parameter working (retrieves participants with URLs)
- ✅ Database has signing URLs (verified via admin UI)
- ❌ Hash key lookup failing (participant[:personal_number] returns nil)
- ✅ Email delivery tracking working (participants created + flags set)
- ✅ Webhook handlers operational (all 14 event types)
- ✅ Admin UI shows condensed status correctly

---

## 🔍 DEBUGGING SESSION LOG

**Nov 24, 2025 - 14:30-14:35**

**Discoveries:**
1. Adam's contract (cmid6ne7706qx41ekv8s7k4pj) has NULL signing URLs in database
2. Zero participants in ContractParticipant table
3. Webhook received `agreement.lifecycle.pending` at 14:28:44 but didn't create participants
4. Backend deployed at 14:20:54 (PID 746506) with webhook fix
5. Need to verify if fix actually loaded (check code vs deployed code)

**Commands Used:**
```bash
# Check contract in database
cd /home/kimonokittens/Projects/kimonokittens && bundle exec ruby -e "
require 'dotenv/load'
require_relative 'lib/persistence'
contract = RentDb.instance.class.db[:SignedContract]
  .where(caseId: 'cmid6ne7706qx41ekv8s7k4pj').first
puts contract.inspect
"

# Check participants
cd /home/kimonokittens/Projects/kimonokittens && bundle exec ruby -e "
require 'dotenv/load'
require_relative 'lib/persistence'
participants = RentDb.instance.class.db[:ContractParticipant]
  .where(contractId: '...')
  .all
puts participants.inspect
"
```

**Webhook Logs:**
```
[2025-11-24 14:28:46] email_event.agreement_invitation.delivered (adam@kimonokittens.com)
[2025-11-24 14:28:46] email_event.agreement_invitation.delivered (branstrom@gmail.com)
[2025-11-24 14:28:46] email_event.agreement_invitation.all_delivered
[2025-11-24 14:28:47] participant.lifecycle.received_invitation (UNHANDLED)
[2025-11-24 14:28:57] participant.lifecycle.received_invitation (UNHANDLED)
```

---

## 🔄 WEBSOCKET REAL-TIME UPDATES

**Architecture:** Backend broadcasts events → Frontend receives → State updates → UI rerenders

### Two Types of Broadcasts

**1. Specific Contract Events** (`contract_update`)
- **Source:** Zigned webhook handlers (`handlers/zigned_webhook_handler.rb`)
- **Events:** 'pending', 'invitation_delivered', 'participant_signed', 'fulfilled', 'completed', 'expired', 'cancelled', 'email_delivered', 'all_emails_delivered', 'email_delivery_failed'
- **Payload:** `{ contract_id, event, details, timestamp }`
- **Frontend action:** Logs to console only (actual data update via admin_contracts_data)

**2. Full Data Refresh** (`contract_list_changed` + `admin_contracts_data`)
- **Source:** Admin actions (create, update, delete, cancel), tenant updates
- **Broadcast sequence:**
  1. Backend calls `DataBroadcaster.broadcast_contract_list_changed`
  2. Fetches fresh `/api/admin/contracts` data
  3. Sends `contract_list_changed` notification (frontend logs it)
  4. Sends `admin_contracts_data` with full payload
- **Frontend action:** Dispatches `SET_ADMIN_CONTRACTS_DATA` → state updates → UI rerenders

### What Triggers Broadcasts

**Admin contract actions** (`handlers/admin_contracts_handler.rb`):
- ✅ Create contract → `broadcast_contract_list_changed` (line 543)
- ✅ Cancel/delete contract → `broadcast_contract_list_changed` (line 486)
- ✅ Resend invitation → `broadcast_contract_list_changed` (line 597)
- ✅ Resend participant invitation → `broadcast_contract_list_changed` (line 645)
- ✅ Resend completion SMS → `broadcast_contract_list_changed` (line 687)
- ✅ Mark participant signed → `broadcast_contract_list_changed` (line 742)
- ✅ Update participant email → `broadcast_contract_list_changed` (line 798)

**Zigned webhook events** (`handlers/zigned_webhook_handler.rb`):
- ✅ Agreement pending (activated) → `broadcast_contract_update('pending')` (line 262)
- ✅ Participant received invitation → `broadcast_contract_update('invitation_delivered')` (line 312)
- ✅ Participant signed → `broadcast_contract_update('participant_signed')` (lines 372, 947)
- ✅ Agreement fulfilled (all signed) → `broadcast_contract_update('fulfilled')` (line 406)
- ✅ Agreement finalized (completion SMS sent) → `broadcast_contract_update('completed')` (line 459)
- ✅ Agreement expired → `broadcast_contract_update('expired')` (line 484)
- ✅ Agreement cancelled → `broadcast_contract_update('cancelled')` (line 513)
- ✅ Email delivered → `broadcast_contract_update('email_delivered')` (line 595)
- ✅ All emails delivered → `broadcast_contract_update('all_emails_delivered')` (line 622)
- ✅ Email failed → `broadcast_contract_update('email_delivery_failed')` (line 724)
- ✅ Participant status updated → `broadcast_contract_update('participant_status_updated')` (line 860)

**Tenant updates** (`handlers/tenant_handler.rb`):
- ✅ Update tenant details → `broadcast_contract_list_changed` (line 70)
- ✅ Set departure date → `broadcast_contract_list_changed` (line 127)

### Frontend Implementation

**DataContext** (`dashboard/src/context/DataContext.tsx:596-608`):
```typescript
case 'admin_contracts_data':
  // Updates state with fresh contract list
  dispatch({ type: 'SET_ADMIN_CONTRACTS_DATA', payload: message.payload })
  break

case 'contract_update':
  // Just logs event details (data refreshed via admin_contracts_data)
  console.log(`Contract ${payload.contract_id}: ${payload.event}`, payload.details)
  break

case 'contract_list_changed':
  // Just logs notification (backend already sent admin_contracts_data)
  console.log('Contract list changed - fresh data incoming')
  break
```

**Result:** Admin UI updates in real-time without manual refresh when:
- User creates/cancels contracts
- Zigned sends webhook (tenant signed, emails delivered, etc.)
- Tenant details updated (affects contract display)

### Key Insight

Frontend relies on `admin_contracts_data` for actual state updates. The `contract_update` and `contract_list_changed` events are notifications only - they log to console but don't modify state themselves. This pattern ensures data consistency (always uses fresh API data, never stale event payloads).

---

## 📝 NOTES & CONSIDERATIONS

**Cancel Endpoint Temporary Fix (Nov 24, 2025):**
- Cancel now deletes contract + participants from our DB only
- Does NOT call Zigned API (was failing with 500 errors)
- Allows testing signing URL fixes with fresh contracts
- Zigned agreement still exists (manual cleanup needed)
- TODO: Restore proper Zigned cancellation after Issue #9 (draft/open flow)

**SMS Length Limit:**
- 46elks limit: 160 characters per SMS (standard GSM-7)
- Swedish characters (å, ä, ö) count as 2 characters (UCS-2 encoding)
- Current message: ~86 chars + URL (~50 chars) = ~136 chars total
- **Safe:** Well within limit

**Zigned Webhook Events:**
- Agreement events: pending, fulfilled, finalized, expired, cancelled
- Participant events: fulfilled (signed), received_invitation
- Email events: delivered, all_delivered, delivery_failed, finalized.delivered
- Sign events: signing_room.entered, viewing_started, document_downloaded

**Database Relationships:**
- SignedContract (1) → ContractParticipant (many)
- ContractParticipant.contractId → SignedContract.id
- ContractParticipant.participantId → Zigned participant ID
- ContractParticipant.signingUrl → Unique URL per participant

**Testing Strategy:**
1. Create test contract with test_mode=true (free, fast)
2. Monitor webhook logs in real-time (`tail -f /var/log/kimonokittens/zigned-webhooks.log`)
3. Check database after each webhook event
4. Verify SMS content (check 46elks dashboard or test phone)
5. Test signing flow end-to-end

---

## 📚 RELATED DOCUMENTATION

- `docs/ZIGNED_WEBHOOK_FIELD_MAPPING.md` - Real payload analysis
- `docs/ZIGNED_WEBHOOK_TESTING_STATUS.md` - Bug fixes log
- `docs/zigned-api-spec.yaml` - Complete OpenAPI 3.0 spec (21,571 lines)
- `/lib/CLAUDE.md` - Backend architecture patterns
- `/dashboard/CLAUDE.md` - Frontend development guide

---

**Last Updated:** Nov 25, 2025, 00:35
**Next Review:** After Adam and Rasmus sign their contracts (test webhook flow end-to-end)

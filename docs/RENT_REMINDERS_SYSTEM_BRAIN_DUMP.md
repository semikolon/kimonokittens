# Rent Reminders & Payment Automation System - Complete Brain Dump
**Date**: November 14, 2025
**Session Context**: Complete exploration of codebase for rent payment automation system

---

## USER REQUIREMENTS & PREFERENCES

### Primary Goal (from user messages)
User wants to implement automated rent reminders system integrated into current admin dashboard.

### Key User Decisions So Far

**Bank Integration Choice**:
- **PREFERENCE**: Lunch Flow API (not BankBuster)
- **REASON**: "I think it's not requiring me to use bankid to sign in every time it fetches new transactions"
- **STATUS**: User needs to verify Lunch Flow authentication model via online research
- **NOTE**: User has NOT signed up for 46elks yet (SMS provider)

**Approach to GPT-5 Prompt**:
- User does NOT want to blindly accept GPT-5's detailed specifications
- Wants freedom to endorse or tweak the details
- Prefers Socratic question-by-question refinement
- Quote: "Let's not necessarily start entirely from scratch - I just want the freedom to endorse or tweak the details"

### SMS Provider Status
- **46elks**: User mentioned but has NOT signed up yet
- User said: "I also need to sign up for an account for the 46elks or whatever it is called, before anything requiring that integration to be ready/tested"
- **BLOCKER**: Cannot test/implement SMS features until 46elks account created

---

## GPT-5 PROMPT - COMPLETE VERBATIM TEXT

```
Scan the repo deeply (Ruby backend, React dashboard, Node-RED, etc.). Specifically inspect: `rent.rb`, `rent_history.rb`, `calculate_monthly_rent.rb`, `detailed_breakdown.rb`, `puma_server.rb`, everything under `handlers/`, `bank_payments_reader.rb`, `bankbuster/`, `www/`, `deployment/`, `systemd` files, and any DB access (`prisma/`, `lib/*`, `config.ru`, `Gemfile`). Confirm the existence and shape of **RentLedger** and a **Tenant** table. Do NOT introduce YAML for people/config; persist per-tenant SMS/payday metadata in Postgres.

**Goal (Phase-1):** Hourly bank sync via Lunch Flow REST API; automatic reconciliation against RentLedger; daily SMS reminders via 46elks only to tenants still unpaid; friendly short messages (template-first with optional LLM); Swish deep-link on mobile and QR fallback on desktop; admin SMS when a payment is detected. No tenant "mark paid" flow—paid state derives from reconciliation.

---

### 0) DB model (migrations)
- **tenants**: add columns if missing
  - `phone_e164` text not null
  - `swish_number` text
  - `payday_start_day` integer default 25
  - `sms_opt_out` boolean default false
  - `sms_tone` text default 'gentle-quirky'
  - `lang` text default 'sv'
- **bank_transactions**
  - `id` PK
  - `external_id` text UNIQUE (Lunch Flow's id)
  - `account_id` text
  - `booked_at` timestamptz
  - `amount` numeric(12,2)
  - `currency` text
  - `description` text
  - `counterparty` text
  - `raw_json` jsonb
  - `created_at` timestamptz default now()
- **rent_receipts** (matches transactions to tenant-month)
  - `id` PK
  - `month` text (YYYY-MM)
  - `tenant_id` FK tenants(id)
  - `amount` numeric(12,2)
  - `matched_tx_id` FK bank_transactions(id) nullable
  - `matched_via` text CHECK in ('reference','amount+name','manual')
  - `paid_at` timestamptz
  - `partial` boolean default false
- **sms_events** (operational log; not money)
  - `id` PK
  - `tenant_id` FK
  - `month` text
  - `direction` text CHECK in ('out','in','dlr')
  - `provider_id` text  -- 46elks message id
  - `body` text
  - `parts` int
  - `status` text
  - `meta` jsonb
  - `created_at` timestamptz default now()

If there is an existing DB utility in the repo, reuse it; else add minimal PG access (`pg` gem) with small query helpers under `lib/db.rb`.

---

### 1) Lunch Flow bank sync (hourly)
- `lib/banking/lunchflow_client.rb` (stdlib `Net::HTTP`):
  - Auth: `Authorization: Bearer $LUNCHFLOW_API_KEY`
  - Endpoints: `/api/v1/accounts`, `/api/v1/transactions?since=<cursor>` (or paginate if needed)
  - Robust retry/backoff; normalize ISO8601 times → `booked_at`
- `bin/bank_sync`:
  - Read last cursor from `state/bank_sync.json` **or** a `kv_state` table.
  - UPSERT into `bank_transactions` by `external_id`.
  - Update cursor.

`systemd/bank-sync.service` + `.timer` (hourly, :05). Add install instructions to README.

---

### 2) Reconciliation (against RentLedger)
- Implement `lib/rent/current_month.rb` (or extend existing small API) to expose for current month:
  - `[{ tenant_id, name, amount_due, message_ref, breakdown }]`
  - **message_ref** must be stable/unique, e.g. `KK-<YYYY-MM>-<TENANTID>` (fits in Swish message).
- For each tenant with remaining amount:
  - **Match order**:
    1) **reference**: `bank_transactions.description` contains `message_ref`
    2) **amount+name**: `abs(amount) == remainder_due` (±1 SEK tolerance) AND fuzzy match on `counterparty ~ tenant.name`
    3) **partial**: if a tx `< remainder_due`, create a `rent_receipts` partial row and reduce remainder
  - When sum(receipts) ≥ amount_due ⇒ mark tenant-month as **paid** (derived, not stored); set `paid_at` = latest matched tx `booked_at`.
- On any new match (full or partial) send **admin SMS** to me (phone in env or a Settings table) with a short summary.

Expose a tiny read API:
- `GET /api/rent/status?month=YYYY-MM` → each tenant: {due, paid, remaining, last_tx, last_reminder_at}

---

### 3) Swish deep link (no Commerce API)
- `lib/swish/link.rb` → `prefill_url(tenant, amount, message_ref)` returns `https://<host>/swish.html#<b64({p,a,m,ref,tenant,month})>`
- `www/swish.html` (static):
  - On load: `fetch('/swish/track?token=…')` to log `swish_clicked`
  - Try `window.location = "swish://payment?..."` (app prefill). If it fails, show QR + copyable details.
- `handlers/swish_tracking.rb`: `GET /swish/track?token=…` → append `sms_events` with `direction='out'` + `meta.clicked=true` (never marks paid).

---

### 4) 46elks SMS (provider abstraction)
- `lib/sms/gateway.rb` iface; `lib/sms/elks_client.rb` implements `send(to:, body:, meta:)` via `POST https://api.46elks.com/a1/sms` (Basic Auth `ELKS_USERNAME/PASSWORD`), with `whendelivered` to our DLR endpoint.
- `handlers/elks_webhooks.rb`:
  - `POST /webhooks/elks/sms` (incoming):
    - Log to `sms_events` (`direction='in'`).
    - Support helpful commands only (we don't use replies for paid state):
      - `status` → remaining for current month + link + `message_ref`
      - `help` / `iban` / `ref` → short answers
      - Otherwise: pass to optional LLM for a brief friendly line (≤140 chars). If no API key, use templates.
    - Reply **inline** in webhook body (46elks pattern) so no extra API call.
  - `POST /webhooks/elks/dlr`:
    - Update `sms_events.status` and `parts`.
- Keep SMS messages short (<160 chars + link). Store returned `provider_id` for idempotency.

---

### 5) Daily reminders (payday-aware, only if unpaid)
- `bin/rent_reminders`:
  - Today's month → from RentLedger.
  - For each tenant where:
    - `today >= (tenant.payday_start_day || 25)`
    - `sms_opt_out = false`
    - **not paid** (per reconciliation)
  - Compose message (ERB template first, optional LLM personality from `sms_tone/lang`), include: total due, electricity share if available, **Swish link**, and **message_ref**.
  - Send via gateway; insert `sms_events` with `direction='out'`.
  - Idempotent per (tenant, month, date): don't double-send for the same day.

`systemd/rent-reminders.service` + `.timer` (daily 10:00 Europe/Stockholm).

---

### 6) Admin & ops
- Admin SMS on new matches (`<name> paid <X> kr for <YYYY-MM> (remaining <R> kr). Ref <ref>.`).
- `.env.example`: `ELKS_USERNAME`, `ELKS_PASSWORD`, `LUNCHFLOW_API_KEY`, `ADMIN_PHONE`, optional `OPENAI_API_KEY`.
- Webhooks: require shared secret header; verify 46elks DLR source if feasible.
- `Makefile`:
  - `make bank:sync` / `make bank:dry`
  - `make reminders:dry` / `make reminders:send`
  - `make webhook:serve`
- Update `puma_server.rb` to mount:
  - `POST /webhooks/elks/sms`
  - `POST /webhooks/elks/dlr`
  - `GET  /swish/track`
  - Serve `www/swish.html` statically

---

### 7) Tests
- Matching: reference, amount+name, partials; edge cases: rounding, multiple partials.
- Phone normalization; SMS length budgeting.
- Idempotency: `external_id` (bank), `provider_id` (SMS), day-level reminder guard.
- Swish link encode/decode roundtrip.

---

### 8) Copy (SV default; concise)
- Reminder: `Hej <%= name %>! Hyra <%= month %>: <%= amount %> kr (el inkl.). Betala smidigast här: <%= swish_url %>. Ref: <%= ref %>. Tack! —Kollektivet`
- Status reply: `Hyra <%= month %>: <%= remaining %> kr kvar. Ref: <%= ref %>. Länk: <%= swish_url %>`

---

### Acceptance
- Hourly bank sync persists new transactions and reconciliation attaches them to tenant-month records.
- A tenant stops receiving reminders as soon as reconciliation shows fully paid.
- Admin gets an SMS when a payment/partial is matched.
- All people/config live in **tenants** (Postgres), not YAML.
- Dry-run commands print who would be reminded and show the composed messages.
- No usage of the term "invoice" anywhere in code or copy.
```

---

## CODEBASE EXPLORATION - COMPLETE FINDINGS

### Database Architecture (Subagent 1: Database Schema)

**Database Platform**: PostgreSQL (production: `kimonokittens_production`, test: `kimonokittens_test`)

**Location**: `prisma/schema.prisma`

#### Existing Models Relevant to Payment Tracking

**1. RentLedger** - Immutable Financial Audit Trail
```prisma
model RentLedger {
  id               String    @id
  tenantId         String
  period           DateTime  # Month start (UTC)
  amountDue        Float
  amountPaid       Float     # ← PAYMENT TRACKING FIELD
  paymentDate      DateTime? # ← PAYMENT CONFIRMATION FIELD
  daysStayed       Float?
  roomAdjustment   Float?
  baseMonthlyRent  Float?
  calculationTitle String?
  calculationDate  DateTime?
  createdAt        DateTime  @default(now())
  Tenant           Tenant    @relation(fields: [tenantId], references: [id])
}
```

**Domain Model Methods** (`lib/models/rent_ledger.rb`):
- `paid?` → `amount_paid >= amount_due`
- `partially_paid?` → `0 < amount_paid < amount_due`
- `outstanding` → `amount_due - amount_paid`
- `payment_status` → Returns "paid", "partially_paid", "unpaid"

**Repository Methods** (`lib/repositories/rent_ledger_repository.rb`):
- `find_unpaid_by_tenant(tenant_id)` - Get all unpaid/partial entries
- `record_payment(ledger_id, amount_paid, payment_date)` - **Update payment info** ← EXISTS BUT NO CALLER
- `find_by_tenant_and_period(tenant_id, period)` - Get specific entry

**CRITICAL FINDING**: Payment tracking fields exist (`amountPaid`, `paymentDate`) and repository has `record_payment()` method, but **NO CODE CALLS THIS METHOD**. All payments currently show as "unpaid".

**2. Tenant** - Household Members
```prisma
model Tenant {
  id                String    @id
  name              String
  email             String    @unique
  phone             String?   # ← EXISTS for SMS
  personnummer      String?   # ← EXISTS
  facebookId        String?   @unique
  avatarUrl         String?
  room              String?
  roomAdjustment    Float?
  startDate         DateTime?
  departureDate     DateTime?
  status            String    @default("active")
  deposit           Decimal?
  furnishingDeposit Decimal?
  baseRent          Decimal?
  createdAt         DateTime
  updatedAt         DateTime
}
```

**Key Fields for Payment System**:
- `phone` - EXISTS (nullable) - needs E.164 format validation
- `personnummer` - EXISTS (nullable)
- No `phone_e164`, `swish_number`, `payday_start_day`, `sms_opt_out`, `sms_tone`, `lang` fields yet (GPT-5 proposes adding these)

**3. RentConfig** - Monthly Configuration
```prisma
model RentConfig {
  id           String   @id
  key          String   # "el", "drift_rakning", "vattenavgift"
  value        String
  period       DateTime
  isProjection Boolean
  createdAt    DateTime
  updatedAt    DateTime
}
```
**Unique constraint**: `[key, period]`

**4. ElectricityBill** - Raw Bill Data
```prisma
model ElectricityBill {
  id          String   @id
  provider    String   # "Vattenfall", "Fortum"
  billDate    DateTime
  amount      Float
  billPeriod  DateTime
  createdAt   DateTime
  updatedAt   DateTime
}
```

**Service Integration**: `ApplyElectricityBill` - Orchestrates bill storage → aggregation → RentConfig update (WORKING MODEL FOR PAYMENT INTEGRATION)

**MISSING TABLES** (proposed by GPT-5):
- ❌ `bank_transactions` - Would store Lunch Flow transactions
- ❌ `rent_receipts` - Would link transactions to RentLedger entries
- ❌ `sms_events` - Would log all SMS activity

---

### Rent Calculation & API Layer (Subagent 2: Handlers)

**Primary API Handler**: `handlers/rent_calculator_handler.rb`

**Key Endpoints**:
1. **GET /api/rent/friendly_message** (lines 549-625)
   - Current month rent with Swedish formatting
   - Returns: `{message, year, month, data_source, electricity_amount, heating_cost_line, quarterly_invoice_projection, virtual_pot}`
   - Query params: `?year=YYYY&month=MM` (defaults to current)
   - **IMPORTANT**: Config month = current month, but message shows NEXT month's rent (advance payment)

2. **PUT /api/rent/config** (lines 213-347)
   - Update config values
   - Triggers WebSocket broadcast via `$pubsub.publish('rent_data_updated')`
   - Auto-clears `isProjection` flag on manual updates

3. **Other endpoints**: `/api/rent`, `/api/rent/history`, `/api/rent/forecast`, `/api/rent/roommates`

**Calculation Flow**:
```
extract_config(year, month) → RentConfig.for_period (with auto-projection)
extract_roommates(year, month) → Tenant queries + days_stayed calculation
RentCalculator.friendly_message() → Swedish rent message
```

**WebSocket Integration**:
```ruby
# Global PubSub (puma_server.rb:269-270)
$pubsub = PubSub.new
$data_broadcaster = DataBroadcaster.new($pubsub)

# Broadcast trigger after config changes
$pubsub&.publish('rent_data_updated')
```

**CRITICAL FOR SMS**: `friendly_message` endpoint already generates Swedish rent messages - can be adapted for SMS format.

**MISSING**:
- ❌ Endpoint to record payments (`POST /api/rent/payments`)
- ❌ Endpoint to get payment status (`GET /api/rent/status`)
- ❌ Integration between payment reconciliation and WebSocket broadcast

---

### Banking Integration (Subagent 3: BankBuster)

**Existing Infrastructure**: BankBuster - Swedbank XML Scraper

**Files**:
- `bank_buster.rb` (380 lines) - Ferrum headless browser automation
- `bank_payments_reader.rb` (56 lines) - XML parser (camt.054 format)
- `handlers/bank_buster_handler.rb` - WebSocket handler (STUBBED, commented out)

**How BankBuster Works**:
1. **Authentication**: Bank-ID QR code (requires manual scan, saves screenshot to `screenshots/qr_code.jpg`)
2. **Download**: Navigates to `/app/ib/dokument` API endpoint
3. **Parse**: Extracts payments from XML using Ox gem
4. **Output**: Array of payment hashes

**Payment Data Structure**:
```ruby
{
  debtor_name: "SARA BLOMQVIST SPÅNBERG",
  payment_date: "2023-12-22",
  total_amount: "3146.00",
  reference: "2021342"  # OCR number
}
```

**Storage**: XML files in `transactions/` directory (env var: `TRANSACTIONS_DIR`)

**Invoice Matcher** (`bankbuster/data/invoice_payments_matcher.rb`):
- Reconciles unpaid invoices against bank payments
- OCR reference matching + fuzzy name matching (Levenshtein distance)
- Amount validation with overpayment tracking
- **PRODUCTION-READY LOGIC** that could be adapted for rent payments

**CRITICAL FINDINGS**:
- ✅ BankBuster scraper works today
- ✅ Payment parsing logic exists
- ✅ OCR matching logic exists (for invoices)
- ❌ **Requires Bank-ID QR scan every time** (not fully automated)
- ❌ Not integrated with RentLedger
- ❌ No scheduled cron job running

**Tink Integration** (Historical):
- `.tink-transactions.json` (3,069 lines) - Large transaction history
- `tink-accounts.json` - Account metadata
- ⚠️ **NO ACTIVE CODE** - appears dormant

**Swish Integration**:
- ❌ **NONE EXISTS** - Would be greenfield implementation

**User's Preference**: Lunch Flow API (NOT BankBuster) because it doesn't require repeated Bank-ID authentication

---

### Admin Dashboard UI (Subagent 4: Frontend)

**Component Hierarchy**:
```
AdminDashboard.tsx (main view)
└── ContractList
    └── MemberRow (unified contracts + tenants)
        ├── Collapsed: Name, room, dates, status badges, buttons
        └── Expanded:
            ├── ContractDetails (if type === 'contract')
            └── TenantDetails (always shown, includes rent info)
```

**Where Rent Status Should Appear**:

**Option 1: Status Badge in Collapsed Row** (RECOMMENDED)
- Location: `MemberRow.tsx:287-294`
- Current badges: Contract status (Klar, Väntar, Utflyttad)
- Proposed: Add rent payment badge alongside (`Betald` / `Obetald`)
- Visual: Semi-transparent background (20% opacity) + bright text + 30% border
- Colors: cyan-400 (paid) / yellow-400 (unpaid) - matches existing scheme

**Option 2: Payment Details in Expanded View**
- Location: `TenantDetails.tsx:296-311`
- Current: Shows "Aktuell hyra" with rent amount
- Proposed: Add 3-column grid with:
  - Current rent (existing)
  - Payment status (Betald/Ej betald with icon)
  - SMS reminder count (number sent this month)

**WebSocket Broadcasting Pattern**:

**Backend Polling** (`lib/data_broadcaster.rb:22`):
```ruby
periodic(60) { fetch_and_publish('admin_contracts_data', "#{@base_url}/api/admin/contracts") }
```

**Manual Refresh** (lines 92-95):
```ruby
def broadcast_contract_list_changed
  fetch_and_publish('admin_contracts_data', "#{@base_url}/api/admin/contracts")
end
```
Called after: contract creation, tenant updates, departure dates, etc.

**Frontend Reception** (`DataContext.tsx:515-516`):
```tsx
case 'admin_contracts_data':
  dispatch({ type: 'SET_ADMIN_CONTRACTS_DATA', payload: message.payload })
```

**Implementation Pattern**:
1. Modify `/api/admin/contracts` to include rent status fields:
   ```ruby
   {
     tenant_id: "...",
     tenant_name: "...",
     current_rent: 7045,
     rent_paid: true,           # NEW
     rent_due_date: "2025-01-27", # NEW
     sms_reminder_count: 0      # NEW
   }
   ```
2. Call `broadcast_contract_list_changed` after payment confirmation
3. Frontend updates automatically via WebSocket

**Color Scheme** (existing patterns):
- Cyan-400 = Success (completed, paid)
- Yellow-400 = Pending (waiting, unpaid)
- Red-400 = Error (failed)
- Orange-400 = Warning (expired)

---

### Deployment & Scheduling (Subagent 5: Systemd/Cron)

**Current Production Setup**:
- User: `kimonokittens`
- Path: `/home/kimonokittens/Projects/kimonokittens/`
- Database: `kimonokittens_production`
- Environment: `/home/kimonokittens/.env` (symlinked)

**Existing Services** (systemd):
- `kimonokittens-dashboard.service` - Main backend (port 3001)
- `kimonokittens-webhook.service` - Deploy webhook (port 49123)
- `kimonokittens-kiosk.service` - Chrome display (user service)

**Existing Cron Pattern** (Electricity Scrapers):
```bash
# Vattenfall (3am daily)
0 3 * * * /bin/bash -l -c 'eval "$(rbenv init -)"; cd /home/kimonokittens/Projects/kimonokittens && timeout 3m bundle exec ruby vattenfall.rb >> logs/vattenfall.log 2>&1'

# Fortum (4am daily)
0 4 * * * /bin/bash -l -c 'eval "$(rbenv init -)"; cd /home/kimonokittens/Projects/kimonokittens && timeout 3m bundle exec ruby fortum.rb >> logs/fortum.log 2>&1'
```

**CRITICAL PATTERNS**:
- ✅ **MUST use `bundle exec`** - Required for gems in `vendor/bundle`
- ✅ **MUST eval rbenv init** - Cron doesn't have rbenv in PATH
- ✅ **Timeout protection** - `timeout Xm` prevents hanging
- ✅ **Logging** - Append to `logs/` directory
- ✅ **Staggered timing** - Prevent resource conflicts

**NO systemd timers currently used** - All scheduled tasks via cron

**Recommended Pattern for Bank Sync + Reminders**:

**Hourly bank sync**:
```bash
15 * * * * /bin/bash -l -c 'eval "$(rbenv init -)"; cd /home/kimonokittens/Projects/kimonokittens && timeout 5m bundle exec ruby bin/bank_sync >> logs/bank_sync.log 2>&1'
```

**Daily SMS reminders**:
```bash
0 9 * * * /bin/bash -l -c 'eval "$(rbenv init -)"; cd /home/kimonokittens/Projects/kimonokittens && timeout 2m bundle exec ruby bin/rent_reminders >> logs/reminders.log 2>&1'
```

**Webhook Infrastructure**:
- GitHub deploy webhook: `deployment/scripts/webhook_puma_server.rb` (port 49123)
- Zigned signature webhook: `handlers/zigned_webhook_handler.rb` (port 3001)
- Pattern exists for adding 46elks webhook handlers

---

## ARCHITECTURE PATTERNS TO REUSE

### Service Layer Pattern (from ElectricityBill)

**Reference**: `lib/services/apply_electricity_bill.rb`

**Flow**:
```
1. Service receives raw data (bill amount, provider, date)
2. Stores in database (ElectricityBill table)
3. Aggregates period totals
4. Updates configuration (RentConfig)
5. Broadcasts WebSocket notification
```

**Adaptation for Payments**:
```
1. Service receives bank transaction
2. Stores in database (BankTransaction table)
3. Matches to RentLedger entry
4. Updates payment fields (amountPaid, paymentDate)
5. Broadcasts WebSocket notification
```

**File to Create**: `lib/services/apply_bank_payment.rb`

### Repository Pattern (Persistence Layer)

**Centralized Access** (`lib/persistence.rb`):
```ruby
module Persistence
  def self.tenants
    @tenant_repository ||= TenantRepository.new
  end

  def self.rent_ledger
    @rent_ledger_repository ||= RentLedgerRepository.new
  end
end
```

**Usage**:
```ruby
tenant = Persistence.tenants.find_by_id(tenant_id)
ledger = Persistence.rent_ledger.find_by_tenant_and_period(tenant_id, period)
```

### Domain Model Pattern (Business Logic)

**Separation of Concerns**:
- Models (`lib/models/`) - Business logic, NO database access
- Repositories (`lib/repositories/`) - Persistence only, NO business rules
- Services (`lib/services/`) - Multi-table transactions

**Example**: `lib/models/rent_ledger.rb`
```ruby
class RentLedger
  def paid?
    amount_paid >= amount_due
  end

  def payment_status
    return 'paid' if paid?
    return 'partially_paid' if partially_paid?
    'unpaid'
  end
end
```

---

## KEY TECHNICAL DECISIONS NEEDED

### 1. Bank Integration Architecture

**Option A: Lunch Flow API** (User's Preference)
- **Pros**: No Bank-ID authentication required (probably OAuth token-based)
- **Cons**: Third-party service, monthly cost, need API documentation
- **Status**: User needs to verify authentication model
- **Implementation**: `lib/banking/lunchflow_client.rb` (as GPT-5 suggested)

**Option B: BankBuster (Existing)**
- **Pros**: Already works, free, direct bank access
- **Cons**: Requires Bank-ID QR scan every execution, not fully automated
- **Status**: Working but user rejected this approach

**Option C: Direct PSD2/Open Banking**
- **Pros**: Standard API, no third-party service
- **Cons**: Complex authentication (90-day re-authorization), per-bank integration
- **Examples**: SEB, Handelsbanken, Swedbank all have PSD2 APIs

### 2. Database Schema Extensions

**Tenant Table Additions** (GPT-5 proposes):
- `phone_e164` text not null
- `swish_number` text
- `payday_start_day` integer default 25
- `sms_opt_out` boolean default false
- `sms_tone` text default 'gentle-quirky'
- `lang` text default 'sv'

**Question**: Which of these are actually needed?
- `phone_e164`: Probably yes (E.164 format for SMS)
- `swish_number`: Maybe (could default to phone number?)
- `payday_start_day`: Maybe (could default to 25 globally?)
- `sms_opt_out`: Yes (legal requirement)
- `sms_tone`: Maybe (nice-to-have for personality)
- `lang`: Probably not yet (all Swedish tenants)

**New Tables** (GPT-5 proposes):
- `bank_transactions`: Yes (store raw transactions from Lunch Flow)
- `rent_receipts`: Maybe (could use RentLedger.amountPaid instead?)
- `sms_events`: Yes (audit trail for SMS sends/receives)

### 3. Payment Matching Strategy

**Reference Matching** (GPT-5 proposes `KK-<YYYY-MM>-<TENANTID>`):
- Pro: Reliable if tenants include reference
- Con: Tenants might forget to add reference

**Amount + Name Matching**:
- Pro: Works even without reference
- Con: Fuzzy matching needed (already exists in invoice_payments_matcher.rb)

**Partial Payments**:
- GPT-5 proposes separate `rent_receipts` table
- Alternative: Use existing `RentLedger.amountPaid` field incrementally

### 4. SMS Provider Setup

**46elks** (mentioned by user):
- Swedish SMS provider
- REST API with Basic Auth
- Webhook support for delivery receipts
- User has NOT signed up yet (BLOCKER)

**Alternative**: Twilio (more documentation, higher cost)

### 5. Swish Integration Approach

**Option A: Swish Commerce API** (Official)
- Requires business Swish account
- Payment confirmations via API
- Monthly cost

**Option B: Deep Links Only** (GPT-5 proposes)
- Generate `swish://payment?...` links
- No payment confirmation from Swish
- Free, but relies on bank transaction matching

**User preference**: Unknown yet

---

## CURRENT STATE SUMMARY

**What Exists Today**:
- ✅ RentLedger with `amountPaid` and `paymentDate` fields
- ✅ Domain model with `paid?`, `payment_status` methods
- ✅ Repository with `record_payment()` method (unused)
- ✅ WebSocket broadcasting infrastructure
- ✅ Admin dashboard with expandable tenant rows
- ✅ Tenant.phone field exists (nullable)
- ✅ BankBuster payment scraper works (but not automated)
- ✅ Invoice payment matching logic (OCR + fuzzy name)
- ✅ Cron scheduling pattern (electricity scrapers)
- ✅ Service layer pattern (ApplyElectricityBill)

**What's Missing**:
- ❌ Automated bank transaction sync
- ❌ Payment matching service
- ❌ API endpoint to record payments
- ❌ SMS sending infrastructure
- ❌ Swish link generation
- ❌ Admin dashboard payment status UI
- ❌ Database tables for transactions/SMS logs
- ❌ 46elks account signup

**Blockers**:
1. User needs to verify Lunch Flow authentication model
2. User needs to sign up for 46elks account
3. Need to decide which GPT-5 proposals to accept/modify

---

## NEXT STEPS

1. **Socratic Refinement Questions** (one at a time):
   - Verify Lunch Flow authentication model
   - Which database fields actually needed on Tenant?
   - Swish approach: Commerce API or deep links only?
   - SMS tone/personality: Template-only or LLM-enhanced?
   - Payment matching: Reference-only or fuzzy fallback?
   - Partial payments: Separate table or increment RentLedger.amountPaid?

2. **Create Refined Implementation Plan** based on user's answers

3. **Phase Implementation** (user's preference):
   - Phase 1: Manual payment entry UI (quick win)
   - Phase 2: Bank sync + auto-matching
   - Phase 3: SMS reminders (requires 46elks signup)
   - Phase 4: Swish integration

---

## FILES REFERENCED DURING EXPLORATION

**Database**:
- `/Users/fredrikbranstrom/Projects/kimonokittens/prisma/schema.prisma`
- `/Users/fredrikbranstrom/Projects/kimonokittens/lib/models/rent_ledger.rb`
- `/Users/fredrikbranstrom/Projects/kimonokittens/lib/repositories/rent_ledger_repository.rb`
- `/Users/fredrikbranstrom/Projects/kimonokittens/lib/persistence.rb`

**Rent Calculation**:
- `/Users/fredrikbranstrom/Projects/kimonokittens/handlers/rent_calculator_handler.rb`
- `/Users/fredrikbranstrom/Projects/kimonokittens/rent.rb`
- `/Users/fredrikbranstrom/Projects/kimonokittens/puma_server.rb`

**Banking**:
- `/Users/fredrikbranstrom/Projects/kimonokittens/bank_buster.rb`
- `/Users/fredrikbranstrom/Projects/kimonokittens/bank_payments_reader.rb`
- `/Users/fredrikbranstrom/Projects/kimonokittens/bankbuster/data/invoice_payments_matcher.rb`
- `/Users/fredrikbranstrom/Projects/kimonokittens/.tink-transactions.json`

**Admin Dashboard**:
- `/Users/fredrikbranstrom/Projects/kimonokittens/dashboard/src/views/AdminDashboard.tsx`
- `/Users/fredrikbranstrom/Projects/kimonokittens/dashboard/src/components/admin/MemberRow.tsx`
- `/Users/fredrikbranstrom/Projects/kimonokittens/dashboard/src/components/admin/TenantDetails.tsx`
- `/Users/fredrikbranstrom/Projects/kimonokittens/dashboard/src/context/DataContext.tsx`
- `/Users/fredrikbranstrom/Projects/kimonokittens/lib/data_broadcaster.rb`

**Services**:
- `/Users/fredrikbranstrom/Projects/kimonokittens/lib/services/apply_electricity_bill.rb`

**Deployment**:
- `/Users/fredrikbranstrom/Projects/kimonokittens/deployment/configs/systemd/`
- `/Users/fredrikbranstrom/Projects/kimonokittens/docs/PRODUCTION_CRON_DEPLOYMENT.md`

---

**END OF BRAIN DUMP**

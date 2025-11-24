# Ruby Backend Architecture & Patterns

**Parent context:** See `/CLAUDE.md` for monorepo overview, critical protocols, and deployment workflows.

---

## 🏗️ Repository Architecture Pattern

**Architecture overview:** See `/CLAUDE.md` for clean architecture diagram and layer explanations.

### Quick Reference

**Access repositories:**
```ruby
require_relative 'lib/persistence'

Persistence.tenants           # TenantRepository
Persistence.rent_configs      # RentConfigRepository
Persistence.rent_ledger       # RentLedgerRepository
Persistence.electricity_bills # ElectricityBillRepository
```

**Domain model methods:**
```ruby
# Electricity billing period calculation:
ElectricityBill.calculate_bill_period(due_date)  # → consumption period Date

# Rent configuration with carry-forward logic:
RentConfig.for_period(year: 2025, month: 10, repository: Persistence.rent_configs)

# Tenant days stayed calculation:
tenant.days_stayed_in_period(period_start, period_end)
```

**Services for transactions:**
```ruby
# Store electricity bill + auto-aggregate + update RentConfig:
ApplyElectricityBill.call(
  provider: 'Vattenfall',
  amount: 1685.69,
  due_date: Date.new(2025, 11, 3)
)
# Automatically: stores bill → aggregates period → updates RentConfig → notifies WebSocket
```

### Documentation

For LLM assistants and future developers:
- **Complete API guide**: `docs/MODEL_ARCHITECTURE.md` (800+ lines)
- **Migration commits**: d96d76f (models), d7b75ec (handlers), 7df8296 (tests)
- **Business logic preservation**: Verified in test suite (spec/models/, spec/repositories/, spec/services/)
- **Test coverage**: 37 tests for domain layer (all passing)

### ⚠️ CRITICAL: Repository Pattern - Model/Persistence Checklist

**🔥 MANDATORY: When working with domain models, ALWAYS check the repository! 🔥**

**The repository is the ONLY gateway between models and database. Missing fields = silent data loss.**

### Three-Layer Consistency Checklist

When adding/modifying model fields, verify ALL THREE layers match:

1. **✅ Domain Model** (`lib/models/*.rb`)
   - `attr_reader` declarations
   - `initialize()` parameters
   - `attr_writer` for mutable fields

2. **✅ Repository** (`lib/repositories/*_repository.rb`)
   - `hydrate()` - reads from database → model
   - `dehydrate()` - writes from model → database
   - **EVERY model field MUST appear in BOTH methods**

3. **✅ Database Schema** (`prisma/schema.prisma`)
   - Column exists with correct type
   - Migrations applied to production

### Common Bugs from Missing Repository Fields

**Bug #1: Silent data loss** (Nov 24, 2025 - ContractParticipant SMS fields)
```ruby
# Model has fields:
attr_reader :sms_delivered, :sms_delivered_at

# Code sets values:
participant.sms_delivered = true
participant_repo.save(participant)

# But repository dehydrate() is missing them:
def dehydrate(participant)
  {
    emailDelivered: participant.email_delivered,
    # smsDelivered: participant.sms_delivered,  # ← MISSING!
  }
end

# Result: Data silently dropped on save! Database stays false forever.
```

**Bug #2: Missing data in queries** (Nov 14, 2025 - Tenant personnummer)
```ruby
# Repository SELECT missing fields:
.select(:id, :name, :email)  # personnummer missing!

# Admin UI shows "—" even though database has data
```

### Verification Commands

**Before deploying model changes:**
```bash
# 1. Check model fields
grep "attr_reader" lib/models/contract_participant.rb

# 2. Check repository includes ALL fields
grep -A 20 "def hydrate" lib/repositories/contract_participant_repository.rb
grep -A 20 "def dehydrate" lib/repositories/contract_participant_repository.rb

# 3. Check database schema
grep -A 30 "model ContractParticipant" prisma/schema.prisma

# 4. Verify no field drift
diff <(grep attr_reader lib/models/contract_participant.rb | grep -oP ':\w+' | sort) \
     <(grep -A 20 "def hydrate" lib/repositories/contract_participant_repository.rb | grep -oP '\w+:' | sed 's/://g' | sort)
```

### When Debugging "Missing Data"

1. **Check database FIRST**: `psql -d kimonokittens_production -c "SELECT * FROM \"ContractParticipant\" LIMIT 1"`
2. **Check repository hydrate()**: Does it read the field from `row[:fieldName]`?
3. **Check repository dehydrate()**: Does it write the field to `fieldName: model.field`?
4. **Check model**: Does `attr_reader` include the field?

**Pattern**: Data in database but not in API → repository hydrate() missing field
**Pattern**: Code sets value but doesn't persist → repository dehydrate() missing field

### Historical Incidents

- **Nov 24, 2025**: ContractParticipant `sms_delivered`/`sms_delivered_at` - model had fields, repository didn't persist them
- **Nov 14, 2025**: Tenant `personnummer` - repository SELECT excluded field, caused UI to show "—"

---

## ⚠️ CRITICAL: RUBY SCRIPT EXECUTION PROTOCOL

**🔥 ALWAYS USE `bundle exec` FOR RUBY SCRIPTS 🔥**

This project uses **`--deployment` mode with `vendor/bundle`** for gem isolation. Ruby scripts MUST run via `bundle exec` to access installed gems.

### ✅ CORRECT EXECUTION:
```bash
bundle exec ruby script.rb
bundle exec ruby -e "require_relative 'lib/contract_signer'; ..."
bundle exec rspec
```

### ❌ WRONG EXECUTION (Will fail with LoadError):
```bash
ruby script.rb          # Can't find gems in vendor/bundle
ruby -e "..."           # Can't load bundled dependencies
rspec                   # Wrong gem versions or missing gems
```

### 🚨 WHY THIS MATTERS:
- **Without `bundle exec`**: Ruby uses system gems, ignoring `vendor/bundle`
- **Result**: `LoadError: cannot load such file` even though gems are installed
- **Production context**: All production code uses bundler's isolated gem environment

**Rule of thumb**: If the project has a `Gemfile` and `vendor/bundle`, ALWAYS prefix with `bundle exec`.

**Lesson learned**: Nov 12, 2025 - Repeatedly failed to run contract signing scripts without `bundle exec` despite `vendor/bundle` clearly existing.

---

## Rent Calculation Timing Quirks ⚠️

### Critical: Config Period = Rent Month - 1

**The system stores rent parameters one month early because rent is paid in advance.**

**Concrete example (November 2025):**
- **Today: November 19, 2025**
- **Dashboard requests: November config** (`/api/rent/friendly_message`)
- **Actually displays: December 2025 rent** ("Hyran för december 2025 ska betalas innan 27 nov")

**WHY:** Rent is paid **in advance** for the upcoming month, but operational costs (electricity) are paid **in arrears** for the previous month. Therefore, November's config stores December's rent parameters.

### Database Period Logic

```ruby
# To show December 2025 rent on November 27:
db.set_config('el', 3869, Time.new(2025, 11, 1))  # November period
# NOT: Time.new(2025, 12, 1)  # This would be wrong!

# Or: October 2025 rent on September 27:
db.set_config('el', 2424, Time.new(2025, 9, 1))   # September period
```

**The rule:** Config month = rent month - 1 (Nov config → Dec rent).

### RentLedger Population Timing

**Script timing:** Run `bin/populate_monthly_ledger 2025 12` in late November (day 22) to create December rent ledger entries. (Automated via cron in production.)

### Payment Structure & Quarterly Savings Mechanism

**Regular Monthly Payments (Advance)**:
- **Base rent** (`kallhyra`): December housing
- **Internet** (`bredband`): December service
- **Utilities** (`vattenavgift`, `va`, `larm`): Building up savings for quarterly bills

**Arrears Payments**:
- **Electricity** (`el`): November consumption bills

**Example:** November 27 payment covers:
- December base rent (advance) + December utilities (savings) + November electricity (arrears)

### Electricity Automation Status ⚡

**Status**: ✅ **FULLY AUTOMATED** (Oct 24, 2025) - No manual entry required for rent calculations

- **Peak/off-peak pricing**: Implemented with 0.6-4.3% winter accuracy (exceeds 5-6% target) - see `docs/ELECTRICITY_AUTOMATION_COMPLETION_SUMMARY.md`
- **Dual-scraper system**: Vattenfall (3am) + Fortum (4am) cron jobs auto-fetch invoices, aggregate totals, update RentConfig - see `docs/PRODUCTION_CRON_DEPLOYMENT.md`
- **Rent calculation**: Fully automated from bill arrival through WebSocket broadcast - zero manual intervention needed
- **Quarterly invoice auto-projection**: Growth-adjusted projections (8.7% YoY) for Apr/Jul/Oct when actual invoices not yet received - see `docs/QUARTERLY_INVOICE_RECURRENCE_PLAN.md`

### Electricity Bill Due Date Timing ⚡

**Key question:** When did the bill ARRIVE and become available for rent calculation?

**Due date determines config period:**
- **Day 25-31**: Config = due month (bill arrived same month)
- **Day 1-10**: Config = due month - 1 (bill arrived previous month)

**Example (August 2025 consumption):**
- Bills arrive mid-Sept → Vattenfall due Sept 30 (day 30) + Fortum due Oct 1 (day 1)
- Both use **Sept config** → October rent
- Flow: Aug consumption → Sept bills arrive → Sept config → Oct rent

**Migration script rule:**
```ruby
config_month = (due_day >= 25) ? due_month : due_month - 1
```

**Historical data:** `electricity_bills_history.txt` + `deployment/historical_config_migration.rb`

**Virtual Pot System** (Nov 2025):
- **Monthly utilities**: Uses provided values OR defaults (343+274+137=754 kr) if not provided
- **Gas**: Always adds 83 kr baseline (regardless of provided utilities)
- **Total accruals**: Typically 754 kr utilities + 83 kr gas = 837 kr/month (when using defaults)
- **Quarterly invoices**: Logged for audit/transparency only, **never used in calculations**
- **No rent spikes**: Fixed monthly accruals replace old "lump sum when invoice arrives" approach
- **Over-collection buffer**: 8.6-10.8% cushion absorbs future cost growth (exhausts ~2026)
- **Auto-projection**: Missing quarters filled with growth-adjusted estimates (8.7% YoY, base 2,787 kr)

**Example:** September 27 payment covers:
- October base rent (advance) + October accruals (837 kr fixed) + September electricity (arrears)

---

## Database Safety Rules ⚠️

### Database Configuration Keys
- **`el`**: Electricity cost (most frequently updated)
- **`drift_rakning`**: Quarterly invoice (logged for audit only, **not used in calculations**)
- **Monthly accruals**: Always 837 kr (754 building + 83 gas), regardless of quarterly invoices

### Debugging Structural Issues
When rent calculations seem wrong, check these patterns:
- **Config timing**: Verify `period` month = rent display month - 1 (Sept config → Oct rent)
- **Test contamination**: Production DB has unexpected `drift_rakning` values from specs
- **Message indicator**: API shows "uppskattade elkostnader" = projection mode (bills not arrived yet)

---

## 📊 DATABASE QUERY QUICK REFERENCE

**Essential commands for querying the persistence layer without confusion.**

### Quick List All Contracts
```bash
cd /home/kimonokittens/Projects/kimonokittens && ruby -e "
require 'dotenv/load'
require_relative 'lib/persistence'

RentDb.instance.class.db[:SignedContract].order(Sequel.desc(:createdAt)).each do |c|
  tenant = Persistence.tenants.find_by_id(c[:tenantId])
  created = c[:createdAt].strftime('%m-%d %H:%M')
  puts \"#{created} | #{tenant&.name || 'Unknown'} | #{c[:caseId]} | test: #{c[:testMode]} | status: #{c[:status]}\"
end
"
```

### Repository Access Patterns
```ruby
require 'dotenv/load'
require_relative 'lib/persistence'

# Get repositories
contract_repo = Persistence.signed_contracts
tenant_repo = Persistence.tenants

# Find by case ID (Zigned's identifier)
contract = contract_repo.find_by_case_id('cmhvx172q067g4cqks8wpyd5h')

# Find by tenant
contracts = contract_repo.find_by_tenant_id(tenant_id)

# Raw Sequel queries (returns hashes with camelCase keys)
all_contracts = RentDb.instance.class.db[:SignedContract]
  .order(Sequel.desc(:createdAt))
  .all

# Filter by test mode
prod_contracts = RentDb.instance.class.db[:SignedContract]
  .where(testMode: false)
  .all
```

### Key Field Mapping
- **Raw Sequel** (hashes): `:testMode`, `:caseId`, `:tenantId`, `:createdAt`
- **Repository** (models): `.test_mode`, `.case_id`, `.tenant_id`, `.created_at`

### Available Repository Methods
```ruby
repo.find_by_id(id)                  # => SignedContract or nil
repo.find_by_case_id(case_id)       # => SignedContract or nil
repo.find_by_tenant_id(tenant_id)   # => Array<SignedContract>
repo.find_completed                  # => Array (status: completed)
repo.find_expiring_soon(days: 7)    # => Array (pending + expires soon)
repo.statistics                      # => Hash with counts by status
```

**Important**: Always `require 'dotenv/load'` first to load DATABASE_URL from .env. Repository methods return domain models; raw Sequel returns hashes.

**Created**: Nov 12, 2025 - After repeated confusion about correct query syntax.

---

## ⚠️ CRITICAL: DATABASE AND DATA OPERATIONS

**Query Before Scripting**: When writing scripts that depend on specific records:

1. **First query to understand actual data state**:
   - What IDs exist in the database?
   - What schema/fields are actually used?
   - Never assume IDs from filenames match database records

2. **Read repository/API documentation** before using methods:
   - Check what methods exist (don't assume `find_all()` exists)
   - Verify method signatures and return types
   - Read the actual code if documentation is missing

3. **Then write scripts based on verified reality**:
   - Use actual IDs discovered from queries
   - Handle missing data gracefully
   - Either discover IDs programmatically or accept parameters

4. **For database operations**:
   - Always check .env for actual `DATABASE_URL` before assuming database names
   - Never connect to `*_development` without verifying it exists
   - Use the database name from .env configuration

**Example - WRONG approach**:
```ruby
# Assumes IDs without verification
sanna = repo.find_by_id('sanna-juni-benemar-8706220020')  # FAILS: ID doesn't exist
```

**Example - CORRECT approach**:
```bash
# First query to discover actual IDs
psql -d kimonokittens -c "SELECT id, name FROM \"Tenant\" WHERE name = 'Sanna Juni Benemar';"
# Returns: cmhqe9enc0000wopipuxgc3kw

# Then use verified ID in script
sanna = repo.find_by_id('cmhqe9enc0000wopipuxgc3kw')  # SUCCESS
```

**Lesson learned**: Nov 8, 2025 - Hardcoded IDs from JSON filenames didn't match database UUIDs, causing export script to fail. Always query first.

---

## 📊 Quarterly Invoice Auto-Projection System

**Status**: ✅ **PRODUCTION** (Oct 25, 2025) - Proactive growth-adjusted projections
**Documentation**: `docs/QUARTERLY_INVOICE_RECURRENCE_PLAN.md`

**Architecture**: RentConfig.for_period → QuarterlyInvoiceProjector → Auto-populate when missing
**Pattern**: Quarterly months (Apr/Jul/Oct) = 3× yearly building operations invoices
**Growth Rate**: 8.7% annual (2024 → 2025: 7,689 kr → 8,361 kr historical trend)
**Base Amount**: 2,787 kr (2025 average of all drifträkningar)

**Key Features**:
- **Proactive auto-population**: Dashboard requests auto-create projections when drift_rakning missing
- **Growth-adjusted formula**: `2,787 × (1.087 ^ years_forward)` → Apr 2026 = 3,030 kr, Apr 2027 = 3,294 kr
- **Projection tracking**: Database `isProjection` flag distinguishes actual vs projected invoices
- **Manual override**: PUT /api/rent/config automatically clears projection flag on updates
- **API transparency**: `quarterly_invoice_projection` boolean + Swedish disclaimer in messages

**Implementation**:
- **Service**: `lib/services/quarterly_invoice_projector.rb` (projection calculations)
- **Model**: `lib/models/rent_config.rb` (auto-population logic in `for_period`)
- **Repository**: `lib/repositories/rent_config_repository.rb` (`save_with_projection_flag` method)
- **Handler**: `handlers/rent_calculator_handler.rb` (API response includes projection status)

**Production Data**:
- Oct 2025: 2,797 kr (actual invoice, isProjection=false) → Nov rent: 7,577 kr/person
- Apr 2026: 3,029 kr (auto-projected, isProjection=true) → May rent shows disclaimer

---

## Testing Best Practices 🧪

**Testing philosophy:** See `/CLAUDE.md` for universal testing principles.

**Status**: ✅ PRODUCTION READY (October 4, 2025) - 39/39 tests passing
**Documentation**: `docs/TESTING_GUIDE.md` (complete reference)

### Critical Rules

1. **Test database isolation** - Tests ALWAYS use `kimonokittens_test` database (4-layer defense in depth)
2. **spec_helper.rb MUST be first require** - Loads `.env.test` before any code
3. **Sequel API**: Use `db.class.db.run()` not `db.conn.exec()` (pre-2025 upgrade)
4. **Default utilities**: Calculator adds 825 kr when utilities not provided
5. **Rounding tolerance**: Use `be_within(1).of(...)` for financial totals
6. **Timestamp comparison**: Compare `.to_date` not full timestamps (timezone differences)

### Quick Commands

```bash
# Run tests (one file at a time for easier fixes)
bundle exec rspec spec/rent_calculator/calculator_spec.rb

# Verify dev database untouched after tests
ruby -e "require 'dotenv/load'; require_relative 'lib/rent_db'; puts RentDb.instance.get_tenants.length"  # Should show 8

# Full test suite
bundle exec rspec
```

### When Tests Fail

**Code behavior likely evolved legitimately** - update test expectations, not implementation:
- Message format changes → Update regex/string matchers
- Rounding differences → Add tolerance
- Default values → Accept calculator's defaults
- Timezone handling → Compare dates not timestamps

**See**: `docs/TESTING_GUIDE.md` for complete patterns, setup, and troubleshooting

---

## WebSocket Data Broadcasting

**Architecture overview:** See `/CLAUDE.md` for data flow diagram.

**Backend implementation:**

### DataBroadcaster (`lib/data_broadcaster.rb`)

**URLs**: Uses `ENV['API_BASE_URL']` for production-ready endpoint fetching

**Data refresh intervals:**
- Temperature data: Every 30s
- Electricity stats: Every 5min (300s)
- Rent data: Every 10min (600s)
- Weather: Every 15min (900s)

**Performance caching:**
- **Electricity anomaly regression** (90-day linear model): Cached until midnight
- Runs once/day instead of every 5min broadcast (99.65% reduction, ~90% CPU savings)
- Cache invalidates when `Date.today` changes
- WebSocket sends updates every 5min regardless (data unchanged until midnight)

### Heating Cost Display

**Calculation**: Uses ElectricityProjector (trailing 12-month baseline + seasonal patterns)
- **Current (Oct 2025)**: "2 °C varmare skulle kosta 143 kr/mån (36 kr/person)"
- **February 2026 (predicted)**: "2 °C varmare skulle kosta 451 kr/mån (113 kr/person)"

**Why February costs 3.5× more**:
- Seasonal multiplier: Feb = 2.04x vs Sep = 0.56x (winter vs fall)
- More heating usage = larger impact per degree adjustment

**Architecture**:
- Shared module: `lib/heating_cost_calculator.rb`
- Sent via `/api/rent/friendly_message` in `heating_cost_line` field
- Auto-updates monthly as ElectricityProjector recalculates

### Electricity Usage Anomaly Detection 📊

**What it measures**: ElectricityWidget sparkline bars glow when consumption deviates ±20% from temperature-based baseline (90-day linear regression). Cost impact = excess kWh × actual peak/offpeak pricing.

**Peak/offpeak pricing included**: Peak 53.6 öre/kWh (Mon-Fri 06:00-22:00, winter), offpeak 21.4 öre/kWh (2.5× difference). Daily cost uses hourly rates for when consumption occurred.

**Root causes** (heating dominates 70-80% of electricity cost):
1. Heatpump running during peak instead of offpeak (poor Node-RED scheduling)
2. Manual overrides (kitchen floor heating +10°C)
3. Additional occupancy (+1 person since Nov 2)
4. Behavioral changes (more cooking, WFH)
5. Equipment issues (insulation, inefficiency)

**Baseline drift limitation**: 90-day window will eventually adopt wasteful non-peak-optimized schedule as new baseline. Comparison only valid during transition periods. Example: Nov 1-12 showed +142 SEK excess spend - this is ongoing waste until Node-RED peak/offpeak scheduling fixed.

**Current use**: Indicates money wasted from poor heatpump timing + behavioral factors (can't disambiguate, but cost is accurate).

---

## 📝 Contract Signing System (Backend)

**Integration overview:** See `/CLAUDE.md` for high-level flow.

**Status**: ✅ **PRODUCTION READY** (Nov 11, 2025) - All 14 webhook event types implemented

### Key Files
- `handlers/zigned_webhook_handler.rb` - Webhook handler (14 events, HMAC-SHA256 signature verification)
- `lib/contract_signer.rb` - PDF generation + Zigned API v3 client
- `lib/models/signed_contract.rb`, `lib/models/contract_participant.rb` - Domain models
- `lib/repositories/signed_contract_repository.rb`, `lib/repositories/contract_participant_repository.rb` - Persistence
- Database: `SignedContract`, `ContractParticipant` tables (Prisma schema)

### Critical Implementation Details
- **Personal number lookup**: Zigned webhooks don't send `personal_number` - handler uses email matching + tenant DB query (`handlers/zigned_webhook_handler.rb:682-708`)
- **Signing URL variants**: Zigned API uses both `signing_url` AND `signing_room_url` - handler checks both with `||` fallback (`handlers/zigned_webhook_handler.rb:661`)
- **Webhook endpoint**: `POST /api/webhooks/zigned` (port 3001)
- **Signature verification**: Stripe-style timestamped HMAC-SHA256 prevents replay attacks

### Monitoring
```bash
# Real-time contract events
journalctl -u kimonokittens-dashboard -f | grep -E "(📝|✍️|🎉|📥|❌)"

# All Zigned webhooks
journalctl -u kimonokittens-dashboard | grep -E "(agreement|participant|email_event)"
```

### Documentation
- `docs/ZIGNED_WEBHOOK_FIELD_MAPPING.md` - Real payload analysis → database field mapping
- `docs/ZIGNED_WEBHOOK_TESTING_STATUS.md` - Bug fixes log (Nov 11: repository.update, personal_number lookup)
- `docs/zigned-api-spec.yaml` - Complete OpenAPI 3.0 spec (21,571 lines)

### Recent Work (Nov 11, 2025)
- Fixed 2 critical bugs revealed by test contract `cmhuyr9pt010x4cqk5tova6bd`
- Implemented all failure handlers (identity, PDF validation, email delivery)
- Complete 14-event coverage: 6 lifecycle + 8 tracking events
- Commits: eff6ccf (complete handler), 1a1d4de (personal_number), 281c137 (repository.update)

---

## 💸 SWISH PAYMENT INTEGRATION

**Status**: ❌ **Swish Handel/Commerce REJECTED** (Nov 15, 2025) - Exploitative pricing model

(Content preserved from original for historical reference)

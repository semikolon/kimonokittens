# RentLedger Period Semantics Migration Plan

**Created:** November 19, 2025
**Status:** Ready for execution
**Estimated time:** 11-16 hours (1.5-2 days)

## Executive Summary

**Goal:** Unify RentConfig and RentLedger period semantics - both should use config month.

**Change:**
- **Before:** RentLedger.period = rent month (2025-12-01 = December rent)
- **After:** RentLedger.period = config month (2025-11-01 = November config → December rent)

**Impact:** 16 files, database migration, comprehensive testing required.

---

## Phase 1: Preparation (30 min)

### 1.1 Verify Git State
```bash
git status  # Should be clean
git pull origin master  # Get latest
```

### 1.2 Create Feature Branch
```bash
git checkout -b unify-rent-ledger-period-semantics
```

### 1.3 Backup Database
```bash
# Production backup
pg_dump -U kimonokittens -d kimonokittens_production > /tmp/pre-migration-backup-$(date +%Y%m%d-%H%M).sql

# Development backup
pg_dump -U kimonokittens -d kimonokittens_development > /tmp/pre-migration-dev-backup-$(date +%Y%m%d-%H%M).sql
```

---

## Phase 2: Database Migration (1 hour)

### 2.1 Create Prisma Migration

**File:** `prisma/migrations/YYYYMMDD_shift_rent_ledger_periods/migration.sql`

```sql
-- RentLedger Period Semantics Migration
-- Change: period now represents CONFIG month (not rent month)
-- Example: period 2025-11-01 = November config → December rent

BEGIN;

-- Shift all RentLedger periods back 1 month
-- This aligns RentLedger.period with RentConfig.period semantics
UPDATE "RentLedger"
SET period = period - INTERVAL '1 month'
WHERE period IS NOT NULL;

-- Verify no duplicate (tenantId, period) combinations created
DO $$
DECLARE
  duplicate_count INTEGER;
BEGIN
  SELECT COUNT(*) INTO duplicate_count
  FROM (
    SELECT "tenantId", period
    FROM "RentLedger"
    GROUP BY "tenantId", period
    HAVING COUNT(*) > 1
  ) AS duplicates;

  IF duplicate_count > 0 THEN
    RAISE EXCEPTION 'Migration created % duplicate (tenantId, period) entries', duplicate_count;
  END IF;
END $$;

COMMIT;
```

**Run migration:**
```bash
npx prisma migrate dev --name shift_rent_ledger_periods
```

**Commit:**
```bash
git add prisma/migrations/
git commit -m "migration: shift RentLedger periods to config month semantics

Changes period field to use config month instead of rent month.
Example: period 2025-11-01 = November config → December rent.

All existing ledger entries shifted back 1 month."
```

### 2.2 Update Prisma Schema Documentation

**File:** `prisma/schema.prisma` (lines 45-59)

```prisma
model RentLedger {
  id                String    @id @default(cuid())
  tenantId          String
  period            DateTime  // Config month (NOT rent month!)
                               // Example: 2025-11-01 = Nov config → Dec rent
  amountDue         Float
  amountPaid        Float     @default(0)
  paymentDate       DateTime?
  daysStayed        Int?
  roomAdjustment    Float?
  baseMonthlyRent   Float?
  calculationTitle  String?   // "December 2025" (rent month display)
  calculationDate   DateTime?
  createdAt         DateTime  @default(now())

  tenant            Tenant    @relation(fields: [tenantId], references: [id])

  @@map("RentLedger")
}
```

**Commit:**
```bash
git add prisma/schema.prisma
git commit -m "docs: update RentLedger schema comments to reflect config month semantics"
```

---

## Phase 3: Domain Models & Helper Methods (2 hours)

### 3.1 Create Period Helper Module

**File:** `lib/models/rent_period_helper.rb` (NEW)

```ruby
# Helper module for RentLedger period semantics
#
# RentLedger.period = config month (when costs were incurred)
# But we often need to display the RENT month (period + 1 month)
module RentPeriodHelper
  # Convert config period to rent month for display
  #
  # @param config_period [Time, Date] Config period (e.g., 2025-11-01)
  # @return [Date] Rent month (e.g., 2025-12-01)
  #
  # @example
  #   config_period = Time.utc(2025, 11, 1)
  #   rent_month = RentPeriodHelper.config_to_rent_month(config_period)
  #   # => #<Date: 2025-12-01>
  def self.config_to_rent_month(config_period)
    date = config_period.to_date
    # Add 1 month, handling year boundary
    next_month = date.next_month
    Date.new(next_month.year, next_month.month, 1)
  end

  # Convert config period to Swedish rent month name
  #
  # @param config_period [Time, Date] Config period
  # @return [String] Swedish month name (e.g., "december")
  #
  # @example
  #   swedish_name = RentPeriodHelper.swedish_rent_month(Time.utc(2025, 11, 1))
  #   # => "december"
  def self.swedish_rent_month(config_period)
    rent_month = config_to_rent_month(config_period)
    month_names = %w[januari februari mars april maj juni juli augusti september oktober november december]
    month_names[rent_month.month - 1]
  end

  # Convert current calendar month to config period
  #
  # @param year [Integer] Current year
  # @param month [Integer] Current month (1-12)
  # @return [Time] Config period for this month's rent calculation
  #
  # @example November 2025 → config period for December rent
  #   period = RentPeriodHelper.current_to_config_period(2025, 11)
  #   # => Time.utc(2025, 11, 1)
  def self.current_to_config_period(year, month)
    Time.utc(year, month, 1)
  end
end
```

**Commit:**
```bash
git add lib/models/rent_period_helper.rb
git commit -m "feat: add RentPeriodHelper for config/rent month conversions

Provides helper methods to convert between config periods and display months.
Essential for SMS messages and UI display after period semantics change."
```

### 3.2 Update RentLedger Model

**File:** `lib/models/rent_ledger.rb`

**Changes:**
- Line 4-24: Update class documentation
- Line 84-91: Update `period_swedish` method to use helper

```ruby
require_relative 'rent_period_helper'

# RentLedger domain model representing tenant rent obligations
#
# CRITICAL: period field = CONFIG MONTH (not rent month!)
# The period represents when costs were incurred (config month).
# To get the rent month being billed, add 1 month to period.
#
# Example:
#   ledger = RentLedger.new(
#     tenant_id: 'cmhqe9enc0000wopipuxgc3kw',
#     period: Time.utc(2025, 11, 1),  # November config
#     amount_due: 7045,
#     calculation_title: 'December 2025'  # Rent FOR December
#   )
#
# @example Query ledger for December 2025 rent
#   # December rent uses November config period
#   ledger = repository.find_by_tenant_and_period(tenant_id, Time.utc(2025, 11, 1))
#   ledger.rent_month  # => #<Date: 2025-12-01>
class RentLedger
  # ... existing code ...

  # Get the rent month this ledger entry is for (period + 1 month)
  # @return [Date] Rent month
  def rent_month
    RentPeriodHelper.config_to_rent_month(period)
  end

  # Return Swedish month name for the RENT month (not config month)
  # @return [String] Swedish month name (e.g., "december")
  def period_swedish
    RentPeriodHelper.swedish_rent_month(period)
  end
end
```

**Commit:**
```bash
git add lib/models/rent_ledger.rb
git commit -m "refactor: update RentLedger to use config month semantics

- Update documentation to clarify period = config month
- Add rent_month helper method (period + 1)
- Update period_swedish to use RentPeriodHelper
- Display methods return rent month, not config month"
```

### 3.3 Update RentLedgerRepository

**File:** `lib/repositories/rent_ledger_repository.rb`

Update documentation comments (lines 58-73):

```ruby
# Get rent payment history for a tenant
#
# Returns ledger entries ordered by period (config month).
# To display rent month, use entry.rent_month or entry.period_swedish.
#
# @param tenant_id [String] Tenant ID
# @return [Array<RentLedger>] Ledger entries (newest first)
#
# @example
#   history = repository.get_rent_history('cmhqe9enc...')
#   history.first.period  # => Time.utc(2025, 11, 1) (Nov config)
#   history.first.rent_month  # => #<Date: 2025-12-01> (Dec rent)
def get_rent_history(tenant_id)
  # ... existing code ...
end
```

**Commit:**
```bash
git add lib/repositories/rent_ledger_repository.rb
git commit -m "docs: update RentLedgerRepository comments for config month semantics"
```

---

## Phase 4: Business Logic Updates (3 hours)

### 4.1 Fix populate_monthly_ledger Script

**File:** `bin/populate_monthly_ledger`

**Changes:**
- Lines 9-22: Update documentation
- Line 16: Keep as-is (fetches config for config month)
- Line 19: **FIX** - now period = config month (not rent month)

```ruby
#!/usr/bin/env ruby
# frozen_string_literal: true

require 'dotenv/load'
require 'date'
require_relative '../lib/persistence'
require_relative '../lib/models/rent_config'
require_relative '../lib/models/rent_period_helper'

# Parse command line arguments
# IMPORTANT: month parameter = CONFIG MONTH (not rent month)
# Example: month=11 creates ledger with period 2025-11-01 (Nov config → Dec rent)
year = ARGV[0]&.to_i || Time.now.year
month = ARGV[1]&.to_i || Time.now.month

rent_month = RentPeriodHelper.config_to_rent_month(Date.new(year, month, 1))
puts "🏠 Populating rent ledger for #{rent_month.strftime('%Y-%m')} rent (using #{year}-#{month.to_s.rjust(2, '0')} config)"

# Get rent configuration for this period (config month)
config = RentConfig.for_period(year: year, month: month, repository: Persistence.rent_configs)

# Calculate period dates - period = CONFIG MONTH
period = Time.utc(year, month, 1)  # Config month (e.g., 2025-11-01)
period_start = Date.new(year, month, 1)
period_end = Date.new(year, month, -1)

# Rest of script unchanged...
```

**Commit:**
```bash
git add bin/populate_monthly_ledger
git commit -m "fix: update populate_monthly_ledger to use config month semantics

Script now correctly uses config month for both:
- Fetching RentConfig
- Creating RentLedger entries

Example: bin/populate_monthly_ledger 2025 11
Creates period 2025-11-01 (Nov config → Dec rent)"
```

### 4.2 Fix bin/rent_reminders

**File:** `bin/rent_reminders`

**Changes:**
- Lines 77-79: Adjust period calculation
- Lines 196-198: Same for admin alerts

```ruby
require_relative '../lib/models/rent_period_helper'

# ... existing code ...

# Lines 77-79: Get current period for ledger lookup
current_month = Date.today.strftime('%Y-%m')
current_year = Date.today.year
current_cal_month = Date.today.month

# Config period = current calendar month (for next month's rent)
current_period = RentPeriodHelper.current_to_config_period(current_year, current_cal_month)

# ... rest unchanged, ledger lookups use current_period ...
```

**Commit:**
```bash
git add bin/rent_reminders
git commit -m "fix: update rent_reminders to use config month for ledger queries

Uses current calendar month as config period when looking up ledgers.
Example: In November, queries period 2025-11-01 for December rent."
```

### 4.3 Fix ApplyBankPayment Service

**File:** `lib/services/apply_bank_payment.rb`

**Changes:**
- Lines 51-54: Update period calculation
- Lines 158-159: Same for find_by_period

```ruby
require_relative '../models/rent_period_helper'

class ApplyBankPayment
  # ... existing code ...

  def call
    # Get current config period (current calendar month)
    current_year = Date.today.year
    current_month = Date.today.month
    current_period = RentPeriodHelper.current_to_config_period(current_year, current_month)

    # ... rest of logic uses current_period ...
  end
end
```

**Commit:**
```bash
git add lib/services/apply_bank_payment.rb
git commit -m "fix: update ApplyBankPayment to use config period for ledger queries"
```

### 4.4 Fix Admin Contracts Handler

**File:** `handlers/admin_contracts_handler.rb`

**Changes:** Lines 799, 823, 838 in helper methods

```ruby
require_relative '../lib/models/rent_period_helper'

# Line 799: payment_status helper
def payment_status(tenant_id)
  current_year = Date.today.year
  current_month = Date.today.month
  period = RentPeriodHelper.current_to_config_period(current_year, current_month)
  # ... rest unchanged ...
end

# Lines 823, 838: Similar changes for current_rent_amount and remaining_amount
```

**Commit:**
```bash
git add handlers/admin_contracts_handler.rb
git commit -m "fix: update admin contracts handler to use config period semantics"
```

### 4.5 Fix ELKS Webhooks Handler

**File:** `handlers/elks_webhooks.rb`

**Changes:** Lines 122-124

```ruby
require_relative '../lib/models/rent_period_helper'

# Line 122-124: SMS status reply
current_year = Date.today.year
current_month = Date.today.month
period = RentPeriodHelper.current_to_config_period(current_year, current_month)

ledger = Persistence.rent_ledger.find_by_tenant_and_period(tenant.id, period)
if ledger
  rent_month_name = ledger.period_swedish  # Uses helper, returns rent month
  reply_body = "Hyra #{rent_month_name}: Betald"
  # ...
end
```

**Commit:**
```bash
git add handlers/elks_webhooks.rb
git commit -m "fix: update ELKS webhooks to use config period + display rent month"
```

---

## Phase 5: Test Updates (3-4 hours)

### 5.1 Update Service Tests

**File:** `spec/services/apply_bank_payment_spec.rb`

```ruby
# Line 15: Update current_period expectation
let(:current_period) { Time.utc(2025, 11, 1) }  # Nov config for Dec rent

# Update all expectations throughout file
```

**Commit:**
```bash
git add spec/services/apply_bank_payment_spec.rb
git commit -m "test: update ApplyBankPayment specs for config month semantics"
```

### 5.2 Update Handler Tests

**File:** `spec/handlers/admin_contracts_handler_spec.rb`

```ruby
# Line 33: Update period expectations
period: Date.new(2025, 11, 1)  # Nov config for Dec rent

# Lines 58, 76, 90, 104, 116, 125, 141, 157, 169: Update mocks
```

**Commit:**
```bash
git add spec/handlers/admin_contracts_handler_spec.rb
git commit -m "test: update admin contracts handler specs for config month semantics"
```

### 5.3 Update Calculator Tests

**File:** `spec/rent_calculator/database_autosave_spec.rb`

```ruby
# Lines 107, 155, 219, 254: Update rent_period expectations
rent_period: Time.utc(2025, 10, 1)  # Oct config for Nov rent (not 2025-11-01)
```

**Commit:**
```bash
git add spec/rent_calculator/database_autosave_spec.rb
git commit -m "test: update database autosave specs for config month semantics"
```

### 5.4 Update Webhook Tests

**File:** `spec/handlers/elks_webhooks_spec.rb`

```ruby
# Line 55: Update mock expectations
allow(repo).to receive(:find_by_tenant_and_period)
  .with(tenant.id, Time.utc(2025, 11, 1))  # Nov config
  .and_return(ledger)
```

**Commit:**
```bash
git add spec/handlers/elks_webhooks_spec.rb
git commit -m "test: update ELKS webhooks specs for config month semantics"
```

### 5.5 Run Full Test Suite

```bash
bundle exec rspec

# Should see all tests passing
# If failures, debug and fix before proceeding
```

---

## Phase 6: Documentation Updates (1-2 hours)

### 6.1 Update CLAUDE.md

**File:** `lib/CLAUDE.md`

Find sections referencing period semantics and update:

```markdown
## Rent Calculation Timing Quirks ⚠️

### Critical: Config Period = Rent Month - 1

**IMPORTANT:** Both RentConfig.period and RentLedger.period use config month semantics.

**Example:**
- Config period: 2025-11-01 (November config)
- Used for: December 2025 rent
- RentLedger.period: 2025-11-01 (same)
- Display: "December 2025" (via calculation_title or rent_month helper)
```

**Commit:**
```bash
git add lib/CLAUDE.md
git commit -m "docs: update CLAUDE.md to reflect unified period semantics"
```

### 6.2 Update Model Architecture Docs

**File:** `docs/MODEL_ARCHITECTURE.md`

Update repository pattern examples to clarify period = config month.

**Commit:**
```bash
git add docs/MODEL_ARCHITECTURE.md
git commit -m "docs: update model architecture docs for period semantics"
```

### 6.3 Update Rent Reminders Docs

**Files:** `docs/RENT_REMINDERS_*.md`

Update any references to period semantics.

**Commit:**
```bash
git add docs/RENT_REMINDERS_*.md
git commit -m "docs: update rent reminders docs for period semantics"
```

---

## Phase 7: Production Testing (2-3 hours)

### 7.1 Development Database Test

```bash
# Run migration on development DB
cd /home/fredrik/Projects/kimonokittens
DATABASE_URL="postgresql://kimonokittens:blargh9@localhost/kimonokittens_development" npx prisma migrate deploy

# Verify migration
DATABASE_URL="postgresql://kimonokittens:blargh9@localhost/kimonokittens_development" ruby -e "
require 'dotenv/load'
require_relative 'lib/persistence'

# Check that periods shifted correctly
entries = RentDb.instance.class.db[:RentLedger].order(:period).all
entries.each do |e|
  puts \"Period: #{e[:period]}, Title: #{e[:calculationTitle]}\"
end
"
```

### 7.2 Create Test Ledger Entry

```bash
# Create December 2025 rent ledger using November config
bundle exec ruby bin/populate_monthly_ledger 2025 11

# Should create entries with:
# - period: 2025-11-01 (November config)
# - calculationTitle: "December 2025" (rent month)
```

### 7.3 Test Rent Reminders

```bash
bundle exec ruby bin/rent_reminders --dry-run

# Verify:
# - Queries correct period (current calendar month)
# - SMS messages show correct rent month name
# - "Hyra december" (if run in November)
```

### 7.4 Test Payment Matching

```bash
# Manually test ApplyBankPayment with mock transaction
# Verify it matches to correct period
```

---

## Phase 8: Production Deployment

### 8.1 Merge to Master

```bash
# Ensure all tests pass
bundle exec rspec

# Push feature branch
git push origin unify-rent-ledger-period-semantics

# Merge to master (via PR or direct)
git checkout master
git merge unify-rent-ledger-period-semantics
git push origin master
```

### 8.2 Production Migration

```bash
# SSH to production
ssh pop

# Pull latest code
cd /home/kimonokittens/Projects/kimonokittens
git pull origin master

# Run migration
npx prisma migrate deploy

# Verify migration succeeded
ruby -e "
require 'dotenv/load'
require_relative 'lib/persistence'

puts 'Verifying period shift...'
entries = RentDb.instance.class.db[:RentLedger].order(Sequel.desc(:period)).limit(5).all
entries.each do |e|
  puts \"Period: #{e[:period].strftime('%Y-%m')}, Title: #{e[:calculationTitle]}\"
end
"
```

### 8.3 Restart Services

```bash
sudo systemctl restart kimonokittens-dashboard
sudo -u kimonokittens systemctl --user restart kimonokittens-kiosk
```

### 8.4 Smoke Tests

1. Check dashboard displays correct rent month
2. Test creating new ledger entry
3. Verify SMS reminder generation (dry-run)
4. Check admin UI payment status

---

## Rollback Plan (If Needed)

### Rollback Migration

```sql
-- Shift periods forward 1 month (reverse operation)
BEGIN;

UPDATE "RentLedger"
SET period = period + INTERVAL '1 month'
WHERE period IS NOT NULL;

COMMIT;
```

### Rollback Code

```bash
# Revert to commit before migration
git log --oneline  # Find commit hash before migration
git revert <commit-hash>..HEAD  # Revert all migration commits
git push origin master
```

---

## Success Criteria

- [ ] All tests pass
- [ ] Database migration completed without errors
- [ ] December 2025 rent shows correctly (using Nov 2025 config period)
- [ ] SMS messages display correct month name ("Hyra december" in November)
- [ ] Payment matching works
- [ ] Admin UI shows correct rent information
- [ ] Documentation updated
- [ ] No regression in existing functionality

---

## Post-Migration Cleanup

### Update Deployment Plan

Reference this migration in `PRODUCTION_DEPLOYMENT_MASTER_PLAN_NOV_2025.md`.

### Create Migration Summary

Document in session brain dump:
- What changed
- Why it was needed
- Lessons learned
- Time taken vs estimated

---

**End of Migration Plan**

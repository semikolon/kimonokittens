# Test Database Isolation Setup Guide

**Date:** October 4, 2025
**Status:** 🚧 In Progress
**Priority:** CRITICAL - Must complete before running any tests
**Backup:** ✅ Dev database backed up to `~/backups/migration_20251004/dev_db_backup_20251004_192707.sql`

---

## Table of Contents

1. [Problem Statement](#problem-statement)
2. [Current Dangerous State](#current-dangerous-state)
3. [Solution Architecture](#solution-architecture)
4. [Implementation Steps](#implementation-steps)
5. [Remaining Tasks After Setup](#remaining-tasks-after-setup)
6. [Verification Checklist](#verification-checklist)
7. [Rollback Plan](#rollback-plan)

---

## Problem Statement

### Critical Issue Discovered

**Tests are currently truncating the development database!**

```ruby
# spec/rent_calculator/support/test_helpers.rb:18
def clean_database
  db = RentDb.instance
  # This TRUNCATES dev database before EVERY test!
  db.conn.exec('TRUNCATE TABLE "Tenant", "RentConfig", "RentLedger" RESTART IDENTITY CASCADE;')
end
```

**Current state:**
- ❌ No separate test database exists
- ❌ `DATABASE_URL` points to dev database during tests
- ❌ `clean_database` truncates dev data before each test
- ❌ Running tests = losing dev data

**Evidence:**
```bash
# .env contains:
DATABASE_URL="postgresql://fredrikbranstrom@localhost:5432/kimonokittens"  # DEV!

# lib/rent_db.rb:14
@db ||= Sequel.connect(ENV.fetch('DATABASE_URL'))  # No test isolation!
```

---

## Current Dangerous State

### What Happens When Tests Run

1. **Test starts** → Loads `dotenv/load` → Reads `.env`
2. **DATABASE_URL** = `kimonokittens` (dev database)
3. **RentDb.instance** connects to dev database
4. **`clean_database` executes** → **TRUNCATES DEV TABLES** 😱
5. **Test runs** → Inserts test data into dev database
6. **Next test starts** → **TRUNCATES AGAIN** → Lost data

### Historical Contamination

**From session report:** Integration tests wrote `drift_rakning: 2612` to production database, causing incorrect rent calculations (7,492 kr instead of 7,045 kr).

**This proves tests have been contaminating databases!**

---

## Solution Architecture

### Rails-Style Environment Isolation

**Philosophy:**
1. **Separate databases per environment** (test, development, production)
2. **Explicit test detection** before any database operations
3. **Multiple safety guards** preventing cross-contamination
4. **Zero configuration** for developers (automatic test mode)

### Database Naming Convention

```
kimonokittens           # Development database (current work)
kimonokittens_test      # Test database (isolated, safe to truncate)
kimonokittens_production # Production database (on kiosk server)
```

### Environment Override Strategy

```ruby
# spec/spec_helper.rb (loads FIRST, before all other code)
ENV['DATABASE_URL'] = 'postgresql://fredrikbranstrom@localhost:5432/kimonokittens_test'

# This overrides .env file, ensuring tests ALWAYS use test database
```

### Safety Layers (Defense in Depth)

1. **Layer 1:** `spec_helper.rb` forces test database URL
2. **Layer 2:** `spec_helper.rb` validates database name contains `_test`
3. **Layer 3:** `spec_helper.rb` blocks production database
4. **Layer 4:** `clean_database` verifies test database before truncate
5. **Layer 5:** Schema isolation (test database = separate PostgreSQL database)

---

## Implementation Steps

### Step 1: Create Test Database

**Command:**
```bash
createdb kimonokittens_test
```

**Verification:**
```bash
psql -l | grep kimonokittens
# Should show:
# kimonokittens      | fredrikbranstrom | UTF8     | ...
# kimonokittens_test | fredrikbranstrom | UTF8     | ...
```

**Time:** 5 seconds
**Risk:** None (creates new database, doesn't touch existing)

---

### Step 2: Create `spec/spec_helper.rb`

**Critical:** This file loads BEFORE any other test code.

**File:** `spec/spec_helper.rb`

```ruby
# CRITICAL: Override DATABASE_URL BEFORE any code loads
# This ensures tests NEVER touch development or production databases
ENV['DATABASE_URL'] = 'postgresql://fredrikbranstrom@localhost:5432/kimonokittens_test'

# ============================================================================
# SAFETY GUARDS - Prevent catastrophic database contamination
# ============================================================================

# Safety check 1: Block production database
if ENV['DATABASE_URL']&.include?('production')
  abort "FATAL: Cannot run tests against production database!"
end

# Safety check 2: Enforce test database
unless ENV['DATABASE_URL']&.include?('_test')
  abort "FATAL: Tests must use a _test database. Found: #{ENV['DATABASE_URL']}"
end

# Visual confirmation (helps during development)
puts "=" * 80
puts "🧪 TEST MODE"
puts "=" * 80
puts "Database: #{ENV['DATABASE_URL']}"
puts "=" * 80
puts ""

# Now safe to load dotenv (our explicit override takes precedence)
require 'dotenv/load'

# Standard RSpec configuration
RSpec.configure do |config|
  # Recommended settings for modern RSpec
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.shared_context_metadata_behavior = :apply_to_host_groups

  # Filter lines from Rails gems in backtraces
  config.filter_rails_from_backtrace!

  # Disable monkey patching (best practice)
  config.disable_monkey_patching!

  # Use documentation format for readable test output
  config.default_formatter = 'doc' if config.files_to_run.one?

  # Print slowest tests
  config.profile_examples = 10

  # Run specs in random order to detect order dependencies
  config.order = :random
  Kernel.srand config.seed
end
```

**Why this works:**
- ENV override happens **before** `require 'dotenv/load'`
- All subsequent `ENV.fetch('DATABASE_URL')` calls get test database
- Safety checks prevent accidents
- Visual output confirms test mode

**Time:** 2 minutes
**Risk:** None (new file, doesn't modify existing code)

---

### Step 3: Add Safety Checks to `clean_database`

**File:** `spec/rent_calculator/support/test_helpers.rb`

**Current code (UNSAFE):**
```ruby
def clean_database
  db = RentDb.instance
  db.conn.exec('TRUNCATE TABLE "Tenant", "RentConfig", "RentLedger" RESTART IDENTITY CASCADE;')
end
```

**Updated code (SAFE):**
```ruby
def clean_database
  db = RentDb.instance

  # ============================================================================
  # CRITICAL SAFETY CHECK: Verify we're in test database before truncating
  # ============================================================================
  current_db = db.class.db.opts[:database]

  unless current_db&.include?('test')
    raise "FATAL: Attempted to clean non-test database: #{current_db}\n" \
          "This would have destroyed your development data!\n" \
          "Tests should ONLY run against databases with '_test' suffix."
  end

  # Safe to truncate test database
  db.conn.exec('TRUNCATE TABLE "Tenant", "RentConfig", "RentLedger" RESTART IDENTITY CASCADE;')

  # Optional: Truncate ElectricityBill if needed
  db.conn.exec('TRUNCATE TABLE "ElectricityBill" RESTART IDENTITY CASCADE;')
end
```

**Why this works:**
- Reads actual database name from Sequel connection
- Blocks truncate if database doesn't contain "test"
- Provides clear error message explaining what was prevented
- Additional safety layer beyond spec_helper.rb

**Time:** 1 minute
**Risk:** None (adds safety, doesn't remove functionality)

---

### Step 4: Update Test Files to Require `spec_helper`

**Need to update these files:**
```
spec/rent_calculator_spec.rb
spec/rent_calculator/config_spec.rb
spec/rent_calculator/calculator_spec.rb
spec/rent_calculator/adjustment_calculator_spec.rb
spec/rent_calculator/weight_calculator_spec.rb
spec/rent_calculator/integration_spec.rb
spec/rent_history_spec.rb
spec/websocket_integration_spec.rb
spec/handbook_handler_spec.rb
spec/strava_workouts_handler_spec.rb
spec/bank_buster_spec.rb
spec/train_departure_handler_spec.rb
```

**Add to top of each file (BEFORE other requires):**
```ruby
require_relative 'spec_helper'  # For files in spec/
# OR
require_relative '../spec_helper'  # For files in spec/subdirectory/
```

**Current pattern in integration_spec.rb:**
```ruby
require_relative 'support/test_helpers'  # Line 1
require_relative '../../handlers/rent_calculator_handler'  # Line 2
```

**Updated pattern:**
```ruby
require_relative '../spec_helper'  # NEW - MUST BE FIRST
require_relative 'support/test_helpers'
require_relative '../../handlers/rent_calculator_handler'
```

**Why order matters:**
- `spec_helper.rb` sets `ENV['DATABASE_URL']` BEFORE any code loads
- If `test_helpers.rb` loads first, it might load `rent_db.rb` with wrong DATABASE_URL
- Explicit load order = explicit test isolation

**Time:** 5 minutes (12 files to update)
**Risk:** None (only adds require, doesn't change logic)

---

### Step 5: Apply Schema to Test Database

**Two options:**

#### Option A: Prisma Migration (Recommended)
```bash
# Apply migrations to test database
DATABASE_URL="postgresql://fredrikbranstrom@localhost:5432/kimonokittens_test" \
  npx prisma migrate deploy
```

#### Option B: Manual SQL (Alternative)
```bash
# Apply schema migration SQL directly
psql kimonokittens_test -f prisma/migrations/20251004112744_remove_generated_column_extend_ledger/migration.sql
```

**Verification:**
```bash
# Check tables exist
psql kimonokittens_test -c "\dt"

# Should show:
# Tenant
# RentConfig
# RentLedger
# ElectricityBill
# _prisma_migrations
```

**Time:** 10 seconds
**Risk:** None (test database is empty, safe to apply schema)

---

### Step 6: Verify Test Isolation

**Verification commands:**

```bash
# 1. Verify test database exists and is empty
psql kimonokittens_test -c "SELECT COUNT(*) FROM \"Tenant\";"
# Expected: 0 rows

# 2. Verify dev database has data (untouched)
psql kimonokittens -c "SELECT COUNT(*) FROM \"Tenant\";"
# Expected: 8 rows (or whatever your current count is)

# 3. Run Ruby check
ruby -e "
  ENV['DATABASE_URL'] = 'postgresql://fredrikbranstrom@localhost:5432/kimonokittens_test'
  require_relative 'lib/rent_db'
  puts 'Test DB: ' + RentDb.db.opts[:database]
  puts 'Tenants: ' + RentDb.tenants.count.to_s
"
# Expected: Test DB: kimonokittens_test, Tenants: 0

# 4. Try running a single test (SAFE - will truncate test DB only)
bundle exec rspec spec/rent_calculator/config_spec.rb

# 5. Verify dev database STILL has data (proof of isolation)
psql kimonokittens -c "SELECT COUNT(*) FROM \"Tenant\";"
# Expected: 8 rows (unchanged)
```

**Time:** 2 minutes
**Risk:** Low (if isolation works, dev DB is safe; if not, safety checks should abort)

---

## Remaining Tasks After Setup

### Once Test Isolation is Verified

**From user's original request:**

> "  3. Verify Guide Clarity
>
>   The guide should explicitly state:
>   - Step 3: Apply Schema Migration → Changes database structure (Prisma)
>   - Step 5-6: Run Data Migration Scripts → Populates data (Ruby)
>
>   Want me to:
>   1. ✅ Add terminology section to guide explaining schema vs data migrations?
>   2. ✅ Create RSpec test for auto-save following existing patterns?
>   3. ✅ Run existing tests to verify nothing broke?"

### Task 1: Add Terminology Section to Production Migration Guide

**File:** `docs/PRODUCTION_MIGRATION_GUIDE.md`

**Add new section:**
```markdown
## Understanding Migration Types (Rails vs Prisma)

### For Rails Developers: Key Differences

**In Rails (what you're used to):**
```ruby
class MigrationName < ActiveRecord::Migration[7.0]
  def change
    # Schema changes
    add_column :table, :column, :type

    # Data changes (same file!)
    Model.update_all(column: value)
  end
end
```
One migration file handles both schema and data.

**In Prisma/Node Ecosystem (what we have here):**

Two completely separate systems:

1. **Prisma Migrations** = Schema Only
   - Location: `prisma/migrations/`
   - Purpose: Database structure (CREATE TABLE, ADD COLUMN)
   - Language: SQL
   - Applied: `npx prisma migrate deploy`
   - Example: `20251004112744_remove_generated_column_extend_ledger/migration.sql`

2. **Data Migration Scripts** = Data Only
   - Location: `deployment/`
   - Purpose: Populate/transform data
   - Language: Ruby (could be any language)
   - Applied: Manual execution
   - Example: `complete_rent_data_migration.rb`

**Why separate?**
- Prisma philosophy: Schema and data are separate concerns
- Schema migrations: Declarative, auto-generated, versioned
- Data migrations: Imperative, custom logic, run-once

**In this project:**
- Step 3: Apply Prisma schema migration (SQL changes structure)
- Steps 5-6: Run Ruby data migration scripts (populate tables)
```

**Time:** 10 minutes
**Complexity:** Documentation only

---

### Task 2: Create RSpec Test for Auto-Save Feature

**File:** `spec/rent_calculator/database_autosave_spec.rb` (NEW)

**Purpose:** Test that `RentCalculator.calculate_and_save` automatically saves to database

```ruby
require_relative '../spec_helper'
require_relative 'support/test_helpers'
require_relative '../../rent'
require 'time'

RSpec.describe 'RentCalculator Database Auto-Save' do
  include RentCalculatorSpec::TestHelpers

  let(:db) { RentDb.instance }

  before(:each) do
    clean_database

    # Setup test tenants
    db.add_tenant(name: 'Alice', start_date: '2024-01-01')
    db.add_tenant(name: 'Bob', start_date: '2024-01-01')
  end

  describe 'calculate_and_save' do
    context 'when test_mode is false' do
      it 'saves config values to RentConfig table' do
        # Arrange
        roommates = {
          'Alice' => { days: 30, room_adjustment: 0 },
          'Bob' => { days: 30, room_adjustment: 0 }
        }
        config = {
          year: 2025,
          month: 10,
          kallhyra: 25000,
          el: 2000,
          bredband: 400,
          vattenavgift: 375,
          va: 300,
          larm: 150
        }

        # Act
        RentCalculator.calculate_and_save(
          roommates: roommates,
          config: config,
          history_options: {
            title: 'Test October 2025 Rent',
            test_mode: false  # Enable database save
          }
        )

        # Assert - RentConfig entries created
        config_period = Time.utc(2025, 10, 1)

        saved_el = db.class.rent_configs
          .where(key: 'el', period: config_period)
          .first
        expect(saved_el).not_to be_nil
        expect(saved_el[:value].to_i).to eq(2000)

        saved_kallhyra = db.class.rent_configs
          .where(key: 'kallhyra', period: config_period)
          .first
        expect(saved_kallhyra).not_to be_nil
        expect(saved_kallhyra[:value].to_i).to eq(25000)
      end

      it 'saves per-tenant amounts to RentLedger with audit trail' do
        # Arrange
        roommates = {
          'Alice' => { days: 30, room_adjustment: 0 },
          'Bob' => { days: 15, room_adjustment: -500 }  # Half month + adjustment
        }
        config = {
          year: 2025,
          month: 10,
          kallhyra: 24000,
          el: 2000,
          bredband: 400
        }

        # Act
        results = RentCalculator.calculate_and_save(
          roommates: roommates,
          config: config,
          history_options: {
            title: 'Test Partial Month',
            test_mode: false
          }
        )

        # Assert - RentLedger entries created
        rent_period = Time.utc(2025, 11, 1)  # October config → November rent

        alice_id = db.class.tenants.where(name: 'Alice').first[:id]
        bob_id = db.class.tenants.where(name: 'Bob').first[:id]

        alice_ledger = db.class.rent_ledger
          .where(tenantId: alice_id, period: rent_period)
          .first

        bob_ledger = db.class.rent_ledger
          .where(tenantId: bob_id, period: rent_period)
          .first

        # Verify Alice's entry
        expect(alice_ledger).not_to be_nil
        expect(alice_ledger[:amountDue]).to eq(results['Rent per Roommate']['Alice'])
        expect(alice_ledger[:daysStayed]).to eq(30)
        expect(alice_ledger[:roomAdjustment]).to eq(0)
        expect(alice_ledger[:baseMonthlyRent]).to eq(12000.0)  # 24000 / 2
        expect(alice_ledger[:calculationTitle]).to eq('Test Partial Month')
        expect(alice_ledger[:calculationDate]).not_to be_nil

        # Verify Bob's entry (partial month + adjustment)
        expect(bob_ledger).not_to be_nil
        expect(bob_ledger[:amountDue]).to eq(results['Rent per Roommate']['Bob'])
        expect(bob_ledger[:daysStayed]).to eq(15)
        expect(bob_ledger[:roomAdjustment]).to eq(-500)
        expect(bob_ledger[:baseMonthlyRent]).to eq(12000.0)
      end

      it 'updates existing RentLedger entries on recalculation' do
        # Arrange - first calculation
        roommates = {
          'Alice' => { days: 30, room_adjustment: 0 },
          'Bob' => { days: 30, room_adjustment: 0 }
        }
        config = { year: 2025, month: 10, kallhyra: 24000, el: 2000, bredband: 400 }

        RentCalculator.calculate_and_save(
          roommates: roommates,
          config: config,
          history_options: { title: 'First Calculation', test_mode: false }
        )

        # Act - recalculate with different values
        new_config = { year: 2025, month: 10, kallhyra: 24000, el: 2500, bredband: 400 }

        RentCalculator.calculate_and_save(
          roommates: roommates,
          config: new_config,
          history_options: { title: 'Recalculation', test_mode: false }
        )

        # Assert - entry updated, not duplicated
        rent_period = Time.utc(2025, 11, 1)
        alice_id = db.class.tenants.where(name: 'Alice').first[:id]

        entries = db.class.rent_ledger
          .where(tenantId: alice_id, period: rent_period)
          .all

        expect(entries.count).to eq(1)  # Only one entry, not two
        expect(entries.first[:calculationTitle]).to eq('Recalculation')
      end
    end

    context 'when test_mode is true' do
      it 'does not save to database' do
        # Arrange
        roommates = {
          'Alice' => { days: 30, room_adjustment: 0 },
          'Bob' => { days: 30, room_adjustment: 0 }
        }
        config = { year: 2025, month: 10, kallhyra: 24000, el: 2000, bredband: 400 }

        # Act
        RentCalculator.calculate_and_save(
          roommates: roommates,
          config: config,
          history_options: {
            title: 'Test Mode Calculation',
            test_mode: true  # Disable database save
          }
        )

        # Assert - no database entries created
        config_period = Time.utc(2025, 10, 1)
        rent_period = Time.utc(2025, 11, 1)

        expect(db.class.rent_configs.where(period: config_period).count).to eq(0)
        expect(db.class.rent_ledger.where(period: rent_period).count).to eq(0)
      end
    end

    context 'with quarterly invoice (drift_rakning)' do
      it 'saves drift_rakning to RentConfig and reflects in calculations' do
        # Arrange
        roommates = {
          'Alice' => { days: 30, room_adjustment: 0 },
          'Bob' => { days: 30, room_adjustment: 0 }
        }
        config = {
          year: 2025,
          month: 10,
          kallhyra: 24000,
          el: 2000,
          bredband: 400,
          drift_rakning: 2612  # Quarterly invoice (replaces monthly utilities)
        }

        # Act
        results = RentCalculator.calculate_and_save(
          roommates: roommates,
          config: config,
          history_options: { title: 'With Quarterly Invoice', test_mode: false }
        )

        # Assert - drift_rakning saved
        config_period = Time.utc(2025, 10, 1)
        saved_drift = db.class.rent_configs
          .where(key: 'drift_rakning', period: config_period)
          .first

        expect(saved_drift).not_to be_nil
        expect(saved_drift[:value].to_i).to eq(2612)

        # Verify it affected total calculation
        expect(results['Total']).to eq(24000 + 2000 + 400 + 2612)
      end
    end
  end
end
```

**Coverage:**
- ✅ Config values saved to RentConfig
- ✅ Per-tenant amounts saved to RentLedger
- ✅ Audit trail fields populated correctly
- ✅ Partial month support (daysStayed)
- ✅ Room adjustments preserved
- ✅ Recalculation updates existing entries
- ✅ test_mode prevents database writes
- ✅ Quarterly invoice handling

**Time:** 30 minutes
**Risk:** None (test-only code, validates new functionality)

---

### Task 3: Run All Existing Tests

**After test isolation is verified:**

```bash
# Run all tests
bundle exec rspec

# Or run specific test suites
bundle exec rspec spec/rent_calculator/
bundle exec rspec spec/websocket_integration_spec.rb
bundle exec rspec spec/handbook_handler_spec.rb
```

**Expected outcome:**
- ✅ All tests pass
- ✅ Dev database unchanged (verify with psql)
- ✅ Test database contains test data (verify with psql)
- ✅ No cross-contamination

**If tests fail:**
- Check which database they're using
- Verify spec_helper.rb is loaded first
- Check clean_database safety validation
- Review test logic (may need updates for new database behavior)

**Time:** 5-10 minutes
**Risk:** Low (if isolation works correctly)

---

## Verification Checklist

### Before Running Any Tests

- [ ] Test database created (`kimonokittens_test`)
- [ ] `spec/spec_helper.rb` exists with DATABASE_URL override
- [ ] `spec/spec_helper.rb` has safety checks (production block, test suffix)
- [ ] `clean_database` has database name validation
- [ ] All spec files require `spec_helper` as first line
- [ ] Schema applied to test database (Tenant, RentConfig, RentLedger, ElectricityBill)
- [ ] Test database is empty (SELECT COUNT(*) = 0)
- [ ] Dev database is untouched (SELECT COUNT(*) = 8 tenants)
- [ ] Dev database backup exists (`~/backups/migration_20251004/`)

### After First Test Run

- [ ] Test passed/failed as expected
- [ ] Dev database STILL has 8 tenants (proof of isolation)
- [ ] Test database has test data (proof tests ran)
- [ ] No errors about database contamination

---

## Rollback Plan

### If Something Goes Wrong

**Scenario 1: Test database setup fails**
```bash
# Drop and recreate test database
dropdb kimonokittens_test
createdb kimonokittens_test
# Reapply schema
```

**Scenario 2: Tests accidentally truncated dev database (before safety checks)**
```bash
# Restore from backup
psql kimonokittens < ~/backups/migration_20251004/dev_db_backup_20251004_192707.sql
```

**Scenario 3: Want to start over completely**
```bash
# Remove test database
dropdb kimonokittens_test

# Remove spec_helper.rb
rm spec/spec_helper.rb

# Revert test_helpers.rb changes
git checkout spec/rent_calculator/support/test_helpers.rb

# Revert spec file changes
git checkout spec/
```

---

## Best Practices Summary

### Why This Approach

1. **Explicit override** - No ambiguity about which database tests use
2. **Multiple safety layers** - Defense in depth prevents accidents
3. **Rails-style convention** - Familiar pattern for Ruby developers
4. **Zero configuration** - Automatic for all tests once set up
5. **Production-safe** - Impossible to run tests against production
6. **Visual feedback** - Clear output showing test mode active

### Lessons Learned

**From historical contamination:**
- Tests wrote `drift_rakning: 2612` to production → wrong calculations
- Need explicit database isolation BEFORE running tests
- Safety checks catch mistakes before data loss

**Best practices:**
1. Always have separate test database
2. Always verify database name before destructive operations
3. Always backup before major changes
4. Always use explicit environment overrides in test setup

---

## Success Criteria

**Test database isolation is successful when:**

✅ Tests run without touching dev database
✅ Dev database tenant count unchanged after test runs
✅ Test database has expected test data after runs
✅ Safety checks prevent accidental dev database truncation
✅ All existing tests pass with new isolation
✅ New auto-save test passes
✅ Documentation updated with terminology clarity

---

**Status tracking:**
- [ ] Step 1: Create test database
- [ ] Step 2: Create spec_helper.rb
- [ ] Step 3: Add safety checks to clean_database
- [ ] Step 4: Update test files to require spec_helper
- [ ] Step 5: Apply schema to test database
- [ ] Step 6: Verify test isolation
- [ ] Task 1: Add terminology to migration guide
- [ ] Task 2: Create auto-save spec
- [ ] Task 3: Run all tests

**Next:** Proceed with implementation following this plan.

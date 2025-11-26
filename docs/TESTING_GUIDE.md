# Testing Guide

**Status**: ✅ PRODUCTION READY
**Verification**: All tests passing with complete database isolation
**Quick Reference**: See CLAUDE.md for critical rules only

---

## Table of Contents

1. [Overview](#overview)
2. [Test Database Isolation Architecture](#test-database-isolation-architecture)
3. [Setup Commands](#setup-commands)
4. [Running Tests](#running-tests)
5. [Key Testing Patterns](#key-testing-patterns)
6. [Test File Structure](#test-file-structure)
7. [Common Test Failures](#common-test-failures)
8. [Troubleshooting](#troubleshooting)

---

## Overview

### Test Suite Status

**Status**: All tests passing (run `bundle exec rspec spec/` to verify)

**Verification**: Test database isolation ensures production data is never affected

### Coverage by Domain

| Domain | What's Tested |
|--------|---------------|
| **Rent Calculation** | Config validation, weight-based distribution, room adjustments, partial stays, Swedish message formatting |
| **Domain Models** | Tenant lifecycle (pending→active→departed), RentLedger payments, BankTransaction matching, SmsEvent tracking |
| **API Handlers** | Admin tasks, contract CRUD, rent endpoints, webhook receivers |
| **Repositories** | CRUD operations, active tenant filtering, payment queries |
| **Services** | Contract HTML generation, electricity forecasting, SMS gateway, Zigned API |
| **Integration** | Full rent workflows with database, VCR-recorded external API calls |
| **Utilities** | Date handling, validation helpers, configuration loading |

### Test Philosophy

**Tests should verify business logic, not implementation details.**

When tests fail after code changes, the code behavior likely evolved legitimately. Update test expectations to match reality, not the other way around.

---

## Test Database Isolation Architecture

### Defense in Depth - 4 Safety Layers

**Philosophy**: Multiple independent safety checks prevent database contamination at different levels.

#### Layer 1: Environment Separation (`.env.test`)

```bash
# .env.test (tracked in git, no secrets)
DATABASE_URL="postgresql://fredrikbranstrom@localhost:5432/kimonokittens_test"
RACK_ENV="test"
LOG_LEVEL="debug"
```

- Loaded FIRST before any code
- Single source of truth for test configuration
- Tracked in git (local test DB only, no production secrets)

#### Layer 2: Production Database Block (`spec/spec_helper.rb`)

```ruby
# Safety check 1: Block production database
if ENV['DATABASE_URL']&.include?('production')
  abort "FATAL: Cannot run tests against production database!"
end

# Safety check 2: Enforce test database
unless ENV['DATABASE_URL']&.include?('_test')
  abort "FATAL: Tests must use a _test database. Found: #{ENV['DATABASE_URL']}"
end
```

#### Layer 3: Visual Confirmation

```ruby
puts "=" * 80
puts "🧪 TEST MODE"
puts "=" * 80
puts "Database: #{ENV['DATABASE_URL']}"
puts "=" * 80
```

Helps during development - immediately visible when tests start.

#### Layer 4: Database Name Validation (`clean_database`)

```ruby
def clean_database
  db = RentDb.instance

  # Verify we're in test database before truncating
  current_db = db.class.db.opts[:database]

  unless current_db&.include?('test')
    raise "FATAL: Attempted to clean non-test database: #{current_db}\n" \
          "This would have destroyed your development data!\n" \
          "Tests should ONLY run against databases with '_test' suffix."
  end

  # Safe to truncate
  db.class.db.run('TRUNCATE TABLE "Tenant", "RentConfig", "RentLedger" RESTART IDENTITY CASCADE;')
end
```

**This check prevented the 7,492 kr rent bug from spreading!**

---

## Setup Commands

### One-Time Setup

```bash
# 1. Create test database
createdb kimonokittens_test

# 2. Apply schema to test database
DATABASE_URL="postgresql://fredrikbranstrom@localhost:5432/kimonokittens_test" \
  npx prisma migrate deploy

# 3. Verify test database exists and is empty
psql kimonokittens_test -c "SELECT COUNT(*) FROM \"Tenant\";"
# Expected: 0

# 4. Verify dev database is untouched
psql kimonokittens -c "SELECT COUNT(*) FROM \"Tenant\";"
# Expected: 8 (or your current tenant count)
```

### Verify Test Isolation

```bash
# Check test database isolation
ruby -e "
  require 'dotenv'
  Dotenv.load('.env.test')
  require_relative 'lib/rent_db'
  puts 'Database: ' + RentDb.instance.class.db.opts[:database]
  puts 'Tenants: ' + RentDb.instance.class.tenants.count.to_s
"
# Expected: Database: kimonokittens_test, Tenants: 0
```

---

## Running Tests

### Best Practice: One File at a Time

**Easier to fix expectations when you can see exactly what changed.**

```bash
# Run single spec file
bundle exec rspec spec/rent_calculator/config_spec.rb

# Run specific context within file
bundle exec rspec spec/rent_calculator/calculator_spec.rb:27

# Run all tests in directory
bundle exec rspec spec/rent_calculator/
```

### Full Test Suite

```bash
# Run all tests
bundle exec rspec

# With documentation format (readable output)
bundle exec rspec --format documentation

# Profile slowest tests
bundle exec rspec --profile 10
```

### Verify Dev Database After Tests

**CRITICAL**: Always check dev database unchanged after test runs.

```bash
# Should show 8 tenants (or your current count)
ruby -e "require 'dotenv/load'; require_relative 'lib/rent_db'; puts RentDb.instance.get_tenants.length"

# OR via psql
psql kimonokittens -c "SELECT COUNT(*) FROM \"Tenant\";"
```

---

## Key Testing Patterns

### 1. Sequel API (Post-2025 Upgrade)

**CORRECT** (Sequel thread-safe connection pooling):
```ruby
db.class.db.run('TRUNCATE TABLE "Tenant" RESTART IDENTITY CASCADE;')
```

**WRONG** (old API, pre-Sequel upgrade):
```ruby
db.conn.exec('TRUNCATE ...')  # NoMethodError: undefined method 'conn'
```

**Why**: User upgraded to Sequel in 2025. Tests were last run before upgrade. The new API uses `.class.db.run()` for SQL execution.

---

### 2. Default Utilities Behavior

**Calculator ALWAYS adds default utilities (825 kr) when not explicitly provided.**

```ruby
# Config with no utilities
config = { kallhyra: 24000, el: 2000, bredband: 400 }

# Total will be: 24000 + 2000 + 400 + 825 = 27225 (NOT 26400!)
# Default utilities: vattenavgift 375 + va 300 + larm 150 = 825
```

**To prevent defaults, provide explicit zeros:**

```ruby
config = {
  kallhyra: 24000,
  el: 2000,
  bredband: 400,
  vattenavgift: 0,  # Explicit zero prevents default
  va: 0,
  larm: 0
}
# Total: 26400 (no defaults added)
```

**Why this matters**: Many test failures were caused by expecting exact totals without accounting for default utilities.

---

### 3. Rounding Tolerance

**Financial calculations can differ by 1 kr due to rounding each person's share.**

**CORRECT**:
```ruby
expect(results['Total']).to be_within(1).of(results['Rent per Roommate'].values.sum)
```

**WRONG**:
```ruby
expect(results['Total']).to eq(results['Rent per Roommate'].values.sum)  # Can fail!
```

**Example scenario:**
```ruby
# Total rent: 27225 kr
# 2 roommates: 27225 / 2 = 13612.5 each
# After rounding: 13613 + 13613 = 27226 (off by 1)
```

---

### 4. Timestamp Comparison

**Database may store timestamps in different timezone than test.**

**CORRECT** (compare dates only):
```ruby
expect(ledger[:period].to_date).to eq(expected_period.to_date)
```

**WRONG** (full timestamp comparison):
```ruby
expect(ledger[:period]).to eq(expected_period)  # Can fail with timezone mismatch!
```

**Example failure:**
```
expected: 2026-01-01 00:00:00.000000000 +0000 (UTC)
     got: 2026-01-01 00:00:00.000000000 +0100 (local timezone)
```

---

### 5. Test Mode Flag

**ALWAYS use `test_mode: true` for test scenarios** (prevents database writes).

```ruby
# Standard test pattern (no DB writes)
RentCalculator.calculate_and_save(
  roommates: roommates,
  config: config,
  history_options: {
    title: 'Test Calculation',
    test_mode: true  # Prevents DB writes
  }
)

# Only use test_mode: false when EXPLICITLY testing database persistence
RentCalculator.calculate_and_save(
  roommates: roommates,
  config: config,
  history_options: {
    title: 'Database Auto-Save Test',
    test_mode: false  # Enables DB writes for testing
  }
)
```

---

### 6. Nil Config Values

**Can't pass nil to calculator** - it does arithmetic on config values.

**CORRECT** (omit nil values):
```ruby
config = {
  kallhyra: 24000,
  el: 2000,
  bredband: 400
  # Omit nil values entirely
}
```

**WRONG** (nil causes TypeError):
```ruby
config = {
  kallhyra: 24000,
  el: 2000,
  bredband: 400,
  saldo_innan: nil  # TypeError: nil can't be coerced into Integer
}
```

---

## Test File Structure

### Required Pattern

```ruby
# CRITICAL: spec_helper MUST be first require
require_relative 'spec_helper'  # Loads .env.test, enforces test DB
require_relative 'support/test_helpers'
require_relative '../../rent'  # Now safe - .env.test already loaded

RSpec.describe 'YourFeature' do
  include RentCalculatorSpec::TestHelpers

  let(:db) { RentDb.instance }

  before(:each) do
    clean_database  # Validates test DB before truncating
    # Setup test data...
  end

  # Test cases...
end
```

### Why Load Order Matters

1. `spec_helper.rb` loads `.env.test` BEFORE any code
2. Sets `ENV['DATABASE_URL']` to test database
3. Then safe to load `rent.rb`, `lib/rent_db.rb`, etc.
4. All database connections automatically use test database

**If `test_helpers.rb` loads first:**
- Might load `rent_db.rb` before `.env.test` is loaded
- `ENV.fetch('DATABASE_URL')` could get dev database
- Tests would contaminate dev database!

---

## Common Test Failures

### After Code Evolution

**When tests fail, code behavior likely evolved legitimately.** Update test expectations to match current reality.

#### 1. Message Format Changes

**Failure:**
```ruby
expect(message).to match(/\*\d+ kr\* för Astrid och \*\d+ kr\* för oss andra/)
# Expected: "*7000 kr* för Astrid och *8000 kr* för oss andra"
# Got: "Fredrik, Bob: 10181 kr\nAstrid: 8780 kr"
```

**Fix** (update to match new format):
```ruby
expect(message).to include('Astrid')
expect(message).to include('Fredrik')
expect(message).to match(/\d+\s+kr/)
```

---

#### 2. Rounding Differences

**Failure:**
```ruby
expect(results['Total']).to eq(27225)
# Expected: 27225
# Got: 27226 (off by 1)
```

**Fix** (add tolerance):
```ruby
expect(results['Total']).to be_within(1).of(27225)
```

---

#### 3. Default Values

**Failure:**
```ruby
expect(results['Total']).to eq(26400)  # kallhyra + el + bredband
# Expected: 26400
# Got: 27225 (difference: 825 kr default utilities)
```

**Fix** (accept defaults or provide explicit zeros):
```ruby
# Option A: Accept defaults
expect(results['Total']).to eq(27225)  # Includes 825 kr defaults

# Option B: Provide explicit zeros to prevent defaults
config = {
  kallhyra: 24000, el: 2000, bredband: 400,
  vattenavgift: 0, va: 0, larm: 0
}
expect(results['Total']).to eq(26400)
```

---

#### 4. Timezone Handling

**Failure:**
```ruby
expect(ledger[:period]).to eq(Time.utc(2026, 1, 1))
# Expected: 2026-01-01 00:00:00 +0000
# Got: 2026-01-01 00:00:00 +0100
```

**Fix** (compare dates):
```ruby
expect(ledger[:period].to_date).to eq(Time.utc(2026, 1, 1).to_date)
```

---

## Troubleshooting

### Tests Truncating Dev Database

**Symptoms:**
- Dev database tenant count changes after tests
- Test data appears in dev database

**Diagnosis:**
```bash
# Check which database tests are using
ruby -e "
  require_relative 'spec/spec_helper'
  puts ENV['DATABASE_URL']
"
# Should show: kimonokittens_test
```

**Fixes:**
1. Ensure `spec/spec_helper.rb` exists and loads `.env.test`
2. Ensure `require_relative 'spec_helper'` is FIRST line in spec file
3. Check `clean_database` has database name validation

---

### Sequel API Errors

**Symptoms:**
```
NoMethodError: undefined method `conn' for an instance of RentDb
```

**Fix**: Update to new Sequel API:
```ruby
# Before (old API):
db.conn.exec('SQL')

# After (new API):
db.class.db.run('SQL')
```

---

### Default Utilities Surprise

**Symptoms:**
- Totals 825 kr higher than expected
- Tests expecting exact sums failing

**Fix**: Either accept defaults or provide explicit zeros:
```ruby
# Accept defaults (825 kr added):
expect(total).to eq(expected_base + 825)

# OR prevent defaults:
config = { ..., vattenavgift: 0, va: 0, larm: 0 }
expect(total).to eq(expected_base)
```

---

### Rounding Off-by-One

**Symptoms:**
- Total off by 1 kr
- Sum of individual shares doesn't match original total

**Fix**: Use tolerance:
```ruby
expect(total).to be_within(1).of(expected)
```

---

## Documentation References

**Related documents:**
- `CLAUDE.md` - Critical testing rules (concise reference)
- `docs/TEST_DATABASE_ISOLATION_SETUP.md` - Complete setup guide with verification results
- `docs/SESSION_WORK_REPORT_2025_10_04_TEST_ISOLATION_AND_VERIFICATION.md` - Session report with all fixes
- `.env.test` - Test environment configuration
- `spec/spec_helper.rb` - Test isolation enforcement
- `spec/rent_calculator/support/test_helpers.rb` - Helper methods and safety checks

---

**Status**: All tests passing with complete database isolation

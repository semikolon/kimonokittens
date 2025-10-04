# Rent Data Architecture Analysis: Complete Database Migration Plan

**Date:** October 4, 2025
**Status:** ✅ APPROVED - Ready for implementation
**Context:** After successful RentConfig migration, planning complete elimination of JSON/text files

---

## Executive Summary

**Goal:** Migrate all historical rent data from JSON files and electricity bills text file into PostgreSQL database, enabling complete deletion of these files.

**Approach:** Hybrid architecture (normalized master data + immutable ledger) - the financial industry standard.

**Outcome:** Single source of truth = PostgreSQL database, with git history as disaster recovery.

---

## Critical Insight: Why We Need This Migration

### Current Problem
**Data is split across three locations:**
1. **Database** (RentConfig, RentLedger) - Partial data only
2. **JSON files** (data/rent_history/*.json) - Complete calculation snapshots
3. **Text file** (electricity_bills_history.txt) - Provider bills

**This creates:**
- Dual maintenance burden (update both database AND files)
- Query complexity (must parse files for historical data)
- Data integrity risk (sources can diverge)
- Unclear single source of truth

### The Solution: Financial Best Practice Pattern

**GPT-5's recommendation:** Option C (Hybrid Architecture)
- **Normalized master data** → Who lives here, current state
- **Immutable ledger** → Historical snapshots of what was billed
- **Standard in accounting/ERP systems** → Proven pattern

**Why this works:**
1. **Auditability:** Can't retroactively change past bills
2. **No drift:** Later rule changes don't affect historical data
3. **Fast queries:** No file parsing needed
4. **Complete information:** Captures WHY amount was charged

---

## Existing Database Structures (Already Present!)

### Tenant Table ✅

**Already contains most needed data:**

```ruby
model Tenant {
  id             String    @id @default(cuid())
  name           String
  email          String    @unique
  roomAdjustment Float?    # CURRENT pricing adjustment
  startDate      DateTime? # When they moved in
  departureDate  DateTime? # When they moved out
  # ... other fields
}
```

**Current data:**
- Astrid: roomAdjustment = -1400, lived Feb 2024 - Nov 2024
- Fredrik: startDate = Feb 2023 (still living here)
- etc.

**What it provides:**
- ✅ Who lived here when (startDate/departureDate)
- ✅ Current room adjustment
- ❌ **Missing:** Historical per-period adjustment values
- ❌ **Missing:** Days stayed that specific month (15.5 for partial months)

### RentLedger Table ✅

**Already exists, but incomplete:**

```ruby
model RentLedger {
  id          String    @id @default(cuid())
  tenantId    String
  period      DateTime  # Rent month
  amountDue   Float     # What they owed
  amountPaid  Float     # What they paid
  paymentDate DateTime?
  createdAt   DateTime
}
```

**Current population:** Created from JSON `final_results` by production_migration.rb

**What it has:**
- ✅ Final amounts (who owed what)
- ✅ Payment tracking
- ❌ **Missing:** HOW amount was calculated
- ❌ **Missing:** Days stayed
- ❌ **Missing:** Room adjustment applied that period

### ElectricityBill Table ✅

**Already defined in schema (not yet populated):**

```ruby
model ElectricityBill {
  id          String   @id @default(cuid())
  provider    String   # "fortum" or "vattenfall"
  billDate    DateTime # Due date
  amount      Float    # Amount in SEK
  billPeriod  DateTime # Consumption month
  createdAt   DateTime
  updatedAt   DateTime
}
```

**Perfect for replacing electricity_bills_history.txt!**

---

## What's Missing: The Gap Analysis

### Data Unique to JSON Files

**RentHistory JSON structure:**
```json
{
  "metadata": {
    "calculation_date": "2025-03-10T11:53:13+01:00",
    "version": 10,
    "title": "March 2025 - With Adam (Exact Half Rent)"
  },
  "roommates": {
    "Adam": { "days": 15.5, "room_adjustment": 0 }
  },
  "final_results": {
    "Adam": 4526
  }
}
```

**Critical data NOT in database:**
1. **Days stayed that month** (15.5 for partial month)
2. **Room adjustment applied THAT period** (not just current)
3. **Calculation metadata** (title, version, when calculated)
4. **Audit trail** (how was final amount derived?)

**Why this matters:**
- Can't answer "Why did Adam pay 4526 kr?" without JSON file
- Can't verify calculation accuracy
- Can't handle disputes ("I only stayed 15 days!")

---

## The Hybrid Architecture Solution

### Core Principle: Immutable Ledger Pattern

**Financial best practice (accounting/ERP systems):**

**Normalized tables** (current state, planning):
- Tenant → Who lives here now, current adjustment
- (Future) Occupancy history → Effective-dated tenancy periods
- (Future) Adjustment history → When adjustment values changed

**Immutable ledger** (what was actually billed):
- RentLedger → Snapshot of what we charged, with full context

**Key insight:** The ledger captures inputs used AT BILLING TIME, preventing retroactive drift.

### Modified Approach: Extend RentLedger (Not New Table)

**Instead of creating `RentCalculation` table, extend existing `RentLedger`:**

```diff
model RentLedger {
  id          String    @id @default(cuid())
  tenantId    String
  period      DateTime
  amountDue   Float
  amountPaid  Float
  paymentDate DateTime?
  createdAt   DateTime
+  # NEW: Audit trail fields
+  daysStayed       Float?    # For partial months (15.5 days)
+  roomAdjustment   Float?    # Adjustment applied THAT period
+  baseMonthlyRent  Float?    # Base rent used for calculation
+  calculationTitle String?   # "March 2025 - With Adam"
+  calculationDate  DateTime? # When calculation was performed
  tenant      Tenant    @relation(fields: [tenantId], references: [id])
}
```

**Benefits:**
- ✅ Minimal schema changes (extend existing table)
- ✅ All data in one place per tenant-period
- ✅ Preserves complete audit trail
- ✅ Supports partial months (days: 15.5)
- ✅ Historical adjustment values preserved
- ✅ No complex joins needed for queries

**Why this is better than separate `RentCalculation` table:**
- Simpler queries (one table instead of joins)
- Natural grouping (billing data + context together)
- Matches financial ledger pattern (single immutable record)

---

## Complete Migration Plan

### Phase 1: Schema Migration (Prisma)

**Add fields to RentLedger:**

```prisma
model RentLedger {
  id               String    @id @default(cuid())
  tenantId         String
  period           DateTime
  amountDue        Float
  amountPaid       Float
  paymentDate      DateTime?
  createdAt        DateTime  @default(now())

  // Audit trail fields (NEW)
  daysStayed       Float?    // Partial months supported
  roomAdjustment   Float?    // Historical adjustment value
  baseMonthlyRent  Float?    // Base rent that period
  calculationTitle String?   // Human-readable context
  calculationDate  DateTime? // When bill was generated

  tenant           Tenant    @relation(fields: [tenantId], references: [id])
}
```

**Migration steps:**
1. `npx prisma migrate dev --name extend_rent_ledger_audit_fields`
2. Verify migration SQL
3. Apply to development database

### Phase 2: Historical Data Migration

**Script: `deployment/complete_rent_data_migration.rb`**

#### Part A: Update Existing RentLedger Records

**Source:** JSON `roommates` section

```ruby
# For each historical JSON file:
data = JSON.parse(File.read(json_file))

# Extract metadata
config_month = data['constants']['month']
rent_month = config_month + 1
calc_date = Time.parse(data['metadata']['calculation_date'])
title = data['metadata']['title']

# Update each tenant's ledger entry
data['roommates'].each do |tenant_name, config|
  # Find existing RentLedger record
  ledger_entry = RentLedger.find_by(
    tenant_id: tenant_id_map[tenant_name],
    period: Time.new(rent_year, rent_month, 1)
  )

  # Add audit trail data
  ledger_entry.update!(
    daysStayed: config['days'],
    roomAdjustment: config['room_adjustment'] || 0,
    baseMonthlyRent: data['constants']['kallhyra'] / data['roommates'].size.to_f,
    calculationTitle: title,
    calculationDate: calc_date
  )
end
```

**Handles:**
- ✅ Partial months (Adam: 15.5 days)
- ✅ Room adjustments (Astrid: -1400 historically)
- ✅ Base rent changes over time
- ✅ Calculation metadata preservation

#### Part B: Populate ElectricityBill Table

**Source:** `electricity_bills_history.txt`

```ruby
# For each line in text file:
# "2025-10-01  1632 kr"

ElectricityBill.create!(
  provider: detect_provider(line),  # "vattenfall" or "fortum"
  billDate: parse_date(line),       # 2025-10-01
  amount: parse_amount(line),       # 1632
  billPeriod: calculate_consumption_month(billDate) # 2025-09-01
)
```

**Provider detection logic:**
```ruby
def detect_provider(date, amount)
  # Heuristic: Vattenfall bills are typically larger
  # Can be refined with historical patterns
  amount > 1000 ? 'vattenfall' : 'fortum'
  # Or: Manual mapping for known bills
end
```

**Consumption month calculation:**
```ruby
def calculate_consumption_month(due_date)
  # Bills lag by ~1 month
  # Oct 1 due date → Sep consumption
  due_date - 1.month
end
```

### Phase 3: Verification & Cleanup

**Verification queries:**

```ruby
# 1. Verify all ledger entries have audit data
missing_audit = RentLedger.where(daysStayed: nil).count
puts "Missing audit data: #{missing_audit}" # Should be 0

# 2. Verify electricity bills match RentConfig totals
period = Time.new(2025, 9, 1)
bill_total = ElectricityBill.where(billPeriod: period).sum(:amount)
config_total = RentConfig.find_by(key: 'el', period: period).value.to_f
puts "Match: #{bill_total == config_total}" # Should be true

# 3. Spot check: Adam's half-month rent
adam_march = RentLedger.find_by(
  tenant: Tenant.find_by(name: 'Adam'),
  period: Time.new(2025, 3, 1)
)
puts "Adam March: #{adam_march.daysStayed} days, #{adam_march.amountDue} kr"
# Should show: 15.5 days, 4526 kr

# 4. Count totals
puts "RentLedger records: #{RentLedger.count}"
puts "ElectricityBill records: #{ElectricityBill.count}"
```

**Cleanup steps:**
1. ✅ Backup JSON files to archive directory
2. ✅ Delete `data/rent_history/*.json`
3. ✅ Delete `electricity_bills_history.txt`
4. ✅ Update rent.rb to NOT save JSON files
5. ✅ Git commit with message documenting deletion

---

## Phase 4: Update rent.rb Auto-Save

**Current behavior:**
```ruby
def calculate_and_save(...)
  history.save  # Saves to JSON only
end
```

**New behavior:**
```ruby
def calculate_and_save(roommates:, config: {}, history_options: {})
  breakdown = rent_breakdown(roommates: roommates, config: config)
  rent_period = Time.new(config.year, config.month + 1, 1)

  # Save to database (PRIMARY)
  breakdown['Rent per Roommate'].each do |name, amount|
    RentLedger.create!(
      tenantId: get_tenant_id_by_name(name),
      period: rent_period,
      amountDue: amount,
      amountPaid: 0,  # Not yet paid

      # Audit trail (NEW)
      daysStayed: roommates[name][:days] || days_in_month(rent_period),
      roomAdjustment: roommates[name][:room_adjustment] || 0,
      baseMonthlyRent: config[:kallhyra] / roommates.size.to_f,
      calculationTitle: history_options[:title],
      calculationDate: Time.now
    )
  end

  # Save config values
  config.to_h.each do |key, value|
    next if value.nil? || value == 0
    db.set_config(key, value.to_s, Time.new(config.year, config.month, 1))
  end

  # NO LONGER SAVE TO JSON
  # history.save  # DELETE THIS LINE

  breakdown
end
```

**Benefits:**
- Database becomes authoritative immediately
- No dual maintenance
- Consistent with historical data
- Complete audit trail preserved

---

## Data Flow: Before vs After

### Before (Current State)

```
Rent Calculation (rent.rb)
  ↓
RentHistory JSON file (primary)
  ↓ (production_migration.rb - manual)
  ├→ RentLedger (amounts only, partial data)
  └→ RentConfig (config values only)

Electricity bills
  ↓
electricity_bills_history.txt (primary)
  ↓ (historical_config_migration.rb - manual)
  └→ RentConfig (aggregated by period)

Query for history: Parse JSON files
```

### After (Target State)

```
Rent Calculation (rent.rb)
  ↓
  ├→ RentLedger (complete: amounts + audit trail)
  └→ RentConfig (config values)

Electricity bills
  ↓
ElectricityBill table (individual bills)
  ↓ (aggregated on-the-fly)
  └→ RentConfig (for rent calculations)

Query for history: SELECT from database
```

**Files deleted:**
- ✅ `data/rent_history/*.json` (14+ files)
- ✅ `electricity_bills_history.txt`
- ✅ Still in git history for disaster recovery

---

## Migration Script Structure

**File:** `deployment/complete_rent_data_migration.rb`

```ruby
#!/usr/bin/env ruby
# Complete Rent Data Migration: JSON + Text File → Database
# Usage: ruby deployment/complete_rent_data_migration.rb

require 'dotenv/load'
require_relative '../lib/rent_db'
require 'json'

puts "=== COMPLETE RENT DATA MIGRATION ==="
puts "Migrating JSON files + text file → PostgreSQL"
puts

db = RentDb.instance

# PHASE 1: Extend RentLedger with audit data from JSON files
puts "📊 PHASE 1: Updating RentLedger with audit trail data"
json_count = 0

Dir.glob('data/rent_history/*.json').sort.each do |json_file|
  data = JSON.parse(File.read(json_file))

  # Extract period info
  config_month = data['constants']['month'] || extract_from_filename(json_file)
  config_year = data['constants']['year'] || extract_from_filename(json_file)
  rent_month = config_month + 1
  rent_year = config_year
  # ... handle year rollover ...

  # Update each tenant's ledger entry
  data['roommates'].each do |tenant_name, config|
    tenant = db.class.tenants.where(name: tenant_name).first
    next unless tenant

    ledger = db.class.rent_ledger.where(
      tenantId: tenant[:id],
      period: Time.new(rent_year, rent_month, 1)
    ).first

    if ledger
      db.class.rent_ledger.where(id: ledger[:id]).update(
        daysStayed: config['days'] || days_in_month(rent_month, rent_year),
        roomAdjustment: config['room_adjustment'] || 0,
        baseMonthlyRent: data['constants']['kallhyra'] / data['roommates'].size.to_f,
        calculationTitle: data['metadata']['title'],
        calculationDate: Time.parse(data['metadata']['calculation_date'])
      )
      json_count += 1
    end
  end
end

puts "✅ Updated #{json_count} RentLedger entries with audit data"

# PHASE 2: Migrate electricity bills to ElectricityBill table
puts "\n📄 PHASE 2: Migrating electricity bills to database"
bill_count = 0

File.readlines('electricity_bills_history.txt').each do |line|
  next if line.strip.empty? || line.include?('Vattenfall') || line.include?('Fortum')

  if line =~ /^(\d{4})-(\d{2})-(\d{2})\s+(\d+)/
    due_date = Date.parse("#{$1}-#{$2}-#{$3}")
    amount = $4.to_i
    provider = detect_provider(due_date, amount)
    consumption_month = calculate_consumption_month(due_date)

    db.class.electricity_bills.insert(
      id: Cuid.generate,
      provider: provider,
      billDate: due_date,
      amount: amount,
      billPeriod: consumption_month,
      createdAt: Time.now,
      updatedAt: Time.now
    )
    bill_count += 1
  end
end

puts "✅ Migrated #{bill_count} electricity bills"

# PHASE 3: Verification
puts "\n✅ MIGRATION COMPLETE"
puts "\n📊 Verification:"
puts "   RentLedger with audit data: #{db.class.rent_ledger.where { Sequel.~(daysStayed: nil) }.count}"
puts "   ElectricityBill records: #{db.class.electricity_bills.count}"
puts "\n⚠️  NEXT STEPS:"
puts "   1. Run verification queries (see docs)"
puts "   2. Backup JSON files: mv data/rent_history data/rent_history_backup"
puts "   3. Delete text file: git rm electricity_bills_history.txt"
puts "   4. Update rent.rb to stop saving JSON"
puts "   5. Commit changes"
```

---

## Implementation Timeline

### Immediate (Do Now)
1. ✅ Create architecture documentation (this file)
2. ⏸️ Create Prisma migration for RentLedger fields
3. ⏸️ Write complete migration script
4. ⏸️ Test locally (verify all data migrates)
5. ⏸️ Run in production

### Same Session (After Migration Verified)
1. Update rent.rb to save to database (not JSON)
2. Delete JSON files (after backup)
3. Delete text file
4. Git commit all changes

### Future (Low Priority)
1. Add effective-dated Occupancy table (if needed)
2. Add AdjustmentHistory table (if needed)
3. Build query interfaces for historical data
4. Dashboard widgets for payment tracking

---

## Risk Mitigation

### Migration Risks

**Risk:** Data loss during migration
**Mitigation:**
- ✅ Run locally first
- ✅ Verify counts match
- ✅ Spot check critical records
- ✅ Keep JSON/text files until verified
- ✅ Git backup (can restore any file)

**Risk:** Missing edge cases
**Mitigation:**
- ✅ Test with all 14+ historical JSON files
- ✅ Handle old format (2023_11_v1.json without year/month)
- ✅ Verify partial months (15.5 days)
- ✅ Check room adjustments (-1400)

**Risk:** Production deployment failure
**Mitigation:**
- ✅ Idempotent migration (can re-run)
- ✅ Transaction support (all or nothing)
- ✅ Rollback plan (restore from backup)

### Post-Migration Risks

**Risk:** Can't verify old calculations
**Mitigation:**
- ✅ Git history preserves JSON files forever
- ✅ Complete audit trail in RentLedger
- ✅ Can still clone old commit and read JSONs

**Risk:** Missing context for disputes
**Mitigation:**
- ✅ calculationTitle field ("March 2025 - With Adam")
- ✅ daysStayed shows exact partial month details
- ✅ roomAdjustment shows historical pricing

---

## Success Criteria

**Migration is successful when:**

1. ✅ All RentLedger entries have audit fields populated
2. ✅ ElectricityBill table has all historical bills
3. ✅ Spot checks match JSON file data exactly
4. ✅ No queries need JSON file parsing
5. ✅ rent.rb saves to database (not JSON)
6. ✅ JSON files deleted, only in git history
7. ✅ Text file deleted, only in git history
8. ✅ Single source of truth = PostgreSQL

**Verification queries pass:**
```sql
-- No missing audit data
SELECT COUNT(*) FROM "RentLedger" WHERE "daysStayed" IS NULL;  -- Should be 0

-- Bill totals match config
SELECT SUM(amount) FROM "ElectricityBill" WHERE "billPeriod" = '2025-09-01';  -- Should match RentConfig

-- Partial month preserved
SELECT "daysStayed", "amountDue" FROM "RentLedger"
WHERE "tenantId" = (SELECT id FROM "Tenant" WHERE name = 'Adam')
AND period = '2025-03-01';  -- Should show 15.5 days

-- Total record counts
SELECT COUNT(*) FROM "RentLedger";  -- Should be 58+ (all historical + new)
SELECT COUNT(*) FROM "ElectricityBill";  -- Should be ~48 (2 providers × 24 months)
```

---

## FAQs

### Why extend RentLedger instead of separate RentCalculation table?

**Answer:** Simpler queries, matches financial ledger pattern (single immutable record), natural grouping of billing data + context.

### Can we derive who lived when from Tenant.startDate/departureDate?

**Answer:** Partially yes, but:
- ❌ Can't represent partial months (15.5 days)
- ❌ Loses historical adjustment values (Astrid's -1400 for specific periods)
- ❌ No audit trail of what was ACTUALLY used in calculation

**Better:** Store snapshot in RentLedger (immutable financial record).

### Should we keep JSON files after migration?

**Answer:** NO - delete them immediately after verification:
- ✅ Git history = disaster recovery (can restore any commit)
- ✅ Database = complete data with better query capabilities
- ✅ No dual maintenance burden
- ✅ Clear single source of truth

### What about electricity text file?

**Answer:** DELETE after migrating to ElectricityBill table:
- ✅ Database has individual bills (better granularity)
- ✅ Can aggregate on-the-fly for any period
- ✅ Git history preserves original if needed
- ✅ ElectricityBill schema supports future automation

### How do we handle future calculations?

**Answer:** Update rent.rb to save directly to database:
- RentLedger: Complete record (amount + audit trail)
- RentConfig: Input values by period
- ElectricityBill: Individual provider bills (manual or automated)
- NO JSON files created

---

## Conclusion

**This migration achieves:**
- ✅ Single source of truth (PostgreSQL)
- ✅ Complete audit trail (who paid what, why)
- ✅ Financial best practices (immutable ledger)
- ✅ Fast queries (no file parsing)
- ✅ Clean codebase (no dual systems)
- ✅ Git backup (disaster recovery)

**Ready to implement!** 🚀

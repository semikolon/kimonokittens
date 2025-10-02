# RentConfig Schema Migration Plan

**Date**: September 28, 2025
**Purpose**: Fix temporal configuration contamination bug
**Approach**: Composite key with month-level uniqueness (GPT-5 recommended)

## Problem Statement

Current `RentConfig` table has `UNIQUE` constraint on `key` column, preventing multiple time periods per configuration key. This causes:
- Quarterly invoices from 2024 contaminating 2025 calculations
- Cannot store monthly electricity bills (September + October electricity)
- Forces dangerous "most recent value" logic for all configuration types

## Solution: Option 2 - Composite Key with Refinements

### Current Schema
```sql
RentConfig (
  id text PRIMARY KEY,
  key text UNIQUE,          -- ❌ PROBLEM: Only one record per key
  value text,
  period timestamp,
  createdAt timestamp,
  updatedAt timestamp
)
```

### Target Schema
```sql
RentConfig (
  id text PRIMARY KEY,
  key text,                 -- ✅ Multiple records per key allowed
  value text,
  period timestamp,         -- ✅ Normalized to month start
  period_month date,        -- ✅ Generated column for uniqueness
  createdAt timestamp,
  updatedAt timestamp,
  UNIQUE(key, period_month) -- ✅ One record per key per month
)
```

## Migration Steps

### Step 1: Add Generated Month Column
```sql
ALTER TABLE "RentConfig"
  ADD COLUMN period_month date GENERATED ALWAYS AS (date_trunc('month', period)::date) STORED;
```
**Purpose**: Enable month-level uniqueness matching business logic

### Step 2: Create Unique Constraint
```sql
CREATE UNIQUE INDEX rentconfig_key_period_month_uniq
  ON "RentConfig"(key, period_month);
```
**Purpose**: Prevent contamination - one config per key per month

### Step 3: Add Performance Index
```sql
CREATE INDEX rentconfig_key_period_desc_idx
  ON "RentConfig"(key, period DESC);
```
**Purpose**: Optimize persistent key "most recent <= target" lookups

### Step 4: Remove Old Constraint
```sql
ALTER TABLE "RentConfig" DROP CONSTRAINT "RentConfig_key_key";
```
**Purpose**: Allow multiple periods per key

### Step 5: Add Safety Constraint
```sql
ALTER TABLE "RentConfig"
  ADD CONSTRAINT period_is_month_start
  CHECK (date_trunc('month', period) = period);
```
**Purpose**: Ensure all periods are normalized to month start

## Application Code Changes

### Update set_config Method
**File**: `lib/rent_db.rb` lines 103-111

**Before**:
```ruby
def set_config(key, value, period = Time.now)
  self.class.rent_configs.insert(
    # ...
    period: period.utc,  # ❌ Any timestamp
    # ...
  )
end
```

**After**:
```ruby
def set_config(key, value, period = Time.now)
  # Normalize to month start for exact matching
  normalized = Time.utc(period.year, period.month, 1)

  self.class.rent_configs.insert(
    # ...
    period: normalized,  # ✅ Always 1st of month
    # ...
  )
end
```

## Business Logic Compatibility

### Period-Specific Keys (Exact Match)
```ruby
# lib/rent_db.rb lines 78-85
PERIOD_SPECIFIC_KEYS.each do |key|
  config_record = self.class.rent_configs
    .where(key: key, period: target_date.to_time.utc)  # ✅ Will match exactly
    .first
end
```

### Persistent Keys (Most Recent)
```ruby
# lib/rent_db.rb lines 88-97
PERSISTENT_KEYS.each do |key|
  config_record = self.class.rent_configs
    .where(key: key)
    .where { period <= end_of_month }  # ✅ Optimized by new index
    .order(Sequel.desc(:period))
    .first
end
```

## Data Examples After Migration

### Before (Contamination Risk)
```
key         | value | period
------------|-------|------------------
el          | 2424  | 2025-08-31 22:00 (only one allowed)
```

### After (Proper Temporal Modeling)
```
key         | value | period     | period_month
------------|-------|------------|-------------
el          | 2424  | 2025-09-01 | 2025-09-01
el          | 1876  | 2025-10-01 | 2025-10-01
drift_rä... | 2612  | 2024-10-01 | 2024-10-01  (isolated)
kallhyra    | 24530 | 2025-03-01 | 2025-03-01   (carries forward)
```

## Risk Assessment

### High Success Probability
- ✅ Zero downtime migration (additive changes first)
- ✅ Backward compatible during transition
- ✅ Matches existing business logic perfectly
- ✅ GPT-5 expert validation

### Rollback Plan
```sql
-- Emergency rollback if needed
DROP INDEX IF EXISTS rentconfig_key_period_month_uniq;
DROP INDEX IF EXISTS rentconfig_key_period_desc_idx;
ALTER TABLE "RentConfig" ADD CONSTRAINT "RentConfig_key_key" UNIQUE (key);
ALTER TABLE "RentConfig" DROP COLUMN IF EXISTS period_month;
ALTER TABLE "RentConfig" DROP CONSTRAINT IF EXISTS period_is_month_start;
```

## Testing Strategy

### Pre-Migration Validation
```sql
-- Check current data compatibility
SELECT key, period, date_trunc('month', period) = period AS is_normalized
FROM "RentConfig"
ORDER BY key, period;
```

### Post-Migration Verification
```sql
-- Verify constraints work
SELECT key, COUNT(*) as records_per_key
FROM "RentConfig"
GROUP BY key
HAVING COUNT(*) > 1;

-- Test period-specific lookup
SELECT * FROM "RentConfig"
WHERE key = 'el' AND period = '2025-09-01'::timestamp;

-- Test persistent lookup
SELECT * FROM "RentConfig"
WHERE key = 'kallhyra' AND period <= '2025-10-31'::timestamp
ORDER BY period DESC LIMIT 1;
```

### Rent Calculation Validation
```ruby
# Verify October 2025 calculation
config = db.get_rent_config(year: 2025, month: 10)
# Should show period-specific keys as 0, persistent keys with values
# Final rent should be 7,045 kr per person
```

## Success Metrics

### Functional Requirements
- ✅ Can store multiple electricity bills (September 2424, October 1876)
- ✅ Quarterly invoices don't contaminate other quarters
- ✅ Period-specific keys default to 0 when no exact match
- ✅ Persistent keys carry forward properly
- ✅ October 2025 rent calculates to exactly 7,045 kr

### Technical Requirements
- ✅ Configuration queries complete < 100ms
- ✅ Database enforces temporal integrity
- ✅ Application logic unchanged (compatible)
- ✅ No data loss during migration

## Implementation Timeline

### Phase 1: Database Migration (30 minutes)
1. Backup current database
2. Run migration SQL script
3. Verify constraints and indexes
4. Test basic queries

### Phase 2: Application Update (15 minutes)
1. Update `set_config` method
2. Test configuration insertion
3. Verify both lookup patterns work

### Phase 3: Validation (15 minutes)
1. Run rent calculation for October 2025
2. Verify no contamination between periods
3. Test edge cases (missing data, future months)

### Phase 4: Documentation Update (15 minutes)
1. Update implementation plan status
2. Document new schema in CLAUDE.md
3. Record lessons learned

## Long-term Benefits

### Operational
- ✅ Bulletproof temporal data integrity
- ✅ Clear separation of period-specific vs persistent data
- ✅ Performance optimized for both lookup patterns
- ✅ Foundation for future enhancements

### Business
- ✅ Accurate historical rent calculations
- ✅ No more cross-contamination bugs
- ✅ Supports complex scenarios (quarterly invoices, monthly bills)
- ✅ Audit trail for all configuration changes

---

**Status**: Ready for implementation
**Approval**: User confirmed "Ok sounds good, proceed!"
**Next**: Execute Phase 1 - Database Migration
# Configuration Key Classification Implementation Plan

**Date**: September 27, 2025
**Context**: Critical production bug fix for rent calculation contamination
**Issue**: Test data (drift_rakning: 2612) from 2024 contaminated 2025 calculations (7492 kr vs 7045 kr)

## Session Summary: The Great Configuration Contamination Crisis

### Problem Discovered
- **Symptom**: Dashboard showed 7,492 kr rent instead of expected 7,045 kr
- **Root Cause**: 2024 integration test wrote `drift_rakning: 2612` to production database
- **Architectural Flaw**: `get_rent_config()` uses "most recent value per key where period <= target" for ALL keys
- **Result**: Quarterly invoice from 2024 Q4 contaminated all 2025 calculations

### Work Completed Today
1. ✅ **Mystery Solved**: Traced 2612 kr to `/spec/rent_calculator/integration_spec.rb:102`
2. ✅ **Database Cleaned**: Removed contaminated test data
3. ✅ **API Fixed**: Now returns correct 7,045 kr
4. ✅ **Timing Issue Resolved**: September config period → October rent (advance payment logic)
5. ✅ **Documentation**: Created `CLAUDE.md` explaining timing quirks
6. ✅ **Expert Consensus**: GPT-5 + Gemini + O3 analysis on temporal data modeling

### Expert Model Analysis Results
- **GPT-5**: Hybrid classification + expiration approach (8/10 confidence)
- **Gemini**: Pure expiration logic with `expires_at` column (9/10 confidence)
- **O3**: Temporal validity intervals, lean toward expiration (8/10 confidence)
- **User Insight**: Real-world semantics don't match expiration model complexity

### Final Decision: Key Classification Based on Business Logic

## The Fundamental Issue

**Current Dangerous Logic:**
```sql
-- DANGEROUS: All keys use same "most recent" logic
SELECT key, value
FROM rent_configs
WHERE period <= target_month
ORDER BY period DESC
LIMIT 1 PER key
```

**Problems:**
- Quarterly invoices leak across years/quarters
- Test data contaminates production permanently
- Electricity bills carry forward inappropriately
- One-time adjustments become permanent

## Business Semantics Analysis

### Period-Specific Keys (NO carry-forward)
```ruby
PERIOD_SPECIFIC_KEYS = %w[el drift_rakning saldo_innan extra_in]
```

**Characteristics:**
- **`el`**: Monthly electricity bills - "This is September's bill, period"
- **`drift_rakning`**: Quarterly invoices - "This is Q3 2024 invoice, period"
- **`saldo_innan`**: Previous balance adjustments - "One-time correction"
- **`extra_in`**: Extra income - "This month's special income"

**Behavior**: Exact period match only. Default to 0 if not found.

### Persistent Keys (carry-forward until changed)
```ruby
PERSISTENT_KEYS = %w[kallhyra bredband vattenavgift va larm]
```

**Characteristics:**
- **`kallhyra`**: Base rent - Set once, applies until landlord changes
- **`bredband`**: Internet cost - Applies until ISP changes pricing
- **`vattenavgift`**: Water fee - Monthly fee, stable until adjusted
- **`va`**: Sewage fee - Monthly fee, stable until adjusted
- **`larm`**: Alarm fee - Monthly fee, stable until adjusted

**Behavior**: Use most recent value where period <= target month.

## Implementation Plan

### Phase 1: Schema Design
**Option A**: Application-level classification (RECOMMENDED)
```ruby
# No schema changes needed
# Classification logic in Ruby code
PERIOD_SPECIFIC_KEYS = %w[el drift_rakning saldo_innan extra_in]
PERSISTENT_KEYS = %w[kallhyra bredband vattenavgift va larm]
```

**Option B**: Database-level classification
```sql
-- Add classification column
ALTER TABLE rent_configs ADD COLUMN config_type VARCHAR(20);
UPDATE rent_configs SET config_type = 'period_specific' WHERE key IN (...);
UPDATE rent_configs SET config_type = 'persistent' WHERE key IN (...);
```

**Decision**: Start with Option A for speed, migrate to Option B later for robustness.

### Phase 2: Query Logic Redesign

**New `get_rent_config()` method:**
```ruby
def get_rent_config(year:, month:)
  target_date = Date.new(year, month, 1)
  end_of_month = (target_date.next_month - 1).to_time.utc

  config = {}

  # Period-specific: exact match only, no carry-forward
  PERIOD_SPECIFIC_KEYS.each do |key|
    result = self.class.rent_configs
      .where(key: key, period: target_date.to_time.utc)
      .first

    config[key] = result ? result[:value].to_i : 0
  end

  # Persistent: use most recent value where period <= target
  PERSISTENT_KEYS.each do |key|
    result = self.class.rent_configs
      .where(key: key)
      .where { period <= end_of_month }
      .order(Sequel.desc(:period))
      .first

    config[key] = result ? result[:value].to_i : (DEFAULTS[key.to_sym] || 0)
  end

  config
end
```

### Phase 3: Data Migration Strategy

**Current State Assessment:**
```bash
# Check contamination
ruby -e "require 'dotenv/load'; require_relative 'lib/rent_db';
db = RentDb.instance;
db.class.rent_configs.where(key: 'drift_rakning').all.each { |r| puts r }"
```

**Cleanup Steps:**
1. Identify and remove test contamination
2. Verify period-specific entries have correct periods
3. Ensure persistent entries are properly timestamped

### Phase 4: Testing Strategy

**Critical Test Cases:**
1. **Year Boundary**: December 2024 → January 2025 calculations
2. **Quarter Boundary**: Q4 → Q1 transition for drift_rakning
3. **Missing Data**: Period-specific key not found (should default to 0)
4. **Cross-Contamination**: 2024 test data should NOT affect 2025
5. **Persistent Updates**: New kallhyra should apply to future months

**Test Implementation:**
```ruby
RSpec.describe "Fixed Configuration Logic" do
  it "prevents cross-year drift_rakning contamination" do
    # Set Q4 2024 quarterly invoice
    db.set_config('drift_rakning', 2612, Time.new(2024, 10, 1))

    # Should NOT appear in Q1 2025
    config = db.get_rent_config(year: 2025, month: 1)
    expect(config['drift_rakning']).to eq(0)
  end

  it "carries forward persistent values" do
    # Set internet cost in March
    db.set_config('bredband', 450, Time.new(2025, 3, 1))

    # Should apply to April
    config = db.get_rent_config(year: 2025, month: 4)
    expect(config['bredband']).to eq(450)
  end
end
```

### Phase 5: Production Deployment

**Rollout Steps:**
1. Deploy new classification logic to staging
2. Run comprehensive test suite
3. Backup production database
4. Deploy to production during low-traffic period
5. Monitor first few API calls for correctness
6. Update documentation

**Rollback Plan:**
```ruby
# Emergency rollback: restore old query logic
def get_rent_config_old(year:, month:)
  # Original implementation as backup
end
```

## Risk Assessment

### High Risk
- **Query Logic Error**: Wrong classification could under/over-charge rent
- **Default Value Issues**: Missing period-specific entries causing 0 instead of reasonable defaults

### Medium Risk
- **Performance Impact**: Separate queries for each key type
- **Memory Usage**: Loading more config entries per request

### Low Risk
- **Migration Complexity**: Application-level change, no schema migration needed
- **Backward Compatibility**: Existing API unchanged

## Success Metrics

### Functional Success
- ✅ October 2025 rent: exactly 7,045 kr (not 7,492 kr)
- ✅ No cross-year contamination in test suite
- ✅ Quarterly invoices isolated to their quarters
- ✅ Persistent values carry forward correctly

### Technical Success
- ✅ All existing tests pass with new logic
- ✅ Performance acceptable (<100ms config queries)
- ✅ Clean separation of period-specific vs persistent logic

## Future Enhancements

### Database Schema Evolution
```sql
-- Later: add formal classification
ALTER TABLE rent_configs ADD COLUMN config_type VARCHAR(20);
ALTER TABLE rent_configs ADD CONSTRAINT valid_config_type
  CHECK (config_type IN ('period_specific', 'persistent'));
```

### UI/UX Improvements
- **Period-specific entries**: Auto-expire after period
- **Persistent entries**: Clear "effective until changed" messaging
- **Quarterly invoices**: Calendar view showing which quarters are covered

### Monitoring & Alerting
```ruby
# Alert on unexpected config patterns
def validate_config_sanity(year:, month:)
  config = get_rent_config(year: year, month: month)

  # Alert if electricity suspiciously high
  alert("High electricity: #{config['el']}") if config['el'] > 3000

  # Alert if quarterly invoice appears outside expected quarters
  if config['drift_rakning'] > 0
    quarter = ((month - 1) / 3) + 1
    alert("Unexpected quarterly invoice in Q#{quarter}") unless [1,4,7,10].include?(month)
  end
end
```

## Context Preservation

**This document captures the complete journey from discovery to solution:**
1. **Crisis**: 7,492 kr vs 7,045 kr discrepancy
2. **Investigation**: Database contamination from integration tests
3. **Expert Analysis**: Multi-model consensus on temporal data patterns
4. **Business Reality**: Real-world semantics beat pure technical elegance
5. **Solution**: Key classification matching actual data entry workflows

**The key insight**: The most elegant technical solution (expiration dates) doesn't match how users actually think about and enter configuration data. Business logic should drive technical architecture, not the reverse.

---

## Implementation Status (Session 2 Update)

### ✅ COMPLETED WORK
- **Phase 1**: Key classification constants implemented in `lib/rent_db.rb`
- **Phase 2**: New `get_rent_config()` method with business logic classification
- **Testing**: Comprehensive validation completed, logic proven correct
- **October 2025**: Now calculates correct 7,045 kr with September electricity

### 🚨 CRITICAL DISCOVERY: Schema Constraint Issue

**Problem**: Database has `UNIQUE` constraint on `key` column (`RentConfig_key_key`)
- Only allows ONE record per configuration key
- Prevents multiple periods for same key (e.g., monthly electricity entries)
- Explains why original system used "most recent value" approach

**Current Workaround**: Our implementation works within constraint limitations:
- Period-specific keys default to 0 when no exact period match
- Persistent keys use most recent value with proper defaults
- Contamination prevention achieved through classification logic

### ⚠️ NEXT STEPS REQUIRED (Phase 6: Schema Evolution)

**Option A: Remove Unique Constraint**
```sql
ALTER TABLE "RentConfig" DROP CONSTRAINT "RentConfig_key_key";
```

**Option B: Composite Primary Key** (RECOMMENDED)
```sql
-- Create new table with proper schema
CREATE TABLE "RentConfigNew" (
  id text PRIMARY KEY,
  key text NOT NULL,
  value text NOT NULL,
  period timestamp(3) NOT NULL,
  "createdAt" timestamp(3) DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" timestamp(3) NOT NULL,
  UNIQUE(key, period)  -- Allow multiple periods per key
);
```

**Option C: Soft Delete Approach**
```sql
ALTER TABLE "RentConfig" ADD COLUMN active boolean DEFAULT true;
-- Keep unique constraint, mark old entries as inactive
```

### 📊 Validation Results
- ✅ Period-specific isolation: electricity & quarterly invoices don't contaminate
- ✅ Persistent carry-forward: base rent, internet, utilities work correctly
- ✅ Default values: missing keys use business-appropriate defaults
- ✅ October 2025 calculation: exactly 7,045 kr as expected

**Implementation Status**: ✅ LOGIC COMPLETE, ⚠️ SCHEMA MIGRATION NEEDED
**Next Session**: Execute schema migration (Phase 6)
**Critical**: Schema change required for full period-specific functionality
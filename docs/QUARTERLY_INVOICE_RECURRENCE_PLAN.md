# Quarterly Invoice (Drifträkning) Recurrence Implementation Plan

**Created**: October 25, 2025
**Status**: Planning
**Goal**: Automate recurring quarterly building operations invoices every 3 months

---

## Executive Summary

Implement automatic quarterly invoice recurrence in the rent calculation system. First occurrence: October 2025 (2,797 kr due Oct 31). Future occurrences: January, April, July, October.

**Impact**:
- November 2025 rent: 28,337 kr → 31,134 kr (7,084 kr → 7,783 kr per person)
- Eliminates manual quarterly invoice entry
- Maintains historical pattern (825 kr monthly utilities × 3 = ~2,475 kr quarterly)

---

## Current State Analysis

### Existing Infrastructure

**Database Model** (`lib/models/rent_config.rb:32`):
```ruby
PERIOD_SPECIFIC_KEYS = %w[el drift_rakning saldo_innan extra_in].freeze
```
- `drift_rakning` already exists as period-specific configuration key
- Stored per config period (not persistent/carry-forward)

**Calculation Logic** (`handlers/rent_calculator_handler.rb:398-403`):
```ruby
if config_hash[:drift_rakning] && config_hash[:drift_rakning].to_f > 0
  config_hash.delete(:vattenavgift)
  config_hash.delete(:va)
  config_hash.delete(:larm)
end
```
- Quarterly invoice replaces monthly utilities (375 + 300 + 150 = 825 kr)
- Logic already handles substitution correctly

**Historical Usage**:
- Previous quarterly invoices stored manually in RentConfig
- No automatic recurrence - requires manual entry each quarter
- Amount varies slightly: ~2,600-2,800 kr (building costs fluctuate)

---

## Quarterly Invoice Pattern

### First Known Occurrence
- **Invoice**: Bostadsagenturen - 2,797.00 SEK
- **Due Date**: October 31, 2025
- **Config Period**: October 2025 (day 31 ≥ 25 → arrived October)
- **Used For**: November 2025 rent (due October 27)

### Recurrence Schedule
- **Frequency**: Every 3 months
- **Months**: January, April, July, October (Q1, Q2, Q3, Q4 endings)
- **Pattern**: Quarterly building operations costs
- **Timing**: Typically due last day of quarter month

### Amount Variability
- **Historical average**: ~2,600 kr
- **October 2025**: 2,797 kr
- **Expectation**: Amount varies ±10% based on actual building costs
- **Cannot hardcode**: Must allow manual adjustment each quarter

---

## Implementation Options

### Option 1: Manual Entry with Reminder System ⭐ **RECOMMENDED**

**Approach**:
- Keep manual entry but add proactive reminders
- Quarterly validation check in rent calculation API
- Warning if quarterly month has no drift_rakning set

**Pros**:
- Handles variable amounts (2,600-2,800 kr)
- Simple implementation
- No risk of incorrect automation
- Maintains human oversight

**Cons**:
- Still requires manual action each quarter
- Risk of forgetting (but reminder mitigates this)

**Implementation**:
```ruby
# In handlers/rent_calculator_handler.rb
def validate_quarterly_invoice_presence(year, month)
  quarterly_months = [1, 4, 7, 10]  # Jan, Apr, Jul, Oct

  if quarterly_months.include?(month)
    config = extract_config(year: year, month: month)

    if config[:drift_rakning].to_i == 0
      {
        warning: true,
        message: "Quarterly invoice expected for #{Date::MONTHNAMES[month]} #{year} but not set",
        suggested_amount: 2700,  # Historical average
        action: "POST /api/rent/config with drift_rakning value"
      }
    end
  end
end
```

### Option 2: Automatic with Override

**Approach**:
- Auto-populate drift_rakning with historical average in quarterly months
- Allow manual override for actual amount
- Mark as "projected" vs "actual" in config

**Pros**:
- Zero-touch for projections
- Still allows actual amounts when available

**Cons**:
- More complex database schema (needs "is_projection" flag)
- Risk of forgetting to update with actual amount
- Projected rent may confuse roommates

**Implementation**: (Not recommended - complexity outweighs benefits)

### Option 3: Scraper Integration (Future)

**Approach**:
- Scrape quarterly invoice from Bostadsagenturen portal
- Auto-detect PDF/email arrival
- Parse amount and due date

**Pros**:
- Fully automated like electricity bills
- Actual amounts, not projections

**Cons**:
- Requires new scraper development
- Bostadsagenturen site may not have API/portal
- Quarterly frequency makes testing difficult
- High complexity for 4× yearly task

**Status**: Deferred - electricity scrapers took priority, same pattern could apply later

---

## Recommended Implementation: Option 1 Enhanced

### Phase 1: Immediate Fix (November 2025 Rent)

**Action**: Manually set October 2025 quarterly invoice

```bash
# Add quarterly invoice to October config
curl -X PUT 'http://localhost:3001/api/rent/config' \
  -H 'Content-Type: application/json' \
  -d '{
    "year": 2025,
    "month": 10,
    "updates": {
      "drift_rakning": 2797
    }
  }'

# Trigger dashboard reload
curl -X POST 'http://localhost:3001/api/reload'
```

**Verification**:
```bash
# Check November rent calculation
curl -s 'http://localhost:3001/api/rent/friendly_message' | jq -r '.message'
# Expected: "Hyran för november 2025 ska betalas innan 27 okt"
# Expected: "7783 kr" per person (was 7084 kr)
```

### Phase 2: Validation System (Next Week)

**File**: `lib/services/quarterly_invoice_validator.rb`

```ruby
# Quarterly invoice validation service
class QuarterlyInvoiceValidator
  QUARTERLY_MONTHS = [1, 4, 7, 10].freeze  # Jan, Apr, Jul, Oct
  HISTORICAL_AVERAGE = 2700  # Updated as more data available

  def self.validate(year:, month:)
    return { required: false } unless QUARTERLY_MONTHS.include?(month)

    config = Persistence.rent_configs.find_by_key_and_period(
      'drift_rakning',
      Time.new(year, month, 1)
    )

    {
      required: true,
      present: config && config.numeric_value > 0,
      amount: config&.numeric_value || 0,
      suggested_amount: HISTORICAL_AVERAGE,
      warning: config.nil? || config.numeric_value == 0
    }
  end
end
```

**Integration**: Add to `/api/rent/friendly_message` response

```ruby
# In handle_friendly_message method
validation = QuarterlyInvoiceValidator.validate(year: year, month: month)

result = {
  message: friendly_text,
  # ... existing fields ...
  quarterly_invoice_status: validation
}
```

### Phase 3: Dashboard Warning UI (Following Week)

**Component**: `dashboard/src/components/QuarterlyInvoiceWarning.tsx`

```typescript
interface QuarterlyInvoiceStatus {
  required: boolean;
  present: boolean;
  amount: number;
  suggested_amount: number;
  warning: boolean;
}

// Display warning banner in RentWidget when quarterly invoice expected but missing
// Similar to electricity data source indicator
```

---

## Database Schema Changes

**None required** - Current schema already supports:
- `RentConfig.drift_rakning` as period-specific key
- Value storage per config period
- Replacement logic in rent calculator

---

## Testing Strategy

### Unit Tests

**File**: `spec/services/quarterly_invoice_validator_spec.rb`

```ruby
describe QuarterlyInvoiceValidator do
  it 'requires quarterly invoice in October' do
    result = QuarterlyInvoiceValidator.validate(year: 2025, month: 10)
    expect(result[:required]).to be true
  end

  it 'does not require quarterly invoice in November' do
    result = QuarterlyInvoiceValidator.validate(year: 2025, month: 11)
    expect(result[:required]).to be false
  end

  it 'warns when quarterly invoice missing in expected month' do
    # Setup: no drift_rakning in October config
    result = QuarterlyInvoiceValidator.validate(year: 2025, month: 10)
    expect(result[:warning]).to be true
  end

  it 'does not warn when quarterly invoice present' do
    # Setup: drift_rakning = 2797 in October config
    result = QuarterlyInvoiceValidator.validate(year: 2025, month: 10)
    expect(result[:warning]).to be false
  end
end
```

### Integration Tests

**Manual verification**:
1. Set October 2025 drift_rakning = 2797
2. Call `/api/rent/friendly_message`
3. Verify rent = 7,783 kr per person
4. Verify monthly utilities (vattenavgift, va, larm) not included in breakdown

**Regression tests**:
1. Non-quarterly month (November) should include monthly utilities
2. Quarterly month with no drift_rakning should show warning
3. Dashboard should display correct total with quarterly invoice

---

## Deployment Strategy

### Production Deployment

**Order**:
1. **Immediate**: Manually set October 2025 drift_rakning via API (Phase 1)
2. **Next week**: Deploy QuarterlyInvoiceValidator service (Phase 2)
3. **Following week**: Deploy dashboard warning UI (Phase 3)

**Rollback Plan**:
- Phase 1: Delete drift_rakning from October config if incorrect
- Phase 2: No database changes - remove validator calls from API
- Phase 3: Remove warning component from dashboard

### Future Quarterly Invoices

**January 2026 Process**:
1. Receive invoice from Bostadsagenturen (late December/early January)
2. Dashboard shows warning: "Quarterly invoice expected but not set"
3. Update via API or manual RentConfig insert
4. Dashboard auto-updates via WebSocket

**Improvement for 2026**:
- Consider scraper if Bostadsagenturen has digital portal
- Track historical amounts to improve suggested_amount accuracy
- Add Slack/email notification when quarterly month approaches

---

## Success Criteria

✅ **Phase 1 Complete When**:
- November 2025 rent shows 7,783 kr per person (not 7,084 kr)
- Dashboard displays correct quarterly invoice in rent breakdown
- Monthly utilities NOT shown for November (replaced by drift_rakning)

✅ **Phase 2 Complete When**:
- API returns quarterly_invoice_status in friendly_message response
- Warning flag correctly set when quarterly expected but missing
- Unit tests passing with >90% coverage

✅ **Phase 3 Complete When**:
- Dashboard shows warning banner when quarterly invoice missing
- Warning disappears when drift_rakning is set
- UI matches existing electricity data source indicator style

---

## Risk Mitigation

**Risk**: Forget to update quarterly invoice in future quarters
**Mitigation**: Validation warning system (Phase 2), dashboard UI (Phase 3)

**Risk**: Incorrect amount entered
**Mitigation**: Historical average suggestion, manual verification step

**Risk**: Quarterly invoice arrives late (after rent due date)
**Mitigation**: System allows retroactive correction, next month rent auto-adjusts

**Risk**: Building changes quarterly billing schedule
**Mitigation**: QUARTERLY_MONTHS constant easy to update, no hardcoded dependencies

---

## Documentation Updates

**Files to Update**:
1. `CLAUDE.md:420-426` - Add line about quarterly invoice automation status
2. `DEVELOPMENT.md` - Add section on quarterly invoice handling
3. `docs/RENT_CALCULATION_GUIDE.md` - Document drift_rakning replacement logic
4. `README.md` - Update "Rent Calculation" section with quarterly invoice mention

**API Documentation**:
- Add `quarterly_invoice_status` field to `/api/rent/friendly_message` response schema
- Document `/api/rent/config` PUT endpoint for drift_rakning updates

---

## Timeline

**Week 1 (Oct 25-31)**:
- ✅ Plan document created
- [ ] Phase 1: Manual October invoice entry
- [ ] Verify November rent calculation correct
- [ ] Update CLAUDE.md with automation status note

**Week 2 (Nov 1-7)**:
- [ ] Phase 2: Implement QuarterlyInvoiceValidator service
- [ ] Add validation to API response
- [ ] Unit tests for validator
- [ ] Deploy to production

**Week 3 (Nov 8-14)**:
- [ ] Phase 3: Dashboard warning UI component
- [ ] Integration with RentWidget
- [ ] User acceptance testing
- [ ] Deploy to production

**Future (Dec 2025)**:
- [ ] Monitor for January 2026 quarterly invoice arrival
- [ ] Evaluate scraper feasibility
- [ ] Consider notification system

---

## Appendix: Historical Quarterly Invoice Data

**October 2025**: 2,797 kr (due Oct 31)
**July 2025**: Unknown (need to check historical records)
**April 2025**: Unknown (need to check historical records)
**January 2025**: Unknown (need to check historical records)

**Action**: Search `data/rent_history/` JSON files for past drift_rakning values to establish historical pattern.

---

**Next Steps**:
1. Approve this plan
2. Execute Phase 1 (manual October entry)
3. Begin Phase 2 development (validator service)

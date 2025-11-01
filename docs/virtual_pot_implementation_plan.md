# Virtual Pot Implementation Plan

**Date**: October 28, 2025
**Status**: Planning Phase
**Goal**: Transition from reactive cash-based accounting to proactive accrual-based discipline

---

## Problem Statement

### Current Reality (2025 and earlier)
- Collect 754 kr/month for "savings" (9 months) = 6,786 kr
- Collect full invoice amounts (3 months) = 8,391 kr
- **Total collected: 15,177 kr**
- **Actual building costs: 8,933 kr**
- **Difference: 6,244 kr spent on gas, toilet paper, misc household needs**

### The Issue
When advertising rent to new roommates as 7,100 kr/person, this implies:
- Annual building costs: 754 kr × 12 = 9,048 kr
- But we're actually collecting 15,177 kr
- This is misleading and represents double-counting

### Future Goal (2026+)
- **Strict separation**: House account ONLY for rent-related costs
- **Personal expenses**: Gas, toilet paper, broken items = paid separately by individuals
- **Accurate reporting**: Advertised rent = TRUE annual average
- **Disciplined saving**: 754 kr/month actually SAVED for quarterly invoices

---

## Core Architecture Changes

### 1. Rent Calculation Logic Changes

**ALWAYS collect consistent monthly amounts, never invoice spikes:**

```ruby
# rent.rb Config#drift_total
def drift_total
  # NEVER use drift_rakning amount directly in calculations
  # Always use monthly accrual amounts
  monthly_building_ops = vattenavgift + va + larm  # = 754 kr
  monthly_gas = gas  # 83 kr baseline (500 kr / 6 months)

  el + bredband + monthly_building_ops + monthly_gas
end
```

**Current defaults to update:**

```ruby
# rent.rb Config::DEFAULTS
DEFAULTS = {
  kallhyra: 24_530,
  el: 1_600,
  bredband: 400,
  vattenavgift: 343,  # 45.5% of 754 kr
  va: 274,           # 36.4% of 754 kr
  larm: 137,         # 18.2% of 754 kr
  drift_rakning: nil, # NO LONGER USED in calculations
  gas: 83,           # NEW: 500 kr / 6 months
  saldo_innan: 0,
  extra_in: 0
}
```

**Expected rent with new logic:**

```
Normal month (October 2025):
  Kallhyra: 24,530 kr
  El: 2,424 kr
  Bredband: 400 kr
  Building ops: 754 kr (always consistent)
  Gas: 83 kr (always consistent)
  Total: 28,191 kr / 4 = 7,048 kr/person

Invoice month (November 2025):
  SAME AS ABOVE: 7,048 kr/person
  Virtual Pot handles the invoice separately
```

### 2. Virtual Pot Tracking System

**New database table: `HouseholdReserve`**

```sql
CREATE TABLE HouseholdReserve (
  id TEXT PRIMARY KEY,
  period DATE NOT NULL,           -- Month this applies to (YYYY-MM-01)
  reserve_type TEXT NOT NULL,     -- 'building_ops' or 'gas'
  opening_balance REAL NOT NULL,  -- Balance at start of month
  accrual_amount REAL NOT NULL,   -- Amount added this month (754 or 83)
  invoice_paid REAL DEFAULT 0,    -- Actual invoice paid this month
  closing_balance REAL NOT NULL,  -- Balance at end of month
  createdAt DATETIME,
  updatedAt DATETIME
);

CREATE INDEX idx_reserve_period ON HouseholdReserve(period);
CREATE INDEX idx_reserve_type ON HouseholdReserve(reserve_type);
```

**Reserve calculation logic:**

```ruby
# lib/models/household_reserve.rb
class HouseholdReserve
  attr_reader :reserve_type, :opening_balance, :accrual_amount,
              :invoice_paid, :closing_balance

  def self.for_period(year:, month:, reserve_type:, repository:)
    # Get last month's closing balance
    previous_balance = get_previous_balance(year, month, reserve_type, repository)

    # Calculate this month
    accrual = case reserve_type
              when 'building_ops' then 754.0
              when 'gas' then 83.0
              else 0.0
              end

    # Check if invoice was paid this month
    invoice_paid = get_invoice_amount(year, month, reserve_type, repository)

    closing = previous_balance + accrual - invoice_paid

    new(
      reserve_type: reserve_type,
      opening_balance: previous_balance,
      accrual_amount: accrual,
      invoice_paid: invoice_paid,
      closing_balance: closing
    )
  end

  def shortfall?
    closing_balance < 0
  end

  def shortfall_amount
    [0, -closing_balance].max
  end
end
```

### 3. Dashboard Widget Enhancements

**New component: `VirtualPotWidget.tsx`**

Display in RentWidget as additional lines below heating cost:

```typescript
interface VirtualPotData {
  building_ops: {
    next_invoice_date: string;      // "2026-04-15" (estimated)
    next_invoice_amount: number;    // 3,029 kr (projected)
    days_until: number;             // 168 days
    pot_balance: number;            // 2,262 kr
    coverage_percent: number;       // 75%
    shortfall: number;              // 767 kr (if invoice today)
  };
  gas: {
    next_refill_date: string;       // "2026-01-15" (estimated)
    next_refill_amount: number;     // 500 kr
    days_until: number;             // 79 days
    pot_balance: number;            // 249 kr
    coverage_percent: number;       // 50%
    shortfall: number;              // 251 kr
  };
}
```

**Visual representation:**

```
─────────────────────────────────────
Hyran för november 2025
7,048 kr för alla
─────────────────────────────────────
Baserad på aktuella elräkningar för september
2 °C varmare skulle kosta 198 kr/mån (50 kr/person)

📊 Nästa driftavi: ~168 dagar (apr 2026)
   Projicerad: 3,029 kr | Sparat: 2,262 kr (75%)
   ⚠️ Behöver: 767 kr extra om avin kommer nu

⛽ Nästa gasol: ~79 dagar (jan 2026)
   Kostnad: ~500 kr | Sparat: 249 kr (50%)
   💡 Behöver: 251 kr extra vid påfyllning
```

### 4. API Enhancements

**Update `/api/rent/friendly_message` response:**

```json
{
  "message": "*Hyran för november 2025*\n7048 kr för alla",
  "year": 2025,
  "month": 10,
  "data_source": {...},
  "electricity_amount": 2424,
  "heating_cost_line": "...",
  "virtual_pot": {
    "building_ops": {
      "next_invoice": {
        "projected_date": "2026-04-15",
        "projected_amount": 3029,
        "days_until": 168
      },
      "pot_status": {
        "current_balance": 2262,
        "coverage_percent": 75,
        "shortfall_if_today": 767
      }
    },
    "gas": {
      "next_refill": {
        "projected_date": "2026-01-15",
        "projected_amount": 500,
        "days_until": 79
      },
      "pot_status": {
        "current_balance": 249,
        "coverage_percent": 50,
        "shortfall_if_today": 251
      }
    }
  }
}
```

### 5. Reuse Existing Code

**Quarterly invoice projection (already exists):**
- `lib/services/quarterly_invoice_projector.rb` - 8.7% YoY growth
- `lib/models/rent_config.rb` - Auto-population in Apr/Jul/Oct

**New: Gas tracking service:**

```ruby
# lib/services/gas_tracker.rb
class GasTracker
  BASELINE_COST = 500.0        # kr per refill
  BASELINE_INTERVAL = 6        # months between refills
  MONTHLY_ACCRUAL = BASELINE_COST / BASELINE_INTERVAL  # 83 kr

  # Later enhancement: Track actual purchase history
  # For now, use baseline projection

  def self.project_next_refill(current_date:, last_refill_date: nil)
    # TODO: Query GasPurchases table for actual history
    # For now, assume 6-month cycle from Jan 2025
    base_date = last_refill_date || Date.new(2025, 1, 15)

    # Find next refill after current_date
    months_since = ((current_date.year - base_date.year) * 12 +
                   (current_date.month - base_date.month))
    cycles_passed = (months_since.to_f / BASELINE_INTERVAL).floor
    next_refill = base_date >> ((cycles_passed + 1) * BASELINE_INTERVAL)

    {
      date: next_refill,
      amount: BASELINE_COST,
      days_until: (next_refill - current_date).to_i
    }
  end

  def self.calculate_pot_balance(current_date:, last_refill_date: nil)
    # Months since last refill × 83 kr/month
    base_date = last_refill_date || Date.new(2025, 1, 15)
    months_since = ((current_date.year - base_date.year) * 12 +
                   (current_date.month - base_date.month))
    cycles_passed = (months_since.to_f / BASELINE_INTERVAL).floor
    months_in_current_cycle = months_since - (cycles_passed * BASELINE_INTERVAL)

    months_in_current_cycle * MONTHLY_ACCRUAL
  end
end
```

---

## Implementation Phases

### Phase 1: Core Logic Changes (Immediate)

**Goal**: Stop double-counting, always collect consistent monthly amounts

1. ✅ Update `rent.rb` Config::DEFAULTS (add gas: 83)
2. ✅ Update `rent.rb` Config#drift_total (always use monthly accruals, never invoice)
3. ✅ Update `lib/models/rent_config.rb` DEFAULTS (add gas: 83)
4. ✅ Test rent calculations for normal and invoice months (should be identical)
5. Document the change in CLAUDE.md

**Verification**:
- October rent (no invoice): 7,048 kr/person
- November rent (with invoice in DB): ALSO 7,048 kr/person
- Invoice stored but not used in calculation

### Phase 2: Virtual Pot Backend (Week 1)

**Goal**: Track pot balances and calculate shortfalls

1. Create Prisma migration for HouseholdReserve table
2. Implement HouseholdReserve model and repository
3. Implement GasTracker service (baseline only)
4. Create VirtualPotCalculator service that combines:
   - Building ops pot (uses HouseholdReserve + QuarterlyInvoiceProjector)
   - Gas pot (uses GasTracker)
5. Update rent_calculator_handler.rb to include virtual_pot in response
6. Test API response includes all virtual_pot fields

### Phase 3: Dashboard UI (Week 1-2)

**Goal**: Make pot visible and actionable

1. Create VirtualPotWidget component
2. Update RentWidget to display virtual pot data
3. Add visual indicators:
   - Green: pot > 90% of projected
   - Yellow: pot 60-90%
   - Red: pot < 60%
4. Add tooltip/modal with detailed explanation
5. Test on production kiosk

### Phase 4: Gas Purchase Tracking (Week 2-3)

**Goal**: Replace baseline with actual purchase history

1. Create GasPurchases table (date, amount, vendor, notes)
2. Add admin interface to log gas purchases
3. Update GasTracker to use actual history
4. Backfill historical purchases if records available
5. Improve next_refill projection based on actual intervals

### Phase 5: Reserve Management Tools (Week 3-4)

**Goal**: Enable manual pot adjustments and reconciliation

1. Add API endpoint to record invoice payments (updates HouseholdReserve)
2. Add API endpoint to adjust pot balance (for corrections)
3. Create admin dashboard for reserve management
4. Implement monthly reconciliation report
5. Add alerts when shortfall detected

---

## Migration Strategy

### Existing Users

**Don't break current rent calculations immediately:**

1. Add feature flag: `USE_VIRTUAL_POT` (default: false)
2. When false: Use old logic (invoice spikes)
3. When true: Use new logic (consistent monthly + pot tracking)
4. Announce the change to roommates with clear explanation
5. Give 1 month transition period to understand new system
6. Flip flag after confirmation

### Communication Plan

**Message to roommates:**

> Starting December 2025, we're implementing proper financial discipline:
>
> **What changes:**
> - Monthly rent stays consistent at ~7,050 kr/person
> - No more surprise spikes when quarterly invoices arrive
> - Dashboard shows savings balance for upcoming bills
>
> **Why this matters:**
> - Accurate rent reporting to new roommates
> - Better cash flow planning
> - Prevents scrambling when bills arrive
>
> **What you need to do:**
> - Personal expenses (toilet paper, gas, etc.) paid separately
> - Check dashboard warnings about upcoming bills
> - Help ensure savings don't get spent on misc items

---

## Testing Plan

### Unit Tests

1. HouseholdReserve model (balance calculations)
2. GasTracker service (projection accuracy)
3. VirtualPotCalculator (combined pot logic)
4. Updated Config#drift_total (always uses accruals)

### Integration Tests

1. API response includes virtual_pot data
2. Monthly progression (pot increments correctly)
3. Invoice payment (pot decrements correctly)
4. Shortfall detection and warnings

### Manual Testing

1. Check October rent: should be 7,048 kr/person
2. Check November rent: should ALSO be 7,048 kr/person (not 7,577 kr)
3. Verify virtual pot shows in dashboard
4. Test countdown updates daily
5. Verify warnings appear when pot < 80%

---

## Success Metrics

### Immediate (Phase 1-2)
- ✅ Rent calculations consistent month-to-month
- ✅ No more invoice spikes
- ✅ Virtual pot data available via API

### Short-term (Phase 3-4)
- ✅ Dashboard displays pot status
- ✅ Roommates understand new system
- ✅ Gas purchases tracked accurately

### Long-term (3-6 months)
- 📊 Pot balance remains positive
- 📊 No scrambling when invoices arrive
- 📊 Accurate rent reporting to new roommates
- 📊 Separation of household vs personal expenses maintained

---

## Risks and Mitigation

### Risk 1: Pot Gets Spent Despite Tracking
**Mitigation**:
- Regular dashboard warnings
- Monthly reconciliation
- Consider separate bank account for house reserves

### Risk 2: Actual Costs Exceed Projections
**Mitigation**:
- 8.7% YoY growth already conservative
- Annual reconciliation and adjustment
- Buffer included in 754 kr (actual average is 744 kr)

### Risk 3: Roommate Confusion During Transition
**Mitigation**:
- Clear communication plan
- 1-month transition period
- Dashboard tooltips explaining new system
- FAQ document

---

## Future Enhancements

### Advanced Features (Post-MVP)

1. **Separate Bank Account Integration**: Link to actual reserve account balance
2. **SMS/Email Alerts**: When pot drops below threshold
3. **Historical Analytics**: Chart of pot balance over time
4. **Move-in/Move-out Handling**: Pro-rata pot settlement
5. **Multi-currency Support**: If house has international roommates
6. **Receipt Upload**: Photo storage for invoice verification

### Gas Tracking Enhancements

1. Track consumption rate (usage per day)
2. Seasonal adjustments (more cooking in winter)
3. Vendor comparison (find cheapest refill)
4. Delivery scheduling integration

---

## Files to Create/Modify

### New Files
- `lib/models/household_reserve.rb`
- `lib/repositories/household_reserve_repository.rb`
- `lib/services/gas_tracker.rb`
- `lib/services/virtual_pot_calculator.rb`
- `dashboard/src/components/VirtualPotWidget.tsx`
- `prisma/migrations/YYYYMMDD_add_household_reserve.sql`
- `prisma/migrations/YYYYMMDD_add_gas_purchases.sql`
- `spec/models/household_reserve_spec.rb`
- `spec/services/gas_tracker_spec.rb`

### Modified Files
- `rent.rb` (Config::DEFAULTS, Config#drift_total)
- `lib/models/rent_config.rb` (DEFAULTS)
- `handlers/rent_calculator_handler.rb` (add virtual_pot to response)
- `dashboard/src/components/RentWidget.tsx` (display VirtualPotWidget)
- `CLAUDE.md` (document new logic)

---

## Questions for Clarification

1. **Gas purchase history**: Do you have records of past gas purchases (dates, amounts)?
2. **Separate account**: Are you planning to open a separate bank account for reserves?
3. **Admin access**: Who should have permission to log invoices and adjust pot balances?
4. **Transition date**: Confirm starting December 2025 rent calculation?
5. **Roommate approval**: Should we present this plan to roommates before implementing?

---

## Conclusion

This implementation transitions the household from reactive cash chaos to proactive accrual discipline. The Virtual Pot makes invisible savings visible, preventing both double-counting (in rent advertising) and scrambling (when bills arrive).

**Key principle**: The system reflects the IDEAL (disciplined saving) while warning about REALITY (shortfalls), empowering roommates to close the gap.

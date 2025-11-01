# Virtual Pot Implementation Plan v2 (Simplified)

**Date**: October 28, 2025
**Status**: Awaiting Final Approval

---

## Core Problem

**Current System:**
- Database stores actual invoice amounts (2,797 kr in October 2025)
- Rent calculation uses those amounts directly
- Creates spikes: 7,067 kr normal → 7,577 kr invoice months
- Annual total collected: 15,177 kr
- Actual invoice costs: 8,371 kr
- Difference (6,806 kr) was historically spent on gas/household misc

**Goal for 2026+:**
- Advertise accurate average rent to new roommates
- Maintain financial discipline (don't spend savings)
- Track actual invoices for transparency
- Provide early warning when bills approach

---

## Solution: Separate Tracking from Billing

### 1. Database - TRACK Actual Invoices (No Change)

**KEEP** storing actual invoice amounts in RentConfig:
```ruby
# October 2025 config
{
  drift_rakning: "2797",  # Actual invoice amount - STORED but not used in billing
  vattenavgift: "343",
  va: "274",
  larm: "137"
}
```

**Purpose**: Historical records, projection accuracy, transparency

### 2. Rent Calculation - BILL Consistent Amounts (Change)

**ALWAYS** use monthly accruals, never invoice amounts:

```ruby
# rent.rb Config#drift_total
def drift_total
  # Building operations: consistent monthly accrual
  monthly_building_ops = vattenavgift + va + larm  # Always 754 kr

  # Gas: consistent monthly accrual (baseline for now)
  monthly_gas = gas  # Always 83 kr

  # NEVER use drift_rakning amount here
  el + bredband + monthly_building_ops + monthly_gas
end
```

**Result**:
- October 2025 (el: 2,424): 7,048 kr/person
- November 2025 (el: 2,581): 7,087 kr/person
- Only electricity varies, building ops stays at 754 kr

**Annual average advertised**: ~7,100 kr/person (TRUE average, not inflated)

### 3. Dashboard - RECONCILE Difference (New)

**Two simple text lines in RentWidget** below heating cost line:

```
📊 Nästa driftavi: ~45 dagar (apr 2026, ~3,030 kr)
   Sparat hittills: 2,262 kr | Behöver: 768 kr extra

⛽ Nästa gasol: ~79 dagar (jan 2026, ~500 kr)
   Sparat hittills: 249 kr | Behöver: 251 kr extra
```

**No colors, no interactivity, just information.**

---

## Implementation Details

### Backend Changes

**File: `rent.rb`**

Update Config::DEFAULTS:
```ruby
DEFAULTS = {
  kallhyra: 24_530,
  el: 1_600,
  bredband: 400,
  vattenavgift: 343,
  va: 274,
  larm: 137,
  drift_rakning: nil,  # Stored in DB but not used in calculations
  gas: 83,             # NEW: 500 kr / 6 months baseline
  saldo_innan: 0,
  extra_in: 0
}
```

Update Config#drift_total method:
```ruby
def drift_total
  monthly_building_ops = vattenavgift + va + larm  # Always 754 kr
  monthly_gas = gas  # Always 83 kr
  el + bredband + monthly_building_ops + monthly_gas
end
```

**File: `lib/models/rent_config.rb`**

Update DEFAULTS to match:
```ruby
DEFAULTS = {
  kallhyra: 24530,
  bredband: 400,
  vattenavgift: 343,
  va: 274,
  larm: 137
}.freeze
```

**File: `handlers/rent_calculator_handler.rb`**

Add virtual pot calculation to `/api/rent/friendly_message`:

```ruby
def handle_friendly_message(req)
  # ... existing code ...

  # Calculate virtual pot status
  virtual_pot_data = calculate_virtual_pot_status(year: year, month: month)

  result = {
    message: friendly_text,
    # ... existing fields ...
    virtual_pot: virtual_pot_data
  }
end

private

def calculate_virtual_pot_status(year:, month:)
  {
    building_ops: calculate_building_ops_pot(year, month),
    gas: calculate_gas_pot(year, month)
  }
end

def calculate_building_ops_pot(year, month)
  # Use existing QuarterlyInvoiceProjector for next invoice
  projector = QuarterlyInvoiceProjector

  # Find last invoice date from database
  last_invoice = find_last_quarterly_invoice(year, month)

  # Calculate months since last invoice
  months_since = calculate_months_between(last_invoice[:date], Date.new(year, month, 1))

  # Virtual pot balance = months × 754 kr
  pot_balance = months_since * 754.0

  # Next invoice projection (uses existing code)
  next_invoice = projector.find_next_quarterly_month(year, month)
  next_amount = projector.calculate_projection(
    year: next_invoice[:year],
    month: next_invoice[:month]
  )

  # Days until next invoice
  next_date = Date.new(next_invoice[:year], next_invoice[:month], 15)
  days_until = (next_date - Date.new(year, month, 1)).to_i

  {
    next_invoice_date: next_date.to_s,
    next_invoice_amount: next_amount[:amount],
    days_until: days_until,
    pot_balance: pot_balance.round,
    shortfall: [next_amount[:amount] - pot_balance, 0].max.round
  }
end

def calculate_gas_pot(year, month)
  # Simple baseline for now (6-month cycle)
  # Assume last refill: Jan 2025, next refill: Jul 2025, then Jan 2026, etc.

  base_refill_date = Date.new(2025, 1, 15)
  current_date = Date.new(year, month, 1)

  # Find next refill date (6-month intervals)
  months_since_base = (current_date.year - base_refill_date.year) * 12 +
                      (current_date.month - base_refill_date.month)
  cycles_passed = (months_since_base / 6).floor
  next_refill_date = base_refill_date >> ((cycles_passed + 1) * 6)

  # Months since last refill
  last_refill_date = base_refill_date >> (cycles_passed * 6)
  months_in_cycle = (current_date.year - last_refill_date.year) * 12 +
                    (current_date.month - last_refill_date.month)

  # Virtual pot balance = months × 83 kr
  pot_balance = months_in_cycle * 83.0

  # Days until next refill
  days_until = (next_refill_date - current_date).to_i

  {
    next_refill_date: next_refill_date.to_s,
    next_refill_amount: 500,
    days_until: days_until,
    pot_balance: pot_balance.round,
    shortfall: [500 - pot_balance, 0].max.round
  }
end

def find_last_quarterly_invoice(year, month)
  repo = Persistence.rent_configs

  # Look back up to 12 months for last drift_rakning entry
  12.downto(0) do |months_back|
    check_date = Date.new(year, month, 1) << months_back
    config = repo.find_by_key_and_period('drift_rakning',
                                         Time.utc(check_date.year, check_date.month, 1))
    if config && config.value.to_f > 0
      return {
        date: check_date,
        amount: config.value.to_f
      }
    end
  end

  # Default: assume October 2024 if nothing found
  { date: Date.new(2024, 10, 1), amount: 2612 }
end

def calculate_months_between(start_date, end_date)
  (end_date.year - start_date.year) * 12 + (end_date.month - start_date.month)
end
```

### Frontend Changes

**New Component: `VirtualPotDisplay.tsx`**

```typescript
interface VirtualPotProps {
  building_ops: {
    next_invoice_date: string;
    next_invoice_amount: number;
    days_until: number;
    pot_balance: number;
    shortfall: number;
  };
  gas: {
    next_refill_date: string;
    next_refill_amount: number;
    days_until: number;
    pot_balance: number;
    shortfall: number;
  };
}

export function VirtualPotDisplay({ building_ops, gas }: VirtualPotProps) {
  // Format date as "apr 2026"
  const formatDate = (dateStr: string) => {
    const date = new Date(dateStr);
    const months = ['jan', 'feb', 'mar', 'apr', 'maj', 'jun',
                   'jul', 'aug', 'sep', 'okt', 'nov', 'dec'];
    return `${months[date.getMonth()]} ${date.getFullYear()}`;
  };

  // Format amount with space: "3 030 kr"
  const formatKr = (amount: number) => {
    return amount.toString().replace(/\B(?=(\d{3})+(?!\d))/g, ' ') + ' kr';
  };

  return (
    <div className="virtual-pot-lines">
      <div className="pot-line">
        📊 Nästa driftavi: ~{building_ops.days_until} dagar
        ({formatDate(building_ops.next_invoice_date)}, {formatKr(building_ops.next_invoice_amount)})
        <br />
        &nbsp;&nbsp;&nbsp;Sparat hittills: {formatKr(building_ops.pot_balance)} |
        Behöver: {formatKr(building_ops.shortfall)} extra
      </div>

      <div className="pot-line">
        ⛽ Nästa gasol: ~{gas.days_until} dagar
        ({formatDate(gas.next_refill_date)}, {formatKr(gas.next_refill_amount)})
        <br />
        &nbsp;&nbsp;&nbsp;Sparat hittills: {formatKr(gas.pot_balance)} |
        Behöver: {formatKr(gas.shortfall)} extra
      </div>
    </div>
  );
}
```

**Modified: `RentWidget.tsx`**

```typescript
// Add virtual_pot to RentData interface
interface RentData {
  message: string;
  electricity_amount: number;
  electricity_month: string;
  heating_cost_line: string;
  virtual_pot?: {  // NEW
    building_ops: {...};
    gas: {...};
  };
}

// In render, after heating cost line:
{data.heating_cost_line && (
  <p className="text-xs opacity-70">
    {data.heating_cost_line}
  </p>
)}

{data.virtual_pot && (
  <VirtualPotDisplay
    building_ops={data.virtual_pot.building_ops}
    gas={data.virtual_pot.gas}
  />
)}
```

---

## Testing Plan

### Backend Tests

1. **Rent calculation consistency:**
   ```bash
   # October 2025 (no invoice in DB): Should be 7,048 kr
   curl 'http://localhost:3001/api/rent/friendly_message?year=2025&month=9'

   # November 2025 (2,797 kr invoice in DB): Should ALSO be ~7,087 kr (not 7,577 kr)
   curl 'http://localhost:3001/api/rent/friendly_message?year=2025&month=10'
   ```

2. **Virtual pot calculation:**
   ```bash
   # Check API returns virtual_pot data
   curl 'http://localhost:3001/api/rent/friendly_message' | jq '.virtual_pot'
   ```

3. **Gas baseline:**
   ```bash
   # Verify gas adds 83 kr/month to drift_total
   # Total should include: el + 400 + 754 + 83
   ```

### Frontend Tests

1. Dashboard displays two pot lines
2. Countdown updates correctly
3. Shortfall shows 0 when pot > invoice
4. No visual glitches in widget layout

---

## Migration Strategy

**Immediate (December 2025 rent):**
- Deploy changes before December 1st rent calculation
- December rent will reflect new consistent billing (no spike even if invoice in DB)

**Communication to Roommates:**

> **Starting December 2025: More Accurate Rent Calculations**
>
> We're fixing how monthly rent is calculated to be more transparent:
>
> **What changes:**
> - Building costs now consistent at 754 kr/month (saving up for quarterly invoices)
> - Gas costs added at 83 kr/month (saving up for refills)
> - Only electricity varies month-to-month
> - Dashboard shows savings status and upcoming bills
>
> **Why:**
> - Advertised rent to new roommates is now TRUE annual average
> - Better cash planning with visible savings tracker
> - No more surprise spikes when invoices arrive
>
> **Example:**
> - Old way: 7,067 kr normal month → 7,577 kr invoice month
> - New way: ~7,050 kr every month (varies only with electricity)
> - Dashboard warns if savings insufficient for upcoming bills

---

## Answers to Key Questions

### Q: Do we delete quarterly invoice amounts from database?
**A: NO.** Keep storing actual amounts for records. Just don't use them in rent calculations.

### Q: How do we avoid double-counting?
**A: Separate tracking from billing:**
- Database tracks reality (2,797 kr invoice)
- Calculations use consistent accrual (754 kr/month)
- Dashboard reconciles the difference (warning if short)

### Q: What if savings were spent on other things?
**A: Dashboard shows the shortfall** - roommates see "Behöver 768 kr extra" and know to transfer more money or adjust spending.

### Q: Is 754 kr/month accurate?
**A: Yes, slightly conservative:**
- 2025 actual costs: 8,371 kr
- 754 kr × 12 = 9,048 kr
- Buffer: 677 kr/year (8% margin)

---

## Files Changed Summary

### Backend
- ✏️ `rent.rb` - Update DEFAULTS, modify drift_total method
- ✏️ `lib/models/rent_config.rb` - Update DEFAULTS
- ✏️ `handlers/rent_calculator_handler.rb` - Add virtual pot calculation

### Frontend
- ✏️ `dashboard/src/components/RentWidget.tsx` - Display virtual pot
- ➕ `dashboard/src/components/VirtualPotDisplay.tsx` - New component (simple text formatting)

### Documentation
- ✏️ `CLAUDE.md` - Update with new calculation logic
- ➕ `docs/virtual_pot_implementation_plan_v2.md` - This document

**Total: 6 files** (3 modified backend, 2 frontend, 1 doc)

---

## What's NOT Included (Overengineering Removed)

❌ New database tables (calculate on-the-fly instead)
❌ Admin UI (terminal management continues)
❌ Warning colors (just plain text)
❌ Feature flags (direct implementation)
❌ Reserve management tools (future enhancement)
❌ Complex pot reconciliation logic (simple calculation)
❌ Gas purchase tracking database (baseline for now, improve later)

---

## Approval Checklist

Before implementation, Fredrik confirms:

- [ ] Rent calculation always uses 754 kr building ops (no invoice spikes)
- [ ] Gas baseline 83 kr/month (500 kr / 6 months) acceptable for now
- [ ] Two simple text lines in dashboard (no colors, no complexity)
- [ ] Quarterly invoices kept in database (for records/projections)
- [ ] No admin UI needed (terminal management continues)
- [ ] No separate bank account tracking (virtual pot only)
- [ ] Communicate change to roommates before December rent
- [ ] Annual average rent (~7,100 kr) is TRUE average (no double-counting)

---

## Timeline

**Estimated**: 4-6 hours total work

1. Backend changes (2-3 hours)
2. Frontend component (1-2 hours)
3. Testing and verification (1 hour)
4. Deploy before December 1st

**Ready to proceed after final approval.**

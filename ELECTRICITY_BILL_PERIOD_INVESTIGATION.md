# Electricity Bill Period Investigation

**Date**: October 24, 2025
**Status**: 🚨 CRITICAL BUG FOUND

---

## Executive Summary

**62 out of 63 bills have incorrect `billPeriod` values** - all shifted 1 month into the future due to a bug in the Oct 4, 2025 migration script (`deployment/electricity_bill_migration.rb`).

The bug: Migration calculated **arrival month** but stored it as **consumption period**, missing the final "subtract 1 month" step.

---

## User Questions Answered

### 1. How does ApplyElectricityBill work with no existing bills?

**Answer**: It processes ONE bill at a time (not batch).

**Workflow**:
```ruby
# vattenfall.rb scrapes invoices from website
results[:invoices].each do |invoice|
  ApplyElectricityBill.call(
    provider: invoice['provider'],
    amount: invoice['amount'],
    due_date: invoice['due_date']
  )
end
```

**What it does**:
1. Stores that ONE bill (with deduplication)
2. Aggregates ALL bills for that bill's period
3. Updates RentConfig for that period

**If no bills exist for 3 months**: Running vattenfall.rb would only scrape the CURRENT invoice visible on the website (typically 1 bill), not historical bills from past months.

**To populate 3 months of missing bills**: Would need to run scraper 3 times (once per month) OR manually insert historical bills.

---

### 2. Aggregation Bug - Duplicate Vattenfall Bills?

**Answer**: NOT duplicates! Two different bills for September consumption period:

| Provider | Amount | Due Date | Consumption Period |
|----------|--------|----------|--------------------|
| vattenfall | 1632.0 kr | 2025-10-01 | **2025-09** (WRONG!) |
| Vattenfall | 1685.69 kr | 2025-11-03 | **2025-09** (correct) |
| fortum | 792.0 kr | 2025-10-01 | **2025-09** (WRONG!) |

**Current aggregation**: 1632 + 1685.69 + 792 = **4109.69 kr**

**Correct aggregation should be**:
- Oct 1 bill should be August consumption (not Sept)
- Only the Nov 3 bill (1685.69 kr) belongs to September

**Root cause**: The Oct 1 bills were migrated with incorrect `billPeriod` (stored arrival month instead of consumption month).

---

### 3. Consumption Month vs Config Month Logic

**Two Different Concepts** (semantic confusion):

#### Concept 1: Consumption Period
**Definition**: Month when electricity was actually used
**Example**: Due Oct 1 → arrived Sept → **consumed August**

#### Concept 2: Config Period / Arrival Month
**Definition**: Month when bill arrived (determines which RentConfig to update)
**Example**: Due Oct 1 → arrived Sept → **config Sept** (for Oct rent)

**CLAUDE.md documents Config Period logic**:
- Due Oct 1 → Config Sept → Oct rent

**ElectricityBill model calculates Consumption Period**:
```ruby
def self.calculate_bill_period(due_date)
  # Arrival month
  arrival_month = (due_date.day >= 25) ? due_date : (due_date << 1)

  # Consumption = arrival - 1 month
  consumption_month = arrival_month << 1

  Date.new(consumption_month.year, consumption_month.month, 1)
end
```

**Oct 4 Migration Bug**:
```ruby
# BUG: Only calculated arrival month, not consumption!
if day >= 25
  consumption_month = month      # This is actually ARRIVAL month
else
  consumption_month = month - 1  # This is actually ARRIVAL month
end

bill_period = Date.new(consumption_year, consumption_month, 1)
# Missing: bill_period = bill_period << 1 (subtract 1 month)
```

---

### 4. Most Recent Bill Analysis

**Bill**: Vattenfall 1685.69 kr due Nov 3, 2025

**Calculation**:
```
Due date: Nov 3 (day 3 < 25)
→ Arrival: Nov - 1 = October
→ Consumption: Oct - 1 = September
→ billPeriod: 2025-09-01 ✅ CORRECT
```

**This is the ONLY bill with correct period** (created Oct 21 at 17:28:40, after model refactoring).

**Database value**: 2025-09 ✅
**Calculated value**: 2025-09 ✅
**Match**: YES

**Config Period Logic**:
- Bill arrived October
- Should update **September RentConfig** (not October)
- September config determines **October rent** (paid in advance)

**Will it match invoice to wrong month?**
- Current logic: NO - calculation is correct
- BUT: 62 old bills have wrong periods from migration bug
- New bills (scraped after Oct 21): Will be correct

---

## The Core Problem

**What should `billPeriod` represent?**

### Option A: Consumption Period (Current Model Logic)
- Due Oct 1 → billPeriod = 2025-08 (Aug consumption)
- Makes sense for analytics: "How much did we consume in August?"
- Problem: Confusing for rent calculation (Aug consumption → Sept config → Oct rent)

### Option B: Config Period / Arrival Month (CLAUDE.md + Old Migration)
- Due Oct 1 → billPeriod = 2025-09 (Sept arrival)
- Makes sense for rent: "Which RentConfig should this update?"
- Problem: Misleading field name (not actual billing period)

**Current State**: Model says Option A, database has Option B (from migration bug).

---

## Impact Analysis

### Affected Systems

1. **RentConfig Aggregation** 🔥
   - Currently using wrong periods
   - Sept 2025 config: Should be 1685.69 kr (1 bill), currently 4109.69 kr (3 bills)
   - All historical configs likely wrong

2. **Rent Calculations** 🔥
   - Dashboard shows wrong amounts
   - October rent: Based on incorrect Sept config (4109 kr vs correct 1685.69 kr)

3. **ElectricityProjector** ⚠️
   - Uses RentConfig for historical data
   - Projections based on wrong aggregates

4. **Future Scraping** ✅
   - Will use correct logic (ApplyElectricityBill + current model)
   - But will conflict with historical data

---

## Recommended Fix

### Step 1: Decide Semantic Meaning

**Recommendation**: Use **Config Period / Arrival Month** (Option B)

**Rationale**:
- Matches CLAUDE.md documentation
- Easier rent calculation (billPeriod = config period)
- Less confusing: "Bill for Sept config" vs "Bill consumed in Aug for Sept config"

### Step 2: Fix Model Calculation

Change `ElectricityBill.calculate_bill_period`:
```ruby
def self.calculate_bill_period(due_date)
  day = due_date.day

  # Determine ARRIVAL month (not consumption!)
  if day >= 25
    arrival_month = due_date
  else
    arrival_month = due_date << 1
  end

  # Return ARRIVAL month (this is the config period)
  Date.new(arrival_month.year, arrival_month.month, 1)
end
```

### Step 3: Verify Database Data

After fix, all 62 old bills will be CORRECT (they already have arrival month).

### Step 4: Update Documentation

Clarify in code that `billPeriod` = "Config period (arrival month)" not "Consumption period"

---

## Logging Question

**Does vattenfall.rb log?**
- YES: Logs to stdout (DEBUG mode shows extensive logging)
- Production: Cron wrapper should redirect to file

**Check PRODUCTION_CRON_DEPLOYMENT.md**:
```bash
/home/kimonokittens/.rbenv/shims/ruby vattenfall.rb >> logs/electricity_fetcher.log 2>&1
```

✅ Logging is set up correctly in deployment doc.

---

## Next Steps

**DECISION REQUIRED**:
1. Should `billPeriod` represent consumption period or config period?
2. Fix model calculation accordingly
3. Re-test aggregation logic
4. Verify rent calculations are correct

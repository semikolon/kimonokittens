# Consumption-Based Rent Projection Plan

**Created**: December 1, 2025
**Status**: ✅ **IMPLEMENTED** (Smart projection was already in code, just needed proper labeling)

## Summary

The smart consumption-based projection was **already fully implemented** in `ElectricityProjector.project_from_consumption_and_pricing()` (lines 252-315). The implementation:
- Loads actual hourly consumption from `electricity_usage.json`
- Fetches spot prices from elprisetjustnu.se API
- Calculates hour-by-hour: consumption × (spot_price + grid_rate + tax) × VAT
- Adds fixed monthly fees (Vattenfall 590 kr + Fortum 88 kr)
- Applies empirical adjustment factor (1.045)

**What was missing**: Proper labeling in the API response. The handler couldn't distinguish between:
1. Smart projection (consumption × pricing) ← what we wanted to highlight
2. Seasonal baseline (historical pattern × multiplier) ← fallback method

**Fix applied**: Added `check_consumption_data_available()` helper to detect which projection method was used, enabling accurate labeling:
- "Baserad på faktisk förbrukning och aktuella elpriser" (when consumption data available)
- "Baserad på prognos från förra årets elräkningar" (when falling back to seasonal)

**Test result**: December 2025 config now correctly shows **5956 kr** from November 2025 actual consumption (2453.3 kWh) × current pricing, instead of blindly using 2024 data.

## Problem Statement

Current rent projections use **historical year-over-year bill lookups** (e.g., December 2024 bills → December 2025 projection), which ignores:
- Actual recent consumption trends
- Current electricity pricing (spot prices change significantly)
- Behavioral changes (occupancy, heating usage, etc.)

**Example inaccuracy** (Dec 1, 2025):
- January 2026 rent projection: 5,956 kr (from historical lookup)
- But we have actual November 2025 consumption data sitting unused!

## Proposed Solution

Use **ElectricityProjector's smart calculation** with **actual recent consumption data** for rent projections when bills haven't arrived yet.

### Data Flow

```
Vattenfall Scraper → electricity_usage.json (hourly kWh)
                   ↓
          ElectricityProjector
    (consumption × spot prices + fees)
                   ↓
          Rent Config Projection
```

### Timing Example (January 2026 Rent)

- **Rent due**: December 27, 2025
- **Bills cover**: November 2025 consumption
- **Bills arrive**: Mid-December 2025 (around Dec 15)
- **Projection window**: Dec 1-15 (before bills arrive)

**What we have on Dec 1**:
- November 1-30 consumption data (complete month!)
- Current spot prices (elprisetjustnu.se API)
- All fee structures (Vattenfall 590 kr/month, Fortum 88 kr/month)

**What we calculate**:
```ruby
november_kwh = sum(electricity_usage.json, nov 1-30)
november_cost = ElectricityProjector.calculate_from_consumption(
  kwh_data: november_kwh,
  month: 11,
  year: 2025
)
# Returns precise cost including peak/offpeak, taxes, all fees
```

## Implementation Plan

### Phase 1: Extract Consumption-Based Calculation Method

**File**: `lib/electricity_projector.rb`

Add new public method:
```ruby
def calculate_from_actual_consumption(month:, year:)
  # 1. Load electricity_usage.json
  # 2. Filter to target month's hourly data
  # 3. Calculate cost using existing spot price + fee logic
  # 4. Return total cost for rent config
end
```

### Phase 2: Update Rent Config Projection Logic

**File**: `lib/models/rent_config.rb` (or handler)

When fetching config for period without actual bills:
```ruby
# Check if consumption data exists for target month
if consumption_data_available?(config_month - 1)
  # Use smart projection
  projected_cost = ElectricityProjector.new.calculate_from_actual_consumption(
    month: config_month - 1,
    year: config_year
  )
else
  # Fall back to historical lookup (current behavior)
  projected_cost = historical_lookup(config_month, config_year)
end
```

### Phase 3: Update Source Determination

**File**: `handlers/rent_calculator_handler.rb`

Add new data source type:
```ruby
{
  type: 'consumption_projection',
  electricity_source: 'actual_consumption_with_current_pricing',
  description_sv: 'Baserad på faktisk förbrukning och aktuella elpriser'
}
```

## Fallback Strategy

**Priority order**:
1. **Actual bills** (ElectricityBill records exist) → "aktuella elräkningar"
2. **Consumption projection** (consumption data available, no bills yet) → "faktisk förbrukning och aktuella elpriser"
3. **Historical lookup** (no consumption data, no bills) → "prognos från förra årets elräkningar"
4. **Defaults** (everything failed) → "uppskattade elkostnader"

## Benefits

- **Accuracy**: Uses actual consumption + current pricing (not year-old data)
- **Timeliness**: Works as soon as consumption month completes (no waiting for bills)
- **Transparency**: Dashboard shows "based on actual consumption" (honest!)
- **Reuses existing code**: ElectricityProjector already has all the pricing logic

## Edge Cases

### Incomplete Consumption Data

If we only have partial month data (e.g., Nov 1-15 on Nov 16):
- **Option A**: Extrapolate (daily_avg × days_in_month)
- **Option B**: Wait until month complete
- **Recommendation**: Option B for accuracy (only use when full month available)

### Consumption Data File Missing

Fall back gracefully to historical lookup (existing behavior).

### Multiple Months Ahead

For projections >1 month ahead (e.g., projecting February in December):
- Use historical lookup (can't project future consumption reliably)
- Only use consumption-based projection for **immediate next period**

## Historical Context

User mentioned "old code (at least in distant git history)" that may have done something similar - worth checking git history for `ElectricityProjector` or consumption-based calculations.

## Next Steps

1. ✅ Document plan (this file)
2. ⬜ Implement `calculate_from_actual_consumption` method
3. ⬜ Update config projection logic
4. ⬜ Update source determination
5. ⬜ Test with December config (should use November consumption data)
6. ⬜ Deploy via webhook
7. ⬜ Monitor accuracy when real bills arrive mid-December

## Success Metrics

- Projection accuracy within 5% of actual bills when they arrive
- Dashboard clearly indicates when using consumption-based projection
- Graceful fallback if consumption data unavailable
- No regression in existing historical lookup fallback

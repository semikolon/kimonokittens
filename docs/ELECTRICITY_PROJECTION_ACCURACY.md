# Electricity Projection Accuracy & Testing Strategy

**Created**: November 20, 2025
**Status**: 🚧 **In Progress** - VCR ✅ done, accuracy validation & expanded testing pending
**Completed**: VCR realistic test fixtures (Nov 20, 2025)
**Next**: Accuracy validation, expanded test coverage, Tibber investigation

---

## 🚨 CRITICAL: Tibber Confusion Investigation Required

**IMPORTANT FINDING**: The codebase contains references to "Tibber" as a consumption data source, but **we are NOT Tibber customers**.

**Actual consumption data source**: Vattenfall scraper (`bin/vattenfall.rb`)
**File location**: `electricity_usage.json` (scraped hourly consumption from Vattenfall)
**Investigation needed**:
- Search codebase for "Tibber" references
- Verify all consumption data truly comes from Vattenfall scraper
- Update any misleading comments/documentation
- Ensure no code depends on non-existent Tibber integration

**Action**: Investigate after VCR implementation (see "Next Steps" section below)

---

## Overview

This document covers:
1. How the ElectricityProjector works (algorithm details)
2. Current accuracy state and gaps
3. VCR testing strategy for realistic API fixtures
4. Projection accuracy validation methodology
5. Action plan for implementation

**Related documentation**:
- `docs/ELECTRICITY_AUTOMATION_COMPLETION_SUMMARY.md` - Peak/off-peak implementation (0.6-4.3% accuracy)
- `docs/PRODUCTION_CRON_DEPLOYMENT.md` - Automated bill scraping
- `DEVELOPMENT.md:84-94` - Electricity bill timing explanation
- `docs/QUARTERLY_INVOICE_RECURRENCE_PLAN.md` - Quarterly invoice projections

---

## Current State: How ElectricityProjector Works

### Algorithm Overview

The `ElectricityProjector` (`lib/electricity_projector.rb`) uses sophisticated consumption-weighted pricing:

```ruby
# For each hour in the consumption month:
hourly_cost = consumption_kwh × (
  spot_price +           # From elprisetjustnu.se API (market price)
  grid_transfer +        # Peak: 53.6 öre, Off-peak: 21.4 öre (time-of-use)
  energy_tax            # 43.9 öre/kWh (fixed by Skatteverket)
) × 1.25 (VAT)

# Total projection:
total = sum(all_hourly_costs) + fixed_fees (678 kr/month)
```

### Data Sources

| Component | Source | Update Frequency | Notes |
|-----------|--------|------------------|-------|
| **Hourly consumption** | `electricity_usage.json` | Daily (3am cron) | Scraped by Vattenfall scraper |
| **Spot prices** | elprisetjustnu.se API | Real-time | SE3 region (Stockholm) |
| **Grid transfer rates** | Constants in code | Annual review | Vattenfall Tidstariff T4 |
| **Energy tax** | Constants in code | Annual review | Verified from Skatteverket |
| **Fixed fees** | Constants in code | Annual review | Vattenfall (590 kr) + Fortum (88 kr) |

### Peak/Off-Peak Logic

**Peak hours** (higher grid transfer: 53.6 öre/kWh):
- Monday-Friday 06:00-22:00
- Only in winter months (Jan/Feb/Mar/Nov/Dec)
- Excludes holidays

**Off-peak hours** (lower grid transfer: 21.4 öre/kWh):
- All other times
- Entire summer (Apr-Oct)
- **Savings**: 2.5× cheaper than peak!

### Timing Model (2-Month Lag)

```
September consumption → Bills arrive October → October config → November rent
```

**Critical**: The `config_month` parameter represents the CONFIG PERIOD, not the consumption month. The algorithm handles the lag internally.

---

## Problem Discovered: Incomplete Test Data

### What Happened

Integration test for forecast endpoint showed:
```
Found 720 hours, total 1052.7 kWh  ✅ Full consumption data
Found 24 hourly prices             ❌ Only 1 day of pricing!
Calculated costs for 24/720 hours  ⚠️ Only 3.3% coverage!
Variable cost: 64.58 kr
Fixed fees: 678 kr
Total projected: 743 kr
```

**Expected**: ~1840 kr (based on realistic pricing)
**Actual**: 743 kr (severely underestimated due to incomplete data)

### Root Cause

The test used a simplified WebMock stub:
```ruby
# Only provides 24 hours of flat-rate pricing
stub_request(:get, /elprisetjustnu\.se/)
  .to_return(
    body: Array.new(24) { |h| { SEK_per_kWh: 0.5 } }.to_json
  )
```

**Issues with this approach**:
1. Only 1 day of data (need 30 days)
2. Flat rate (no peak/off-peak variation)
3. No seasonal patterns
4. Unrealistic pricing (0.5 SEK is just a guess)

### Current Behavior: Silent Underestimation

The projector **continues with incomplete data** rather than failing. This means:
- Tests pass but produce incorrect results
- Production could silently underestimate if API fails
- No warning when pricing coverage is low

**Design decision needed**: Should the projector:
1. **Fail fast** when data insufficient? (strict validation)
2. **Warn but continue** with partial calculation? (current behavior)
3. **Fallback** to trailing-12-month baseline? (resilient)

---

## Solution 1: VCR for Realistic Test Fixtures

**✅ IMPLEMENTED** (November 20, 2025)

**Outcome**:
- 144KB cassette with 720 hours of real pricing data
- Projection: 1840 kr (realistic, vs 743 kr from fake stub)
- Test suite: 410 tests passing, 0 failures
- Execution time: 0.45s (vs 1.76s initial capture)
- Deterministic: No network dependency

---

### Why VCR?

**VCR (Video Cassette Recorder)** records real HTTP interactions once, then replays them in tests.

**Benefits**:
- ✅ Real API responses (720 hours of actual pricing)
- ✅ Realistic peak/off-peak patterns
- ✅ Seasonal variations preserved
- ✅ No network calls in CI/CD (fast, deterministic)
- ✅ One-time capture, infinite replays

### Implementation

**1. Add VCR gem:**

```ruby
# Gemfile
group :test do
  gem 'vcr'
  gem 'webmock'  # Already present
end
```

**2. Configure in spec_helper.rb:**

```ruby
require 'vcr'

VCR.configure do |config|
  config.cassette_library_dir = "spec/fixtures/vcr_cassettes"
  config.hook_into :webmock
  config.configure_rspec_metadata!

  # Don't record localhost (for Ferrum/Chrome)
  config.ignore_localhost = true

  # Only record if cassette doesn't exist
  config.default_cassette_options = {
    record: :once,
    match_requests_on: [:method, :uri, :body]
  }
end
```

**3. Update integration test:**

```ruby
# spec/rent_calculator/integration_spec.rb
describe 'GET /api/rent/forecast (forecast)' do
  it 'generates a correct forecast for a future month',
     vcr: { cassette_name: 'electricity_prices_2025_06' } do

    # VCR automatically intercepts elprisetjustnu.se calls
    # First run: Makes real API call, saves to cassette
    # Subsequent runs: Replays cassette (no network)

    # ... existing test code ...
  end
end
```

**4. First run captures real data:**

```bash
# Remove old stub from test file
# Run test - VCR captures real API response
bundle exec rspec spec/rent_calculator/integration_spec.rb

# Creates: spec/fixtures/vcr_cassettes/electricity_prices_2025_06.yml
# Contains: ~720 hours of real spot price data
```

**5. Commit cassette to git:**

```bash
git add spec/fixtures/vcr_cassettes/electricity_prices_2025_06.yml
git commit -m "Add VCR cassette with real electricity spot prices"
```

### Expected Outcome

After VCR implementation:
- Test will use **real** 30-day price data
- Projection should be ~1840 kr (or whatever is realistic)
- Test becomes deterministic (same result every time)
- No external API dependency in CI/CD

---

## Solution 2: Projection Accuracy Validation

### Historical Backtesting

Compare projections to actual bills we already have:

```ruby
# spec/electricity_projector_accuracy_spec.rb
RSpec.describe 'ElectricityProjector Accuracy', :vcr do
  let(:projector) { ElectricityProjector.new }

  # Periods where we have BOTH projections and actual bills
  HISTORICAL_PERIODS = [
    { config: [2025, 9], actual_bill: 2424, consumption_month: '2025-08' },
    { config: [2025, 10], actual_bill: 2800, consumption_month: '2025-09' },
    # Add more as data accumulates
  ].freeze

  describe 'historical accuracy' do
    HISTORICAL_PERIODS.each do |period|
      it "projects within 10% of actual bill for #{period[:consumption_month]}" do
        projection = projector.project(
          config_year: period[:config][0],
          config_month: period[:config][1]
        )

        actual = period[:actual_bill]
        error_pct = ((projection - actual).abs.to_f / actual * 100).round(1)

        expect(error_pct).to be < 10,
          "Projected #{projection} kr vs actual #{actual} kr = #{error_pct}% error"
      end
    end

    it 'has mean absolute percentage error (MAPE) under 8%' do
      errors = HISTORICAL_PERIODS.map do |period|
        projection = projector.project(
          config_year: period[:config][0],
          config_month: period[:config][1]
        )
        ((projection - period[:actual_bill]).abs.to_f / period[:actual_bill] * 100)
      end

      mape = errors.sum / errors.size
      expect(mape).to be < 8
    end
  end
end
```

### Accuracy Metrics

**Primary metric: MAPE (Mean Absolute Percentage Error)**

```
MAPE = (1/n) × Σ |actual - projected| / actual × 100%
```

**Target**: MAPE < 8% (based on existing 0.6-4.3% accuracy claims)

**Secondary metrics**:
- MAE (Mean Absolute Error): Average kr difference
- RMSE (Root Mean Square Error): Penalizes large errors
- Max error: Worst single projection

### Feature Completeness Tests

Verify all data sources are used correctly:

```ruby
describe 'feature completeness' do
  it 'uses hourly consumption data' do
    expect(File.exist?('electricity_usage.json')).to be true
    data = JSON.parse(File.read('electricity_usage.json'))
    expect(data.first.keys).to include('date', 'consumption')
  end

  it 'fetches spot prices from API', vcr: { cassette_name: 'spot_prices_current' } do
    projection = projector.project(config_year: 2025, config_month: 11)
    expect(projection).to be > 678  # At least fixed fees
  end

  it 'applies peak/off-peak differentiation' do
    peak_rate = ElectricityProjector::GRID_TRANSFER_PEAK_EXCL_VAT
    offpeak_rate = ElectricityProjector::GRID_TRANSFER_OFFPEAK_EXCL_VAT

    expect(peak_rate).to be > (offpeak_rate * 2)
  end

  it 'handles incomplete spot price data gracefully' do
    # Design decision: How should projector behave?
    # - Fail fast? Warn? Fallback to baseline?
  end
end
```

### Edge Case Testing

```ruby
describe 'edge cases' do
  it 'handles first month of year (December consumption)' do
    projection = projector.project(config_year: 2025, config_month: 1)
    expect(projection).to be > 0
  end

  it 'projects higher costs for winter months' do
    winter = projector.project(config_year: 2025, config_month: 2)
    summer = projector.project(config_year: 2025, config_month: 7)

    expect(winter).to be > (summer * 1.5),
      "Winter should cost significantly more than summer"
  end
end
```

---

## Solution 3: Continuous Accuracy Tracking

### Projection Log System

Track every projection made and compare to actuals when bills arrive:

```ruby
# lib/projection_accuracy_tracker.rb
class ProjectionAccuractyTracker
  LOG_FILE = 'projections_log.jsonl'

  def self.record_projection(config_year:, config_month:, projected_amount:)
    File.open(LOG_FILE, 'a') do |f|
      f.puts({
        timestamp: Time.now.iso8601,
        config_period: "#{config_year}-#{sprintf('%02d', config_month)}",
        projected_amount: projected_amount,
        type: 'projection'
      }.to_json)
    end
  end

  def self.record_actual(config_year:, config_month:, actual_amount:)
    File.open(LOG_FILE, 'a') do |f|
      f.puts({
        timestamp: Time.now.iso8601,
        config_period: "#{config_year}-#{sprintf('%02d', config_month)}",
        actual_amount: actual_amount,
        type: 'actual'
      }.to_json)
    end
  end

  def self.accuracy_report(months: 12)
    # Load last N months of projections vs actuals
    # Calculate MAPE, MAE, RMSE
    # Show trend over time
    # Identify systematic biases (always over/under?)
  end
end
```

### Integration Points

**Record projections** when rent calculation uses projected electricity:
```ruby
# handlers/rent_calculator_handler.rb
if result['el'].to_s == '0'
  projected_el = projector.project(config_year: year, config_month: month)
  result['el'] = projected_el.to_s

  # Track projection for later validation
  ProjectionAccuracyTracker.record_projection(
    config_year: year,
    config_month: month,
    projected_amount: projected_el
  )
end
```

**Record actuals** when scrapers find new bills:
```ruby
# lib/services/apply_electricity_bill.rb
def self.call(provider:, amount:, due_date:)
  # ... existing bill processing ...

  # Track actual for accuracy validation
  period = ElectricityBill.calculate_bill_period(due_date)
  ProjectionAccuracyTracker.record_actual(
    config_year: period.year,
    config_month: period.month,
    actual_amount: aggregated_total
  )
end
```

### Monthly Accuracy Dashboard

Generate accuracy report as part of admin dashboard:

```bash
# bin/electricity_accuracy_report
#!/usr/bin/env ruby
require_relative '../lib/projection_accuracy_tracker'

puts ProjectionAccuracyTracker.accuracy_report(months: 12)
```

**Output example**:
```
Electricity Projection Accuracy Report (Last 12 Months)
========================================================

Period     Projected    Actual    Error   Error %
---------- ----------- --------- -------- --------
2025-09    2400 kr     2424 kr   +24 kr   +1.0%
2025-10    2750 kr     2800 kr   +50 kr   +1.8%
2025-11    3100 kr     2950 kr   -150 kr  -5.1%
...

Summary Statistics:
- MAPE: 2.8%
- MAE: 67 kr
- RMSE: 89 kr
- Bias: -0.3% (slight under-projection)
- Trend: Improving (MAPE was 4.1% 6 months ago)
```

---

## Next Steps

### Phase 1: VCR Implementation (Immediate)

1. ✅ Add VCR gem to Gemfile
2. ✅ Configure VCR in spec_helper.rb
3. ✅ Update integration test to use VCR
4. ✅ Capture real API cassette (one-time)
5. ✅ Verify test produces realistic projection (~1840 kr)
6. ✅ Commit cassette to git

**Estimated time**: 30 minutes
**Impact**: Fixes immediate test inaccuracy, establishes pattern for future tests

### Phase 2: Tibber Investigation (High Priority)

**CRITICAL**: Codebase references "Tibber" but we're NOT Tibber customers.

**Tasks**:
1. Search codebase for all "Tibber" references
2. Verify consumption data source is actually Vattenfall scraper
3. Check if any code depends on non-existent Tibber integration
4. Update misleading comments/documentation
5. Document actual data flow: Vattenfall scraper → electricity_usage.json → ElectricityProjector

**Files to check**:
- `lib/electricity_projector.rb` - Comments mention "Tibber"
- `bin/vattenfall.rb` - Actual consumption scraper
- Any historical migration scripts
- Documentation files

**Expected outcome**: Clear documentation that consumption data comes from Vattenfall, not Tibber.

### Phase 3: Accuracy Test Suite (Medium Priority)

1. Create `spec/electricity_projector_accuracy_spec.rb`
2. Add historical backtest data (last 3-6 months)
3. Implement MAPE calculation
4. Add feature completeness tests
5. Add edge case tests

**Estimated time**: 2 hours
**Impact**: Systematic validation of projection quality

### Phase 4: Continuous Tracking (Low Priority)

1. Implement ProjectionAccuracyTracker
2. Integrate with rent calculator handler
3. Integrate with bill scraper service
4. Create accuracy report script
5. Add to admin dashboard

**Estimated time**: 3 hours
**Impact**: Long-term accuracy monitoring and improvement

### Phase 5: Design Decisions (Discussion Needed)

**Question**: How should projector handle incomplete spot price data?

**Options**:
1. **Fail fast** - Raise error if <90% pricing coverage
   - Pro: Explicit failures, no silent errors
   - Con: Tests become fragile, production could break

2. **Warn and continue** - Log warning, use partial data
   - Pro: Resilient to API issues
   - Con: Silently inaccurate (current behavior)

3. **Fallback to baseline** - Use trailing-12-month average
   - Pro: Always has a valid estimate
   - Con: More complex logic, baseline could be stale

**Recommendation**: Option 3 (fallback to baseline) with explicit logging:
```ruby
if spot_price_coverage < 0.9  # Less than 90% coverage
  warn "Insufficient spot price data (#{coverage}%), falling back to baseline"
  return calculate_baseline_projection(config_year, config_month)
end
```

---

## Open Questions

1. **Consumption data source**: Verify Vattenfall scraper is the ONLY source (not Tibber)
2. **Incomplete data handling**: Choose strategy (fail/warn/fallback)
3. **Accuracy targets**: Is 8% MAPE acceptable? Should we aim lower?
4. **Seasonal baseline**: Should we use trailing 12 months or multi-year seasonal averages?
5. **Peak/off-peak coverage**: Are we correctly identifying peak hours in the algorithm?

---

## References

### Internal Documentation
- `docs/ELECTRICITY_AUTOMATION_COMPLETION_SUMMARY.md` - Scraper accuracy metrics
- `docs/PRODUCTION_CRON_DEPLOYMENT.md` - Automated bill fetching
- `DEVELOPMENT.md` - Electricity bill timing explanation
- `docs/QUARTERLY_INVOICE_RECURRENCE_PLAN.md` - Quarterly projections

### Code Files
- `lib/electricity_projector.rb` - Main projection algorithm
- `lib/services/apply_electricity_bill.rb` - Bill aggregation service
- `bin/vattenfall.rb` - Consumption data scraper
- `handlers/rent_calculator_handler.rb` - Rent calculation with projection fallback

### External Resources
- [VCR gem documentation](https://github.com/vcr/vcr)
- [elprisetjustnu.se API](https://www.elprisetjustnu.se/elpris-api)
- [Vattenfall Tidstariff T4](https://www.vattenfalleldistribution.se/kund-i-elnatet/elnatspriser/)
- [Skatteverket - Energy tax rates](https://www.skatteverket.se/energiskatt)

---

**Document status**: Living document - update as implementation progresses

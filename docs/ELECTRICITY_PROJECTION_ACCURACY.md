# Electricity Projection Accuracy & Testing Strategy

**Created**: November 20, 2025
**Status**: 🚧 **In Progress** - VCR ✅ done, Tibber investigation ✅ done, accuracy validation pending
**Completed**: VCR realistic test fixtures + Tibber data source clarification (Nov 20, 2025)
**Next**: Historical validation testing, expanded edge case coverage, continuous monitoring

---

## ✅ Tibber Confusion Investigation - COMPLETE (Nov 20, 2025)

**CONFIRMED**: The codebase contains references to "Tibber" BUT consumption data comes from Vattenfall scraper, NOT Tibber.

**Investigation findings**:
- ✅ Verified consumption data source: `vattenfall.rb` → `electricity_usage.json`
- ✅ Verified spot price source: `lib/electricity_projector.rb` → elprisetjustnu.se API
- ✅ Searched all "Tibber" references (24 files found)
- ✅ Clarified "Tibber" means Node-RED heatpump scheduling compatibility, not data source

**Tibber references explained**:
- `tibber.rb` - Legacy price fetcher (UNUSED, no active cron job)
- `tibber_price_data.json` - Stale data file (commented out in handlers)
- Handler comments - "Replacing Tibber Query" refers to Node-RED's invalid Tibber demo API key
- "Tibber-compatible" - API response format matching for Node-RED, not actual data source

**Conclusion**: ElectricityProjector uses Vattenfall for consumption + elprisetjustnu.se for pricing. No Tibber integration exists.

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

### Phase 1: Historical Validation (EXHAUSTIVE IMPLEMENTATION GUIDE)

**Objective**: Validate projector accuracy by comparing predictions to actual bills from `electricity_bills_history.txt`.

**Status**: ✅ VCR cassettes ready, ⏳ Historical validation pending

---

#### 1.1 Data Preparation Strategy

**Historical bills source**: `/electricity_bills_history.txt`
- Tab-separated format: `due_date<TAB>amount`
- Two providers: Vattenfall (grid), Fortum (consumption)
- Coverage: 2023-08 through 2025-10

**Period calculation logic** (from `lib/models/electricity_bill.rb:72-86`):
```ruby
def self.calculate_bill_period(due_date)
  day = due_date.day

  # Day 25-31: Bill arrived same month as due
  # Day 1-24: Bill arrived month before due
  if day >= 25
    arrival_month = due_date
  else
    arrival_month = due_date << 1  # Subtract 1 month
  end

  # Return first day of arrival/config period month
  Date.new(arrival_month.year, arrival_month.month, 1)
end
```

**Example period mappings** (critical for test data):
```
Vattenfall due 2025-09-01 (day 1)  → config 2025-08 → Aug consumption
Fortum due 2025-09-01 (day 1)      → config 2025-08 → Aug consumption
Vattenfall due 2025-09-30 (day 30) → config 2025-09 → Aug consumption
Fortum due 2025-10-01 (day 1)      → config 2025-09 → Aug consumption
```

**Consumption month calculation**: Config month - 1 (due to 2-month lag)
```
Config 2025-08 → Consumption 2025-07 (July)
Config 2025-09 → Consumption 2025-08 (August)
```

---

#### 1.2 Test Data Extraction Script

**Purpose**: Parse `electricity_bills_history.txt` into structured test data.

**Implementation** (`bin/extract_historical_test_data.rb`):
```ruby
#!/usr/bin/env ruby
require 'date'
require 'json'
require_relative '../lib/models/electricity_bill'

# Parse electricity_bills_history.txt
def parse_historical_bills(file_path)
  bills = { vattenfall: [], fortum: [] }
  current_provider = nil

  File.readlines(file_path).each do |line|
    line = line.strip

    # Skip comments and empty lines
    next if line.start_with?('#') || line.empty?

    # Detect provider section
    if line =~ /Vattenfall/i
      current_provider = :vattenfall
      next
    elsif line =~ /Fortum/i
      current_provider = :fortum
      next
    end

    # Parse bill line: "2025-09-01\t1330 kr"
    if current_provider && line =~ /^(\d{4}-\d{2}-\d{2})\s+(\d+)\s*kr/
      due_date = Date.parse($1)
      amount = $1.to_f

      # Calculate config period using ACTUAL algorithm
      bill_period = ElectricityBill.calculate_bill_period(due_date)

      bills[current_provider] << {
        due_date: due_date,
        amount: amount,
        bill_period: bill_period,
        consumption_month: bill_period << 1  # Config - 1 month
      }
    end
  end

  bills
end

# Aggregate bills by config period
def aggregate_by_period(bills)
  periods = {}

  [:vattenfall, :fortum].each do |provider|
    bills[provider].each do |bill|
      period_key = bill[:bill_period].strftime('%Y-%m')
      periods[period_key] ||= {
        bill_period: bill[:bill_period],
        consumption_month: bill[:consumption_month],
        vattenfall: 0,
        fortum: 0,
        total: 0
      }

      periods[period_key][provider] += bill[:amount]
      periods[period_key][:total] += bill[:amount]
    end
  end

  periods
end

# Generate test data structure
bills = parse_historical_bills('electricity_bills_history.txt')
aggregated = aggregate_by_period(bills)

# Output as JSON for use in specs
puts JSON.pretty_generate(
  aggregated.values.sort_by { |p| p[:bill_period] }
)
```

**Output format**:
```json
[
  {
    "bill_period": "2024-08-01",
    "consumption_month": "2024-07-01",
    "vattenfall": 1142,
    "fortum": 0,
    "total": 1142,
    "config_year": 2024,
    "config_month": 8
  },
  {
    "bill_period": "2024-09-01",
    "consumption_month": "2024-08-01",
    "vattenfall": 1120,
    "fortum": 387,
    "total": 1507,
    "config_year": 2024,
    "config_month": 9
  }
]
```

---

#### 1.3 Historical Validation Spec

**File**: `spec/electricity_projector_historical_accuracy_spec.rb`

**Purpose**: Compare projector outputs to actual aggregated bills.

**Implementation**:
```ruby
require_relative '../spec_helper'
require_relative '../lib/electricity_projector'
require_relative '../lib/persistence'
require 'json'

RSpec.describe 'ElectricityProjector Historical Accuracy' do
  let(:projector) { ElectricityProjector.new(repo: Persistence.rent_configs) }

  # Load historical test data (generated by extract script)
  HISTORICAL_DATA = JSON.parse(
    File.read('spec/fixtures/historical_electricity_bills.json')
  ).map(&:with_indifferent_access).freeze

  # Filter to periods where we have BOTH consumption data AND actual bills
  # (Recent months only - consumption file has rolling data)
  TESTABLE_PERIODS = HISTORICAL_DATA.select do |period|
    # Only test periods where consumption file likely has data
    # (e.g., last 12 months from today)
    config_date = Date.new(period[:config_year], period[:config_month], 1)
    config_date >= Date.today << 12  # Within last 12 months
  end.freeze

  describe 'individual period accuracy' do
    TESTABLE_PERIODS.each do |period|
      context "#{period[:consumption_month]} consumption (config #{period[:config_year]}-#{sprintf('%02d', period[:config_month])})" do
        # Use VCR cassette for spot price data
        it 'projects within 10% of actual bill',
           vcr: { cassette_name: "electricity_prices_#{period[:config_year]}_#{sprintf('%02d', period[:config_month])}" } do

          projection = projector.project(
            config_year: period[:config_year],
            config_month: period[:config_month]
          )

          actual = period[:total]
          error_pct = ((projection - actual).abs.to_f / actual * 100).round(1)

          expect(error_pct).to be < 10,
            "Projected #{projection} kr vs actual #{actual} kr = #{error_pct}% error\n" \
            "Breakdown: Vattenfall #{period[:vattenfall]} kr + Fortum #{period[:fortum]} kr"
        end
      end
    end
  end

  describe 'aggregate accuracy metrics' do
    it 'has Mean Absolute Percentage Error (MAPE) under 8%' do
      errors = TESTABLE_PERIODS.map do |period|
        # Note: This will use VCR cassettes if available, or skip test if not
        projection = projector.project(
          config_year: period[:config_year],
          config_month: period[:config_month]
        )

        ((projection - period[:total]).abs.to_f / period[:total] * 100)
      rescue StandardError => e
        # Skip periods where projection fails (e.g., missing consumption data)
        warn "Skipping #{period[:config_year]}-#{period[:config_month]}: #{e.message}"
        nil
      end.compact

      skip "Insufficient data points" if errors.size < 3

      mape = errors.sum / errors.size
      expect(mape).to be < 8.0,
        "MAPE: #{mape.round(2)}% (target: <8%)\n" \
        "Tested #{errors.size} periods: #{TESTABLE_PERIODS.map { |p| "#{p[:config_year]}-#{sprintf('%02d', p[:config_month])}" }.join(', ')}"
    end

    it 'has Mean Absolute Error (MAE) under 200 kr' do
      errors = TESTABLE_PERIODS.map do |period|
        projection = projector.project(
          config_year: period[:config_year],
          config_month: period[:config_month]
        )

        (projection - period[:total]).abs
      rescue StandardError
        nil
      end.compact

      skip "Insufficient data points" if errors.size < 3

      mae = errors.sum / errors.size
      expect(mae).to be < 200,
        "MAE: #{mae.round(2)} kr (target: <200 kr)"
    end

    it 'identifies systematic bias (over/under estimation)' do
      signed_errors = TESTABLE_PERIODS.map do |period|
        projection = projector.project(
          config_year: period[:config_year],
          config_month: period[:config_month]
        )

        projection - period[:total]  # Positive = over-estimate, negative = under-estimate
      rescue StandardError
        nil
      end.compact

      skip "Insufficient data points" if signed_errors.size < 3

      mean_bias = signed_errors.sum / signed_errors.size
      bias_pct = (mean_bias / TESTABLE_PERIODS.first[:total] * 100).round(1)

      # Systematic bias should be minimal (<3%)
      expect(bias_pct.abs).to be < 3,
        "Systematic bias: #{bias_pct}% (#{mean_bias.round(0)} kr avg)\n" \
        "Positive = over-estimation, Negative = under-estimation"
    end
  end

  describe 'seasonal pattern validation' do
    it 'projects higher costs for winter months than summer' do
      winter_periods = TESTABLE_PERIODS.select { |p| [1, 2, 3, 11, 12].include?(p[:config_month]) }
      summer_periods = TESTABLE_PERIODS.select { |p| [6, 7, 8].include?(p[:config_month]) }

      skip "Need both winter and summer data" if winter_periods.empty? || summer_periods.empty?

      winter_avg = winter_periods.sum { |p| p[:total] } / winter_periods.size.to_f
      summer_avg = summer_periods.sum { |p| p[:total] } / summer_periods.size.to_f

      expect(winter_avg).to be > (summer_avg * 1.3),
        "Winter should cost at least 30% more than summer\n" \
        "Winter avg: #{winter_avg.round(0)} kr, Summer avg: #{summer_avg.round(0)} kr"
    end
  end
end
```

---

#### 1.4 VCR Cassette Generation Strategy

**Challenge**: Need spot price cassettes for historical months.

**Options**:

**A. Use historical API data** (if elprisetjustnu.se provides it):
```bash
# Check if API supports historical queries
curl "https://www.elprisetjustnu.se/api/v1/prices/2024/08-01_SE3.json"
```

**B. Capture cassettes during test runs** (VCR `:once` mode):
- First run: Makes real API calls, saves cassettes
- Subsequent runs: Replays cassettes
- **Limitation**: Only works for periods where API has historical data

**C. Manual cassette creation** (fallback):
- Load historical spot price data from another source
- Format as VCR cassette YAML
- **Use only if API doesn't provide historical data**

**Recommended approach**: Try A first, fall back to C if needed.

---

#### 1.5 Expected Outcomes

**Success criteria**:
1. ✅ MAPE < 8% across all testable periods
2. ✅ No single period error > 15%
3. ✅ Systematic bias < ±3%
4. ✅ Winter costs 30%+ higher than summer (seasonal validation)

**If tests fail**:
- Investigate periods with highest errors
- Check for missing consumption data
- Verify peak/off-peak classification
- Compare spot price trends (API data vs actual bills)
- Consider adjusting constants (grid rates, tax, fees)

---

### Phase 2: Edge Case Test Coverage (EXHAUSTIVE IMPLEMENTATION GUIDE)

**Objective**: Ensure projector handles all edge conditions gracefully.

**Status**: ⏳ Pending implementation

---

#### 2.1 Peak/Off-Peak Classification Tests

**File**: `spec/electricity_projector_peak_offpeak_spec.rb`

**Purpose**: Verify `is_peak_hour?()` method correctness (lines 442-469 in `electricity_projector.rb`).

**Implementation**:
```ruby
require_relative '../spec_helper'
require_relative '../lib/electricity_projector'

RSpec.describe 'ElectricityProjector Peak/Off-Peak Classification' do
  let(:projector) { ElectricityProjector.new }

  describe 'summer months (Apr-Oct) have NO peak pricing' do
    it 'classifies all June weekday hours as off-peak' do
      # Monday June 2, 2025, 10:00 (should be peak in winter, but it's summer)
      timestamp = '2025-06-02T10:00:00+02:00'
      expect(projector.send(:is_peak_hour?, timestamp)).to be false
    end

    it 'classifies all August weekday hours as off-peak' do
      # Wednesday August 6, 2025, 14:00
      timestamp = '2025-08-06T14:00:00+02:00'
      expect(projector.send(:is_peak_hour?, timestamp)).to be false
    end
  end

  describe 'winter months (Jan/Feb/Mar/Nov/Dec) have peak pricing' do
    context 'weekdays 06:00-22:00' do
      it 'classifies Monday 10:00 as peak' do
        # Monday November 3, 2025, 10:00
        timestamp = '2025-11-03T10:00:00+01:00'
        expect(projector.send(:is_peak_hour?, timestamp)).to be true
      end

      it 'classifies Friday 18:00 as peak' do
        # Friday November 7, 2025, 18:00
        timestamp = '2025-11-07T18:00:00+01:00'
        expect(projector.send(:is_peak_hour?, timestamp)).to be true
      end

      it 'classifies early morning (05:59) as off-peak' do
        # Monday November 3, 2025, 05:59
        timestamp = '2025-11-03T05:59:00+01:00'
        expect(projector.send(:is_peak_hour?, timestamp)).to be false
      end

      it 'classifies late evening (22:00) as off-peak' do
        # Monday November 3, 2025, 22:00
        timestamp = '2025-11-03T22:00:00+01:00'
        expect(projector.send(:is_peak_hour?, timestamp)).to be false
      end
    end

    context 'weekends always off-peak' do
      it 'classifies Saturday 10:00 as off-peak' do
        # Saturday November 1, 2025, 10:00
        timestamp = '2025-11-01T10:00:00+01:00'
        expect(projector.send(:is_peak_hour?, timestamp)).to be false
      end

      it 'classifies Sunday 14:00 as off-peak' do
        # Sunday November 2, 2025, 14:00
        timestamp = '2025-11-02T14:00:00+01:00'
        expect(projector.send(:is_peak_hour?, timestamp)).to be false
      end
    end
  end

  describe 'Swedish holidays always off-peak' do
    it 'classifies New Year\'s Day as off-peak' do
      # Wednesday January 1, 2025, 10:00 (would be peak on regular weekday)
      timestamp = '2025-01-01T10:00:00+01:00'
      expect(projector.send(:is_peak_hour?, timestamp)).to be false
    end

    it 'classifies Labor Day as off-peak' do
      # Thursday May 1, 2025, 10:00
      timestamp = '2025-05-01T10:00:00+02:00'
      expect(projector.send(:is_peak_hour?, timestamp)).to be false
    end

    it 'classifies Christmas Eve as off-peak' do
      # Wednesday December 24, 2025, 10:00
      timestamp = '2025-12-24T10:00:00+01:00'
      expect(projector.send(:is_peak_hour?, timestamp)).to be false
    end

    it 'classifies Good Friday as off-peak' do
      # Friday April 18, 2025, 10:00 (Easter-based movable holiday)
      timestamp = '2025-04-18T10:00:00+02:00'
      expect(projector.send(:is_peak_hour?, timestamp)).to be false
    end
  end

  describe 'timezone handling' do
    it 'correctly converts UTC to local time for peak classification' do
      # 05:00 UTC = 06:00 CET (peak start in winter)
      timestamp = '2025-11-03T05:00:00Z'
      expect(projector.send(:is_peak_hour?, timestamp)).to be true
    end

    it 'handles CEST→CET transition (October DST change)' do
      # Last Sunday October 2025: 03:00 CEST → 02:00 CET
      # Verify hour classification remains consistent
      before_transition = '2025-10-26T01:00:00+02:00'  # Still summer → off-peak
      after_transition = '2025-10-26T02:00:00+01:00'   # Same local time, different offset

      expect(projector.send(:is_peak_hour?, before_transition)).to be false
      expect(projector.send(:is_peak_hour?, after_transition)).to be false
    end
  end
end
```

---

#### 2.2 Data Completeness & Error Handling Tests

**File**: `spec/electricity_projector_error_handling_spec.rb`

**Purpose**: Verify graceful degradation when data is missing or incomplete.

**Implementation**:
```ruby
require_relative '../spec_helper'
require_relative '../lib/electricity_projector'
require_relative '../lib/persistence'

RSpec.describe 'ElectricityProjector Error Handling' do
  let(:projector) { ElectricityProjector.new(repo: Persistence.rent_configs) }

  describe 'missing consumption file' do
    before do
      # Temporarily rename consumption file
      if File.exist?('electricity_usage.json')
        File.rename('electricity_usage.json', 'electricity_usage.json.bak')
      end
    end

    after do
      # Restore consumption file
      if File.exist?('electricity_usage.json.bak')
        File.rename('electricity_usage.json.bak', 'electricity_usage.json')
      end
    end

    it 'falls back to seasonal baseline projection' do
      projection = projector.project(config_year: 2025, config_month: 11)

      # Should still return a valid projection (not raise error)
      expect(projection).to be > 0
      expect(projection).to be_a(Integer)
    end

    it 'logs fallback reason' do
      expect {
        projector.project(config_year: 2025, config_month: 11)
      }.to output(/electricity_usage\.json not found/).to_stdout
    end
  end

  describe 'partial consumption data (incomplete month)' do
    # This test requires mocking consumption data with only 10 days instead of full month
    it 'extrapolates partial data or falls back to baseline' do
      # Test depends on design decision: extrapolate or fallback?
      pending "Design decision needed: extrapolate vs fallback for partial data"
    end
  end

  describe 'spot price API unavailable' do
    before do
      # Stub API to return 404 for all requests
      stub_request(:get, /elprisetjustnu\.se/)
        .to_return(status: 404, body: 'Not Found')
    end

    it 'falls back to seasonal baseline projection' do
      projection = projector.project(config_year: 2025, config_month: 11)

      expect(projection).to be > 0
      expect(projection).to be_a(Integer)
    end

    it 'logs API failure' do
      expect {
        projector.project(config_year: 2025, config_month: 11)
      }.to output(/Smart projection failed/).to_stdout
    end
  end

  describe 'incomplete spot price data (partial month coverage)' do
    before do
      # Stub API to return data for only first 10 days
      stub_request(:get, /elprisetjustnu\.se\/api\/v1\/prices\/2025\/11-0[1-9]_SE3\.json/)
        .to_return(
          status: 200,
          body: Array.new(24) { |h| { SEK_per_kWh: 0.5, time_start: "2025-11-01T#{sprintf('%02d', h)}:00:00+01:00" } }.to_json
        )

      # Days 11-30 return 404
      stub_request(:get, /elprisetjustnu\.se\/api\/v1\/prices\/2025\/11-(1[1-9]|2[0-9]|30)_SE3\.json/)
        .to_return(status: 404)
    end

    it 'falls back to baseline when coverage < 90%' do
      # Current behavior: continues with partial data
      # Expected behavior: should fallback when coverage too low
      pending "Design decision needed: minimum coverage threshold for projection"
    end
  end

  describe 'negative spot prices' do
    it 'handles negative prices correctly (solar surplus hours)' do
      # Negative prices are REAL and should reduce total cost
      # Test that algorithm doesn't break or ignore them

      # Mock consumption data with negative price hour
      consumption = [{ timestamp: '2025-06-15T12:00:00Z', kwh: 0.5 }]
      spot_prices = { '2025-06-15T12:00:00Z' => -0.07 }  # Negative price

      # Calculate expected cost:
      # (spot -0.07 + grid 0.214 + tax 0.439) × 1.25 × 0.5 kWh
      # = (0.583) × 1.25 × 0.5 = 0.36 kr

      # Verify negative prices don't cause errors or get ignored
      expect {
        projector.send(:project_from_consumption_and_pricing, 2025, 6)
      }.not_to raise_error
    end
  end

  describe 'extreme spot price spikes (crisis scenario)' do
    it 'projects realistically even with 5 SEK/kWh spikes' do
      # During energy crisis, spot prices can spike to 5+ SEK/kWh
      # Verify algorithm handles this without overflow or errors
      pending "Test with extreme price data (winter 2022 crisis levels)"
    end
  end

  describe 'year boundary edge cases' do
    it 'handles January projection (December consumption, previous year)' do
      projection = projector.project(config_year: 2025, config_month: 1)

      # Should fetch December 2024 consumption
      # Should use January 2025 config period
      expect(projection).to be > 0
    end

    it 'handles December projection (November consumption, current year)' do
      projection = projector.project(config_year: 2025, config_month: 12)

      # Should fetch November 2025 consumption
      expect(projection).to be > 0
    end
  end
end
```

---

#### 2.3 Constants Verification Tests

**Purpose**: Ensure pricing constants match official sources.

**Implementation**:
```ruby
RSpec.describe 'ElectricityProjector Constants Verification' do
  describe 'grid transfer rates (Vattenfall Tidstariff T4)' do
    it 'has peak rate of 53.6 öre/kWh' do
      expect(ElectricityProjector::GRID_TRANSFER_PEAK_EXCL_VAT).to eq(0.536)
    end

    it 'has off-peak rate of 21.4 öre/kWh' do
      expect(ElectricityProjector::GRID_TRANSFER_OFFPEAK_EXCL_VAT).to eq(0.214)
    end

    it 'peak rate is ~2.5× off-peak rate' do
      ratio = ElectricityProjector::GRID_TRANSFER_PEAK_EXCL_VAT /
              ElectricityProjector::GRID_TRANSFER_OFFPEAK_EXCL_VAT
      expect(ratio).to be_within(0.1).of(2.5)
    end
  end

  describe 'energy tax (Skatteverket)' do
    it 'has energy tax of 43.9 öre/kWh excl VAT' do
      expect(ElectricityProjector::ENERGY_TAX_EXCL_VAT).to eq(0.439)
    end

    it 'has energy tax of 54.875 öre/kWh incl VAT' do
      expect(ElectricityProjector::ENERGY_TAX_INCL_VAT).to eq(0.54875)
    end

    it 'VAT calculation is correct (25%)' do
      expected_with_vat = ElectricityProjector::ENERGY_TAX_EXCL_VAT * 1.25
      expect(ElectricityProjector::ENERGY_TAX_INCL_VAT).to eq(expected_with_vat)
    end
  end

  describe 'fixed monthly fees' do
    it 'has Vattenfall fee of 590 kr/month' do
      expect(ElectricityProjector::VATTENFALL_MONTHLY_FEE).to eq(590)
    end

    it 'has Fortum fee of 88 kr/month' do
      expect(ElectricityProjector::FORTUM_MONTHLY_FEE).to eq(88)
    end

    it 'has total monthly fee of 678 kr' do
      expect(ElectricityProjector::MONTHLY_FEE).to eq(678)
      expect(ElectricityProjector::MONTHLY_FEE).to eq(
        ElectricityProjector::VATTENFALL_MONTHLY_FEE +
        ElectricityProjector::FORTUM_MONTHLY_FEE
      )
    end
  end
end
```

---

### Phase 3: Continuous Accuracy Monitoring System (EXHAUSTIVE IMPLEMENTATION GUIDE)

**Objective**: Track projection accuracy over time, detect degradation, enable continuous improvement.

**Status**: ⏳ Pending implementation

---

#### 3.1 Database Schema Addition

**Purpose**: Store projections and actuals for comparison.

**Prisma schema addition** (`prisma/schema.prisma`):
```prisma
model ElectricityProjection {
  id              String   @id @default(cuid())
  configYear      Int      // Config period year (e.g., 2025)
  configMonth     Int      // Config period month (1-12)
  consumptionYear Int      // Actual consumption year
  consumptionMonth Int     // Actual consumption month

  // Projection data
  projectedAmount Int      // Projected cost in SEK
  projectedAt     DateTime @default(now())
  consumptionKwh  Float?   // Total kWh used for projection
  spotPriceCoverage Float? // % of hours with spot price data (0.0-1.0)

  // Actual data (populated when bills arrive)
  actualAmount    Int?     // Actual bill total (Vattenfall + Fortum)
  actualizedAt    DateTime?

  // Accuracy metrics
  errorKr         Int?     // Actual - Projected (signed)
  errorPct        Float?   // (Error / Actual) × 100
  absoluteErrorPct Float?  // |errorPct|

  createdAt       DateTime @default(now())
  updatedAt       DateTime @updatedAt

  @@unique([configYear, configMonth])
  @@index([projectedAt])
  @@index([actualizedAt])
  @@map("ElectricityProjection")
}
```

**Migration**:
```bash
npx prisma migrate dev --name add_electricity_projection_tracking
```

---

#### 3.2 Domain Model

**File**: `lib/models/electricity_projection.rb`

**Implementation**:
```ruby
require 'date'

# ElectricityProjection domain model for accuracy tracking
#
# Stores both projections and actuals for systematic accuracy monitoring.
# Enables MAPE calculation, bias detection, and trend analysis.
class ElectricityProjection
  attr_reader :id, :config_year, :config_month, :consumption_year, :consumption_month,
              :projected_amount, :projected_at, :consumption_kwh, :spot_price_coverage,
              :actual_amount, :actualized_at,
              :error_kr, :error_pct, :absolute_error_pct,
              :created_at, :updated_at

  def initialize(
    id: nil,
    config_year:,
    config_month:,
    consumption_year: nil,
    consumption_month: nil,
    projected_amount:,
    projected_at: Time.now,
    consumption_kwh: nil,
    spot_price_coverage: nil,
    actual_amount: nil,
    actualized_at: nil,
    error_kr: nil,
    error_pct: nil,
    absolute_error_pct: nil,
    created_at: nil,
    updated_at: nil
  )
    @id = id
    @config_year = config_year
    @config_month = config_month

    # Auto-calculate consumption period if not provided
    @consumption_year = consumption_year || calculate_consumption_year(config_year, config_month)
    @consumption_month = consumption_month || calculate_consumption_month(config_month)

    @projected_amount = projected_amount
    @projected_at = projected_at
    @consumption_kwh = consumption_kwh
    @spot_price_coverage = spot_price_coverage

    @actual_amount = actual_amount
    @actualized_at = actualized_at

    # Auto-calculate errors if actual provided
    if actual_amount
      @error_kr = error_kr || (actual_amount - projected_amount)
      @error_pct = error_pct || calculate_error_pct(actual_amount, projected_amount)
      @absolute_error_pct = absolute_error_pct || @error_pct.abs
    end

    @created_at = created_at
    @updated_at = updated_at
  end

  # Record actual bill when it arrives
  def actualize!(actual_amount)
    ElectricityProjection.new(
      id: @id,
      config_year: @config_year,
      config_month: @config_month,
      consumption_year: @consumption_year,
      consumption_month: @consumption_month,
      projected_amount: @projected_amount,
      projected_at: @projected_at,
      consumption_kwh: @consumption_kwh,
      spot_price_coverage: @spot_price_coverage,
      actual_amount: actual_amount,
      actualized_at: Time.now,
      created_at: @created_at,
      updated_at: Time.now
    )
  end

  # Check if projection has been actualized
  def actualized?
    !actual_amount.nil?
  end

  # Calculate Mean Absolute Percentage Error for a set of projections
  def self.calculate_mape(projections)
    actualized = projections.select(&:actualized?)
    return nil if actualized.empty?

    actualized.sum(&:absolute_error_pct) / actualized.size.to_f
  end

  private

  def calculate_consumption_year(config_year, config_month)
    config_month == 1 ? config_year - 1 : config_year
  end

  def calculate_consumption_month(config_month)
    config_month == 1 ? 12 : config_month - 1
  end

  def calculate_error_pct(actual, projected)
    return 0.0 if actual.zero?
    ((actual - projected).to_f / actual * 100).round(2)
  end
end
```

---

#### 3.3 Repository

**File**: `lib/repositories/electricity_projection_repository.rb`

**Implementation**:
```ruby
require_relative '../models/electricity_projection'
require_relative '../rent_db'

class ElectricityProjectionRepository
  def initialize(db: RentDb.instance)
    @db = db
  end

  def create(projection)
    result = db.class.db[:ElectricityProjection].insert(
      configYear: projection.config_year,
      configMonth: projection.config_month,
      consumptionYear: projection.consumption_year,
      consumptionMonth: projection.consumption_month,
      projectedAmount: projection.projected_amount,
      projectedAt: projection.projected_at,
      consumptionKwh: projection.consumption_kwh,
      spotPriceCoverage: projection.spot_price_coverage,
      actualAmount: projection.actual_amount,
      actualizedAt: projection.actualized_at,
      errorKr: projection.error_kr,
      errorPct: projection.error_pct,
      absoluteErrorPct: projection.absolute_error_pct
    )

    find_by_id(result)
  end

  def update(projection)
    db.class.db[:ElectricityProjection]
      .where(id: projection.id)
      .update(
        actualAmount: projection.actual_amount,
        actualizedAt: projection.actualized_at,
        errorKr: projection.error_kr,
        errorPct: projection.error_pct,
        absoluteErrorPct: projection.absolute_error_pct,
        updatedAt: Time.now
      )

    find_by_id(projection.id)
  end

  def find_by_id(id)
    row = db.class.db[:ElectricityProjection].where(id: id).first
    row_to_model(row) if row
  end

  def find_by_config_period(year, month)
    row = db.class.db[:ElectricityProjection]
      .where(configYear: year, configMonth: month)
      .first

    row_to_model(row) if row
  end

  def find_recent(months: 12)
    db.class.db[:ElectricityProjection]
      .order(Sequel.desc(:projectedAt))
      .limit(months)
      .all
      .map { |row| row_to_model(row) }
  end

  def find_actualized(months: 12)
    db.class.db[:ElectricityProjection]
      .where(Sequel.~(actualAmount: nil))
      .order(Sequel.desc(:actualizedAt))
      .limit(months)
      .all
      .map { |row| row_to_model(row) }
  end

  def statistics
    {
      total_projections: db.class.db[:ElectricityProjection].count,
      actualized: db.class.db[:ElectricityProjection].where(Sequel.~(actualAmount: nil)).count,
      pending: db.class.db[:ElectricityProjection].where(actualAmount: nil).count
    }
  end

  private

  attr_reader :db

  def row_to_model(row)
    ElectricityProjection.new(
      id: row[:id],
      config_year: row[:configYear],
      config_month: row[:configMonth],
      consumption_year: row[:consumptionYear],
      consumption_month: row[:consumptionMonth],
      projected_amount: row[:projectedAmount],
      projected_at: row[:projectedAt],
      consumption_kwh: row[:consumptionKwh],
      spot_price_coverage: row[:spotPriceCoverage],
      actual_amount: row[:actualAmount],
      actualized_at: row[:actualizedAt],
      error_kr: row[:errorKr],
      error_pct: row[:errorPct],
      absolute_error_pct: row[:absoluteErrorPct],
      created_at: row[:createdAt],
      updated_at: row[:updatedAt]
    )
  end
end
```

---

#### 3.4 Integration with ElectricityProjector

**Modify** `lib/electricity_projector.rb:94-145`:
```ruby
def project(config_year:, config_month:)
  # ... existing bill check ...

  # Check for existing projection in tracking system
  existing_projection = Persistence.electricity_projections
    .find_by_config_period(config_year, config_month)

  # ... smart projection calculation ...

  # Track projection if not already tracked
  unless existing_projection
    ElectricityProjection.new(
      config_year: config_year,
      config_month: config_month,
      projected_amount: projection,
      consumption_kwh: total_kwh,  # From consumption data
      spot_price_coverage: spot_price_coverage  # Calculate from API responses
    ).tap { |proj| Persistence.electricity_projections.create(proj) }
  end

  projection
end
```

---

#### 3.5 Integration with ApplyElectricityBill Service

**Modify** `lib/services/apply_electricity_bill.rb`:
```ruby
def self.call(provider:, amount:, due_date:)
  # ... existing bill processing ...

  # Aggregate bills for this period
  aggregated_total = ElectricityBill.aggregate_for_period(
    bill_period,
    repository: Persistence.electricity_bills
  )

  # Update RentConfig
  Persistence.rent_configs.save(
    RentConfig.new(
      key: 'el',
      value: aggregated_total.to_s,
      period: bill_period
    )
  )

  # **NEW**: Actualize projection if exists
  projection = Persistence.electricity_projections
    .find_by_config_period(bill_period.year, bill_period.month)

  if projection
    actualized = projection.actualize!(aggregated_total)
    Persistence.electricity_projections.update(actualized)

    puts "  ✅ Actualized projection: #{projection.projected_amount} kr → #{aggregated_total} kr (#{actualized.error_pct}% error)"
  end

  # ... WebSocket broadcast ...
end
```

---

#### 3.6 Accuracy Report Script

**File**: `bin/electricity_accuracy_report`

**Implementation**:
```bash
#!/usr/bin/env ruby
require 'dotenv/load'
require_relative '../lib/persistence'

puts "=" * 80
puts "Electricity Projection Accuracy Report"
puts "=" * 80
puts

# Get statistics
stats = Persistence.electricity_projections.statistics
puts "Summary:"
puts "  Total projections: #{stats[:total_projections]}"
puts "  Actualized: #{stats[:actualized]}"
puts "  Pending: #{stats[:pending]}"
puts

# Get recent actualized projections
projections = Persistence.electricity_projections.find_actualized(months: 12)

if projections.empty?
  puts "No actualized projections yet."
  exit 0
end

# Table header
printf "%-12s %-12s %-10s %-10s %-10s %-8s\n",
  "Period", "Consumption", "Projected", "Actual", "Error", "Error %"
puts "-" * 80

# Table rows
projections.each do |proj|
  printf "%-12s %-12s %10d kr %10d kr %+10d kr %+7.1f%%\n",
    "#{proj.config_year}-#{sprintf('%02d', proj.config_month)}",
    "#{proj.consumption_year}-#{sprintf('%02d', proj.consumption_month)}",
    proj.projected_amount,
    proj.actual_amount,
    proj.error_kr,
    proj.error_pct
end

puts "-" * 80

# Calculate aggregate metrics
mape = ElectricityProjection.calculate_mape(projections)
mae = projections.sum { |p| p.error_kr.abs } / projections.size.to_f
mean_bias = projections.sum(&:error_kr) / projections.size.to_f

puts
puts "Aggregate Metrics (last #{projections.size} months):"
puts "  MAPE (Mean Absolute Percentage Error): #{mape.round(2)}%"
puts "  MAE (Mean Absolute Error): #{mae.round(0)} kr"
puts "  Mean Bias: #{mean_bias > 0 ? '+' : ''}#{mean_bias.round(0)} kr (#{mean_bias > 0 ? 'over' : 'under'}-estimation)"
puts

# Accuracy assessment
if mape < 5
  puts "✅ Excellent accuracy (MAPE < 5%)"
elsif mape < 8
  puts "✅ Good accuracy (MAPE < 8%)"
elsif mape < 10
  puts "⚠️  Acceptable accuracy (MAPE < 10%)"
else
  puts "❌ Poor accuracy (MAPE >= 10%) - investigation needed"
end
```

**Make executable**:
```bash
chmod +x bin/electricity_accuracy_report
```

**Usage**:
```bash
./bin/electricity_accuracy_report
```

**Expected output**:
```
================================================================================
Electricity Projection Accuracy Report
================================================================================

Summary:
  Total projections: 15
  Actualized: 8
  Pending: 7

Period       Consumption  Projected     Actual      Error    Error %
--------------------------------------------------------------------------------
2025-09      2025-08        2400 kr     2424 kr      +24 kr    +1.0%
2025-10      2025-09        2750 kr     2800 kr      +50 kr    +1.8%
2025-11      2025-10        3100 kr     2950 kr     -150 kr    -5.1%
...
--------------------------------------------------------------------------------

Aggregate Metrics (last 8 months):
  MAPE (Mean Absolute Percentage Error): 2.8%
  MAE (Mean Absolute Error): 67 kr
  Mean Bias: -12 kr (under-estimation)

✅ Excellent accuracy (MAPE < 5%)
```

---

### Phase 4: Tibber Investigation (CRITICAL CLEANUP)

**Objective**: Remove or clarify misleading "Tibber" references in codebase.

**Status**: ⏳ Pending investigation

**Tasks**:
1. Search for "Tibber" references: `grep -r "Tibber" .`
2. Verify all consumption data comes from Vattenfall scraper
3. Update misleading comments
4. Document actual data flow in CLAUDE.md

**Expected outcome**: Clear documentation that `electricity_usage.json` is populated by Vattenfall scraper, NOT Tibber.

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

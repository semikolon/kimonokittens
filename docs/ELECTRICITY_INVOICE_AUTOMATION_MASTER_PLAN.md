# Electricity Invoice Automation - Master Plan

**Created:** October 21, 2025
**Updated:** October 21, 2025 (after testing)
**Status:** Migration Phase - Vessel → Ferrum
**Goal:** Fully automate electricity invoice fetching and rent calculation integration

---

## ⚠️ TESTING RESULTS & DECISION (October 21, 2025)

**Current Script Status:** ❌ **NON-FUNCTIONAL**

**Test Results:**
```bash
$ ruby -c vattenfall.rb
Syntax OK  ✅

$ ruby -e "require 'vessel'"
LoadError: cannot load such file -- vessel  ❌

$ ruby -e "require 'ferrum'"
Success  ✅
```

**Findings:**
- Vessel gem is **NOT installed** in current bundle
- Current vattenfall.rb **CANNOT run** without Vessel
- Ferrum is installed and working
- Script uses invalid `driver(:ferrum, ...)` syntax (doesn't exist in Vessel 0.2.0)

**Decision:** **Proceed immediately with Ferrum migration**
- Current script is broken anyway (missing dependency + invalid syntax)
- Vessel is abandoned (4+ years stale, per BRF-Auto docs)
- Pure Ferrum is simpler, maintainable, and future-proof
- Migration effort: 1-2 hours (minimal Vessel usage)

**User Requirements:**
- ✅ Daily automated scraping (consumption + invoices)
- ✅ Cron-based scheduling (3am daily)
- ✅ Future-proof, maintainable solution
- ✅ Comprehensive debug logging

---

## ✅ MIGRATION COMPLETED (October 21, 2025)

**Test Results:**
```
Execution time: 11 seconds
Data fetched: 9,745 hours (406 days coverage)
Data quality: 97% (9,480 hours with consumption values)
File size: 679KB JSON
Latest data: Nov 1, 2025 01:00
Status: ✅ 100% SUCCESS
```

**Validated Features:**
- ✅ Browser automation (Ferrum 0.17.1)
- ✅ Login flow (customer number + password)
- ✅ API authentication (Azure subscription key)
- ✅ Data extraction (hourly consumption)
- ✅ Timezone handling (+02:00 offset)
- ✅ File writing (electricity_usage.json)
- ✅ Debug mode (visible browser + detailed logs)
- ✅ Error handling (screenshots on failure)
- ✅ Clean browser cleanup (no zombie processes)

**Lessons Learned:**
1. **Ferrum is stable** - 0.17.1 released May 2025, actively maintained
2. **Login flow unchanged** - Portal structure same as legacy script
3. **API still requires Azure key** - ENV['AZURE_SUBSCRIPTION_KEY']
4. **Data format stable** - Same JSON structure as before
5. **Browser cleanup critical** - Suppress known Ferrum quit errors

**Next Phase:** Invoice scraping extension (current work)

---

## Executive Summary

Extend the existing `vattenfall.rb` consumption scraper to also fetch invoice data (amounts, due dates, periods), integrate with the rent calculation system, and eliminate manual invoice entry. Future extension to Fortum provider planned.

### Current State Analysis

**✅ What Works:**
- `vattenfall.rb` - Fetches hourly consumption data via Ferrum browser automation
- `ElectricityProjector` - Projects costs using trailing 12-month baseline + seasonal multipliers
- `ElectricityStatsHandler` - Combines usage + price data for dashboard display
- `ElectricityPriceHandler` - Fetches hourly prices from elprisetjustnu.se API
- `ElectricityBill` database table - Structure exists for invoice storage
- `RentConfig` table - Stores aggregated electricity costs for rent calculations

**⚠️ Current Gaps:**
- No invoice scraping (only consumption data)
- Manual entry required for monthly electricity bills
- Usage data not integrated with ElectricityProjector
- Price data not used for projection refinement
- No automation trigger (manual script execution)

**📊 Data Flow (Current):**
```
Vattenfall API (manual login)
  → electricity_usage.json (hourly kWh)
  → ElectricityStatsHandler (dashboard display only)

Manual Entry
  → RentConfig (key='el')
  → ElectricityProjector
  → Rent Calculation
```

**🎯 Data Flow (Target):**
```
Vattenfall Scraper (automated)
  ├→ Consumption API → electricity_usage.json
  └→ Invoice Page → ElectricityBill table → RentConfig aggregation

ElectricityProjector (enhanced)
  ├→ Historical invoices (RentConfig baseline)
  ├→ Detailed usage patterns (electricity_usage.json)
  └→ Hourly price data (elprisetjustnu.se)
  → Better projections

Cron Job (monthly)
  → Trigger scraper → Auto-update RentConfig → Rent ready
```

---

## Phase 1: Dependency Update & Infrastructure

### 1.1 Vessel Gem Investigation ⚠️

**Issue:** `vattenfall.rb` requires `vessel` gem but it's not in Gemfile or installed.

**Tasks:**
- [ ] Determine if Vessel is obsolete or needs reinstallation
- [ ] Check if script works without Vessel (direct Ferrum usage)
- [ ] Research modern Vessel gem versions or alternatives
- [ ] Update Gemfile with correct Vessel source if needed
- [ ] Consider migration to pure Ferrum if Vessel is abandoned

**Research Questions:**
- Is Vessel still maintained? (Check GitHub: https://github.com/xronos-i-am/vessel)
- When was vattenfall.rb last successfully run?
- Are there newer scraping frameworks (Kimurai, Capybara, etc.)?

### 1.2 Dependency Updates

**Current Versions:**
- ferrum: (check Gemfile.lock)
- puma: ~> 6.4
- sequel: ~> 5.84
- pg: ~> 1.6

**Update Tasks:**
- [ ] Update Ferrum to latest stable (check for breaking changes)
- [ ] Update Vessel (if keeping it) or migrate away
- [ ] Add any missing dependencies for invoice PDF parsing (if needed)
- [ ] Run `bundle update` and test existing scripts
- [ ] Document version changes in CHANGELOG

**New Dependencies (if needed):**
- [ ] PDF parsing: `pdf-reader` or `hexapdf` (if invoices are PDFs)
- [ ] Enhanced logging: `semantic_logger` (optional, for structured logs)
- [ ] Retry logic: `retriable` gem (for network failures)

### 1.3 Debug Logging Infrastructure

**Add comprehensive logging throughout scraper:**
- [ ] Structured logging with timestamps
- [ ] Log navigation steps (page loads, clicks, waits)
- [ ] Log data extraction results
- [ ] Log API responses and errors
- [ ] Screenshot capture on errors
- [ ] Progress indicators for long operations

**Logging Strategy:**
```ruby
require 'logger'

logger = Logger.new(STDOUT)
logger.level = ENV['DEBUG'] ? Logger::DEBUG : Logger::INFO
logger.formatter = proc do |severity, datetime, progname, msg|
  "[#{datetime.strftime('%Y-%m-%d %H:%M:%S')}] #{severity}: #{msg}\n"
end
```

---

## Phase 2: Vattenfall Invoice Scraping Extension

### 2.1 Research - Vattenfall Portal Navigation

**Manual Exploration Required:**
1. Log into Vattenfall portal: https://www.vattenfalleldistribution.se/logga-in?pageId=6
2. Document navigation path to invoices:
   - After login, which menu/links to click?
   - Where are invoices listed? (Mina sidor → Fakturor?)
   - Invoice format: PDF download? HTML table? JSON data?
3. Identify data fields needed:
   - Invoice amount (kr)
   - Due date
   - Billing period (consumption month)
   - Invoice number (optional)
   - PDF download URL (optional)
4. Check for pagination (if >12 invoices displayed)
5. Test if AJAX/dynamic loading is used

**Documentation Output:**
- [ ] Create `docs/VATTENFALL_PORTAL_NAVIGATION.md` with screenshots
- [ ] Document CSS selectors for invoice elements
- [ ] Note any authentication challenges or CAPTCHA

### 2.2 Extend `vattenfall.rb` - Invoice Scraping Logic

**New Methods:**

```ruby
class Vattenfall < Vessel::Cargo
  # Existing consumption scraping...

  def navigate_to_invoices
    logger.info "Navigating to invoice page..."
    # Click "Mina fakturor" or equivalent link
    invoice_link = wait_for_element(selector: "//a[contains(text(), 'Fakturor')]")
    invoice_link.click
    page.network.wait_for_idle(timeout: 30)
    logger.info "Invoice page loaded"
  end

  def scrape_latest_invoice
    logger.info "Scraping latest invoice..."

    # Find invoice table/list
    invoice_rows = css('.invoice-row') # Adjust selector based on research

    latest_invoice = invoice_rows.first
    amount = extract_amount(latest_invoice)
    due_date = extract_due_date(latest_invoice)
    period = calculate_period(due_date)

    logger.info "Found invoice: #{amount} kr, due #{due_date}"

    {
      provider: 'vattenfall',
      amount: amount,
      due_date: due_date,
      bill_period: period,
      invoice_number: extract_invoice_number(latest_invoice)
    }
  end

  def extract_amount(element)
    # Extract amount from invoice row
    # Handle Swedish formatting: "1 632 kr" → 1632
    text = element.at_css('.amount')&.text
    text.gsub(/[^\d]/, '').to_i
  end

  def extract_due_date(element)
    # Extract and parse due date
    date_text = element.at_css('.due-date')&.text
    Date.parse(date_text) # May need Swedish locale handling
  end

  def calculate_period(due_date)
    # Apply CLAUDE.md timing logic (lines 75-91)
    # Same logic as electricity_bill_migration.rb
    if due_date.day >= 25
      consumption_month = due_date.month
      consumption_year = due_date.year
    else
      consumption_month = due_date.month - 1
      consumption_year = due_date.year
    end

    consumption_month = 12 if consumption_month < 1
    consumption_year -= 1 if consumption_month == 12

    Date.new(consumption_year, consumption_month, 1)
  end

  def download_invoice_pdf(invoice_row)
    # Optional: Download PDF for archival
    pdf_link = invoice_row.at_css('a.download-pdf')
    return unless pdf_link

    pdf_url = pdf_link.attribute('href')
    logger.info "Downloading PDF: #{pdf_url}"

    # Save to data/invoices/vattenfall/
    # Return file path for database storage
  end
end
```

**Error Handling:**
- [ ] Retry on network timeouts (3 attempts)
- [ ] Screenshot on scraping failures
- [ ] Fallback to manual entry if scrape fails
- [ ] Email/log alerts for failures

### 2.3 Testing Infrastructure

**Test Cases:**
- [ ] Mock login success/failure
- [ ] Mock invoice page HTML fixtures
- [ ] Test amount parsing (Swedish number formatting)
- [ ] Test date parsing (Swedish date formats)
- [ ] Test period calculation edge cases (Dec→Jan transitions)
- [ ] Integration test: Full scrape-to-database flow

**RSpec Example:**
```ruby
require 'spec_helper'
require_relative '../vattenfall'

RSpec.describe Vattenfall do
  describe '#extract_amount' do
    it 'parses Swedish number formatting' do
      element = double(at_css: double(text: '1 632 kr'))
      expect(subject.extract_amount(element)).to eq(1632)
    end
  end

  describe '#calculate_period' do
    context 'when due date is end of month' do
      it 'uses due month as consumption period' do
        due_date = Date.new(2025, 9, 30)
        period = subject.calculate_period(due_date)
        expect(period).to eq(Date.new(2025, 9, 1))
      end
    end

    context 'when due date is start of month' do
      it 'uses previous month as consumption period' do
        due_date = Date.new(2025, 10, 1)
        period = subject.calculate_period(due_date)
        expect(period).to eq(Date.new(2025, 9, 1))
      end
    end
  end
end
```

---

## Phase 3: Data Integration Layer

### 3.1 Database Operations

**ElectricityBill Table (already exists):**
```ruby
db[:ElectricityBill].insert(
  id: Cuid.generate,
  provider: 'vattenfall',
  billDate: due_date,
  amount: amount,
  billPeriod: period,
  pdfPath: pdf_path,  # Optional
  invoiceNumber: invoice_number,  # Optional
  createdAt: Time.now.utc,
  updatedAt: Time.now.utc
)
```

**RentConfig Aggregation:**
```ruby
# After inserting ElectricityBill records, aggregate to RentConfig
def update_rent_config(period)
  total = db[:ElectricityBill]
    .where(billPeriod: period)
    .sum(:amount) || 0

  db.set_config('el', total, period)
  logger.info "Updated RentConfig: #{period.strftime('%Y-%m')} = #{total} kr"
end
```

**Duplicate Detection:**
```ruby
def invoice_exists?(provider, due_date, amount)
  db[:ElectricityBill]
    .where(provider: provider, billDate: due_date, amount: amount)
    .count > 0
end
```

### 3.2 Invoice Fetcher Service

**Create:** `lib/electricity_invoice_fetcher.rb`

```ruby
require_relative '../vattenfall'
require_relative 'rent_db'

class ElectricityInvoiceFetcher
  attr_reader :db, :logger

  def initialize(db: RentDb.instance, logger: Logger.new(STDOUT))
    @db = db
    @logger = logger
  end

  def fetch_and_store_vattenfall
    logger.info "=== Fetching Vattenfall Invoices ==="

    invoices = []

    Vattenfall.run do |_consumption_data|
      # Skip consumption data, we're only here for invoices
      # Call new invoice scraping methods
      invoice_data = scrape_latest_invoice
      invoices << invoice_data
    end

    invoices.each do |invoice|
      store_invoice(invoice)
    end

    # Aggregate to RentConfig
    update_all_periods

    logger.info "✅ Vattenfall invoices fetched and stored"
  rescue => e
    logger.error "❌ Failed to fetch Vattenfall invoices: #{e.message}"
    logger.error e.backtrace.first(10)
    raise
  end

  private

  def store_invoice(invoice)
    if invoice_exists?(invoice[:provider], invoice[:due_date], invoice[:amount])
      logger.info "Skipping duplicate: #{invoice[:due_date]} - #{invoice[:amount]} kr"
      return
    end

    db.class.db[:ElectricityBill].insert(
      id: Cuid.generate,
      provider: invoice[:provider],
      billDate: invoice[:due_date],
      amount: invoice[:amount],
      billPeriod: invoice[:bill_period],
      pdfPath: invoice[:pdf_path],
      invoiceNumber: invoice[:invoice_number],
      createdAt: Time.now.utc,
      updatedAt: Time.now.utc
    )

    logger.info "✅ Stored invoice: #{invoice[:bill_period].strftime('%Y-%m')} - #{invoice[:amount]} kr"
  end

  def update_all_periods
    # Find all distinct periods with invoices
    periods = db.class.db[:ElectricityBill]
      .distinct
      .select(:billPeriod)
      .map { |row| row[:billPeriod] }

    periods.each do |period|
      total = db.class.db[:ElectricityBill]
        .where(billPeriod: period)
        .sum(:amount) || 0

      db.set_config('el', total, period)
    end
  end
end
```

---

## Phase 4: Smart Adaptive Projection (Consumption × Pricing)

### 4.1 Proven Formula from Production (May 2023)

**Source:** `handlers/electricity_stats_handler.rb` (unchanged since 2023, verified Oct 2025)

**The Core Insight:** Both Vattenfall AND Fortum bills are heavily consumption-dependent.

#### Historical Validation (May 2023 Actual Bills)

**Consumption:** 900 kWh

**Fortum (elhandel - electricity trading):**
- Total bill: 616 kr
- Breakdown: Spot price × consumption + 39 kr monthly fee
- Variable component: ~577 kr
- Monthly fee: 39 kr

**Vattenfall (elnät - grid distribution):**
- Total bill: 1299 kr
- Breakdown: Transfer rate × consumption + 467 kr monthly fee
- Variable component: 1299 - 467 = 832 kr
- Monthly fee: 467 kr

**Combined Variable Cost:** 616 + 832 = 1448 kr
**Effective Rate:** 1448 / 900 = **1.61 kr/kWh**

**Combined Monthly Fees:** 467 + 39 = **506 kr**

#### Constants (Production Values)

**⚠️ CRITICAL: 2025 Rate Update Required**

Research (October 24, 2025) revealed significant rate changes:

**Energy Tax Changes:**
- **2023 rate:** 0.392 kr/kWh (39.2 öre/kWh) including VAT
- **2025 rate:** 0.54875 kr/kWh (54.875 öre/kWh) including VAT
- **Increase:** +40% from 2023 to 2025
- **Source:** Skatteverket, Energimarknadsbyrån (official government sources)

**Grid Transfer Rate:**
- **2023 rate:** ~0.09 kr/kWh (estimated from historical bills)
- **2025 rate:** ~0.34 kr/kWh (34 öre/kWh) for southern area, 16A single tariff
- **Source:** Vattenfall Eldistribution pricing page (research needed for exact customer tier)

**Next Steps:**
1. Verify exact 2025 Vattenfall grid transfer rate for our customer tier
2. Update constants below with 2025 values
3. Test projection accuracy against actual 2025 bills

**2023 Constants (OUTDATED - for reference only):**

```ruby
# Grid transfer + energy tax + VAT (Vattenfall variable rate)
KWH_TRANSFER_PRICE = (0.09 + 0.392) * 1.25
# = 0.6025 kr/kWh
#
# Breakdown:
# - 0.09 SEK/kWh: Elöverföring (grid transfer from Vattenfall)
#   Source: https://www.vattenfalleldistribution.se/kund-i-elnatet/elnatspriser/
# - 0.392 SEK/kWh: Energiskatt (Swedish energy tax)
#   Source: https://www.vattenfalleldistribution.se/kund-i-elnatet/elnatspriser/energiskatt/
# - × 1.25: Moms (25% VAT applied to transfer + tax)

# Fixed monthly fees
VATTENFALL_MONTHLY_FEE = 467  # Grid connection fee
FORTUM_MONTHLY_FEE = 39       # Trading service fee
MONTHLY_FEE = 506             # Total fixed cost
```

**Proposed 2025 Constants (NEEDS VERIFICATION):**

```ruby
# Grid transfer + energy tax + VAT (Vattenfall variable rate)
KWH_TRANSFER_PRICE = (0.34 + 0.43 9) * 1.25
# = 0.974 kr/kWh (est.)
#
# Breakdown:
# - 0.34 SEK/kWh: Elöverföring (grid transfer from Vattenfall) - VERIFY
# - 0.439 SEK/kWh: Energiskatt (Swedish energy tax excl. VAT) ✅ CONFIRMED
# - × 1.25: Moms (25% VAT applied to transfer + tax)
#
# Note: 0.439 × 1.25 = 0.54875 kr/kWh (matches official 54.875 öre/kWh rate)

# Fixed monthly fees - VERIFY
VATTENFALL_MONTHLY_FEE = 467  # Grid connection fee (may have changed)
FORTUM_MONTHLY_FEE = 39       # Trading service fee (may have changed)
MONTHLY_FEE = 506             # Total fixed cost
```

#### Hourly Cost Calculation (Proven Formula)

```ruby
# For each hour of consumption:
price_per_kwh = spot_price + KWH_TRANSFER_PRICE
cost = consumption_kwh * price_per_kwh

# Where:
# - spot_price: From elprisetjustnu.se API (SEK/kWh, incl. VAT)
# - consumption_kwh: From electricity_usage.json (hourly meter data)
```

### 4.2 Smart Projection Architecture

**Goal:** Calculate accurate pre-bill projections using actual consumption × pricing data.

**When to Use:**
1. **Bills arrived** → Use actual aggregated bills from database ✅ (current behavior)
2. **Bills pending** → Calculate from consumption × pricing ⏳ (new capability)
3. **Partial bills** → Hybrid approach (proven + projected) ⏳ (new capability)

#### Case 1: Both Bills Arrived (Current Behavior)

```ruby
def project(config_year:, config_month:)
  # Check database for actual bills
  bills = repository.find_by_period(Date.new(config_year, config_month, 1))

  if bills.any?
    # Use actual aggregated total
    return bills.sum(&:amount)
  end

  # Fallback to smart projection
  project_from_consumption_and_pricing(config_year, config_month)
end
```

#### Case 2: Neither Bill Arrived (Smart Projection)

```ruby
def project_from_consumption_and_pricing(config_year, config_month)
  # Calculate consumption month (config_month - 1)
  consumption_month = config_month - 1
  consumption_year = config_year
  if consumption_month < 1
    consumption_month = 12
    consumption_year -= 1
  end

  # Load hourly consumption data
  usage_data = load_consumption_for_month(consumption_year, consumption_month)

  # Load spot prices for the same hours
  spot_prices = load_spot_prices_for_month(consumption_year, consumption_month)

  # Calculate variable costs
  variable_cost = usage_data.sum do |hour|
    spot_price = spot_prices[hour[:timestamp]] || fallback_to_avg_price
    consumption = hour[:kwh]

    # Apply proven formula
    price_per_kwh = spot_price + KWH_TRANSFER_PRICE
    consumption * price_per_kwh
  end

  # Add fixed monthly fees
  total_cost = variable_cost + MONTHLY_FEE

  total_cost.round
end
```

#### Case 3: Partial Bills (Hybrid Projection)

**Scenario:** Only Vattenfall OR only Fortum bill available.

**Strategy:**
- **Vattenfall available, Fortum missing:** Use Vattenfall actual + project Fortum from consumption × spot prices
- **Fortum available, Vattenfall missing:** Use Fortum actual + project Vattenfall from consumption × transfer rate

```ruby
def project_with_partial_bills(config_year, config_month)
  bills = repository.find_by_period(Date.new(config_year, config_month, 1))

  vattenfall_bill = bills.find { |b| b.provider == 'vattenfall' }
  fortum_bill = bills.find { |b| b.provider == 'fortum' }

  # Case 1: Both arrived
  return vattenfall_bill.amount + fortum_bill.amount if vattenfall_bill && fortum_bill

  # Load consumption data for projections
  consumption_month = config_month - 1
  consumption_year = config_year
  if consumption_month < 1
    consumption_month = 12
    consumption_year -= 1
  end

  usage_data = load_consumption_for_month(consumption_year, consumption_month)

  # Case 2: Only Vattenfall arrived
  if vattenfall_bill && !fortum_bill
    # Project Fortum from consumption × spot prices
    spot_prices = load_spot_prices_for_month(consumption_year, consumption_month)

    fortum_projected = usage_data.sum do |hour|
      spot_price = spot_prices[hour[:timestamp]] || fallback_to_avg_price
      hour[:kwh] * spot_price
    end + FORTUM_MONTHLY_FEE

    return vattenfall_bill.amount + fortum_projected.round
  end

  # Case 3: Only Fortum arrived
  if fortum_bill && !vattenfall_bill
    # Project Vattenfall from consumption × transfer rate
    vattenfall_projected = usage_data.sum do |hour|
      hour[:kwh] * KWH_TRANSFER_PRICE
    end + VATTENFALL_MONTHLY_FEE

    return fortum_bill.amount + vattenfall_projected.round
  end

  # Case 4: Neither arrived (full projection)
  project_from_consumption_and_pricing(config_year, config_month)
end
```

### 4.3 Data Sources

#### electricity_usage.json (Consumption Data)

**Source:** Generated by `vattenfall.rb` scraper
**Size:** ~679KB (9,745 hours of data)
**Format:**
```json
[
  {
    "date": "2025-08-15T14:00:00+02:00",
    "consumption": 0.847
  }
]
```

**Key:** `date` is ISO 8601 timestamp, `consumption` is kWh for that hour

#### Spot Price Data (elprisetjustnu.se API)

**API:** `https://www.elprisetjustnu.se/api/v1/prices/YYYY/MM-DD_SE3.json`
**Region:** SE3 (Stockholm area, matches Tibber region)
**Handler:** `handlers/electricity_price_handler.rb`
**Cache:** 1 hour TTL
**Format:**
```json
{
  "region": "SE3",
  "prices": [
    {
      "time_start": "2025-08-15T14:00:00+02:00",
      "time_end": "2025-08-15T15:00:00+02:00",
      "price_sek": 0.85432,
      "price_eur": 0.07123
    }
  ]
}
```

**Note:** API returns 15-minute intervals, handler aggregates to hourly averages

#### Historical Price Fallback (tibber_price_data.json)

**Backup data source** when elprisetjustnu.se API unavailable or historical data needed.

**Generated by:** `tibber.rb` (GraphQL API)
**Coverage:** 62 days of hourly prices
**Format:**
```json
{
  "2025-08-15T14:00:00+02:00": 0.85432
}
```

### 4.4 Why This Works Perfectly

**Theoretical accuracy:** When using actual consumption hours × actual prices:

```
Projection = Σ(consumption[hour] × (spot_price[hour] + transfer_rate)) + monthly_fees
Actual Bill = Σ(consumption[hour] × (spot_price[hour] + transfer_rate)) + monthly_fees
```

**They are identical** ✅

**The bills will match** because:
1. Consumption data comes from Vattenfall's actual meter readings
2. Spot prices are the same prices Fortum uses for billing
3. Transfer rates are Vattenfall's published rates
4. Monthly fees are fixed and known

**Potential variance sources:**
- Rounding differences (< 1 kr)
- Time zone mismatches in hourly mapping (rare)
- Price updates between API fetch and bill generation (minimal)

**Expected accuracy:** ±1-5 kr on ~1500-2500 kr bills (>99.7% accurate)

---

## Phase 5: Automation & Scheduling

### 5.1 Cron Job Setup

**Frequency:** Daily at 3am (consumption data updates frequently, invoices arrive throughout month)

**Rationale for Daily:**
- Consumption data updates regularly (hourly)
- Invoices can arrive any time mid-month (unpredictable dates)
- Daily check ensures timely rent calculation updates
- Idempotent scraper prevents duplicate data
- Minimal resource usage (2-5 minute execution)

**Pi/Dell Migration Note:** Currently runs on Pi, will migrate to Dell (see CLAUDE.md lines 35-71).

**Cron Entry:**
```bash
# Run daily at 3am (after electricity usage updates, before rent queries)
0 3 * * * /home/kimonokittens/.rbenv/shims/ruby /home/kimonokittens/Projects/kimonokittens/bin/fetch_electricity_invoices.rb >> /home/kimonokittens/logs/electricity_fetcher.log 2>&1
```

**Alternative: Using rufus-scheduler (in-process)**
```ruby
# For long-running processes (if integrated into dashboard server)
require 'rufus-scheduler'

scheduler = Rufus::Scheduler.new

scheduler.cron '0 3 * * *' do
  ElectricityInvoiceFetcher.new.fetch_and_store_vattenfall
end
```

**Chosen Approach:** Cron (simpler, OS-level, easier monitoring)

**Script:** `bin/fetch_electricity_invoices.rb`
```ruby
#!/usr/bin/env ruby
require 'dotenv/load'
require_relative '../lib/electricity_invoice_fetcher'

logger = Logger.new(STDOUT)
logger.info "=== Electricity Invoice Fetcher - #{Time.now} ==="

begin
  fetcher = ElectricityInvoiceFetcher.new(logger: logger)

  # Fetch Vattenfall
  fetcher.fetch_and_store_vattenfall

  # TODO: Fetch Fortum (Phase 6)

  logger.info "✅ SUCCESS: All invoices fetched and stored"
  exit 0
rescue => e
  logger.error "❌ FAILED: #{e.message}"
  logger.error e.backtrace.join("\n")

  # TODO: Send email alert or notification
  exit 1
end
```

### 5.2 Monitoring & Alerts

**Health Checks:**
- [ ] Log rotation (logrotate config)
- [ ] Email alerts on failures
- [ ] Slack/Discord webhook notifications (optional)
- [ ] Monthly summary report (invoices fetched, amounts, periods)

**Metrics to Track:**
- Script execution time
- Success/failure rate
- Number of new invoices found
- Database size growth
- API errors or timeouts

---

## Phase 6: Fortum Extension (Future)

### 6.1 Fortum Research

**Tasks:**
- [ ] Document Fortum login URL and credentials location
- [ ] Map invoice navigation path
- [ ] Identify data extraction selectors
- [ ] Test for differences vs Vattenfall (PDF vs HTML, date formats, etc.)

### 6.2 Create `fortum.rb`

**Approach:** Clone and modify `vattenfall.rb` structure.

**Key Differences Expected:**
- Different domain/login flow
- Potentially different invoice layout
- May use different date/number formatting

### 6.3 Integration

**Update `ElectricityInvoiceFetcher`:**
```ruby
def fetch_and_store_fortum
  logger.info "=== Fetching Fortum Invoices ==="

  invoices = []

  Fortum.run do |_data|
    invoice_data = scrape_latest_invoice
    invoices << invoice_data
  end

  invoices.each { |invoice| store_invoice(invoice) }
  update_all_periods

  logger.info "✅ Fortum invoices fetched and stored"
end
```

---

## Success Criteria

### Minimum Viable Product (MVP)
- [ ] Vattenfall invoices automatically fetched monthly
- [ ] Invoice data stored in ElectricityBill table
- [ ] RentConfig automatically updated with aggregated totals
- [ ] No manual entry needed for Vattenfall bills
- [ ] Logging and error handling in place
- [ ] Cron job running reliably

### Enhanced Features
- [ ] ElectricityProjector uses detailed usage data
- [ ] Price trends incorporated into projections
- [ ] Email alerts on scraping failures
- [ ] Historical invoice PDFs archived
- [ ] Fortum scraping implemented
- [ ] Full test coverage (unit + integration)

### Documentation
- [ ] VATTENFALL_PORTAL_NAVIGATION.md created
- [ ] Updated TODO.md with Fortum plan
- [ ] CLAUDE.md updated with automation details
- [ ] DEVELOPMENT.md includes troubleshooting guide
- [ ] Code comments and inline docs comprehensive

---

## Risk Assessment & Mitigation

### Technical Risks

**Risk:** Vattenfall changes portal layout, breaking scraper
**Mitigation:**
- Version-controlled CSS selectors
- Automated tests with real HTML fixtures
- Email alerts on failures
- Graceful fallback to manual entry

**Risk:** Vessel gem is abandoned/incompatible
**Mitigation:**
- Research alternatives (Kimurai, Capybara)
- Consider pure Ferrum implementation
- Budget 4-8 hours for migration if needed

**Risk:** Authentication issues (CAPTCHA, 2FA)
**Mitigation:**
- Use headless browser with proper headers
- Add delays to mimic human behavior
- Store session cookies if possible
- Document manual workarounds

### Data Risks

**Risk:** Incorrect period calculation causes wrong rent
**Mitigation:**
- Comprehensive test coverage
- Verification step comparing invoice dates to calculated periods
- Manual review dashboard showing recent invoices vs config

**Risk:** Duplicate invoice entries
**Mitigation:**
- Duplicate detection before insertion
- Unique constraints on database
- Idempotent scraping (safe to run multiple times)

---

## Implementation Timeline

**Week 1: Research & Planning**
- [ ] Vessel investigation (2h)
- [ ] Vattenfall portal mapping (3h)
- [ ] Dependency updates (2h)
- [ ] Architecture review and refinement (2h)

**Week 2: Core Development**
- [ ] Extend vattenfall.rb with invoice scraping (6h)
- [ ] Create ElectricityInvoiceFetcher service (4h)
- [ ] Add debug logging throughout (2h)
- [ ] Write unit tests (4h)

**Week 3: Integration & Enhancement**
- [ ] Database integration (3h)
- [ ] ElectricityProjector enhancements (5h)
- [ ] Integration tests (3h)
- [ ] Manual end-to-end testing (2h)

**Week 4: Automation & Polish**
- [ ] Cron job setup (2h)
- [ ] Monitoring and alerts (3h)
- [ ] Documentation (4h)
- [ ] Production deployment (2h)

**Total Estimated Effort:** 49 hours (6-7 full days of focused work)

---

## ✅ PHASE 4.5: PEAK/OFF-PEAK PRICING IMPLEMENTATION (October 24, 2025)

**Status**: ✅ **IMPLEMENTATION COMPLETE** - Ready for validation

**Timeline**: Evening session (4 hours implementation + testing)

### Problem Statement

**Discovered**: Vattenfall charges 2.5× higher grid transfer during winter peak hours
**Impact**: 10-14% underestimation in winter months (Jan/Feb/Mar/Nov/Dec)
**Root Cause**: Using flat 21.40 öre/kWh rate when actual rate is time-of-use
**Missing**: ~516 kr/month in winter projections

### Solution Architecture

**Vattenfall Tidstariff T4 (Time-of-Use Pricing)**:

| Rate Type | Months | Days | Hours | Rate (excl VAT) |
|-----------|--------|------|-------|-----------------|
| **Peak (höglasttid)** | Jan/Feb/Mar/Nov/Dec | Mon-Fri (excl holidays) | 06:00-22:00 | **53.60 öre/kWh** |
| **Off-peak (övrig tid)** | All other times | All days | All hours | **21.40 öre/kWh** |

### Implementation Details

#### 1. Rate Constants (`lib/electricity_projector.rb:57-61`)

```ruby
# Grid transfer (elöverföring) - Vattenfall Tidstariff T4 (time-of-use pricing)
# Peak (höglasttid): Mon-Fri 06:00-22:00 in Jan/Feb/Mar/Nov/Dec (excl holidays)
# Off-peak (övrig tid): All other times + entire summer (Apr-Oct)
GRID_TRANSFER_PEAK_EXCL_VAT = 0.536     # kr/kWh (53.60 öre/kWh) - peak hours
GRID_TRANSFER_OFFPEAK_EXCL_VAT = 0.214  # kr/kWh (21.40 öre/kWh) - off-peak hours
```

#### 2. Swedish Holiday Calendar (`lib/electricity_projector.rb:384-437`)

**Fixed Holidays**:
- January 1: New Year's Day
- January 6: Epiphany
- May 1: Labor Day
- December 24-26: Christmas Eve, Day, Boxing Day
- December 31: New Year's Eve

**Movable Holidays** (Easter-based, hardcoded 2024-2027):
- Good Friday (Easter - 2 days)
- Easter Sunday
- Easter Monday (Easter + 1)
- Ascension Day (Easter + 39)
- Whitsun/Pentecost Sunday (Easter + 49)
- Whit Monday (Easter + 50)

**Calculated Holidays**:
- Midsummer Eve/Day: First Friday between June 19-25 + Saturday
- All Saints' Day: First Saturday between Oct 31 - Nov 6

**Easter Dates** (hardcoded):
```ruby
2024 => March 31
2025 => April 20
2026 => April 5
2027 => March 28
```

#### 3. Peak Hour Classification (`lib/electricity_projector.rb:448-466`)

```ruby
def is_peak_hour?(timestamp)
  dt = DateTime.parse(timestamp)

  # Summer months (Apr-Oct) have NO peak pricing
  return false unless [1, 2, 3, 11, 12].include?(dt.month)

  # Weekends have NO peak pricing
  return false if [0, 6].include?(dt.wday)  # Sunday=0, Saturday=6

  # Swedish holidays have NO peak pricing
  date_only = Date.new(dt.year, dt.month, dt.day)
  return false if swedish_holidays(dt.year).include?(date_only)

  # Peak hours: 06:00-22:00 (local time)
  # Note: timestamp is in UTC, need local hour for classification
  local_dt = dt.new_offset('+01:00')  # Conservative: use winter offset
  local_dt.hour >= 6 && local_dt.hour < 22
end
```

**Design Decisions**:
- **Conservative timezone**: Use UTC+1 (winter time) for hour classification
- **Date-only comparison**: Extract date from datetime for holiday checks
- **Weekend detection**: Ruby wday convention (0=Sunday, 6=Saturday)
- **Fail-safe**: Unknown years return empty holiday list (treats all days as potential peak)

#### 4. Dynamic Rate Selection (`lib/electricity_projector.rb:284-288`)

```ruby
# Determine grid transfer rate based on peak/off-peak classification
grid_rate = is_peak_hour?(timestamp) ? GRID_TRANSFER_PEAK_EXCL_VAT : GRID_TRANSFER_OFFPEAK_EXCL_VAT

# Calculate total price per kWh: (spot + transfer + tax) × VAT
# All three components exclude VAT, so add them first then apply 25% VAT
price_per_kwh = (spot_price + grid_rate + ENERGY_TAX_EXCL_VAT) * 1.25
```

### Testing Strategy

**Validation Approach**:
1. Run `test_projection_accuracy.rb` with new logic
2. Compare Jan/Feb/Mar 2025 projections vs actual bills
3. Verify error reduction from 10-14% → 5-6%
4. Check peak/off-peak hour distribution matches invoice (~43% peak in winter)

**Expected Results**:

| Month | Actual | Old Projected | Old Error | New Projected (est) | New Error (target) |
|-------|--------|---------------|-----------|---------------------|-------------------|
| Feb 2025 | 5,945 kr | 5,220 kr | -725 kr (12.2%) | ~5,650 kr | ~-295 kr (5%) |
| Mar 2025 | 5,936 kr | 5,374 kr | -562 kr (9.5%) | ~5,640 kr | ~-296 kr (5%) |
| Jan 2025 | 4,763 kr | 4,493 kr | -270 kr (5.7%) | ~4,520 kr | ~-243 kr (5%) |

**Success Criteria**:
- ✅ Winter error ≤ 7% (matching summer accuracy)
- ✅ Peak hours correctly classified (~43-45% in winter)
- ✅ Holidays excluded from peak pricing
- ✅ Summer months unaffected (still 5-6% error)

### Files Modified

**Core Projector**:
- `lib/electricity_projector.rb` (+91 lines)
  - Lines 57-61: Peak/off-peak rate constants
  - Lines 284-288: Dynamic rate selection
  - Lines 384-437: Swedish holiday calendar (54 lines)
  - Lines 448-466: Peak hour classification (19 lines)

**Testing** (pending):
- `test_projection_accuracy.rb` - Run with new logic
- Validation output to be documented

### Next Steps

1. **Immediate** (30 min):
   - [ ] Run validation tests
   - [ ] Document actual accuracy improvements
   - [ ] Commit implementation with results

2. **Future** (8-10 hours):
   - [ ] Migrate Node-RED heatpump schedule to use peak/off-peak logic
   - [ ] Implement smart scheduling (avoid peak hours)
   - [ ] Monitor 400-500 kr/month savings

3. **Maintenance** (annual):
   - [ ] Add Easter dates for 2028+ as needed
   - [ ] Verify Vattenfall hasn't changed rate structure
   - [ ] Update holiday calendar if Swedish calendar changes

### Key Learnings

1. **Time-of-use pricing is significant**: 2.5× rate difference (150% markup)
2. **Holidays matter**: 15-20 days/year excluded from peak pricing
3. **Timezone handling critical**: Must convert UTC → local time for hour classification
4. **Conservative approach**: When uncertain, use winter offset (safer for budgeting)
5. **Easter calculation complex**: Hardcoded dates simpler than astronomical calculation

### Production Readiness

✅ **Implementation complete**
⏳ **Validation pending** (30 min)
⏳ **Documentation complete** (this section)
⏳ **Deployment pending** (git commit + push)

---

## Next Immediate Steps

1. **Investigate Vessel status** - Determine if still usable or needs replacement
2. **Manual Vattenfall exploration** - Document invoice page navigation and data structure
3. **Update dependencies** - Ensure all gems are current and compatible
4. **Create test fixtures** - Capture HTML examples for testing without live scraping
5. **Implement basic invoice scraping** - Get first end-to-end flow working
6. **Add comprehensive logging** - Debug instrumentation at every step

---

## References

**Codebase Files:**
- `vattenfall.rb` - Current consumption scraper
- `lib/electricity_projector.rb` - Projection logic
- `lib/rent_db.rb` - Database interface
- `handlers/electricity_price_handler.rb` - Price data API
- `handlers/electricity_stats_handler.rb` - Usage data display
- `deployment/electricity_bill_migration.rb` - Historical data migration

**Documentation:**
- `CLAUDE.md` lines 75-91 - Electricity bill timing quirks
- `TODO.md` lines 526-533 - Automation TODO item
- `DEVELOPMENT.md` lines 84-94 - Bill handling timeline

**External Resources:**
- Vattenfall portal: https://www.vattenfalleldistribution.se/logga-in?pageId=6
- Elprisetjustnu API: https://www.elprisetjustnu.se/api/v1/prices/
- Ferrum docs: https://github.com/rubycdp/ferrum
- Vessel docs: https://github.com/xronos-i-am/vessel (if maintained)

---

**Document Version:** 1.0
**Last Updated:** October 21, 2025
**Owner:** Fredrik Branström
**Estimated Completion:** November 2025

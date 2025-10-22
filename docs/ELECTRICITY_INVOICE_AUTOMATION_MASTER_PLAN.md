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

## Phase 4: ElectricityProjector Enhancement

### 4.1 Integration with Usage Data

**Current Limitation:** Projector only uses aggregated monthly totals, ignoring detailed hourly consumption patterns.

**Enhancement Strategy:**

```ruby
class ElectricityProjector
  # Add usage data integration
  def project_with_usage_analysis(config_year:, config_month:)
    basic_projection = project(config_year: config_year, config_month: config_month)

    # Load usage data
    usage_data = load_usage_data
    return basic_projection if usage_data.nil?

    # Analyze recent trends
    recent_trend = analyze_recent_consumption(usage_data)

    # Adjust projection based on trend
    adjusted = apply_consumption_trend(basic_projection, recent_trend)

    logger.info "Enhanced projection: #{basic_projection} kr → #{adjusted} kr (trend: #{recent_trend[:direction]})"
    adjusted
  end

  private

  def load_usage_data
    return nil unless File.exist?('electricity_usage.json')
    Oj.load_file('electricity_usage.json')
  rescue => e
    logger.warn "Could not load usage data: #{e.message}"
    nil
  end

  def analyze_recent_consumption(usage_data)
    # Compare last 30 days vs previous 30 days
    now = Date.today
    last_30 = usage_data.select { |h| Date.parse(h['date']) >= now - 30 }
    prev_30 = usage_data.select { |h| Date.parse(h['date']) >= now - 60 && Date.parse(h['date']) < now - 30 }

    last_total = last_30.sum { |h| h['consumption'] || 0 }
    prev_total = prev_30.sum { |h| h['consumption'] || 0 }

    change_pct = ((last_total - prev_total) / prev_total.to_f) * 100

    {
      last_30_kwh: last_total,
      prev_30_kwh: prev_total,
      change_pct: change_pct,
      direction: change_pct > 5 ? :increasing : (change_pct < -5 ? :decreasing : :stable)
    }
  end

  def apply_consumption_trend(baseline, trend)
    # Conservative adjustment: max ±10%
    adjustment_factor = [[-0.10, trend[:change_pct] / 100].max, 0.10].min
    (baseline * (1 + adjustment_factor)).round
  end
end
```

### 4.2 Price Data Integration

**Goal:** Use actual hourly prices from elprisetjustnu.se to refine projections.

```ruby
class ElectricityProjector
  def project_with_price_forecast(config_year:, config_month:)
    # Load historical price data
    price_data = load_price_data

    # Calculate price trend (last 30 days vs historical average)
    price_trend = analyze_price_trend(price_data)

    # Adjust projection
    baseline = project(config_year: config_year, config_month: config_month)
    adjusted = apply_price_trend(baseline, price_trend)

    logger.info "Price-adjusted projection: #{baseline} kr → #{adjusted} kr"
    adjusted
  end

  private

  def load_price_data
    # Fetch from elprisetjustnu.se or use cached data
    # See handlers/electricity_price_handler.rb for API
  end
end
```

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

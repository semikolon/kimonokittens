# Vessel vs Pure Ferrum: Migration Analysis

**Date:** October 21, 2025
**Decision:** Migrate to pure Ferrum (recommended)
**Effort Estimate:** 1-2 hours
**Risk:** Low

---

## Executive Summary

**Vessel is a thin abstraction layer over Ferrum** that provides:
- DSL sugar for scraper configuration (`domain`, `start_urls`)
- Thread pool management for concurrent scraping
- Request scheduling and middleware support

**Current vattenfall.rb integration is MINIMAL:**
- 95% of the code uses direct Ferrum methods
- Only 5% uses Vessel DSL (class definition, run method)
- No advanced Vessel features used (middleware, concurrent requests)

**Recommendation:** Migrate to pure Ferrum. Vessel is unmaintained, adds complexity, and provides little value for our single-page scraping use case.

---

## Vessel Integration Analysis

### What Vessel Provides (from cargo.rb)

```ruby
# Line 75: Vessel just forwards selectors to Ferrum
delegate %i[at_css css at_xpath xpath] => :page

# DSL methods (lines 22-49)
domain "example.com"          # Just sets settings[:domain]
start_urls "http://..."       # Just sets settings[:start_urls]
ferrum(browser_options: {})   # Just sets settings[:ferrum]
```

**Key insight:** `at_css`, `css`, `at_xpath`, `xpath` are **forwarded directly to Ferrum's page object**. Vessel is just a thin wrapper.

### Vessel Usage in vattenfall.rb

**Line 23:** `class Vattenfall < Vessel::Cargo`
- **Purpose:** Inherit Vessel's DSL and run mechanism
- **Replacement:** Plain Ruby class with Ferrum browser initialization

**Line 24:** `domain "vattenfalleldistribution.se"`
- **Purpose:** Sets domain for request scheduling (unused in our case)
- **Replacement:** None needed (we only scrape one domain manually)

**Line 25:** `start_urls "https://www.vattenfalleldistribution.se/logga-in?pageId=6"`
- **Purpose:** Tells Vessel where to start scraping
- **Replacement:** Direct `browser.goto(url)` call

**Line 28-38:** `driver(:ferrum, browser_options: {...})`
- **⚠️ ISSUE:** This syntax doesn't exist in Vessel 0.2.0!
- Vessel uses `ferrum(...)` not `driver(:ferrum, ...)`
- This suggests the script may be broken or using a custom Vessel version

**Line 66-152:** `def parse`
- **Purpose:** Vessel callback method
- **Usage:** 100% direct Ferrum methods (`page.network.wait_for_idle`, `at_css`, `btn.click`)
- **Replacement:** Regular method called after browser.goto

**Line 160:** `Vattenfall.run do |fresh_data|`
- **Purpose:** Vessel's engine starts browser, navigates to start_urls, calls parse
- **Replacement:** Direct browser initialization and method calls

### Direct Ferrum Methods Used (No Change Needed)

**These stay exactly the same:**
- `page.network.wait_for_idle(timeout: 120)` (line 80, 97, 116)
- `at_css("button[variant='outline-secondary']")` (line 85)
- `at_css('form')`, `at_css('input[id=customerNumber]')` (lines 90-94)
- `customer_number_field.focus`, `.type(ID, :enter)` (lines 92-96)
- `page.go_to(url)` (line 114)
- `page.headers.set({...})` (lines 100-103)
- `page.at_css('pre')&.text` (line 146)
- `page.browser.quit` (line 60)

**Percentage breakdown:**
- Vessel-specific code: ~10 lines (6%)
- Direct Ferrum code: ~140 lines (94%)

---

## Migration Plan

### Before (Vessel)

```ruby
require 'vessel'

class Vattenfall < Vessel::Cargo
  domain "vattenfalleldistribution.se"
  start_urls "https://www.vattenfalleldistribution.se/logga-in?pageId=6"

  driver(:ferrum,
    browser_options: {
      'no-default-browser-check': true,
      'disable-extensions': true
    },
    timeout: 10,
    process_timeout: 120
  )

  def parse
    page.network.wait_for_idle(timeout: 120)
    btn = at_css("button[variant='outline-secondary']")
    btn.click
    # ... rest of scraping logic
  end
end

Vattenfall.run do |fresh_data|
  # Process data
end
```

### After (Pure Ferrum)

```ruby
require 'ferrum'

class VattenfallScraper
  BROWSER_OPTIONS = {
    'no-default-browser-check': true,
    'disable-extensions': true,
    'disable-translate': true,
    'mute-audio': true,
    'disable-sync': true
  }

  attr_reader :browser, :page, :logger

  def initialize(logger: Logger.new(STDOUT))
    @logger = logger
    @browser = Ferrum::Browser.new(
      browser_options: BROWSER_OPTIONS,
      timeout: 10,
      process_timeout: 120,
      headless: true
    )
    @page = browser.create_page
  end

  def run(&block)
    logger.info "Starting Vattenfall scraper..."

    begin
      scrape_consumption
      scrape_invoices  # New functionality

      yield results if block_given?
    ensure
      cleanup
    end
  end

  def scrape_consumption
    logger.info "Navigating to login page..."
    page.go_to('https://www.vattenfalleldistribution.se/logga-in?pageId=6')
    page.network.wait_for_idle(timeout: 120)

    logger.info "Clicking login button..."
    btn = page.at_css("button[variant='outline-secondary']")
    btn.click

    # Rest of scraping logic - EXACTLY THE SAME
    logger.info "Logging in..."
    f = page.at_css('form')
    customer_number_field = f.at_css('input[id=customerNumber]')
    customer_number_field.focus
    customer_number_field.type(ID, :enter)

    # ... continue with existing logic
  end

  def scrape_invoices
    logger.info "Navigating to invoice page..."
    # New invoice scraping logic here
  end

  private

  def cleanup
    logger.info "Closing browser..."
    browser.quit
  rescue => e
    logger.warn "Error during cleanup: #{e.message}"
  end
end

# Usage
scraper = VattenfallScraper.new
scraper.run do |data|
  stats = data['consumption'].map(&:compact)
  Oj.to_file('electricity_usage.json', stats)
end
```

---

## Migration Steps

### Step 1: Remove Vessel Dependency

**Update Gemfile:**
```ruby
# Remove or comment out (if Vessel exists)
# gem 'vessel'

# Keep Ferrum (already in Gemfile)
gem 'ferrum'
```

### Step 2: Refactor Class Structure

**Changes:**
1. Remove `< Vessel::Cargo` inheritance
2. Remove `domain`, `start_urls` DSL calls
3. Remove `driver(:ferrum, ...)` (probably broken anyway)
4. Add `initialize` method with Ferrum browser setup
5. Rename `parse` → `scrape_consumption` (more descriptive)
6. Add `run` method wrapper
7. Add proper cleanup in `ensure` block

### Step 3: Update Method Calls

**No changes needed!** All Ferrum methods stay identical:
- `page.at_css(...)` → `page.at_css(...)`
- `page.network.wait_for_idle` → `page.network.wait_for_idle`
- `page.go_to(...)` → `page.go_to(...)`

### Step 4: Update Usage

**Before:**
```ruby
Vattenfall.run do |fresh_data|
  # ...
end
```

**After:**
```ruby
scraper = VattenfallScraper.new
scraper.run do |data|
  # ...
end
```

### Step 5: Add Enhanced Logging

**Leverage removal of Vessel to add better debugging:**
```ruby
def initialize(logger: Logger.new(STDOUT), debug: ENV['DEBUG'])
  @logger = logger
  @logger.level = debug ? Logger::DEBUG : Logger::INFO

  # Add custom formatter for timestamps
  @logger.formatter = proc do |severity, datetime, progname, msg|
    "[#{datetime.strftime('%Y-%m-%d %H:%M:%S')}] #{severity}: #{msg}\n"
  end

  # Initialize Ferrum with screenshot support
  @browser = Ferrum::Browser.new(
    browser_options: BROWSER_OPTIONS,
    timeout: 10,
    process_timeout: 120,
    headless: !debug,  # Show browser when debugging
    save_path: 'tmp/screenshots'  # Save screenshots on errors
  )
end

def wait_for_element(selector:, type: :css, timeout: 10)
  logger.debug "Waiting for element: #{selector}"
  start_time = Time.now

  max_attempts = timeout
  attempts = 0

  while attempts < max_attempts
    element = type == :css ? page.at_css(selector) : page.at_xpath(selector)
    if element
      elapsed = Time.now - start_time
      logger.debug "Element found after #{elapsed.round(2)}s"
      return element
    end

    sleep 1
    attempts += 1
  end

  # Take screenshot on failure
  page.screenshot(path: "tmp/screenshots/error_#{Time.now.to_i}.png")
  raise "Element '#{selector}' not found after #{max_attempts} attempts"
end
```

---

## Benefits of Migration

### 1. **Simplicity**
- One less dependency to manage
- Direct control over browser lifecycle
- Clearer code flow (no magic callbacks)

### 2. **Maintainability**
- Vessel is unmaintained (last commit: likely years ago)
- Ferrum is actively maintained by rubycdp org
- Future Ferrum upgrades won't break our code

### 3. **Debuggability**
- Direct browser control makes debugging easier
- Can add custom logging at every step
- Can conditionally show browser window (`headless: false`)
- Screenshot capture on errors

### 4. **Extensibility**
- Easy to add invoice scraping methods
- Can reuse scraper instance for multiple operations
- Can add retries, caching, etc. without Vessel constraints

### 5. **Performance**
- No Vessel overhead (thread pool, request scheduler we don't use)
- Direct browser initialization
- Faster startup (no Engine.run abstraction)

---

## Risks & Mitigations

### Risk: Breaking Existing Consumption Scraping

**Mitigation:**
- Keep existing Ferrum method calls identical
- Test against staging environment first
- Create comprehensive test fixtures
- Maintain parallel vattenfall_legacy.rb until verified

### Risk: Unknown Vessel Features We Depend On

**Analysis:** We don't use any advanced Vessel features:
- ❌ No middleware
- ❌ No concurrent requests (single page scrape)
- ❌ No request scheduling
- ✅ Only use basic page navigation and selectors (all Ferrum)

**Mitigation:**
- Thorough code review confirms minimal Vessel usage
- Test script end-to-end after migration
- Keep Vessel gem available for quick rollback if needed

### Risk: `driver(:ferrum, ...)` Syntax May Be Critical

**Analysis:**
- This syntax **doesn't exist in Vessel 0.2.0**
- Cargo.rb shows method is `ferrum(...)` not `driver(:ferrum, ...)`
- Script may already be broken or using custom Vessel version

**Mitigation:**
- Test current script before migration (may not work anyway)
- Document current behavior before changes
- Pure Ferrum approach will fix any syntax issues

---

## Testing Strategy

### 1. Create Test Fixtures

**Capture real HTML from Vattenfall:**
```bash
# Login page
curl 'https://www.vattenfalleldistribution.se/logga-in?pageId=6' > spec/fixtures/vattenfall_login.html

# Invoice page (manual capture after login)
# Save page source from browser after logging in
```

### 2. Unit Tests

```ruby
RSpec.describe VattenfallScraper do
  let(:scraper) { described_class.new }

  describe '#extract_amount' do
    it 'parses Swedish number formatting' do
      element = double(at_css: double(text: '1 632 kr'))
      expect(scraper.send(:extract_amount, element)).to eq(1632)
    end
  end

  describe '#calculate_period' do
    context 'due date at end of month' do
      it 'uses due month as consumption period' do
        period = scraper.send(:calculate_period, Date.new(2025, 9, 30))
        expect(period).to eq(Date.new(2025, 9, 1))
      end
    end
  end
end
```

### 3. Integration Test (with VCR)

```ruby
RSpec.describe VattenfallScraper, :integration do
  it 'fetches consumption data', vcr: true do
    scraper = VattenfallScraper.new

    results = nil
    scraper.run { |data| results = data }

    expect(results).to have_key('consumption')
    expect(results['consumption']).to be_an(Array)
    expect(results['consumption'].first).to have_key('date')
    expect(results['consumption'].first).to have_key('consumption')
  end
end
```

### 4. Manual End-to-End Test

**Checklist:**
- [ ] Script starts without errors
- [ ] Browser opens and navigates to login page
- [ ] Login succeeds (check for post-login page)
- [ ] Consumption data is fetched
- [ ] JSON file is written
- [ ] Browser closes cleanly
- [ ] No zombie Chrome processes left running

---

## Implementation Timeline

### Phase 1: Preparation (30 minutes)
- [ ] Document current vattenfall.rb behavior
- [ ] Test current script (may not work due to driver syntax)
- [ ] Create HTML fixtures from Vattenfall portal
- [ ] Backup current vattenfall.rb → vattenfall_legacy.rb

### Phase 2: Migration (1 hour)
- [ ] Create new VattenfallScraper class
- [ ] Initialize Ferrum browser directly
- [ ] Copy/paste existing Ferrum method calls
- [ ] Add logging and error handling
- [ ] Update Gemfile (remove Vessel if present)

### Phase 3: Testing (30 minutes)
- [ ] Unit tests for data extraction methods
- [ ] Integration test with real login (dev environment)
- [ ] Verify electricity_usage.json output unchanged
- [ ] Check for Chrome zombie processes

### Phase 4: Invoice Extension (separate task)
- [ ] Add scrape_invoices method
- [ ] Navigate to invoice page
- [ ] Extract invoice data
- [ ] Store in ElectricityBill table

**Total Effort:** 2-3 hours for complete migration + testing

---

## Decision

**PROCEED WITH MIGRATION**

**Rationale:**
1. Vessel provides <5% of actual functionality
2. Migration is low-risk (Ferrum methods stay identical)
3. Removes unmaintained dependency
4. Simplifies codebase for future invoice scraping
5. Better debugging and logging capabilities
6. Script may already be broken (invalid driver syntax)

**Next Steps:**
1. Test current vattenfall.rb (document if broken)
2. Create backup (vattenfall_legacy.rb)
3. Implement pure Ferrum version
4. Test consumption scraping works
5. Extend with invoice scraping in same session

---

## Appendix: Vessel 0.2.0 Cargo API

**From `/Projects/brf-auto/vendor/bundle/.../gems/vessel-0.2.0/lib/vessel/cargo.rb`:**

```ruby
# Available DSL methods (lines 22-56)
def domain(name)
def start_urls(*urls)
def delay(value)
def timeout(value)
def headers(value)
def threads(min: MIN_THREADS, max: MAX_THREADS)
def middleware(*classes)
def ferrum(**options)  # NOT driver(:ferrum, ...)
def intercept(&block)

# Delegated to Ferrum page (line 75)
delegate %i[at_css css at_xpath xpath] => :page

# Helper methods (lines 93-103)
def request(**options)
def absolute_url(relative)
def current_url
```

**Vessel abstraction summary:**
- Provides DSL for scraper configuration
- Manages threading and request scheduling
- Forwards all selectors to Ferrum page object
- Handles browser lifecycle through Engine.run

**Our usage:** Only uses inheritance, start_urls, and delegated selectors. No threading, no middleware, no concurrent requests.

**Conclusion:** Vessel is overkill for single-page scraping with sequential navigation.

---

**Document Version:** 1.0
**Author:** Claude (Haiku 4.5) + Fredrik Branström
**Last Updated:** October 21, 2025

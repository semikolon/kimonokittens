#!/usr/bin/env ruby
# frozen_string_literal: true

# Fortum Electricity Invoice Scraper (Pure Ferrum)
#
# Purpose: Automated fetching of electricity invoices from Fortum elhandel portal.
#
# Architecture: Pure Ferrum (browser automation) - cloned from vattenfall.rb
#
# Usage:
#   ruby fortum.rb                        # Fetch and store invoices
#   DEBUG=1 ruby fortum.rb                # Run with debug logging
#   COMPARE_HISTORY=1 ruby fortum.rb      # Compare scraped vs historical/database
#
# Output:
#   - ElectricityBill database records (via ApplyElectricityBill service)
#   - RentConfig updates (aggregated period totals)
#
# Schedule: Run daily at 4am via cron (1 hour after Vattenfall)
#
# Created: October 24, 2025 (cloned from vattenfall.rb)

require 'dotenv/load'
require 'json'
require 'ferrum'
require 'oj'
require 'logger'
require 'date'
require_relative 'lib/persistence'
require_relative 'lib/services/apply_electricity_bill'

# Credentials from environment
ID = ENV['FORTUM_ID']
PW = ENV['FORTUM_PW']

if ID.nil? || ID.empty?
  abort '❌ ERROR: FORTUM_ID environment variable required'
elsif PW.nil? || PW.empty?
  abort '❌ ERROR: FORTUM_PW environment variable required'
end

class FortumScraper
  BROWSER_OPTIONS = {
    'no-default-browser-check': true,
    'disable-extensions': true,
    'disable-translate': true,
    'mute-audio': true,
    'disable-sync': true
  }.freeze

  TIMEOUT = 10
  PROCESS_TIMEOUT = 120
  LOGIN_URL = 'https://sso.fortum.com/am/XUI/?realm=/alpha&locale=sv&authIndexType=service&authIndexValue=SeB2COGWLogin#/'
  INVOICES_URL = 'https://www.fortum.com/se/el/inloggad/fakturor'

  attr_reader :browser, :page, :logger

  def initialize(logger: nil, headless: true, debug: ENV['DEBUG'])
    @logger = logger || create_logger(debug)
    @debug = debug

    @logger.info "=" * 80
    @logger.info "Fortum Scraper (Pure Ferrum)"
    @logger.info "Started: #{Time.now.strftime('%Y-%m-%d %H:%M:%S')}"
    @logger.info "Debug mode: #{@debug ? 'ENABLED' : 'disabled'}"
    @logger.info "=" * 80

    initialize_browser(headless: headless)
  end

  def run(&block)
    @logger.info "🚀 Starting scraping session..."

    begin
      # Login first
      perform_login

      # Navigate to invoices and inspect (DEBUG/INSPECT mode only)
      inspect_invoice_page if @debug || ENV['INSPECT_INVOICES']

      # Fetch invoice data (Fortum is invoice-only, no consumption data)
      invoice_data = scrape_invoices unless ENV['SKIP_INVOICES']

      # Results
      results = {
        invoices: invoice_data
      }

      yield results if block_given?

      @logger.info "✅ Scraping completed successfully"

      results
    rescue => e
      @logger.error "❌ Scraping failed: #{e.message}"
      @logger.error e.backtrace.first(10).join("\n")

      # Take screenshot on error if debug mode
      save_error_screenshot if @debug

      raise
    ensure
      cleanup
    end
  end

  def perform_login
    @logger.info ""
    @logger.info "🔐 LOGIN PHASE (Fortum SSO)"
    @logger.info "=" * 40

    # Step 1: Navigate to Fortum SSO login page
    @logger.info "→ Navigating to Fortum SSO login page..."
    page.go_to(LOGIN_URL)
    wait_for_network_idle(timeout: PROCESS_TIMEOUT)

    # Give JavaScript time to render (SSO portals often use client-side rendering)
    sleep 3

    @logger.info "  ✓ SSO login page loaded"
    @logger.info "  Current URL: #{page.current_url}"

    # Save HTML for debugging if needed
    if @debug
      html_path = "tmp/screenshots/login_page_#{Time.now.to_i}.html"
      Dir.mkdir('tmp') unless Dir.exist?('tmp')
      Dir.mkdir('tmp/screenshots') unless Dir.exist?('tmp/screenshots')
      File.write(html_path, page.body)
      @logger.debug "  💾 Login page HTML saved: #{html_path}"
    end

    # Step 2: Enter credentials
    # Fortum SSO typically uses standard input fields (not custom components like Vattenfall)
    @logger.info "→ Entering credentials..."

    begin
      # Try common SSO input patterns
      # Pattern 1: Look for username/email field (common names: username, email, IDToken1)
      username_field = page.at_css('input[name="IDToken1"]') ||
                       page.at_css('input[type="text"]') ||
                       page.at_css('input[type="email"]') ||
                       page.at_css('input[name="username"]')

      raise "Username field not found" unless username_field

      username_field.focus
      username_field.type(ID)
      @logger.info "  ✓ Email/username entered"

      # Pattern 2: Look for password field (common names: password, IDToken2)
      password_field = page.at_css('input[name="IDToken2"]') ||
                       page.at_css('input[type="password"]')

      raise "Password field not found" unless password_field

      password_field.focus
      password_field.type(PW)
      @logger.info "  ✓ Password entered"

      # Step 3: Submit form
      # Try to find submit button
      @logger.info "→ Submitting login form..."
      submit_btn = page.at_css('button[type="submit"]') ||
                   page.at_css('input[type="submit"]') ||
                   page.css('button').find { |btn| btn.text.match?(/logga in|sign in|fortsätt|continue/i) }

      if submit_btn
        submit_btn.click
        @logger.info "  ✓ Submit button clicked"
      else
        # Fallback: press Enter on password field
        password_field.type(:enter)
        @logger.info "  ✓ Login submitted via Enter key"
      end

    rescue => e
      @logger.error "  ❌ Login field interaction failed: #{e.message}"

      # Take screenshot for debugging
      if @debug
        screenshot_path = "tmp/screenshots/login_error_#{Time.now.to_i}.png"
        Dir.mkdir('tmp') unless Dir.exist?('tmp')
        Dir.mkdir('tmp/screenshots') unless Dir.exist?('tmp/screenshots')
        page.screenshot(path: screenshot_path)
        @logger.info "  📸 Debug screenshot: #{screenshot_path}"
      end

      raise
    end

    # Step 4: Wait for authentication and redirect
    @logger.info "→ Waiting for authentication..."
    wait_for_network_idle(timeout: PROCESS_TIMEOUT)

    # Check if we're redirected (successful login usually changes URL)
    current_url = page.current_url
    @logger.info "  ✓ Authentication complete"
    @logger.info "  Current URL: #{current_url}"

    # Step 5: Handle cookie consent if present
    handle_cookie_consent

    # Verify we're logged in (should NOT still be on SSO login page)
    if current_url.include?('sso.fortum.com')
      @logger.warn "  ⚠️  Still on SSO page - login may have failed"
      @logger.warn "  Check for 2FA requirements or incorrect credentials"
    else
      @logger.info "  ✓ Redirected away from SSO - login likely successful"
    end
  end

  def handle_cookie_consent
    @logger.info "→ Checking for cookie consent dialog..."

    begin
      # Look for "Acceptera alla" (Accept all) button using Ruby filtering
      buttons = page.css('button')
      accept_btn = buttons.find { |btn| btn.text.match?(/acceptera\s+alla/i) }

      if accept_btn
        @logger.info "  → Cookie consent found, accepting..."
        accept_btn.click
        sleep 1  # Brief wait for dialog to dismiss
        @logger.info "  ✓ Cookies accepted"
      else
        @logger.info "  ⊘ No cookie consent dialog found (#{buttons.size} buttons checked)"
      end
    rescue => e
      @logger.warn "  ⚠️  Cookie consent handling failed: #{e.message}"
      # Don't raise - cookie consent is not critical for functionality
    end
  end

  def inspect_invoice_page
    @logger.info ""
    @logger.info "📄 INVOICE INSPECTION PHASE (Fortum)"
    @logger.info "=" * 40

    # Navigate to Fortum invoice page
    @logger.info "→ Navigating to Fortum invoice page..."
    page.go_to(INVOICES_URL)
    wait_for_network_idle(timeout: 30)
    @logger.info "  ✓ Navigated to: #{page.current_url}"

    # Handle cookie consent if present (appears on invoice page)
    handle_cookie_consent

    # Take screenshot for analysis
    screenshot_path = "tmp/screenshots/invoice_page_#{Time.now.to_i}.png"
    Dir.mkdir('tmp') unless Dir.exist?('tmp')
    Dir.mkdir('tmp/screenshots') unless Dir.exist?('tmp/screenshots')
    page.screenshot(path: screenshot_path)
    @logger.info "  📸 Screenshot saved: #{screenshot_path}"

    # Inspect page structure
    @logger.info "→ Inspecting page structure..."

    # Look for tables (common for invoice lists)
    tables = page.css('table')
    @logger.info "  Tables found: #{tables.size}"

    if tables.any?
      @logger.info "  Inspecting first table structure:"
      first_table = tables.first
      headers = first_table.css('th')
      @logger.info "    Column headers: #{headers.map(&:text).join(' | ')}"

      rows = first_table.css('tbody tr')
      @logger.info "    Data rows: #{rows.size}"

      if rows.any?
        @logger.info "    Sample first row cells:"
        rows.first.css('td').each_with_index do |cell, i|
          @logger.info "      Cell #{i}: #{cell.text.strip}"
        end
      end
    end

    # Look for invoice-related elements
    invoice_elements = page.css('[class*="invoice"], [class*="faktura"], [id*="invoice"], [id*="faktura"]')
    @logger.info "  Invoice-related elements: #{invoice_elements.size}"

    if invoice_elements.any?
      @logger.info "  Sample element classes:"
      invoice_elements.first(5).each do |el|
        @logger.info "    - #{el.tag_name}.#{el.attribute('class')} (ID: #{el.attribute('id')})"
      end
    end

    # Look for amount patterns (Swedish currency format: "1 685,69 kr")
    amounts = page.css('*').select { |el| el.text.match?(/\d[\d\s]*[,.]?\d*\s*kr/i) }
    if amounts.any?
      @logger.info "  Found #{amounts.size} potential amount elements"
      @logger.info "  Sample amounts:"
      amounts.first(10).each do |el|
        @logger.info "    - #{el.text.strip}"
      end
    end

    # Look for date patterns
    dates = page.css('*').select { |el| el.text.match?(/\d{1,2}\s+(januari|februari|mars|april|maj|juni|juli|augusti|september|oktober|november|december)/i) }
    if dates.any?
      @logger.info "  Found #{dates.size} potential date elements"
      @logger.info "  Sample dates:"
      dates.first(5).each do |el|
        @logger.info "    - #{el.text.strip}"
      end
    end

    # Save page HTML for offline analysis
    html_path = "tmp/screenshots/invoice_page_#{Time.now.to_i}.html"
    File.write(html_path, page.body)
    @logger.info "  💾 HTML saved: #{html_path}"
  end

  def scrape_invoices
    @logger.info ""
    @logger.info "📄 INVOICE SCRAPING PHASE (Fortum)"
    @logger.info "=" * 40

    # Navigate to Fortum invoice page
    @logger.info "→ Navigating to Fortum invoice page..."
    page.go_to(INVOICES_URL)
    wait_for_network_idle(timeout: 30)
    @logger.info "  ✓ Navigated to: #{page.current_url}"

    # Handle cookie consent if present (appears on invoice page)
    handle_cookie_consent

    # Give page time to load dynamic content
    sleep 2

    # Scroll down to load all invoices (lazy loading)
    @logger.info "→ Scrolling to load all invoices..."
    3.times do
      page.execute('window.scrollTo(0, document.body.scrollHeight)')
      sleep 1
    end

    # Extract invoices using JavaScript evaluation to inspect DOM properly
    @logger.info "→ Inspecting DOM structure with JavaScript..."

    invoices = []

    begin
      # Use JavaScript to find invoice containers in the React/Next.js app
      invoice_data = page.evaluate(<<~JS)
        (() => {
          // Swedish months to search for
          const months = ['januari', 'februari', 'mars', 'april', 'maj', 'juni',
                          'juli', 'augusti', 'september', 'oktober', 'november', 'december'];

          // Find all elements containing month names
          const monthElements = [];

          // Find all elements with exactly 5 children that contain invoice-like data
          const allElements = Array.from(document.querySelectorAll('*')).filter(el => {
            const text = el.innerText || '';
            return el.children.length === 5 &&
                   text.length > 10 &&
                   text.length < 150 &&
                   text.match(/\\d{4}/) && // Contains year
                   text.match(/kr/i) &&      // Contains "kr"
                   text.match(/betald|obetald/i); // Contains status
          });

          allElements.forEach(el => {
            monthElements.push({
              tagName: el.tagName.toLowerCase(),
              text: el.innerText,
              children: el.children.length,
              classList: Array.from(el.classList),
              parentTag: el.parentElement ? el.parentElement.tagName.toLowerCase() : null,
              parentClasses: el.parentElement ? Array.from(el.parentElement.classList) : []
            });
          });

          return monthElements; // Return all matches
        })();
      JS

      @logger.info "  Found #{invoice_data.size} invoice-like elements"

      # Swedish month mapping
      month_map = {
        'januari' => '01', 'februari' => '02', 'mars' => '03', 'april' => '04',
        'maj' => '05', 'juni' => '06', 'juli' => '07', 'augusti' => '08',
        'september' => '09', 'oktober' => '10', 'november' => '11', 'december' => '12'
      }

      # Process invoice elements (use the one with 5 children - that's the invoice row container)
      @logger.debug "  Processing #{invoice_data.size} elements (all have 5 children)" if @debug

      invoice_data.each_with_index do |elem, idx|
        text = elem['text']
        lines = text.split("\n").map(&:strip).reject(&:empty?)

        # Handle two formats:
        # Format 1 (2025): "Januari 2025\nBetald\n1 845,00 kr" (3 lines)
        # Format 2 (2024): "december 2024BetaldVisa PDF1 757,00 krBetald" (1 line, concatenated)

        month_name = nil
        year = nil
        status = nil
        amount_text = nil

        if lines.size >= 3
          # Format 1: Proper newlines (2025 invoices)
          month_year_match = lines[0].match(/(\w+)\s+(\d{4})/i)
          if month_year_match
            month_name = month_year_match[1].downcase
            year = month_year_match[2].to_i
            # Check "Obetald" first since /betald/i matches BOTH "Betald" and "Obetald"
            status = lines[1].match?(/obetald/i) ? 'Obetald' : 'Betald'
            amount_text = lines[2]
          end
        elsif lines.size == 1
          # Format 2: Concatenated (2024 invoices)
          # Pattern: "december 2024BetaldVisa PDF1 757,00 krBetald"
          match = text.match(/(\w+)\s+(\d{4})(Betald|Obetald).*?([\d\s,]+)\s*kr/i)
          @logger.debug "  [#{idx}] Format 2 match: #{match ? 'YES' : 'NO'} | Text: #{text[0..60]}" if @debug
          if match
            month_name = match[1].downcase
            year = match[2].to_i
            # Check "Obetald" first since /betald/i matches BOTH "Betald" and "Obetald"
            status = match[3].match?(/obetald/i) ? 'Obetald' : 'Betald'
            amount_text = match[4].strip + ' kr'
            @logger.debug "  [#{idx}] Parsed: #{month_name} #{year} #{status} #{amount_text}" if @debug
          end
        end

        # Skip if we couldn't parse
        if !month_name || !year || !status || !amount_text
          @logger.debug "  [#{idx}] Skipped: Could not parse (#{lines.size} lines): #{text[0..80]}" if @debug
          next
        end

        # Validate month
        month_num = month_map[month_name]
        if !month_num
          @logger.debug "  [#{idx}] Skipped: Unknown month '#{month_name}'" if @debug
          next
        end
        amount_numeric = parse_swedish_amount(amount_text)
        next unless amount_numeric

        # Assume end-of-month due date (reasonable assumption when not visible in list view)
        # ElectricityBill.calculate_bill_period will handle period calculation based on day-of-month
        last_day = Date.new(year, month_num.to_i, -1)  # -1 gives last day of month
        due_date = last_day.strftime('%Y-%m-%d')

        # Skip duplicates
        next if invoices.any? { |inv| inv['due_date'] == due_date }

        invoice_data_hash = {
          'amount' => amount_numeric,
          'amount_formatted' => amount_text,
          'due_date' => due_date,
          'status' => status,
          'provider' => 'fortum'  # Lowercase for consistency with historical data
        }

        invoices << invoice_data_hash
        @logger.info "  ✓ Invoice #{invoices.size}: #{amount_text} (#{month_name.capitalize} #{year}) - #{status}"
      end

    rescue => e
      @logger.error "  ❌ Invoice extraction failed: #{e.message}"
      @logger.error "  #{e.backtrace.first(3).join("\n  ")}"
    end

    @logger.info "✅ Extracted #{invoices.size} invoices"
    invoices
  end

  # Helper method to parse Swedish currency format
  def parse_swedish_amount(amount_text)
    return nil unless amount_text

    # Swedish format: "1 685,69 kr" → 1685.69
    # Remove all spaces (including non-breaking spaces U+00A0)
    clean_amount = amount_text.gsub(/[\s\u00A0]+/, '').gsub(/kr$/i, '')
    # Convert comma to decimal point
    clean_amount = clean_amount.gsub(',', '.')
    clean_amount.to_f
  end

  private

  def create_logger(debug)
    logger = Logger.new(STDOUT)
    logger.level = debug ? Logger::DEBUG : Logger::INFO
    logger.formatter = proc do |severity, datetime, progname, msg|
      timestamp = datetime.strftime('%Y-%m-%d %H:%M:%S')
      "[#{timestamp}] #{severity}: #{msg}\n"
    end
    logger
  end

  def initialize_browser(headless:)
    @logger.info "→ Initializing browser..."
    @logger.debug "  Headless: #{headless}" if @debug

    @browser = Ferrum::Browser.new(
      browser_options: BROWSER_OPTIONS,
      timeout: TIMEOUT,
      process_timeout: PROCESS_TIMEOUT,
      headless: headless
    )

    @page = browser.create_page
    @logger.info "  ✓ Browser ready"
  rescue => e
    @logger.error "❌ Browser initialization failed: #{e.message}"
    raise
  end

  def wait_for_network_idle(timeout: 30)
    page.network.wait_for_idle(timeout: timeout)
  rescue Ferrum::TimeoutError => e
    @logger.warn "⚠️  Network idle timeout after #{timeout}s"
    # Don't raise - page may still be usable
  end

  def save_error_screenshot
    timestamp = Time.now.to_i
    filename = "tmp/screenshots/error_#{timestamp}.png"

    Dir.mkdir('tmp') unless Dir.exist?('tmp')
    Dir.mkdir('tmp/screenshots') unless Dir.exist?('tmp/screenshots')

    page.screenshot(path: filename)
    @logger.info "📸 Error screenshot saved: #{filename}"
  rescue => e
    @logger.warn "Could not save screenshot: #{e.message}"
  end

  def cleanup
    @logger.info ""
    @logger.info "→ Cleaning up..."

    begin
      # Suppress quit errors (common issue in Ferrum)
      original_stdout = $stdout.clone
      $stdout.reopen(File.new('/dev/null', 'w'))

      browser&.quit

      $stdout.reopen(original_stdout)
      @logger.info "  ✓ Browser closed"
    rescue => e
      $stdout.reopen(original_stdout)
      # Only log if it's not the known Ferrum quit error
      unless e.is_a?(NoMethodError) && e.backtrace.first.include?("ferrum/browser.rb")
        @logger.warn "  ⚠️  Cleanup warning: #{e.message}"
      end
    end

    @logger.info ""
    @logger.info "=" * 80
    @logger.info "Session ended: #{Time.now.strftime('%Y-%m-%d %H:%M:%S')}"
    @logger.info "=" * 80
  end
end

# Main execution
if __FILE__ == $PROGRAM_NAME
  # Set Vessel logger to WARN to reduce noise (if any Ferrum dependencies use it)
  begin
    require 'vessel'
    Vessel::Logger.instance.level = ::Logger::WARN
  rescue LoadError
    # Vessel not installed - this is expected and fine
  end

  scraper = FortumScraper.new(
    debug: ENV['DEBUG'],
    headless: !ENV['SHOW_BROWSER']  # Headless by default, SHOW_BROWSER=1 to see browser
  )

  scraper.run do |results|
    # Save consumption data to electricity_usage.json (already done in scrape_consumption_data)

    if results[:invoices]
      puts "\n📊 Invoice Summary:"
      puts "  Total invoices scraped: #{results[:invoices].size}"
      results[:invoices].each_with_index do |invoice, i|
        puts "  #{i+1}. #{invoice['amount_formatted']} due #{invoice['due_date']} (#{invoice['status']})"
      end

      # Save invoices to JSON file (backup)
      Oj.to_file('electricity_invoices.json', results[:invoices])
      puts "\n💾 JSON backup: electricity_invoices.json"

      # Compare with historical data if requested
      if ENV['COMPARE_HISTORY']
        puts "\n🔍 COMPARISON MODE - Historical Data Verification"
        puts "=" * 80

        require_relative 'lib/persistence'
        require_relative 'lib/models/electricity_bill'

        # Load historical file
        historical_bills = []
        if File.exist?('electricity_bills_history.txt')
          current_provider = nil
          File.readlines('electricity_bills_history.txt').each do |line|
            line = line.strip
            next if line.empty?

            # Detect provider sections (including comments)
            if line.match(/Vattenfall/i)
              current_provider = 'vattenfall'
              next
            elsif line.match(/Fortum/i)
              current_provider = 'fortum'
              next
            end

            # Skip other comments
            next if line.start_with?('#')

            # Parse bill lines
            if line.match(/^(\d{4}-\d{2}-\d{2})\s+(\d+)\s*kr/)
              date_str, amount_str = line.match(/^(\d{4}-\d{2}-\d{2})\s+(\d+)\s*kr/).captures
              historical_bills << {
                provider: current_provider,
                due_date: Date.parse(date_str),
                amount: amount_str.to_f
              } if current_provider == 'fortum'
            end
          end
        end

        # Load database bills
        db_bills = Persistence.electricity_bills.all.select { |b|
          b.provider.downcase.include?('fortum')
        }.map { |b|
          {
            provider: 'fortum',
            due_date: b.bill_date,
            amount: b.amount,
            period: b.bill_period
          }
        }

        # Compare scraped invoices
        puts "\n📋 Scraped Invoices (#{results[:invoices].size}):"
        results[:invoices].each do |inv|
          due_date = Date.parse(inv['due_date'])
          amount = inv['amount']

          # Calculate expected period
          expected_period = ElectricityBill.calculate_bill_period(due_date)

          # Check historical file
          hist_match = historical_bills.find { |h|
            h[:due_date] == due_date && (h[:amount] - amount).abs < 1
          }

          # Check database
          db_match = db_bills.find { |d|
            d[:due_date] == due_date && (d[:amount] - amount).abs < 1
          }

          hist_status = hist_match ? "✓" : "✗"
          db_status = db_match ? "✓" : "✗"
          db_period = db_match ? db_match[:period].strftime('%Y-%m') : "N/A"

          puts "  #{inv['due_date']}: #{amount.round(0)} kr"
          puts "    Expected period: #{expected_period.strftime('%Y-%m')}"
          puts "    Historical file: #{hist_status} | Database: #{db_status} (period: #{db_period})"
          puts "    Status: #{inv['status']}"
          puts ""
        end

        puts "\n📊 Summary:"
        puts "  Scraped: #{results[:invoices].size} invoices"
        puts "  Historical file: #{historical_bills.size} Fortum bills"
        puts "  Database: #{db_bills.size} Fortum bills"

        # Exit after comparison (don't store in DB)
        puts "\nℹ️  Comparison complete - skipping database storage"
        exit 0
      end

      # Store in database with deduplication
      unless ENV['SKIP_DB']
        puts "\n💾 Storing invoices in database..."

        inserted_count = 0
        skipped_count = 0
        last_result = nil

        results[:invoices].each do |invoice|
          result = ApplyElectricityBill.call(
            provider: invoice['provider'],
            amount: invoice['amount'],
            due_date: invoice['due_date'],
            electricity_repo: Persistence.electricity_bills,
            config_repo: Persistence.rent_configs
          )

          bill_period = result[:bill_period]&.strftime('%Y-%m') || 'unknown'
          total = result[:aggregated_total]

          if result[:inserted]
            puts "  ✓ #{invoice['provider']} #{invoice['amount_formatted']} → period #{bill_period} (RentConfig #{result[:config_updated]} | total #{total} kr)"
            inserted_count += 1
          else
            puts "  ⊘ Skipped duplicate: #{invoice['provider']} #{invoice['amount_formatted']} (current total #{total} kr)"
            skipped_count += 1
          end

          last_result = result
        end

        puts "\n  Summary: #{inserted_count} inserted, #{skipped_count} skipped"

        if last_result && last_result[:bill_period]
          period_label = last_result[:bill_period].strftime('%Y-%m')
          puts "  RentConfig 'el' for #{period_label}: #{last_result[:aggregated_total]} kr"
        end
      end
    end
  end
end

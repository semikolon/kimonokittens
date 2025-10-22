#!/usr/bin/env ruby
# frozen_string_literal: true

# Vattenfall Electricity Data Scraper (Pure Ferrum)
#
# Purpose: Automated fetching of electricity consumption data and invoices
#          from Vattenfall Eldistribution customer portal.
#
# Architecture: Pure Ferrum (browser automation) - no dependencies on
#               abandoned Vessel gem.
#
# Usage:
#   ruby vattenfall.rb                    # Fetch consumption data
#   DEBUG=1 ruby vattenfall.rb            # Run with debug logging
#
# Output:
#   - electricity_usage.json (hourly consumption data)
#   - Future: ElectricityBill database records
#
# Schedule: Run daily at 3am via cron
#
# Created: Original (with Vessel)
# Migrated: October 21, 2025 (Pure Ferrum)

require 'dotenv/load'
require 'awesome_print'
require 'json'
require 'ferrum'
require 'oj'
require 'logger'
require 'date'
require_relative 'lib/persistence'
require_relative 'lib/services/apply_electricity_bill'

# Credentials from environment
ID = ENV['VATTENFALL_ID']
PW = ENV['VATTENFALL_PW']

if ID.nil? || ID.empty?
  abort '❌ ERROR: VATTENFALL_ID environment variable required'
elsif PW.nil? || PW.empty?
  abort '❌ ERROR: VATTENFALL_PW environment variable required'
end

class VattenfallScraper
  BROWSER_OPTIONS = {
    'no-default-browser-check': true,
    'disable-extensions': true,
    'disable-translate': true,
    'mute-audio': true,
    'disable-sync': true
  }.freeze

  TIMEOUT = 10
  PROCESS_TIMEOUT = 120
  LOGIN_URL = 'https://www.vattenfalleldistribution.se/logga-in?pageId=6'

  # Hardcoded meter ID (from original script)
  METER_ID = 'HDG735999100004995459'

  attr_reader :browser, :page, :logger

  def initialize(logger: nil, headless: true, debug: ENV['DEBUG'])
    @logger = logger || create_logger(debug)
    @debug = debug

    @logger.info "=" * 80
    @logger.info "Vattenfall Scraper (Pure Ferrum)"
    @logger.info "Started: #{Time.now.strftime('%Y-%m-%d %H:%M:%S')}"
    @logger.info "Debug mode: #{@debug ? 'ENABLED' : 'disabled'}"
    @logger.info "=" * 80

    initialize_browser(headless: headless)
  end

  def run(&block)
    @logger.info "🚀 Starting scraping session..."

    begin
      # Login first (common for both operations)
      perform_login

      # Navigate to invoices and inspect (DEBUG/INSPECT mode only)
      inspect_invoice_page if @debug || ENV['INSPECT_INVOICES']

      # Fetch invoice data (Phase 3 - NEW)
      invoice_data = scrape_invoices unless ENV['SKIP_INVOICES']

      # Fetch consumption data (existing functionality)
      consumption_data = scrape_consumption_data

      # Combine results
      results = {
        invoices: invoice_data,
        consumption: consumption_data
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
    @logger.info "🔐 LOGIN PHASE"
    @logger.info "=" * 40

    # Step 1: Navigate to login page
    @logger.info "→ Navigating to login page..."
    page.go_to(LOGIN_URL)
    wait_for_network_idle(timeout: PROCESS_TIMEOUT)
    @logger.info "  ✓ Login page loaded"

    # Step 2: Click login method button
    @logger.info "→ Selecting login method..."
    login_btn = page.at_css("button[variant='outline-secondary']")
    raise "Login button not found" unless login_btn
    login_btn.click
    @logger.info "  ✓ Login method selected"

    # Step 3: Enter credentials
    @logger.info "→ Entering credentials..."
    form = page.at_css('form')
    raise "Login form not found" unless form

    customer_number_field = form.at_css('input[id=customerNumber]')
    customer_number_field.focus
    customer_number_field.type(ID, :enter)
    @logger.info "  ✓ Customer number entered"

    customer_pw_field = form.at_css('input[id=password]')
    customer_pw_field.focus
    customer_pw_field.type(PW, :enter)
    @logger.info "  ✓ Password entered"

    wait_for_network_idle(timeout: PROCESS_TIMEOUT)
    @logger.info "  ✓ Login successful"
    @logger.info "  Current URL: #{page.current_url}"

    # Step 4: Handle cookie consent if present
    handle_cookie_consent
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
    @logger.info "📄 INVOICE INSPECTION PHASE"
    @logger.info "=" * 40

    # Navigate directly to invoice page URL
    @logger.info "→ Navigating to invoice page..."
    invoice_url = 'https://www.vattenfalleldistribution.se/mina-sidor/fakturor/'
    page.go_to(invoice_url)
    wait_for_network_idle(timeout: 30)
    @logger.info "  ✓ Navigated to: #{page.current_url}"

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

  def scrape_consumption_data
    @logger.info ""
    @logger.info "📊 CONSUMPTION DATA PHASE"
    @logger.info "=" * 40

    # Step 1: Set API headers
    @logger.info "→ Configuring API headers..."
    page.headers.set({
      "accept" => 'application/json, text/plain, */*',
      "ocp-apim-subscription-key" => ENV['AZURE_SUBSCRIPTION_KEY']
    })
    @logger.info "  ✓ Headers configured"

    # Step 2: Calculate date range
    today = Date.today
    if today.month == 1
      start_date = Date.new(today.year, 1, 1).strftime("%Y-%m-%d")
    else
      start_date = Date.new(today.year - 1, today.month - 1, [28, today.day].min).strftime("%Y-%m-%d")
    end
    end_date = Date.new(today.year, today.month, -1).strftime("%Y-%m-%d")

    @logger.info "→ Fetching data for period:"
    @logger.info "  Start: #{start_date}"
    @logger.info "  End:   #{end_date}"

    # Step 3: Fetch consumption API
    api_url = "https://services.vattenfalleldistribution.se/consumption/consumption/#{METER_ID}/#{start_date}/#{end_date}/Hourly/Measured?skipDts=true"
    @logger.info "→ Requesting consumption API..."
    @logger.debug "  URL: #{api_url}" if @debug

    page.go_to(api_url)

    begin
      wait_for_network_idle(timeout: 10)
    rescue Ferrum::TimeoutError
      @logger.warn "  ⚠️  Network timeout (may not affect data retrieval)"
    end

    # Step 4: Extract data
    @logger.info "→ Extracting consumption data..."
    measured = page.at_css('pre')&.text
    raise 'No data found in API response' if measured.nil?

    data = Oj.safe_load(measured)

    # Step 5: Process and validate
    stats = data['consumption'].map(&:compact)
    stats.each { |s| s['date'] = DateTime.parse(s['date']).new_offset('+02:00').iso8601 }

    days = (stats.size / 24.0).round(1)
    @logger.info "✅ Successfully fetched #{stats.size} hours (#{days} days)"
    @logger.info "   Last data point: #{DateTime.parse(stats.last['date']).strftime('%b %-d, %H:%M')}"

    # Step 6: Save to file
    @logger.info "→ Saving to electricity_usage.json..."
    Oj.to_file('electricity_usage.json', stats)
    @logger.info "  ✓ File saved"

    data
  end

  def scrape_invoices
    @logger.info ""
    @logger.info "📄 INVOICE SCRAPING PHASE"
    @logger.info "=" * 40

    # Navigate to invoice page
    @logger.info "→ Navigating to invoice page..."
    invoice_url = 'https://www.vattenfalleldistribution.se/mina-sidor/fakturor/'
    page.go_to(invoice_url)
    wait_for_network_idle(timeout: 30)
    @logger.info "  ✓ Navigated to: #{page.current_url}"

    # Extract invoices from desktop table view (more reliable than mobile divs)
    @logger.info "→ Extracting invoice data..."

    tables = page.css('table')
    unless tables.any?
      @logger.warn "  ⚠️  No invoice table found"
      return []
    end

    # Find the main invoice table (look for tbody with invoice rows)
    main_table = tables.find { |t| t.css('tbody.vfdso-invoice-list__item').any? }
    unless main_table
      @logger.warn "  ⚠️  No invoice data rows found"
      return []
    end

    # Extract each invoice row
    invoice_rows = main_table.css('tbody.vfdso-invoice-list__item')
    invoices = []

    invoice_rows.each_with_index do |row, index|
      begin
        # Extract amount from th with class vfdso-invoice-list__item__amount
        amount_cell = row.at_css('th.vfdso-invoice-list__item__amount')
        amount_text = amount_cell&.text&.strip

        # Extract due date from td with class vfdso-invoice-list__item__date
        date_cell = row.at_css('td.vfdso-invoice-list__item__date span')
        due_date = date_cell&.text&.strip

        # Extract status from badge
        status_badge = row.at_css('vfdso-badge div.vfdso-badge span')
        status = status_badge&.text&.strip

        # Convert amount string to numeric
        # Swedish format: "1 685,69 kr" → 1685.69
        # Remove all spaces (including non-breaking spaces U+00A0)
        # Convert comma to decimal point, remove "kr" suffix
        amount_numeric = nil
        if amount_text
          # Remove all whitespace and "kr" suffix
          clean_amount = amount_text.gsub(/[\s\u00A0]+/, '').gsub(/kr$/i, '')
          # Convert comma to decimal point
          clean_amount = clean_amount.gsub(',', '.')
          amount_numeric = clean_amount.to_f
        end

        invoice_data = {
          'amount' => amount_numeric,
          'amount_formatted' => amount_text,
          'due_date' => due_date,
          'status' => status,
          'provider' => 'Vattenfall'
        }

        invoices << invoice_data

        @logger.info "  ✓ Invoice #{index + 1}: #{amount_text} due #{due_date} (#{status})"
      rescue => e
        @logger.warn "  ⚠️  Failed to extract invoice #{index + 1}: #{e.message}"
      end
    end

    @logger.info "✅ Extracted #{invoices.size} invoices"
    invoices
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

  scraper = VattenfallScraper.new(
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

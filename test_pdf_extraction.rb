#!/usr/bin/env ruby
# Test script to download and extract text from Vattenfall invoice PDF

require 'dotenv/load'
require 'ferrum'
require 'logger'
require 'fileutils'
require 'pdf-reader'

ID = ENV['VATTENFALL_ID']
PW = ENV['VATTENFALL_PW']

logger = Logger.new(STDOUT)
logger.level = Logger::INFO

# Initialize browser
logger.info "Initializing browser..."
browser = Ferrum::Browser.new(
  browser_options: {
    'no-default-browser-check': true,
    'disable-extensions': true
  },
  headless: false,  # Show browser for debugging
  timeout: 10
)

page = browser.create_page

begin
  # Login
  logger.info "Logging in to Vattenfall..."
  page.go_to('https://www.vattenfalleldistribution.se/logga-in?pageId=6')
  page.network.wait_for_idle(timeout: 30)

  # Click login button
  login_btn = page.at_css("button[variant='outline-secondary']")
  login_btn.click

  # Enter credentials
  form = page.at_css('form')
  customer_number_field = form.at_css('input[id=customerNumber]')
  customer_number_field.focus
  customer_number_field.type(ID, :enter)

  customer_pw_field = form.at_css('input[id=password]')
  customer_pw_field.focus
  customer_pw_field.type(PW, :enter)

  page.network.wait_for_idle(timeout: 30)
  logger.info "✓ Logged in"

  # Handle cookie consent
  logger.info "Checking for cookie consent..."
  begin
    buttons = page.css('button')
    accept_btn = buttons.find { |btn| btn.text.match?(/acceptera\s+alla/i) }
    if accept_btn
      logger.info "  → Accepting cookies..."
      accept_btn.click
      sleep 1
      logger.info "  ✓ Cookies accepted"
    end
  rescue => e
    logger.warn "  ⚠️  Cookie handling failed: #{e.message}"
  end

  # Navigate to invoices
  logger.info "Navigating to invoice page..."
  page.go_to('https://www.vattenfalleldistribution.se/mina-sidor/fakturor/')
  page.network.wait_for_idle(timeout: 30)

  # Take a screenshot first
  FileUtils.mkdir_p('tmp/screenshots')
  page.screenshot(path: 'tmp/screenshots/invoice_page_before_pdf.png')
  logger.info "Screenshot saved to tmp/screenshots/invoice_page_before_pdf.png"

  # Debug: Show all links on page
  all_links = page.css('a')
  logger.info "Found #{all_links.size} total links on page"

  # Show sample links with "PDF" or "visa" in text
  pdf_related = all_links.select { |a| a.text.match?(/pdf|visa/i) }
  logger.info "Links with PDF or Visa: #{pdf_related.size}"
  pdf_related.first(10).each do |link|
    logger.info "  - Text: #{link.text.strip} | Href: #{link.attribute('href')}"
  end

  # Find "Visa faktura" link (not "Visa PDF")
  logger.info "\nLooking for 'Visa faktura' link..."
  faktura_links = page.css('a').select { |a| a.text.strip == 'Visa faktura' }
  logger.info "Found #{faktura_links.size} 'Visa faktura' links"

  if faktura_links.empty?
    logger.error "No 'Visa faktura' links found!"
    exit 1
  end

  # Click the first "Visa faktura" link
  logger.info "Clicking first 'Visa faktura' link..."
  faktura_links.first.evaluate("el => el.click()")
  sleep 3  # Wait for page to load
  page.network.wait_for_idle(timeout: 30) rescue nil

  # Take screenshot of what loaded
  page.screenshot(path: 'tmp/screenshots/invoice_detail.png')
  logger.info "Screenshot saved to tmp/screenshots/invoice_detail.png"

  current_url = page.current_url
  logger.info "Current URL after clicking: #{current_url}"

  # Check if it's a PDF or HTML page
  if current_url.include?('.pdf') || current_url.start_with?('blob:')
    logger.info "✓ PDF detected in browser"

    # Create temp directory
    FileUtils.mkdir_p('tmp/pdfs')
    pdf_path = "tmp/pdfs/invoice_#{Time.now.to_i}.pdf"

    # Try to extract PDF using browser's print to PDF
    page.pdf(path: pdf_path)
    logger.info "✓ PDF saved to: #{pdf_path}"

    pdf_available = true
  else
    logger.info "HTML detail page loaded (not PDF)"

    # Extract text from HTML page
    logger.info "\n" + "="*80
    logger.info "EXTRACTING DATA FROM HTML PAGE"
    logger.info "="*80

    page_text = page.body
    logger.info "Page HTML length: #{page_text.length} characters"

    # Try to find rate information in the HTML
    # Look for common patterns like "Energiskatt", "Elöverföring", "öre/kWh", etc.

    if match = page_text.match(/energiskatt.*?(\d+[.,]\d+)\s*(öre|kr)/i)
      logger.info "✓ Found energy tax in HTML: #{match[0]}"
    end

    if match = page_text.match(/(elöverföring|överföring).*?(\d+[.,]\d+)\s*(öre|kr)/i)
      logger.info "✓ Found grid transfer in HTML: #{match[0]}"
    end

    # Look for any per-kWh rates
    matches = page_text.scan(/(\d+[.,]\d+)\s*(öre|kr)\s*\/\s*kWh/i)
    if matches.any?
      logger.info "\nFound per-kWh rates in HTML:"
      matches.each do |amount, unit|
        logger.info "  - #{amount} #{unit}/kWh"
      end
    end

    pdf_available = false
  end

  # Parse PDF if available
  if pdf_available
    logger.info "\n" + "="*80
    logger.info "PARSING PDF"
    logger.info "="*80

    reader = PDF::Reader.new(pdf_path)

    logger.info "Pages: #{reader.page_count}"
    logger.info "\nFull text:\n"
    logger.info "-"*80

    reader.pages.each_with_index do |p, i|
      logger.info "Page #{i+1}:"
      text = p.text
      logger.info text
      logger.info "-"*80
    end

    # Search for rate patterns
    logger.info "\n" + "="*80
    logger.info "SEARCHING FOR RATES IN PDF"
    logger.info "="*80

    full_text = reader.pages.map(&:text).join("\n")

    # Look for energy tax (energiskatt)
    if match = full_text.match(/energiskatt.*?(\d+[.,]\d+)\s*(öre|kr)/i)
      logger.info "✓ Found energy tax: #{match[0]}"
    end

    # Look for grid transfer (elöverföring, överföring)
    if match = full_text.match(/(elöverföring|överföring).*?(\d+[.,]\d+)\s*(öre|kr)/i)
      logger.info "✓ Found grid transfer: #{match[0]}"
    end

    # Look for any öre/kWh or kr/kWh rates
    matches = full_text.scan(/(\d+[.,]\d+)\s*(öre|kr)\s*\/\s*kWh/i)
    if matches.any?
      logger.info "\nFound per-kWh rates:"
      matches.each do |amount, unit|
        logger.info "  - #{amount} #{unit}/kWh"
      end
    end

    # Look for fixed fees (fast avgift, månadskostnad)
    if match = full_text.match(/(fast\s+avgift|månadskostnad).*?(\d+[.,]\d+)\s*kr/i)
      logger.info "✓ Found fixed fee: #{match[0]}"
    end
  end

rescue => e
  logger.error "❌ Error: #{e.message}"
  logger.error e.backtrace.first(10).join("\n")
  raise
ensure
  logger.info "\nCleaning up..."
  browser.quit rescue nil
end

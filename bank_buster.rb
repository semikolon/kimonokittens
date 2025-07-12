#coding: utf-8
require 'dotenv/load'
require 'awesome_print'
require 'pathname'
require 'ferrum'
require 'vessel'
require 'oj'
require 'colorize'
require 'billy'
require 'table_print'
require 'pry'
require 'pry-nav'
require 'break'
require './bank_payments_reader.rb'


class FerrumLogger
  def initialize(logger)
    @logger = logger
  end
  def puts(*args)
    @logger << (args)
  end
end

PAYMENT_FILENAME_PATTERN = ENV['PAYMENT_FILENAME_PATTERN']
TRANSACTIONS_DIR = ENV['TRANSACTIONS_DIR'] || "#{Dir.pwd}/transactions"
SCREENSHOTS_DIR = 'screenshots'
SSN = ENV['ADMIN_SSN']

raise 'Bank customer SSN needed' if SSN.nil? || SSN.empty?

class LoginError < StandardError; end
class FileRetrievalError < StandardError; end

class BankBuster < Vessel::Cargo
  INFO_INTERVAL = 20
  MAX_ATTEMPTS = 10 # Define the maximum number of attempts
  
  # Tell Vessel which domain we are on, but we will control the navigation manually.
  domain ENV['BANK_DOMAIN'] if ENV['BANK_DOMAIN']
  
  # We are removing start_urls to take manual control of the first page load.
  # start_urls ENV['BANK_LOGIN_URL'] if ENV['BANK_LOGIN_URL']
   
  # Configure browser options for the modern Vessel API
  def self.browser_options
    {
      headless: ENV['BANKBUSTER_HEADLESS'] != 'false',  # Default to headless
      window_size: [1200, 800],
      save_path: TRANSACTIONS_DIR,
      timeout: 30,
      process_timeout: 180,
      browser_options: {
        'no-default-browser-check' => true,
        'disable-extensions' => true,
        'disable-translate' => true,
        'mute-audio' => true,
        'disable-sync' => true,
        'disable-web-security' => true,
        'disable-features' => 'VizDisplayCompositor',
        'user-agent' => 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36'
      }
    }
  end

  def log_existing_files
    yield({ type: 'LOG', data: "Transactions Dir: #{TRANSACTIONS_DIR}" }) if block_given?
    yield({ type: 'LOG', data: "Pattern: #{PAYMENT_FILENAME_PATTERN}" }) if block_given?
    yield({ type: 'LOG', data: "Files found: #{Dir.glob("#{TRANSACTIONS_DIR}/#{PAYMENT_FILENAME_PATTERN}").count}" }) if block_given?
  end
  
  def parse
    # Manually navigate to the start page to gain more control and better error handling.
    begin
      yield({ type: 'LOG', data: "Manually navigating to #{ENV['BANK_LOGIN_URL']}..." }) if block_given?
      page.go_to(ENV['BANK_LOGIN_URL'])
    rescue Ferrum::TimeoutError => e
      yield({ type: 'ERROR', error: 'Navigation Timeout', message: "The page took too long to become idle. This is common on complex sites. The page content may have loaded anyway." }) if block_given?
      
      # If we time out, let's take a screenshot to see what the page looks like.
      screenshot_path = "#{SCREENSHOTS_DIR}/timeout_error_page.jpg"
      page.screenshot(path: screenshot_path)
      yield({ type: 'LOG', data: "Saved a screenshot of the timed-out page to: #{screenshot_path}" }) if block_given?
    end

    log_existing_files { |event| yield event }
    
    # Filter out non-essential requests
    filter_out_non_essentials
    wait_for_idle_or_rescue
    
    # Accept cookies on the page
    accept_cookies { |event| yield event }
    wait_for_idle_or_rescue
    
    # Start the login process. If this raises a LoginError, it will now
    # propagate up and halt the execution, which is the correct behavior.
    login_process { |event| yield event }
    
    # This part will only be reached after a successful login.
    retrieve_and_parse_files { |event| yield event }
      
  # The rescue block is now simplified. A failure in login_process will be caught
  # by the default Vessel error handler, which will terminate the run.
  # We only need to catch specific Ferrum errors if we want to add custom logging.
  rescue Ferrum::DeadBrowserError => e
    yield({ type: 'ERROR', error: 'Browser error occurred', message: e.message }) if block_given?
    yield({ type: 'LOG', data: "Browser died." }) if block_given?
  rescue NoMethodError => e
    if e.backtrace[0].include?('ferrum') && e.message.include?('command')
      yield({ type: 'ERROR', error: 'Unknown command error occurred', message: e.message }) if block_given?
      yield({ type: 'LOG', data: "Tried to command dead browser." }) if block_given?
    else
      raise # Unexpected error
    end
  end

  def inspect
    "#<#{self.class}:0x#{object_id.to_s(16)}>"
  end

  def wait_for_idle_or_rescue(timeout: 5)
    page.network.wait_for_idle(timeout: timeout)
  rescue Ferrum::TimeoutError
    yield({ type: 'ERROR', error: 'Timeout while waiting for update' })
  end

  def filter_out_non_essentials
    # Intercept network requests
    page.network.intercept
    page.on(:request) do |request|
      # If the request is for an image, font, or stylesheet, abort it unless it's a blob
      if ['Image', 'Font','Stylesheet'].include?(request.resource_type)
        if request.match?("/blob:/")
          request.continue
        else
          request.abort
        end
      else
        # Continue with other types of requests
        request.continue
      end
    end
  end

  def accept_cookies
    yield({ type: 'LOG', data: 'Trying to identify cookie accept button...' }) if block_given?
    attempts = 0
    until cookie_button = at_css("acorn-button[data-cy='acorn-button-accept-all']")
      raise LoginError, 'Could not find cookie accept button' if attempts > 100
      sleep 0.1
      attempts += 1
    end
    cookie_button.click
  end

  def input_login_and_get_qr_code(&block)
    ssn_field = at_css("input[type=text]")
    raise LoginError, 'SSN field not found' unless ssn_field
    ssn_field.focus.type(SSN, :enter)
    yield({ type: 'LOG', data: 'Filled in SSN, starting login...' }) if block_given?
  
    wait_for_idle_or_rescue
    message = at_css("span[slot=message]")&.text
    puts message if message
    raise LoginError, 'Unable to login' if message&.include?('Det gick inte att logga in')
        
    qr_code_url = "#{SCREENSHOTS_DIR}/qr_code.jpg"
    qr_found = false
    qr_selectors = ['img.mobile-bank-id__qr-code--image']
    
    # Keep checking for QR code updates
    attempts = 0
    while attempts < 30  # Check for 30 seconds
      qr_selectors.each do |selector|
        begin
          qr_element = at_css(selector)
          if qr_element
            # Don't take screenshot again if we already have it
            unless qr_found
              page.screenshot(path: qr_code_url, selector: selector)
              yield({ type: 'QR_UPDATE', qr_code_url: qr_code_url }) if block_given?
              qr_found = true
            end
            # We can break the inner loop once found
            break
          end
        rescue => e
          # Ignore errors during polling
        end
      end

      # Now check if the BankID session on the page has timed out
      message_element = at_css("span[slot=message]")
      if message_element && message_element.text.include?('för lång tid')
        yield({ type: 'LOG', data: 'BankID timed out on page, attempting to retry...' }) if block_given?
        retry_button = at_css("acorn-button[label='Försök igen']")
        if retry_button
          retry_button.click
          # After clicking retry, we exit this method. The main loop in `login_process`
          # will then call us again to restart the SSN entry.
          yield({ type: 'LOG', data: 'Clicked "Try Again". Restarting login.' }) if block_given?
          return # Exit to allow the retry loop to take over
        end
      end
      
      break if qr_found
      sleep 1
      attempts += 1
      wait_for_idle_or_rescue
    end
    
    yield({ type: 'LOG', data: "QR code polling finished" }) if block_given?
  end

  def download_all_payment_files(&block)
    page.network.clear(:traffic)
    page.go_to(absolute_url('/app/ib/dokument'))
    wait_for_idle_or_rescue
    # page.screenshot(path: 'files.jpg')
    
    auth_headers = nil
    json = nil
    page.network.traffic.each do |exchange|
      req = exchange.request
      if req && exchange.finished? && req.type == 'XHR' &&
        req.url.include?("message/document/search?")
        auth_headers = req.headers
        json = Oj.safe_load(exchange.response.body)
      end
    end
    
    all_documents = json['documents']
    documents = all_documents.select do |doc|
      doc_filename = PAYMENT_FILENAME_PATTERN.gsub(/\*/, doc['creationDate'])
      doc['type'] == 'Redovisning camt.054' &&
      doc['name'].include?('betalningar') &&
      !Dir.glob("#{TRANSACTIONS_DIR}/*.xml").any? do |file|
        File.basename(file) == doc_filename
      end # only non-downloaded files
    end
    # ap documents
    # documents = documents.take(4)
    yield({ type: 'LOG', data: "Found #{documents.count} documents to download" }) if block_given?
    
    # page.network.clear(:cache)
    documents.each_with_index do |doc, index|
      download_file(id: doc['id'], headers: auth_headers, &block)
      progress = ((index + 1).to_f / documents.size.to_f) * 100
      yield({ type: 'PROGRESS_UPDATE', progress: progress.round(2) })
    end
  end
  
  def download_file(id:, headers:, &block)
    page.headers.set(headers)
    url_to_fetch_url = absolute_url('/TDE_DAP_Portal_REST_WEB/api/v5/message/document/'+id+'/view?referenceType=DOCUMENT_ID')
    page.go_to(url_to_fetch_url)
    
    wait_for_idle_or_rescue(timeout: 1) unless page.network.status == 200
    raise FileRetrievalError, 'Download URL fetch failed' unless page.network.status == 200
    
    location_info = Oj.safe_load(page.at_css('pre').text)
    #=> "{\"url\":\"TDE_DAP_Portal_REST_WEB/api/v5/content/edocument\",\"ticket\":\"52b77e46187277e3eca271571703a6f8d8a7776b\",\"param\":\"ticket\",\"method\":\"GET\",\"internal\":true,\"movedToArchive\":true}"
    #binding.pry
    ticket = location_info['ticket']
    
    page.headers.set(page.headers.get)
    url_to_download = absolute_url('/'+location_info['url']+'?ticket='+ticket)
    begin
      page.go_to(url_to_download)
    rescue Ferrum::StatusError => e
      yield({ type: 'LOG', data: "File download status error, might be irrelevant" }) if block_given?
    end

    #E, [2023-12-25T20:56:59.023791 #78626] ERROR -- : Engine: `Ferrum::StatusError: Request to https://online.swedbank.se/TDE_DAP_Portal_REST_WEB/api/v5/content/edocument?ticket=9b74fd66ad22bf9794b2c9d1c0a929e0adf3028e failed (net::ERR_ABORTED)`
    #/usr/local/var/rbenv/versions/3.2.2/lib/ruby/gems/3.2.0/gems/ferrum-0.14/lib/ferrum/page.rb:118:in `go_to'
    #bank_buster.rb:222:in `download_file'
    #bank_buster.rb:201:in `block in download_all_payment_files'
    
    wait_for_idle_or_rescue(timeout: 1) unless page.network.status == 200
    raise FileRetrievalError, 'Download failed' unless page.network.status == 200
    
    filename = page.network.response.headers['Content-type'].match(/name="(.*)"/)[1]
    yield({ type: 'LOG', data: "Downloaded #{filename}" }) if block_given?
    filename
  end
  
  def login_process
    yield({ type: 'LOG', data: 'Starting login process...' }) if block_given?
    attempts = 0
    # This loop is crucial. It retries the entire SSN input and QR code scan
    # process if the BankID authentication doesn't complete in time.
    until at_css("p[data-cy='verify-yourself']")&.text == ENV['BANK_ID_AUTH_TEXT']
      input_login_and_get_qr_code { |event| yield event }
      attempts += 1
      if attempts > MAX_ATTEMPTS
        error_message = 'Login process timed out after multiple attempts.'
        yield({ type: 'ERROR', error: 'Login Timeout', message: error_message }) if block_given?
        raise LoginError, error_message
      end
      # Give it a moment before retrying
      sleep 1
    end
    
    puts 'QR code picked up. Authenticate with BankID.'.yellow
    yield({ type: 'QR_CODE_PICKED_UP' }) if block_given?
    
    until at_css('acorn-section-header')&.attribute('heading') == ENV['PROFILE_SELECT_TEXT']
      sleep 0.2
      wait_for_idle_or_rescue
    end
    
    company_login = css('acorn-item').select{ |i| i.text.include?(ENV['COMPANY_NAME_TEXT']) }.first
    raise LoginError, 'Could not login as company' unless company_login
    company_login.click
    wait_for_idle_or_rescue
    
    print 'Logging in..'
    attempts = 0
    until at_css('h1')&.text == ENV['WELCOME_TEXT'] && page.url.include?(ENV['START_PAGE_URL_FRAGMENT'])
      raise LoginError, 'Login timed out' if at_css('h1')&.text == ENV['RELOGIN_TEXT']
      raise LoginError, 'Login took too long, please investigate' if attempts > 100
      print '.'
      sleep 0.05
      attempts += 1
    end
    puts "\n"
    
    yield({ type: 'LOG', data: 'Successfully logged in to bank account' }) if block_given?
  end
  

  def retrieve_and_parse_files(&block)
    yield({ type: 'LOG', data: 'Logged in. Reading files...' }) if block_given?
    filenames = download_all_payment_files(&block)
    payments = BankPaymentsReader.parse_files(filenames)
    yield({ type: 'FILES_RETRIEVED', data: payments }) if block_given?
  end

  def handle_errors(e, error_message, screenshot_path, &block)
    yield({ type: 'LOG', data: "\n#{error_message}" }) if block_given?
    page.screenshot(path: "#{SCREENSHOTS_DIR}/#{screenshot_path}")
    block.call if block_given?
    unless e.is_a? Interrupt
      puts $! # e.message
      puts $@ # e.backtrace
    end
    # raise e
  end
  
  def handle_login_errors(e)
    handle_errors(e, "Error during login process. Aborting login.", 'error.jpg') do
      at_css("acorn-button[label='Avbryt']")&.click
      puts "Clicked abort button..."
      wait_for_idle_or_rescue
      # binding.pry
    end
  end
  
  def handle_file_errors(e)
    handle_errors(e, "Error while getting files.", 'error_files.jpg')
  end

  def reset_browser
    browser.reset
  end
end

# This line is from the old Vessel API and is no longer valid.
# The modern Vessel/Ferrum gems handle logging differently.
# Vessel::Logger.instance.level = ::Logger::WARN

# When running in the terminal:
if __FILE__ == $PROGRAM_NAME
  # When run as a standalone script, it will now output a stream of JSON objects.
  BankBuster.run do |event|
    puts Oj.dump(event)
  end
end

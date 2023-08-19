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
  driver :ferrum,
    # slowmo: 2.0,
    # port: 9222, # for remote debugging
    # host: 'localhost',
    save_path: TRANSACTIONS_DIR,
    # headless: false,
    browser_options: {
        'no-default-browser-check' => true,
        'disable-extensions' => true,
        'disable-translate' => true,
        'mute-audio' => true,
        'disable-sync' => true
        #"proxy-bypass-list" => "<-loopback>"
    },
    # proxy: { host: "localhost", port: "3399" },
    # logger: FerrumLogger.new(Logger.new("browser.log")),
    timeout: 10,
    process_timeout: 120
    # delay 2
    domain ENV['BANK_DOMAIN']
    start_urls ENV['BANK_LOGIN_URL']
    # TODO: Start on /start-page and reuse login from last session if possible, need to save and reuse cookies for that though
  
  def parse(&block)
    # Filter out non-essential requests
    filter_out_non_essentials
    wait_for_idle_or_rescue
    # Accept cookies on the page
    accept_cookies
    wait_for_idle_or_rescue(timeout: 1)
    # Start the login process
    login_process
    # Retrieve files and pass the block to the method
    retrieve_and_parse_files(&block)
    # Reset the browser to be able to reuse the crawler instance
    reset_browser

  rescue LoginError => e
    yield({ type: 'ERROR', error: 'Login error occurred', message: e.message }) if block_given?
    handle_login_errors(e)
  rescue FileRetrievalError => e
    yield({ type: 'ERROR', error: 'File retrieval error occurred', message: e.message }) if block_given?
    handle_file_errors(e)
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

  def wait_for_idle_or_rescue(...)
    wait_for_idle(...)
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
    until cookie_button = at_css("acorn-button[data-cy='acorn-button-accept-all-cookies']")
      raise LoginError, 'Could not find cookie accept button' if attempts > 100
      sleep 0.1
      attempts += 1
    end
    cookie_button.click
  end

  def input_login_and_get_qr_code
    ssn_field = at_css("input[type=text]")
    raise LoginError, 'SSN field not found' unless ssn_field
    ssn_field.focus.type(SSN, :enter)
    yield({ type: 'LOG', data: 'Filled in SSN, starting login...' }) if block_given?
  
    wait_for_idle_or_rescue
    message = at_css("span[slot=message]")&.text
    puts message if message
    raise LoginError, 'Unable to login' if message&.include?('Det gick inte att logga in')
        
    qr_code_url = "#{SCREENSHOTS_DIR}/qr_code.jpg"
    while at_css("img.mobile-bank-id__qr-code--image")
      system("clear")
      yield({ type: 'LOG', data: "Open BankID app and scan QR code below:\n" }) if block_given?
      page.screenshot(path: qr_code_url, selector: 'img.mobile-bank-id__qr-code--image')
      yield({ type: 'QR_UPDATE', qr_code_url: qr_code_url })
      sleep 1
      wait_for_idle_or_rescue(timeout: 1)
    end
    yield({ type: 'LOG', data: "\n" }) if block_given?

    message = at_css("span[slot=message]")&.text
    if message&.include?('för lång tid')
      puts 'Timed out. Restarting login attempt...'
      at_css("acorn-button[label='Försök igen']").click
      wait_for_idle_or_rescue
    end
  end

  def download_all_payment_files
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
      download_file(id: doc['id'], headers: auth_headers)
      progress = ((index + 1).to_f / documents.size.to_f) * 100
      yield({ type: 'PROGRESS_UPDATE', progress: progress.round(2) })
    end
  end
  
  def download_file(id:, headers:)
    page.headers.set(headers)
    url_to_fetch_url = absolute_url('/TDE_DAP_Portal_REST_WEB/api/v5/message/document/'+id+'/view?referenceType=DOCUMENT_ID')
    page.go_to(url_to_fetch_url)
    
    wait_for_idle_or_rescue(timeout: 1) unless page.network.status == 200
    raise FileRetrievalError, 'Download URL fetch failed' unless page.network.status == 200
    
    location_info = Oj.safe_load(page.at_css('pre').text)
    ticket = location_info['ticket']
    
    page.headers.set(page.headers.get)
    url_to_download = absolute_url('/'+location_info['url']+'?ticket='+ticket)
    page.go_to(url_to_download)
    
    wait_for_idle_or_rescue(timeout: 1) unless page.network.status == 200
    raise FileRetrievalError, 'Download failed' unless page.network.status == 200
    
    filename = page.network.response.headers['Content-type'].match(/name="(.*)"/)[1]
    yield({ type: 'LOG', data: "Downloaded #{filename}" }) if block_given?
    filename
  end
  
  def login_process
    attempts = 0
    until at_css("p[data-cy='verify-yourself']")&.text == ENV['BANK_ID_AUTH_TEXT']
      input_login_and_get_qr_code
      attempts += 1
      if attempts > MAX_ATTEMPTS
        yield({ type: 'ERROR', error: 'Timeout while waiting for update' })
        return
      end
    end
    puts 'QR code picked up. Authenticate with BankID.'.yellow
    yield({ type: 'QR_CODE_PICKED_UP' })
    
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
  end
  

  def retrieve_and_parse_files
    yield({ type: 'LOG', data: 'Logged in. Reading files...' }) if block_given?
    filenames = download_all_payment_files
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

Vessel::Logger.instance.level = ::Logger::WARN

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

# Billy.configure do |c|
#   c.cache = true
#   c.cache_request_headers = false
#   c.ignore_params = ["http://www.google-analytics.com/__utm.gif",
#                      "https://r.twimg.com/jot",
#                      "http://p.twitter.com/t.gif",
#                      "http://p.twitter.com/f.gif",
#                      "http://www.facebook.com/plugins/like.php",
#                      "https://www.facebook.com/dialog/oauth",
#                      "http://cdn.api.twitter.com/1/urls/count.json"]
#   c.path_blacklist = []
#   c.merge_cached_responses_whitelist = []
#   c.persist_cache = true
#   c.ignore_cache_port = true # defaults to true
#   c.non_successful_cache_disabled = true
#   c.non_successful_error_level = :error # or :warn
#   c.non_whitelisted_requests_disabled = false
#   c.cache_path = 'req_cache/'
#   c.certs_path = 'req_certs/'
#   c.proxy_host = 'localhost'
#   c.proxy_port = 3399 # defaults to random
#   c.proxied_request_host = nil
#   c.proxied_request_port = 80
#   c.cache_whitelist = []
#   c.record_requests = true # defaults to false
#   c.cache_request_body_methods = ['post', 'patch', 'put'] # defaults to ['post']
# end

class FerrumLogger
  def initialize(logger)
    @logger = logger
  end
  def puts(*args)
    @logger << (args)
  end
end

SSN = ENV['ADMIN_SSN']

if SSN.nil? || SSN.empty?
  raise 'Bank customer SSN needed'
end

class BankBuster < Vessel::Cargo
  INFO_INTERVAL = 20
  driver :ferrum,
    # slowmo: 2.0,
    # port: 9222, # for remote debugging
    # host: 'localhost',
    save_path: Dir.pwd,
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
  domain 'online.swedbank.se'
  start_urls 'https://online.swedbank.se/app/ib/logga-in'
  # TODO: Start on /start-page and reuse login from last session if possible, need to save and reuse cookies for that though

  def filter_out_non_essentials
    page.network.intercept
    page.on(:request) do |request|
      if ['Image', 'Font','Stylesheet'].include?(request.resource_type)
        if request.match?("/blob:/")
          request.continue
        else
          request.abort
        end
      else
        request.continue
      end
    end
  end

  def accept_cookies
    puts 'Trying to identify cookie accept button...'.gray
    attempts = 0
    until cookie_button = at_css("acorn-button[data-cy='acorn-button-accept-all-cookies']")
      raise 'Could not find cookie accept button' if attempts > 100
      sleep 0.1
      attempts += 1
    end
    cookie_button.click
  end

  def input_login_and_get_qr_code
    ssn_field = at_css("input[type=text]")
    raise 'SSN field not found' unless ssn_field
    ssn_field.focus.type(SSN, :enter)
    puts 'Filled in SSN, starting login...'

    page.network.wait_for_idle(timeout: 5)
    message = at_css("span[slot=message]")&.text
    puts message if message
    raise 'Unable to login' if message&.include?('Det gick inte att logga in')

    # Assuming this instruction text doesn't matter if we're shown a QR code?
    # login_message = at_css(".mobile-bank-id__qr-code--instruction-list").text
    # raise unless login_message.include?('Öppna BankID-appen')

    print 'Saving QR codes..'
    while at_css("img.mobile-bank-id__qr-code--image")
      print '.' #puts "...".green
      #puts at_css("img.mobile-bank-id__qr-code--image")&.attribute('src')
      page.screenshot(path: 'qr_code.jpg', selector: 'img.mobile-bank-id__qr-code--image')
      # system('imgcat qr_code.jpg')
      # system('qlmanage -p qr_code.jpg 1>&- 2>&- &')
      sleep 1
      page.network.wait_for_idle(timeout: 1)
    end
    puts "\n"

    message = at_css("span[slot=message]")&.text
    if message&.include?('för lång tid')
      puts 'Timed out. Restarting login attempt...'
      at_css("acorn-button[label='Försök igen']").click
      page.network.wait_for_idle
    end
  end

  def download_all_payment_files
    page.network.clear(:traffic)
    page.go_to(absolute_url('/app/ib/dokument'))
    page.network.wait_for_idle
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
      doc['type'] == 'Redovisning camt.054' &&
      doc['name'].include?('betalningar') &&
      !Dir.glob('*.xml').any? do |file|
        file == BankPaymentsReader::PAYMENT_FILENAME_PATTERN.gsub(/\*/, doc['creationDate'])
      end # only non-downloaded files
    end
    ap documents
    # documents = documents.take(4)
    puts "Found #{documents.count} documents to download".cyan

    # page.network.clear(:cache)
    documents.map { |doc| download_file(id: doc['id'], headers: auth_headers) }
  end

  def download_file(id:, headers:)
    page.headers.set(headers)
    url_to_fetch_url = absolute_url('/TDE_DAP_Portal_REST_WEB/api/v5/message/document/'+id+'/view?referenceType=DOCUMENT_ID')
    page.go_to(url_to_fetch_url)
    
    page.network.wait_for_idle(timeout: 1) unless page.network.status == 200
    raise 'Download URL fetch failed' unless page.network.status == 200
    
    location_info = Oj.safe_load(page.at_css('pre').text)
    ticket = location_info['ticket']

    page.headers.set(page.headers.get)
    url_to_download = absolute_url('/'+location_info['url']+'?ticket='+ticket)
    page.go_to(url_to_download)
    
    page.network.wait_for_idle(timeout: 1) unless page.network.status == 200
    raise 'Download failed' unless page.network.status == 200

    filename = page.network.response.headers['Content-type'].match(/name="(.*)"/)[1]
    puts "Downloaded #{filename}".green
    filename
  end
  
  def parse
    filter_out_non_essentials
    page.network.wait_for_idle
    # page.screenshot(path: 'initial.jpg')

    accept_cookies
    page.network.wait_for_idle(timeout: 1)
    # page.screenshot(path: 'after_cookies.jpg')

    begin # if something goes wrong here, click button to abort login

      until at_css("p[data-cy='verify-yourself']")&.text == 'Legitimera dig i BankID-appen'
        input_login_and_get_qr_code
      end
      puts 'QR code picked up. Authenticate with BankID.'.yellow

      until at_css('acorn-section-header')&.attribute('heading') == 'Välj profil'
        sleep 0.2
        page.network.wait_for_idle
      end

      company_login = css('acorn-item').select{ |i| i.text.include?('Förskolan Solsidan') }.first
      raise 'Could not login as company' unless company_login
      company_login.click
      page.network.wait_for_idle

      print 'Logging in..'
      attempts = 0
      until at_css('h1')&.text == 'Välkommen!' && page.url.include?('start-page')
        raise 'Login timed out' if at_css('h1')&.text == "Du behöver logga in igen"
        raise 'Login took too long, please investigate' if attempts > 100
        print '.'
        sleep 0.05
        attempts += 1
      end
      puts "\n"

    rescue Exception => e # Rescue manual interrupt only?
      puts "\nError during login process. Aborting login.".red
      page.screenshot(path: 'error.jpg')
      at_css("acorn-button[label='Avbryt']")&.click
      page.network.wait_for_idle
      binding.pry
      unless e.is_a? Interrupt
        puts $! # e.message
        puts $@ # e.backtrace
      end
      raise e
    end

    begin

      puts 'Logged in. Reading files...'.green
      yield({ filenames: download_all_payment_files })

    rescue Exception => e # Rescue manual interrupt only?
      puts "\nError while getting files.".red
      page.screenshot(path: 'error_files.jpg')
      page.network.wait_for_idle
      binding.pry
      unless e.is_a? Interrupt
        puts $! # e.message
        puts $@ # e.backtrace
      end
      raise e
    end
  end

end

BankBuster.run do |result|
  BankPaymentsReader.parse_files(result[:filenames])
end


# puts "Requests received via Puffing Billy Proxy:"
# puts TablePrint::Printer.table_print(Billy.proxy.requests, [
#   :status,
#   :handler,
#   :method,
#   { url: { width: 100 } },
#   :headers,
#   :body
# ])

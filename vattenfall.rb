require 'dotenv/load'
require 'awesome_print'
require "json"
require 'ferrum'
require "vessel"
require 'oj'
require 'pry'
require 'pry-nav'
require 'colorize'

ID = ENV['VATTENFALL_ID']
PW = ENV['VATTENFALL_PW']

if ID.nil? || ID.empty?
  abort 'Customer ID needed for Vattenfall login'
elsif PW.nil? || PW.empty?
  abort 'Password needed for Vattenfall login'
end

# MAX_RETRIES = 3

class Vattenfall < Vessel::Cargo
  domain "vattenfalleldistribution.se"
  start_urls "https://www.vattenfalleldistribution.se/logga-in?pageId=6"
  
  INFO_INTERVAL = 20
  driver(:ferrum,
    browser_options: {
      'no-default-browser-check': true,
      'disable-extensions': true,
      'disable-translate': true,
      'mute-audio': true,
      'disable-sync': true
    },
    timeout: 10,
    process_timeout: 120
  )
  #"proxy-bypass-list": "<-loopback>"
  
  def wait_for_element(type: :xpath, selector: '')
    max_attempts = 10
    attempts = 0

    while attempts < max_attempts
      element = type == :css ? at_css(selector) : at_xpath(selector)
      return element if element

      sleep 1
      attempts += 1
    end

    raise "Element '#{selector}' not found after #{max_attempts} attempts"
  end

  def quit_browser
    original_stdout = $stdout.clone
    $stdout.reopen(File.new('/dev/null', 'w'))
    
    page &.browser &.quit

  rescue NoMethodError => e
    raise unless e.backtrace.first.include?("ferrum/browser.rb:240:in `quit'")  
  end

  def parse
    Signal.trap("TERM") do
      quit_browser
      exit
    end

    # page.browser.network.intercept
    # page.browser.on(:request) do |request|
    #   if ['Image','Font','Stylesheet'].include?(request.resource_type)
    #     request.abort
    #   else
    #     request.continue
    #   end
    # end
    page.network.wait_for_idle(timeout: 120)
    
    #page.screenshot(path:'before_vf_login.jpg')
    #ap css('button')
    #btn = wait_for_element(selector: "//button[text() = 'Customer number and password']")
    btn = at_css("button[variant='outline-secondary']")
    #btn = css('button')[2]
    #raise 'Could not find login button' unless btn.text == 'Customer number and password'
    btn.click

    f = at_css('form')
    customer_number_field = f.at_css('input[id=customerNumber]')
    customer_number_field.focus
    customer_number_field.type(ID, :enter)
    customer_pw_field = f.at_css('input[id=password]')
    customer_pw_field.focus
    customer_pw_field.type(PW, :enter)
    page.network.wait_for_idle(timeout: 120)
    # page.go_to 'https://www.vattenfalleldistribution.se/mina-sidor/elanvandning/'

    page.headers.set({
      "accept" => 'application/json, text/plain, */*',
      "ocp-apim-subscription-key" => '***REMOVED***'
    })
    today = Date.today
    if today.month == 1
      start_date = Date.new(today.year, 1, 1).strftime("%Y-%m-%d") # Jan 1st of the current year
    else
      start_date = Date.new(today.year - 1, today.month - 1, [28, today.day].min).strftime("%Y-%m-%d")
    end
    end_date = Date.new(today.year, today.month, -1).strftime("%Y-%m-%d") # last day of month

    puts "Fetching data for #{start_date} to #{end_date}...".yellow

    page.go_to "https://services.vattenfalleldistribution.se/consumption/consumption/HDG735999100004995459/#{start_date}/#{end_date}/Hourly/Measured?skipDts=true"
    begin
      page.network.wait_for_idle(timeout: 10)
    rescue Ferrum::TimeoutError
      puts "Timeout error. Might or might not affect data retrieval.".red
    end

    # begin
    #   page.go_to "https://services.vattenfalleldistribution.se/consumption/consumption/HDG735999100004995459/#{start_date}/#{end_date}/Hourly/Measured"
    #   page.network.wait_for_idle(timeout: 120)
    # rescue => Ferrum::TimeoutError
    #   puts "Timeout error. Might or might not affect data retrieval. Error message: #{e.message}.".red
    # end

    # measured = page.at_css('pre')&.text
    # puts measured
    # page.network.wait_for_idle(timeout: 120)

    # r = 0
    # begin
    #   page.go_to "https://services.vattenfalleldistribution.se/consumption/consumption/HDG735999100004995459/#{start_date}/#{end_date}/Hourly/Measured"
    #   page.network.wait_for_idle(timeout: 120)
    # rescue => Ferrum::TimeoutError
    #   r += 1
    #   if r < 3
    #     puts "Timeout error: #{e.message}. Retrying... (Attempt #{r})".red
    #     retry
    #   else
    #     puts "Timeout error: #{e.message}. Aborting after #{r} attempts.".red
    #   end
    # end
    
    measured = page.at_css('pre')&.text
    raise 'No data found' if measured.nil?
    yield Oj.safe_load(measured) # , mode: :strict, bigdecimal_load: :float, allow_gc: false
  ensure
    # This will execute regardless of any exceptions raised
    quit_browser
  end
end

# EXAMPLE:
#{"startDate"=>"2023-03-01T00:00:00", "endDate"=>"2023-03-07T23:38:01.6393038+00:00", "delta"=>nil, "unit"=>"kWh", "aggregationInterval"=>"Daily", "consumption"=>[{"date"=>"2023-03-01T00:00:00", "week"=>nil, "consumption"=>50}, {"date"=>"2023-03-02T00:00:00", "week"=>nil, "consumption"=>52}, {"date"=>"2023-03-03T00:00:00", "week"=>nil, "consumption"=>60}, {"date"=>"2023-03-04T00:00:00", "week"=>nil, "consumption"=>82}, {"date"=>"2023-03-05T00:00:00", "week"=>nil, "consumption"=>78}, {"date"=>"2023-03-06T00:00:00", "week"=>nil, "consumption"=>73}, {"date"=>"2023-03-07T00:00:00", "week"=>nil, "consumption"=>78}]}

Vessel::Logger.instance.level = ::Logger::WARN

Vattenfall.run do |fresh_data|
  stats = fresh_data['consumption'].map(&:compact)
  stats.each{|s| s['date'] = DateTime.parse(s['date']).new_offset('+02:00').iso8601 }
  # ap stats
  puts "Successfully fetched #{(stats.size / 24).round} days of data.".green
  puts "Last data recorded: #{DateTime.parse(stats.last['date']).strftime('%b %-d, %H.%M')}"
  Oj.to_file('electricity_usage.json', stats)
end

# ERROR:
# E, [2023-08-10T11:37:28.293112 #8051] ERROR -- : Engine: there was an issue while processing https://www.vattenfalleldistribution.se/logga-in?pageId=6
# E, [2023-08-10T11:37:28.297081 #8051] ERROR -- : Engine: `Ferrum::TimeoutError: Timed out waiting for response. It's possible that this happened because something took a very long time (for example a page load was slow). If so, setting the :timeout option to a higher value might help.`
# /home/pi/.rbenv/versions/3.1.0/lib/ruby/gems/3.1.0/gems/ferrum-0.13/lib/ferrum/network.rb:65:in `wait_for_idle'
# vattenfall.rb:92:in `parse'
# /home/pi/.rbenv/versions/3.1.0/lib/ruby/gems/3.1.0/bundler/gems/vessel-0dabb8c1a610/lib/vessel/engine.rb:57:in `handle'
# /home/pi/.rbenv/versions/3.1.0/lib/ruby/gems/3.1.0/bundler/gems/vessel-0dabb8c1a610/lib/vessel/engine.rb:132:in `event_loop'
# /home/pi/.rbenv/versions/3.1.0/lib/ruby/gems/3.1.0/bundler/gems/vessel-0dabb8c1a610/lib/vessel/engine.rb:34:in `run'
# <internal:kernel>:90:in `tap'
# /home/pi/.rbenv/versions/3.1.0/lib/ruby/gems/3.1.0/bundler/gems/vessel-0dabb8c1a610/lib/vessel/engine.rb:10:in `run'
# /home/pi/.rbenv/versions/3.1.0/lib/ruby/gems/3.1.0/bundler/gems/vessel-0dabb8c1a610/lib/vessel/cargo.rb:12:in `run'
# vattenfall.rb:105:in `<main>'


# ERROR:
# /home/pi/.rbenv/versions/3.1.0/lib/ruby/gems/3.1.0/gems/ferrum-0.13/lib/ferrum/page.rb:130:in `rescue in go_to': Request to https://services.vattenfalleldistribution.se/consumption/consumption/HDG735999100004995459/2023-03-01/2023-03-31/Daily/Measured reached server, but there are still pending connections: https://services.vattenfalleldistribution.se/consumption/consumption/HDG735999100004995459/2023-03-01/2023-03-31/Daily/Measured (Ferrum::PendingConnectionsError)
#   from /home/pi/.rbenv/versions/3.1.0/lib/ruby/gems/3.1.0/gems/ferrum-0.13/lib/ferrum/page.rb:113:in `go_to'
#   from vattenfall.rb:31:in `parse'
#   from /home/pi/.rbenv/versions/3.1.0/lib/ruby/gems/3.1.0/gems/vessel-0.2.0/lib/vessel/engine.rb:40:in `handle'
#   from /home/pi/.rbenv/versions/3.1.0/lib/ruby/gems/3.1.0/gems/vessel-0.2.0/lib/vessel/engine.rb:29:in `run'
#   from <internal:kernel>:90:in `tap'
#   from /home/pi/.rbenv/versions/3.1.0/lib/ruby/gems/3.1.0/gems/vessel-0.2.0/lib/vessel/engine.rb:6:in `run'
#   from /home/pi/.rbenv/versions/3.1.0/lib/ruby/gems/3.1.0/gems/vessel-0.2.0/lib/vessel/cargo.rb:19:in `run'
#   from vattenfall.rb:42:in `<main>'
# /home/pi/.rbenv/versions/3.1.0/lib/ruby/gems/3.1.0/gems/ferrum-0.13/lib/ferrum/browser/client.rb:46:in `command': Timed out waiting for response. It's possible that this happened because something took a very long time (for example a page load was slow). If so, setting the :timeout option to a higher value might help. (Ferrum::TimeoutError)
#   from /home/pi/.rbenv/versions/3.1.0/lib/ruby/gems/3.1.0/gems/ferrum-0.13/lib/ferrum/page.rb:276:in `command'
#   from /home/pi/.rbenv/versions/3.1.0/lib/ruby/gems/3.1.0/gems/ferrum-0.13/lib/ferrum/page.rb:116:in `go_to'
#   from vattenfall.rb:31:in `parse'
#   from /home/pi/.rbenv/versions/3.1.0/lib/ruby/gems/3.1.0/gems/vessel-0.2.0/lib/vessel/engine.rb:40:in `handle'
#   from /home/pi/.rbenv/versions/3.1.0/lib/ruby/gems/3.1.0/gems/vessel-0.2.0/lib/vessel/engine.rb:29:in `run'
#   from <internal:kernel>:90:in `tap'
#   from /home/pi/.rbenv/versions/3.1.0/lib/ruby/gems/3.1.0/gems/vessel-0.2.0/lib/vessel/engine.rb:6:in `run'
#   from /home/pi/.rbenv/versions/3.1.0/lib/ruby/gems/3.1.0/gems/vessel-0.2.0/lib/vessel/cargo.rb:19:in `run'
#   from vattenfall.rb:42:in `<main>'
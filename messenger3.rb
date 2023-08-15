require "vessel"
require "dotenv/load"

class Messenger < Vessel::Cargo
  domain "www.messenger.com"
  start_urls "https://www.messenger.com/"

  def parse
    accept_cookies
    login(ENV['MESSENGER_EMAIL'], ENV['MESSENGER_PASSWORD'])

    conversation_links = css('a[href^="/t/"]')
    conversation_links.each do |link|
      link.click
      # Initialize current timestamp
      current_timestamp = nil
      # Extract the sender's name
      sender_name = css('h1 span').text
      # Extract the messages and timestamps
      elements = css('div[role="row"]')
      elements.each do |element|
        if element.attribute('data-scope') == 'date_break'
          # This is a timestamp
          timestamp_text = element.css('span span').first.text
          if timestamp_text.start_with?('Yesterday')
            time_parts = timestamp_text.split(' ')[1..-1] # ['at', '2:47', 'PM']
            time_of_day = Time.parse(time_parts[1..-1].join(' ')) # 2:47 PM
            yesterday = Date.today - 1
            current_timestamp = Time.new(yesterday.year, yesterday.month, yesterday.day, time_of_day.hour, time_of_day.min)
          elsif timestamp_text.start_with?('Today')
            time_parts = timestamp_text.split(' ')[1..-1] # ['at', '1:11', 'PM']
            time_of_day = Time.parse(time_parts[1..-1].join(' ')) # 1:11 PM
            today = Date.today
            current_timestamp = Time.new(today.year, today.month, today.day, time_of_day.hour, time_of_day.min)
          else
            # This is a timestamp for an earlier date
            date_parts = timestamp_text.split(' ') # ['June', '29', 'at', '8:32', 'PM']
            month = Date::MONTHNAMES.index(date_parts[0])
            day = date_parts[1].to_i
            time_of_day = Time.parse(date_parts[3..-1].join(' ')) # 8:32 PM
            year = Date.today.year
            current_timestamp = Time.new(year, month, day, time_of_day.hour, time_of_day.min)
          end
        elsif element.attribute('style') && element.attribute('style').include?('--mwp-reply-background-color')
          # This is a message
          text = element.text
          # Do something with the text, sender_name and current_timestamp...
        end
      end
    end
  end

  private

  def accept_cookies
    click_button('button[data-cookiebanner="accept_button"]')
  end

  def login(email, password)
    type_into_field('#email', email)
    type_into_field('#pass', password)
    click_button('#loginbutton')
  end

  def click_button(selector)
    button = wait_for_element(selector)
    button.click
  end

  def type_into_field(selector, text)
    field = wait_for_element(selector)
    field.type(text)
  end

  def wait_for_element(selector)
    max_attempts = 10
    attempts = 0

    while attempts < max_attempts
      element = at_css(selector)
      return element if element

      sleep 1
      attempts += 1
    end

    raise "Element '#{selector}' not found after #{max_attempts} attempts"
  end
end

Messenger.run
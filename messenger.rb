require "vessel"
require "dotenv/load"

class Messenger < Vessel::Cargo
  domain "www.messenger.com"
  start_urls "https://www.messenger.com/"

  def parse
    accept_cookies
    login(ENV['MESSENGER_EMAIL'], ENV['MESSENGER_PASSWORD'])
    # Further steps will go here...
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

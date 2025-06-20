#!/usr/bin/env ruby

old_chromium_count = 0
old_ruby_count = 0

loop do
  # Count the number of Chromium processes
  chromium_count = `ps aux | grep -v grep | grep chromium`.split("\n").size

  # Count the number of Ruby processes
  ruby_count = `ps aux | grep -v grep | grep ruby`.split("\n").size

  # Compare and print if the numbers change
  if chromium_count != old_chromium_count
    puts "Chromium processes: #{chromium_count}"
    old_chromium_count = chromium_count
  end

  if ruby_count != old_ruby_count
    puts "Ruby processes: #{ruby_count}"
    old_ruby_count = ruby_count
  end

  # Sleep for a while before the next iteration
  sleep 5
end


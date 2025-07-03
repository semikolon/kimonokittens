#!/bin/bash

# Initialize variables to hold the previous counts
old_chromium_count=0
old_ruby_count=0

while true; do
  # Count the number of Chromium processes
  chromium_count=$(ps aux | grep -v grep | grep chromium | wc -l)

  # Count the number of Ruby processes
  ruby_count=$(ps aux | grep -v grep | grep ruby | wc -l)

  # Compare and echo if the numbers change
  if [ "$chromium_count" -ne "$old_chromium_count" ]
  then
    echo "Chromium processes: $chromium_count"
    old_chromium_count=$chromium_count
  fi

  if [ "$ruby_count" -ne "$old_ruby_count" ]
  then
    echo "Ruby processes: $ruby_count"
    old_ruby_count=$ruby_count
  fi

  # Sleep for a while before the next iteration
  sleep 5
done


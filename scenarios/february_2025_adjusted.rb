require_relative '../rent'
require 'awesome_print'

# February 2025 Rent Calculation (Adjusted)
# - Includes January 2025 electricity bills (due in February)
# - Excludes December 2024 electricity bills (handled separately)

MONTH_CONFIG = {
  year: 2025,
  month: 1,
  kallhyra: 24_530,
  el: 2_918 + 1_845, # January's bills (Vattenfall + Fortum)
  bredband: 380,
  vattenavgift: 375,
  drift_rakning: nil  # No quarterly invoice this month
}

ROOMMATES = {
  'Fredrik' => {},
  'Rasmus' => {},
  'Frans-Lukas' => {},
  'Elvira' => {}
}

# Calculate and save the rent breakdown
results = RentCalculator.calculate_and_save(
  roommates: ROOMMATES,
  config: MONTH_CONFIG,
  history_options: {
    title: "February 2025 - With January electricity (December handled separately)",
    version: 1
  }
)

puts "\nFebruary 2025 Rent (due January 27):"
puts "================================================="
puts "Includes January's electricity bills"
puts "December's electricity bills handled separately"
puts "\nDetailed Breakdown:"
ap results

puts "\nFriendly Message for Messenger:"
puts RentCalculator.friendly_message(roommates: ROOMMATES, config: MONTH_CONFIG)

puts "\nNOTE: Remember that December's electricity bills (4,226 kr) are handled separately!" 
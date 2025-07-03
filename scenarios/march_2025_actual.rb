require_relative '../rent'
require 'awesome_print'

# Actual March 2025 Rent Calculation (Payment due February 27)
# Using actual February 2025 electricity bills:
# 1. Vattenfall (grid costs): 3,668.23 kr
# 2. Fortum (consumption): 2,277.00 kr
# Total electricity: 5,945.23 kr
#
# NOTE: Frans-Lukas has moved out, so rent is now split between 3 people

MONTH_CONFIG = {
  year: 2025,
  month: 2,  # February (payment due February 27th for March stay)
  kallhyra: 24_530,    # Base rent
  el: 3_668 + 2_277,   # Actual February electricity bills
  bredband: 380,       # Internet
  drift_rakning: nil,  # No quarterly invoice this month
  saldo_innan: 0,      # Assuming no balance carried over
  extra_in: 0,         # No extra income expected
  vattenavgift: 375    # Regular water fee
}

# Current roommates with their adjustments
ROOMMATES = {
  'Fredrik' => {},      # No adjustments
  'Rasmus' => {},      # No adjustments
  'Elvira' => {}       # No adjustments
  # Frans-Lukas has moved out
}

# Calculate and save the rent breakdown
results = RentCalculator.calculate_and_save(
  roommates: ROOMMATES,
  config: MONTH_CONFIG,
  history_options: {
    title: "March 2025 - Actual Bills (Frans-Lukas moved out)",
    version: 9
  }
)

puts "\nActual March 2025 Rent (Due February 27)"
puts "============================================"
puts "This calculation includes:"
puts "1. Actual February electricity costs:"
puts "   - Vattenfall: 3,668.23 kr"
puts "   - Fortum: 2,277.00 kr"
puts "   - Total: 5,945.23 kr"
puts "2. Regular monthly fees (internet, water, etc.)"
puts "3. NOTE: Frans-Lukas has moved out, rent split between 3 people"
puts "\nDetailed Breakdown:"
ap results

puts "\nFriendly Message for Messenger:"
puts RentCalculator.friendly_message(roommates: ROOMMATES, config: MONTH_CONFIG) 
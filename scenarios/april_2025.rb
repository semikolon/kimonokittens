require_relative '../rent'
require 'awesome_print'

# April 2025 Scenario
# Month is set to 3 (March) because:
# 1. Payment is due March 27th
# 2. We're using March's electricity bills that arrived in early April
# 3. The payment month determines when the payment is due
#
# This calculation includes all four roommates:
# - Fredrik, Rasmus, Elvira (full month)
# - Adam (full month)

MONTH_CONFIG = {
  year: 2025,
  month: 3,  # March (when payment is due)
  kallhyra: 24_530,    # Base rent
  el: 3_330.98 + 2_605, # March electricity (Vattenfall 3,330.98 + Fortum 2,605)
  bredband: 380,       # Internet
  drift_rakning: nil,  # No quarterly invoice expected
  saldo_innan: 0,      # No previous balance
  extra_in: 0,         # No extra income
  vattenavgift: 375    # Regular water fee
}

# All roommates for a full month in April
ROOMMATES = {
  'Fredrik' => {},      # Full month
  'Rasmus' => {},       # Full month
  'Elvira' => {},       # Full month
  'Adam' => {}          # Full month
}

# Calculate and save the rent breakdown
results = RentCalculator.calculate_and_save(
  roommates: ROOMMATES,
  config: MONTH_CONFIG,
  history_options: {
    title: "April 2025 - All Four Roommates",
    version: 1,
    force: true
  }
)

puts "\nApril 2025 Rent Calculation"
puts "============================"
puts "Using latest electricity bills from March 2025:"
puts "1. Vattenfall (grid): 3,330.98 kr"
puts "2. Fortum (consumption): 2,605.00 kr"
puts "3. Total electricity: 5,935.98 kr"
puts "\nDetailed Breakdown:"
ap results

puts "\nFriendly Message for Messenger:"
puts RentCalculator.friendly_message(roommates: ROOMMATES, config: MONTH_CONFIG) 
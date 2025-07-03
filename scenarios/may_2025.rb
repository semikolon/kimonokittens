require_relative '../rent'
require 'awesome_print'

# May 2025 Scenario
# Month is set to 4 (April) because:
# 1. Payment is due April 27th
# 2. We're using April's electricity bills
# 3. The payment month determines when the payment is due
#
# This calculation includes:
# - All four roommates for full month
# - Expected quarterly invoice (drift_rakning)
# - Latest electricity bills from April

MONTH_CONFIG = {
  year: 2025,
  month: 4,  # April (when payment is due)
  kallhyra: 24_530,    # Base rent
  el: 2_878.34 + 1_520, # April electricity (Vattenfall 2,878.34 + Fortum 1,520)
  bredband: 380,       # Internet
  #drift_rakning: 2_612, # Expected quarterly invoice (replacing monthly fees)
  saldo_innan: 0,      # No previous balance
  extra_in: 0,         # No extra income
  #vattenavgift: nil    # Included in drift_rakning
}

# All roommates for a full month in May
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
    title: "May 2025 - With Quarterly Invoice",
    version: 1,
    force: true
  }
)

puts "\nMay 2025 Rent Calculation"
puts "========================="
puts "Using latest electricity bills from April 2025:"
puts "1. Vattenfall (grid): 2,878.34 kr"
puts "2. Fortum (consumption): 1,520.00 kr"
puts "3. Total electricity: 4,398.34 kr"
puts "\nQuarterly invoice (drift_rakning): 2,612 kr"
puts "Note: This replaces the usual monthly fees (vattenavgift, va, larm)"
puts "\nDetailed Breakdown:"
ap results

puts "\nFriendly Message for Messenger:"
puts RentCalculator.friendly_message(roommates: ROOMMATES, config: MONTH_CONFIG) 
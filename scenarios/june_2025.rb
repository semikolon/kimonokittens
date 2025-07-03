require_relative '../rent'
require 'awesome_print'

# June 2025 Scenario
# Month is set to 5 (May) because:
# 1. Payment is due May 27th
# 2. We're using May's electricity bills
# 3. The payment month determines when the payment is due
#
# This calculation includes:
# - All four roommates for full month
# - Expected quarterly invoice (drift_rakning)
# - Latest electricity bills from May

MONTH_CONFIG = {
  year: 2025,
  month: 5,  # May (when payment is due)
  kallhyra: 24_530,    # Base rent
  el: 2269.30 + 1050, # May electricity (Vattenfall 2269.30 + Fortum 1050)
  bredband: 380,       # Internet
  #drift_rakning: 2_612, # Expected quarterly invoice (replacing monthly fees)
  saldo_innan: 0,      # No previous balance
  extra_in: 0,         # No extra income
  #vattenavgift: nil    # Included in drift_rakning
}

# All roommates for a full month in June
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
    title: "June 2025 - With Quarterly Invoice",
    version: 1,
    force: true
  }
)

puts "\nJune 2025 Rent Calculation"
puts "========================="
puts "Using latest electricity bills from May 2025:"
puts "1. Vattenfall (grid): 2,269.30 kr"
puts "2. Fortum (consumption): 1,050.00 kr"
puts "3. Total electricity: 3,319.30 kr"
puts "\nDetailed Breakdown:"
ap results

puts "\nFriendly Message for Messenger:"
puts RentCalculator.friendly_message(roommates: ROOMMATES, config: MONTH_CONFIG) 
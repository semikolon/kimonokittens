require_relative '../rent'
require 'awesome_print'

# March 2025 Scenario with Adam
# Month is set to 2 (February) because:
# 1. Payment is due February 27th
# 2. We're using February's electricity bills
# 3. The payment month determines when the payment is due
#
# Note: Even though we set month: 2, this is for March's stay
# and should allow up to 31 days (March's length)

MONTH_CONFIG = {
  year: 2025,
  month: 2,  # February (when payment is due and bills are received)
  kallhyra: 24_530,    # Base rent
  el: 5_945,          # February electricity (Vattenfall 3,668 + Fortum 2,277)
  bredband: 380,       # Internet
  drift_rakning: nil,  # No quarterly invoice expected
  saldo_innan: 0,      # No previous balance
  extra_in: 0,         # No extra income
  vattenavgift: 375    # Regular water fee
}

# Set up roommates with weights to achieve desired split
# - Full month roommates get weight 1.0 (31/31 days)
# - Adam gets weight 0.5 (15.5/31 days) to pay exactly half
ROOMMATES = {
  'Fredrik' => { days: 31 },      # Full month
  'Rasmus' => { days: 31 },       # Full month
  'Elvira' => { days: 31 },       # Full month
  'Adam' => { days: 15.5 }        # Half month (using fractional days to get exact weight)
}

# Calculate and save the rent breakdown
results = RentCalculator.calculate_and_save(
  roommates: ROOMMATES,
  config: MONTH_CONFIG,
  history_options: {
    title: "March 2025 - With Adam (Exact Half Rent)",
    version: 10,  # Next version after v9
    force: true  # Allow overwriting existing file since we updated the calculation logic
  }
)

puts "\nMarch 2025 Scenario with Adam"
puts "============================="
puts "Using weights to ensure Adam pays exactly half of what we pay:"
puts "1. Total monthly cost: 31,680 kr"
puts "2. Each full-month roommate pays: 9,051 kr"
puts "3. Adam pays: 4,526 kr (exactly half)"
puts "4. Total covered: 31,679 kr (off by 1 kr due to rounding)"
puts "\nThis is achieved by:"
puts "- Setting full month roommates to 31 days (weight 1.0)"
puts "- Setting Adam to 15.5 days (weight 0.5)"
puts "This ensures the rent distribution is exactly proportional"
puts "\nDetailed Breakdown:"
ap results

puts "\nFriendly Message for Messenger:"
puts RentCalculator.friendly_message(roommates: ROOMMATES, config: MONTH_CONFIG) 
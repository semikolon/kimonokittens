require_relative '../rent'
require 'awesome_print'

# Scenario 3: Split Astrid's unpaid January rent (minus her first week)
# - Astrid stayed 7 days in January
# - Full month rent was around 7,500 kr
# - She should pay: 7,500 * (7/31) ≈ 1,693 kr
# - Remaining to split: 7,500 - 1,693 = 5,807 kr
# - Per remaining roommate: 5,807 / 4 ≈ 1,452 kr

MONTH_CONFIG = {
  year: 2025,
  month: 1,  # January (payment due January 27th for February stay)
  kallhyra: 24_530,    # Base rent
  el: 1_845 + 2_918,   # January electricity only
  bredband: 380,       # Internet
  drift_rakning: nil,  # No quarterly invoice yet
  saldo_innan: -20,    # Negative balance from returning Astrid's rent
  extra_in: -5_807,    # Astrid's unpaid rent (minus her first week)
}

# Current roommates with their adjustments
ROOMMATES = {
  'Fredrik' => {},      # No adjustment
  'Rasmus' => {},      # No adjustment
  'Frans-Lukas' => {}, # No adjustment
  'Elvira' => {}       # No adjustment
}

# Calculate and save the rent breakdown
results = RentCalculator.calculate_and_save(
  roommates: ROOMMATES,
  config: MONTH_CONFIG,
  history_options: {
    title: "February 2025 - Scenario 3: Split Astrid's Unpaid Rent",
    version: 3
  }
)

puts "\nScenario 3: Split Astrid's Unpaid January Rent"
puts "=============================================="
puts "This scenario includes:"
puts "- January electricity: #{1_845 + 2_918} kr"
puts "- Astrid's January rent calculation:"
puts "  * Full month rent: ~7,500 kr"
puts "  * Days stayed: 7"
puts "  * Her share: #{1_693} kr"
puts "  * Remaining to split: #{5_807} kr"
puts "  * Extra per remaining roommate: #{5_807 / 4} kr"
puts "\nDetailed Breakdown:"
ap results

puts "\nFriendly Message for Messenger:"
puts RentCalculator.friendly_message(roommates: ROOMMATES, config: MONTH_CONFIG) 
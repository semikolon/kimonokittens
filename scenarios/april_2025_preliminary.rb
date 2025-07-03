require_relative '../rent'
require 'awesome_print'

# Updated Preliminary Scenario for April 2025 (Payment due end of March)
# Using projected March 2025 electricity costs with latest trend analysis:
# 1. Vattenfall (grid costs):
#    - March 2024: 2,730.21 kr
#    - Projected 15% increase based on February's actual bills
#    - March 2025 estimate: 3,140 kr
# 2. Fortum (consumption):
#    - March 2024: 1,589.00 kr
#    - Projected 25% decrease based on February's actual bills
#    - March 2025 estimate: 1,192 kr
# Total projected: 4,332 kr
#
# NOTE: Frans-Lukas has moved out, so rent is now split between 3 people

MONTH_CONFIG = {
  year: 2025,
  month: 3,  # March (payment due March 27th for April stay)
  kallhyra: 24_530,    # Base rent
  el: 4_332,          # Projected March electricity (revised trend analysis)
  bredband: 380,       # Internet
  drift_rakning: nil,  # No quarterly invoice expected
  saldo_innan: 0,      # Assuming no balance carried over
  extra_in: 0,         # No extra income expected
  vattenavgift: 375    # Regular water fee
}

# Current roommates after Frans-Lukas moved out
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
    title: "April 2025 - Updated Projection (3 Roommates)",
    version: 2
  }
)

puts "\nUpdated Preliminary Scenario for April 2025 (Due end of March)"
puts "==========================================="
puts "This scenario includes:"
puts "1. Projected March electricity costs:"
puts "   Vattenfall (grid):"
puts "   - March 2024: 2,730.21 kr"
puts "   - Projected +15% based on February's actual trend"
puts "   - March 2025 estimate: 3,140 kr"
puts "\n   Fortum (consumption):"
puts "   - March 2024: 1,589.00 kr"
puts "   - Projected -25% based on February's actual trend"
puts "   - March 2025 estimate: 1,192 kr"
puts "\n   Total projected: 4,332 kr"
puts "2. Regular monthly fees (internet, water, etc.)"
puts "3. NOTE: Frans-Lukas has moved out, rent split between 3 people"
puts "\nDetailed Breakdown:"
ap results

puts "\nFriendly Message for Messenger:"
puts RentCalculator.friendly_message(roommates: ROOMMATES, config: MONTH_CONFIG) 
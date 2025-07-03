require_relative '../rent'
require 'awesome_print'

# Preliminary Scenario for March 2025 (Payment due end of February)
# Using projected February 2025 electricity costs with split analysis:
# 1. Vattenfall (grid costs):
#    - February 2024: 3,300.38 kr
#    - Projected 25% increase based on recent months (+20-45% trend)
#    - February 2025 estimate: 4,125 kr
# 2. Fortum (consumption):
#    - February 2024: 3,017.00 kr
#    - Projected 30% decrease based on consistent trend
#    - February 2025 estimate: 2,112 kr
# Total projected: 6,237 kr

MONTH_CONFIG = {
  year: 2025,
  month: 2,  # February (payment due February 27th for March stay)
  kallhyra: 24_530,    # Base rent
  el: 6_237,          # Projected February electricity (split analysis)
  bredband: 380,       # Internet
  drift_rakning: nil,  # No quarterly invoice expected
  saldo_innan: 0,      # Assuming no balance carried over
  extra_in: 0,         # No extra income expected
  vattenavgift: 375    # Regular water fee
}

# Current roommates with their adjustments
ROOMMATES = {
  'Fredrik' => {},      # No adjustments
  'Rasmus' => {},      # No adjustments
  'Frans-Lukas' => {}, # No adjustments
  'Elvira' => {}       # No adjustments
}

# Calculate and save the rent breakdown
results = RentCalculator.calculate_and_save(
  roommates: ROOMMATES,
  config: MONTH_CONFIG,
  history_options: {
    title: "March 2025 - Split Projection (Grid +25%, Consumption -30%)",
    version: 8
  }
)

puts "\nPreliminary Scenario for March 2025 (Due end of February)"
puts "==========================================="
puts "This scenario includes:"
puts "1. Projected February electricity costs:"
puts "   Vattenfall (grid):"
puts "   - February 2024: 3,300.38 kr"
puts "   - Projected +25% based on recent trend"
puts "   - February 2025 estimate: 4,125 kr"
puts "\n   Fortum (consumption):"
puts "   - February 2024: 3,017.00 kr"
puts "   - Projected -30% based on trend"
puts "   - February 2025 estimate: 2,112 kr"
puts "\n   Total projected: 6,237 kr"
puts "2. Regular monthly fees (internet, water, etc.)"
puts "\nDetailed Breakdown:"
ap results

puts "\nFriendly Message for Messenger:"
puts RentCalculator.friendly_message(roommates: ROOMMATES, config: MONTH_CONFIG) 
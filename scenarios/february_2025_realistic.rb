require_relative '../rent'
require 'awesome_print'

# Realistic Scenario for February 2025
# 1. Pay all December electricity now (4,226 kr)
# 2. Add 1/3 of January electricity (4,763 / 3 ≈ 1,588 kr)
# 3. Count on Astrid's payment for her week (1,099 kr)
# 4. Split Astrid's unpaid portion (3,770 kr) between Fredrik, Frans-Lukas, and Elvira
# 5. Remaining January electricity will be split over March/April

MONTH_CONFIG = {
  year: 2025,
  month: 1,  # January (payment due January 27th for February stay)
  kallhyra: 24_530,    # Base rent
  el: 1_757 + 2_469,   # December electricity (must be paid)
  bredband: 380,       # Internet
  drift_rakning: nil,  # No quarterly invoice yet
  saldo_innan: 193,    # Current house account balance
  extra_in: 1_099,     # Expected from Astrid for Jan 1-7
  # Add 1/3 of January electricity as additional cost
  vattenavgift: (1_845 + 2_918) / 3  # One third of January electricity
}

# Current roommates with their adjustments
# Rasmus gets -1,257 kr adjustment to exclude him from Astrid's unpaid portion (3,770 kr / 3)
# This means Fredrik, Frans-Lukas, and Elvira will each pay 1,257 kr more than Rasmus
ROOMMATES = {
  'Fredrik' => {},      # Will pay normal share + portion of Astrid's unpaid rent
  'Rasmus' => {
    room_adjustment: -1_257  # Excluded from Astrid's unpaid portion
  },
  'Frans-Lukas' => {}, # Will pay normal share + portion of Astrid's unpaid rent
  'Elvira' => {}       # Will pay normal share + portion of Astrid's unpaid rent
}

# Calculate and save the rent breakdown
results = RentCalculator.calculate_and_save(
  roommates: ROOMMATES,
  config: MONTH_CONFIG,
  history_options: {
    title: "February 2025 - Realistic Phased Approach (Split Adjusted)",
    version: 5
  }
)

puts "\nRealistic Scenario for February 2025 (Adjusted Split)"
puts "=================================================="
puts "This scenario includes:"
puts "1. December electricity (must pay): #{1_757 + 2_469} kr"
puts "2. One third of January electricity: #{(1_845 + 2_918) / 3} kr"
puts "3. Previous balance: #{193} kr"
puts "4. Expected from Astrid (Jan 1-7): #{1_099} kr"
puts "5. Astrid's unpaid portion (#{3_770} kr) split between Fredrik, Frans-Lukas, and Elvira"
puts "\nRemaining to handle in March/April:"
puts "- Remaining January electricity: #{(1_845 + 2_918) * 2/3} kr"
puts "  (Will add ~#{(1_845 + 2_918) / 3} kr per month)"
puts "\nDetailed Breakdown:"
ap results

puts "\nFriendly Message for Messenger:"
puts RentCalculator.friendly_message(roommates: ROOMMATES, config: MONTH_CONFIG) 
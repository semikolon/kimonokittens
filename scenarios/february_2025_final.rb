require_relative '../rent'
require 'awesome_print'

# Final Scenario for February 2025
# 1. Pay all December electricity now (4,226 kr)
# 2. Pay all January electricity now (4,763 kr)
# 3. Count on Astrid's payment for her week (1,099 kr)
# 4. Split Astrid's unpaid portion (3,770 kr):
#    - Fredrik: 50% (1,885 kr)
#    - Frans-Lukas: 25% (942.50 kr)
#    - Elvira: 25% (942.50 kr)
#    - Rasmus: 0% (excluded)

MONTH_CONFIG = {
  year: 2025,
  month: 1,  # January (payment due January 27th for February stay)
  kallhyra: 24_530,    # Base rent
  el: (1_757 + 2_469) + (1_845 + 2_918),   # All December + January electricity
  bredband: 380,       # Internet
  drift_rakning: nil,  # No quarterly invoice yet
  saldo_innan: 193,    # Current house account balance
  extra_in: 1_099,     # Expected from Astrid for Jan 1-7
  vattenavgift: 375    # Regular water fee
}

# Current roommates with their adjustments
ROOMMATES = {
  'Fredrik' => {
    room_adjustment: 942  # Extra portion compared to FL/E (50% vs 25%)
  },
  'Rasmus' => {
    room_adjustment: -942  # Excluded from the normal 25% share
  },
  'Frans-Lukas' => {},  # Normal 25% share
  'Elvira' => {}       # Normal 25% share
}

# Calculate and save the rent breakdown
results = RentCalculator.calculate_and_save(
  roommates: ROOMMATES,
  config: MONTH_CONFIG,
  history_options: {
    title: "February 2025 - Final Agreement",
    version: 8
  }
)

puts "\nFinal Scenario for February 2025"
puts "=============================="
puts "This scenario includes:"
puts "1. All December electricity: #{1_757 + 2_469} kr"
puts "2. All January electricity: #{1_845 + 2_918} kr"
puts "3. Previous balance: #{193} kr"
puts "4. Expected from Astrid (Jan 1-7): #{1_099} kr"
puts "5. Astrid's unpaid portion (#{3_770} kr) split:"
puts "   - Fredrik: 50% (#{3_770 * 0.5} kr)"
puts "   - Frans-Lukas: 25% (#{3_770 * 0.25} kr)"
puts "   - Elvira: 25% (#{3_770 * 0.25} kr)"
puts "   - Rasmus: 0% (excluded)"
puts "\nNo electricity bills remaining for March/April"
puts "\nDetailed Breakdown:"
ap results

puts "\nFriendly Message for Messenger:"
puts RentCalculator.friendly_message(roommates: ROOMMATES, config: MONTH_CONFIG) 
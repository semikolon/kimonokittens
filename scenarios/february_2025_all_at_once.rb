require_relative '../rent'
require 'awesome_print'

# Pay Everything Scenario for February 2025
# - All December electricity (4,226 kr)
# - All January electricity (4,763 kr)
# - Count on Astrid's payment for Jan 1-7 (1,099 kr)
# Total electricity to pay: 8,989 kr
# Net cost after Astrid's payment: 7,890 kr

MONTH_CONFIG = {
  year: 2025,
  month: 1,  # January (payment due January 27th for February stay)
  kallhyra: 24_530,    # Base rent
  el: (1_757 + 2_469) + (1_845 + 2_918),  # All December + January electricity
  bredband: 380,       # Internet
  drift_rakning: nil,  # No quarterly invoice yet
  saldo_innan: 193,    # Current house account balance
  extra_in: 1_099,     # Expected from Astrid for Jan 1-7
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
    title: "February 2025 - Pay Everything At Once",
    version: 5
  }
)

puts "\nPay Everything Scenario for February 2025"
puts "========================================"
puts "This scenario includes:"
puts "1. All December electricity: #{1_757 + 2_469} kr"
puts "2. All January electricity: #{1_845 + 2_918} kr"
puts "3. Previous balance: #{-20} kr"
puts "4. Expected from Astrid (Jan 1-7): #{1_099} kr"
puts "\nTotal electricity bills: #{8_989} kr"
puts "Net cost after Astrid's payment: #{8_989 - 1_099} kr"
puts "Extra per person (compared to normal month): #{(8_989 - 1_099 - 4_763) / 4} kr"
puts "\nDetailed Breakdown:"
ap results

puts "\nFriendly Message for Messenger:"
puts RentCalculator.friendly_message(roommates: ROOMMATES, config: MONTH_CONFIG) 
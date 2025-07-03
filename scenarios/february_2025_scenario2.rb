require_relative '../rent'
require 'awesome_print'

# Scenario 2: Split extra costs over 3 months (February, March, April)
# Total extra costs: 9,009 kr (8,989 electricity + 20 balance)
# Monthly extra: 3,003 kr

MONTH_CONFIG = {
  year: 2025,
  month: 1,  # January (payment due January 27th for February stay)
  kallhyra: 24_530,    # Base rent
  el: 1_845 + 2_918,   # Only January's electricity
  bredband: 380,       # Internet
  drift_rakning: nil,  # No quarterly invoice yet
  saldo_innan: -20,    # Negative balance from returning Astrid's rent
  extra_in: 0,         # No extra income
  # Adding 1/3 of December's electricity to this month
  vattenavgift: (1_757 + 2_469) / 3  # Spreading December's electricity over 3 months
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
    title: "February 2025 - Scenario 2: Extra Costs Split Over 3 Months",
    version: 2
  }
)

puts "\nScenario 2: Extra Costs Split Over 3 Months"
puts "==========================================="
puts "This scenario includes:"
puts "- January electricity: #{1_845 + 2_918} kr"
puts "- 1/3 of December electricity: #{(1_757 + 2_469) / 3} kr"
puts "- 1/3 of negative balance: #{-20 / 3} kr"
puts "Monthly extra per person: #{3_003 / 4} kr"
puts "\nNote: Same extra amount will be added in March and April"
puts "\nDetailed Breakdown:"
ap results

puts "\nFriendly Message for Messenger:"
puts RentCalculator.friendly_message(roommates: ROOMMATES, config: MONTH_CONFIG) 
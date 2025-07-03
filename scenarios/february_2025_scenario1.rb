require_relative '../rent'
require 'awesome_print'

# Scenario 1: Include all late invoices in February's rent
# - December electricity (Fortum 1,757 + Vattenfall 2,469)
# - January electricity (Fortum 1,845 + Vattenfall 2,918)
# Total late electricity: 8,989 kr

MONTH_CONFIG = {
  year: 2025,
  month: 1,  # January (payment due January 27th for February stay)
  kallhyra: 24_530,    # Base rent
  el: (1_757 + 2_469) + (1_845 + 2_918),  # December + January electricity
  bredband: 380,       # Internet
  drift_rakning: nil,  # No quarterly invoice yet
  saldo_innan: -20,    # Negative balance from returning Astrid's rent
  extra_in: 0          # No extra income
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
    title: "February 2025 - Scenario 1: All Late Invoices Included",
    version: 1
  }
)

puts "\nScenario 1: All Late Invoices Included in February"
puts "================================================="
puts "This scenario includes:"
puts "- December electricity: #{1_757 + 2_469} kr"
puts "- January electricity: #{1_845 + 2_918} kr"
puts "- Negative balance from Astrid's returned rent"
puts "Total extra costs: #{8_989 + 20} kr"
puts "\nDetailed Breakdown:"
ap results

puts "\nFriendly Message for Messenger:"
puts RentCalculator.friendly_message(roommates: ROOMMATES, config: MONTH_CONFIG) 
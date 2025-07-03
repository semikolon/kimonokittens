require_relative 'rent'
require 'awesome_print'

# January 2025 configuration (for February's rent)
MONTH_CONFIG = {
  year: 2025,
  month: 1,  # January (payment due January 27th for February stay)
  kallhyra: 24_530,    # Base rent
  el: 1_845 + 2_918,   # Fortum (1,845) + Vattenfall (2,918)
  bredband: 380,       # Internet
  drift_rakning: nil,  # Update if quarterly invoice arrives
  saldo_innan: 20,     # Previous balance from December
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
    title: "January 2025 Calculation (February Rent)",
    version: 1  # Explicitly set version 1
  }
)

# Print both detailed and friendly formats
puts "\nDetailed Breakdown:"
ap results

puts "\nFriendly Message for Messenger:"
puts RentCalculator.friendly_message(roommates: ROOMMATES, config: MONTH_CONFIG) 
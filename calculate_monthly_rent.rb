require_relative 'rent'
require 'awesome_print'

# Monthly configuration - Update these values each month
MONTH_CONFIG = {
  year: Time.now.year,
  month: Time.now.month,
  kallhyra: 24_530,    # Base rent (usually constant)
  el: 2_470 + 1_757,           # Update with current electricity cost
  bredband: 380,       # Internet (usually constant)
  drift_rakning: nil,  # Update with quarterly invoice when available
  saldo_innan: 20,      # Previous balance
  extra_in: 0          # Extra income
}

# Current roommates with their adjustments
ROOMMATES = {
  'Fredrik' => {},      # No adjustment
  'Rasmus' => {},      # No adjustment
  'Frans-Lukas' => {}, # No adjustment
  'Astrid' => {
    room_adjustment: -1400 # Fixed discount for smaller room
  },
  'Elvira' => {}       # No adjustment
}

# Calculate and save the rent breakdown
results = RentCalculator.calculate_and_save(
  roommates: ROOMMATES,
  config: MONTH_CONFIG,
  history_options: {
    title: "#{Time.now.strftime('%B')} #{Time.now.year} Rent Calculation"
  }
)

# Print both detailed and friendly formats
puts "\nDetailed Breakdown:"
ap results

puts "\nFriendly Message for Messenger:"
puts RentCalculator.friendly_message(roommates: ROOMMATES, config: MONTH_CONFIG) 
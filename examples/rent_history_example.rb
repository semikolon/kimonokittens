require_relative '../lib/rent_history'
require_relative '../rent'  # To use the actual calculation for v2

# Real-world example showing November 2024's rent calculation and version history.
# See README.md for full documentation on the RentHistory system.

# Important Implementation Note:
# v1 uses rent_november.rb which had a simpler approach to partial months and adjustments
# v2 uses the current rent.rb which has improved handling of:
# - Partial month stays (properly weighted by days)
# - Room adjustments (prorated based on days stayed)
# - More precise floating-point calculations

# First calculation (before Elvira)
november_v1 = RentHistory::Month.new(
  year: 2024,
  month: 11,
  version: 1,
  title: "Initial November Calculation (Pre-Elvira)"
)

# Set up the base costs from rent.rb
november_v1.constants = {
  kallhyra: 24_530,    # Base rent from rent.rb
  el: 1_324 + 276,     # Electricity
  bredband: 400,       # Internet
  drift_rakning: 2_612,# Quarterly invoice
  saldo_innan: 400,    # Previous balance from rent.rb
  extra_in: 0          # No extra income for November
}

# Set up the roommates with actual November data (before Elvira)
november_v1.roommates = {
  'Fredrik' => {
    days: 30,              # Full month
    room_adjustment: 0     # No adjustment
  },
  'Rasmus' => {
    days: 30,             # Full month
    room_adjustment: 0    # No adjustment
  },
  'Frans-Lukas' => {
    days: 30,             # Full month
    room_adjustment: 0    # No adjustment
  },
  'Astrid' => {
    days: 15,             # Half month
    room_adjustment: -1400 # Discount for smaller room
  },
  'Malin' => {
    days: 30,             # Full month
    room_adjustment: -1900 # Discount
  }
}

# Record the actual historical payments for v1
# These numbers can be verified by running rent_november.rb
# which uses the original calculation method with flat adjustments
november_v1.record_results({
  'Fredrik' => 6408.00,
  'Rasmus' => 6408.00,
  'Frans-Lukas' => 6408.00,
  'Astrid' => 5008.00,
  'Malin' => 4508.00
})

# Save first version
november_v1.save  # Will save as 2024_11_v1.json

# Note: After v2 calculation, reimbursements were made:
# - Malin: 259 kr
# - Others (Fredrik, Rasmus, Frans-Lukas): 339 kr each
# This was due to the recalculation with Elvira's partial stay and improved calculation method

# Second calculation (with Elvira)
november_v2 = RentHistory::Month.new(
  year: 2024,
  month: 11,
  version: 2,
  title: "November Recalculation with Elvira's Partial Stay"
)

# Set up the constants - documenting exactly what they were at the time
november_v2.constants = {
  kallhyra: 24_530,    # Base rent
  el: 1_324 + 276,     # Electricity
  bredband: 400,       # Internet
  drift_rakning: 2_612,# Quarterly invoice (replaces vattenavgift, va, larm)
  saldo_innan: 400,    # Previous balance
  extra_in: 0          # No extra income
}

# Set up roommates with updated data
november_v2.roommates = {
  'Fredrik' => {
    days: 30,              # Full month
    room_adjustment: 0     # No adjustment
  },
  'Rasmus' => {
    days: 30,             # Full month
    room_adjustment: 0    # No adjustment
  },
  'Frans-Lukas' => {
    days: 30,             # Full month
    room_adjustment: 0    # No adjustment
  },
  'Astrid' => {
    days: 15,             # Half month
    room_adjustment: -1400 # Always has discount for smaller room
  },
  'Malin' => {
    days: 21,             # Updated stay duration
    room_adjustment: 0    # Using day-weighting instead of flat adjustment
  },
  'Elvira' => {
    days: 8,              # 8 days as specified
    room_adjustment: 0    # No adjustment
  }
}

# Calculate v2 using the current rent.rb calculator
results = RentCalculator.rent_breakdown(november_v2.roommates, november_v2.constants)
november_v2.record_results(results['Rent per Roommate'])

# Save second version
november_v2.save  # Will save as 2024_11_v2.json

# List all versions available for November 2024
versions = RentHistory::Month.versions(year: 2024, month: 11)
puts "\nAvailable versions for November 2024:"
versions.each do |v|
  month = RentHistory::Month.load(year: 2024, month: 11, version: v)
  puts "Version #{v}: #{month.title}"
end

# This example demonstrates:
# 1. How to create and manage versions with titles
# 2. Handling mid-month changes (Elvira joining for 8 days)
# 3. Room adjustments (Astrid's smaller room discount)
# 4. Drift rakning (quarterly invoice) handling
# 5. Historical record keeping including reimbursements
# 6. Production vs test mode separation
  
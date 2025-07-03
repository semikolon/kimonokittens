require_relative '../rent'
require 'awesome_print'

# Averaged Monthly Rent Calculation
# Using averaged electricity costs to even out seasonal variations
# Based on actual monthly totals from April 2023 to January 2025
# (excluding March 2023 due to anomalously low values):
# Total electricity costs: 61,289.16 kr
# Number of complete months: 22
# Actual average: 2,785.87 kr/month

MONTH_CONFIG = {
  year: 2025,
  month: 2,  # February (for March rent)
  kallhyra: 24_530,    # Base rent
  el: 2_786,          # Actual average electricity cost (rounded up)
  bredband: 380,       # Internet
  vattenavgift: 375,   # Regular monthly fees
  drift_rakning: nil   # No quarterly invoice this month
}

# Current roommates with their adjustments
ROOMMATES = {
  'Fredrik' => {},
  'Rasmus' => {},
  'Frans-Lukas' => {},
  'Elvira' => {}
}

# Calculate and save the rent breakdown
results = RentCalculator.calculate_and_save(
  roommates: ROOMMATES,
  config: MONTH_CONFIG,
  history_options: {
    title: "Averaged Monthly Rent (Based on 22-month Average, excluding March 2023)",
    version: 5
  }
)

puts "\nAveraged Monthly Rent Calculation"
puts "================================================="
puts "Using actual average from April 2023 to January 2025"
puts "(excluding March 2023 due to anomalously low values):"
puts "Total electricity costs: 61,289.16 kr"
puts "Number of complete months: 22"
puts "Monthly average: 2,785.87 kr"
puts "\nMonthly totals used in calculation (Vattenfall + Fortum):"
puts "2023:"
puts "Apr: 4,639.00 kr    Aug: 1,167.00 kr    Dec: 4,483.00 kr"
puts "May: 2,878.00 kr    Sep: 1,348.00 kr"
puts "Jun: 1,975.00 kr    Oct: 1,082.00 kr"
puts "Jul: 1,529.00 kr    Nov: 2,112.00 kr"
puts "\n2024:"
puts "Jan: 4,638.79 kr    May: 3,284.84 kr    Sep: 1,301.64 kr"
puts "Feb: 6,317.38 kr    Jun: 1,856.35 kr    Oct: 1,599.36 kr"
puts "Mar: 4,319.21 kr    Jul: 1,496.81 kr    Nov: 2,208.65 kr"
puts "Apr: 4,207.93 kr    Aug: 1,263.54 kr    Dec: 4,226.48 kr"
puts "\n2025:"
puts "Jan: 4,763.18 kr"
puts "\nDetailed Breakdown:"
ap results

puts "\nFriendly Message for Messenger:"
puts RentCalculator.friendly_message(roommates: ROOMMATES, config: MONTH_CONFIG) 
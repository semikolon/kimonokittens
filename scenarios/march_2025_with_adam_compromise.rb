require_relative '../rent'
require 'awesome_print'

# March 2025 Final Scenario
# 
# Final agreement:
# - March rent already paid by 3 people (Fredrik, Rasmus, Elvira): 10,560 kr each
# - Adam joining for exactly half the month (16 days, March 16-31)
# - All roommates (Fredrik, Rasmus, Elvira) get equal refunds

# Calculate what Adam would pay for half a month (16 days)
MONTH_CONFIG = {
  year: 2025,
  month: 2,  # February (payment due February 27th for March stay)
  kallhyra: 24_530,    # Base rent
  el: 3_668 + 2_277,   # Actual February electricity bills
  bredband: 380,       # Internet
  drift_rakning: nil,  # No quarterly invoice this month
  saldo_innan: 0,      # Assuming no balance carried over
  extra_in: 0,         # No extra income expected
  vattenavgift: 375    # Regular water fee
}

# Calculate Adam's payment for 16 days (March 16-31, exactly half the month)
ROOMMATES_HALF_MONTH = {
  'Fredrik' => {},          # Full month
  'Rasmus' => {},          # Full month
  'Elvira' => {},          # Full month
  'Adam' => { days: 16 }   # Half month (March 16-31)
}

results = RentCalculator.rent_breakdown(roommates: ROOMMATES_HALF_MONTH, config: MONTH_CONFIG)

# Original payment that was made (3 roommates)
original_payment_per_person = 10_560
total_already_paid = original_payment_per_person * 3

# Adam's payment for half month
adams_payment = results["Rent per Roommate"]["Adam"]

# Full month roommate payment after Adam joins
new_full_month_payment = results["Rent per Roommate"]["Fredrik"]

# Calculate equal refund for all three roommates
refund_per_person = original_payment_per_person - new_full_month_payment

# Final effective rents after refunds
new_effective_rent = original_payment_per_person - refund_per_person

# Save the final calculation
final_results = {
  "Original Payments" => {
    "Fredrik" => original_payment_per_person,
    "Rasmus" => original_payment_per_person,
    "Elvira" => original_payment_per_person,
    "Total" => total_already_paid
  },
  "Final Arrangement" => {
    "Fredrik" => new_effective_rent,
    "Rasmus" => new_effective_rent,
    "Elvira" => new_effective_rent,
    "Adam" => adams_payment,
    "Total" => (new_effective_rent * 3) + adams_payment
  },
  "Refunds" => {
    "Fredrik" => refund_per_person,
    "Rasmus" => refund_per_person,
    "Elvira" => refund_per_person,
    "Total Refunds" => refund_per_person * 3
  }
}

puts "\nMarch 2025 Final Arrangement (Adam paying for half month)"
puts "=============================================="
puts "Final agreement:"
puts "- March rent already paid: 10,560 kr per person"
puts "- Adam joining for exactly half the month (16 days, March 16-31)"
puts "- All roommates get equal refunds"

puts "\nCalculation Details:"
puts "--------------------------------------"
puts "Days in March: 31 days"
puts "Half of March: 15.5 days (rounded to 16 days)"
puts "Adam pays: #{adams_payment} kr (for 16 days, March 16-31)"
puts "Each roommate gets back: #{refund_per_person} kr"

puts "\nFinal Effective Rents:"
puts "--------------------------------------"
puts "Fredrik: #{new_effective_rent} kr"
puts "Rasmus: #{new_effective_rent} kr"
puts "Elvira: #{new_effective_rent} kr"
puts "Adam: #{adams_payment} kr"
puts "Total: #{final_results["Final Arrangement"]["Total"]} kr"

puts "\nVerification:"
puts "--------------------------------------"
puts "Original total rent: #{results["Total"]} kr"
puts "Sum with final arrangement: #{final_results["Final Arrangement"]["Total"]} kr"
puts "Difference: #{(results["Total"] - final_results["Final Arrangement"]["Total"]).round} kr"

puts "\nFriendly Messaging:"
puts "--------------------------------------"
puts "Adam: Din hyra för mars blir *#{adams_payment} kr* (för 16 dagar, exakt halva månaden)"
puts "Fredrik, Rasmus & Elvira: Ni får tillbaka *#{refund_per_person} kr* var" 
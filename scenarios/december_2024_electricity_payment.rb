require_relative '../rent'
require 'awesome_print'

# December 2024 Electricity Bills (Overdue)
# - Vattenfall: 2,469.48 kr (due 2025-01-02)
# - Fortum: 1,757.00 kr (due 2025-01-03)
# Total: 4,226.48 kr
# Note: Fredrik covers both his and Rasmus's shares

total_electricity = 2_469.48 + 1_757.00
per_person = (total_electricity / 4.0).ceil

puts "\nDecember 2024 Electricity Bills (Overdue)"
puts "==========================================="
puts "Bills to pay:"
puts "1. Vattenfall: 2,469.48 kr (due 2025-01-02)"
puts "2. Fortum: 1,757.00 kr (due 2025-01-03)"
puts "\nTotal: #{total_electricity} kr"
puts "Per person (rounded up): #{per_person} kr"
puts "\nPayment breakdown:"
puts "- Fredrik: #{per_person * 2} kr (covering both Fredrik and Rasmus)"
puts "- Frans-Lukas: #{per_person} kr"
puts "- Elvira: #{per_person} kr"
puts "\nFriendly Message for Messenger:"
puts "*Överförda elräkningar från december 2024*"
puts "Vi behöver betala dessa nu:"
puts "- Frans-Lukas och Elvira: swisha *#{per_person} kr* var till Fredrik"
puts "- Fredrik betalar sin och Rasmus del (#{per_person * 2} kr)"
puts "så snart som möjligt så han kan betala räkningarna." 
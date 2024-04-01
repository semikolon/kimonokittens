require 'oj'
require 'date'

# Read the JSON file
file_path = '/Users/fredrikbranstrom/Dropbox/Code/kimonokittens/tibber_price_data.json'
file_content = File.read(file_path)
data = Oj.load(file_content)

# Initialize a hash to store the sum of prices and count for each hour
hourly_prices = Hash.new { |hash, key| hash[key] = { sum: 0.0, count: 0 } }

# Process each entry in the JSON data
data.each do |timestamp, price|
  hour = DateTime.parse(timestamp).hour
  hourly_prices[hour][:sum] += price
  hourly_prices[hour][:count] += 1
end

# Calculate the average price for each hour
average_prices = {}
hourly_prices.each do |hour, values|
  average_prices[hour] = values[:sum] / values[:count]
end

# Sort by average price to find the cheapest hours
sorted_average_prices = average_prices.sort_by { |hour, avg_price| avg_price }

# Output the average prices in ascending order
sorted_average_prices.each do |hour, avg_price|
  puts "Hour: #{hour}, Average Price: #{'%.4f' % avg_price}"
end

# Find the cheapest hour
cheapest_hour = sorted_average_prices.first
puts "Cheapest Hour: #{cheapest_hour[0]}, Average Price: #{'%.4f' % cheapest_hour[1]}"
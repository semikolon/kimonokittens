require 'faraday'
require 'faraday/excon'
require 'oj'
require 'dotenv/load'
require 'awesome_print'
require 'colorize'

def find_cheapest_hours
  tibber_prices = Oj.load_file('tibber_price_data.json')
    
  avg_price_per_kwh = tibber_prices.values.sum / tibber_prices.count
  
  # Sortera timmarna baserat på pris
  lowest = tibber_prices.sort_by { |date, price| price }
  lowest_hours = lowest.map { |date, price| { hour: DateTime.parse(date).strftime("%H"), price: price } }
  lowest_hours = lowest_hours.group_by { |hour| hour[:hour] }

  # Beräkna genomsnittspriset för varje timme
  average_prices = lowest_hours.map do |hour, prices|
    average_price = prices.sum { |price| price[:price] } / prices.size.to_f
    { hour: hour, average_price: average_price }
  end

  # Sortera listan baserat på det genomsnittliga priset
  sorted_hours = average_prices.sort_by { |h| h[:average_price] }

  # Skriv ut de timmar med lägst genomsnittligt pris
  sorted_hours.first(20).each do |h|
    puts "Hour: #{h[:hour]}, Average price: #{h[:average_price]}"
  end
end

def fetch_tibber_data
  conn = Faraday.new(url: 'https://api.tibber.com/v1-beta/gql') do |f|
    f.headers['Authorization'] = "Bearer #{ENV['TIBBER_API_KEY']}"
    f.headers['Content-Type'] = 'application/json'
    f.adapter :excon
  end

  number_of_days = 62 # 7 * 5

  query = "{
    viewer {
      homes {
        currentSubscription {
          priceInfo {
            range(resolution: HOURLY, last: #{24 * number_of_days}) {
              nodes {
                total
                startsAt
              }
            }
          }
        }
      }
    }
  }"
    
  response = conn.post do |req|
    req.body = Oj.dump({query: query}, mode: :compat)
  end

  data = Oj.load(response.body)
  
  # Skapa en hash med datum och tid som nycklar och elpriser som värden
  price_data = {}
  data['data']['viewer']['homes'][0]['currentSubscription']['priceInfo']['range']['nodes'].each do |edge|
    time = DateTime.parse(edge['startsAt']).new_offset('+02:00').iso8601
    price = edge['total']
    price_data[time] = price
  end

  price_data
end

def fetch_and_store_tibber_data
  price_data = fetch_tibber_data
  # log how many days we fetched prices for
  puts "Fetched prices for #{price_data.count / 24} days, up until #{DateTime.parse(price_data.keys.last).strftime("%Y-%m-%d")}".green
  Oj.to_file('tibber_price_data.json', price_data)
end

fetch_and_store_tibber_data

#find_cheapest_hours

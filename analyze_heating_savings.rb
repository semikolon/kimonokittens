#!/usr/bin/env ruby
require 'json'
require 'date'

# Load consumption data
data = JSON.parse(File.read('electricity_usage.json'))

# Swedish holidays for 2025
holidays_2025 = [
  Date.new(2025, 1, 1),   # New Year's Day
  Date.new(2025, 1, 6),   # Epiphany
  Date.new(2025, 4, 18),  # Good Friday
  Date.new(2025, 4, 20),  # Easter Sunday
  Date.new(2025, 4, 21),  # Easter Monday
  Date.new(2025, 5, 1),   # Labor Day
  Date.new(2025, 5, 29),  # Ascension Day
  Date.new(2025, 6, 6),   # National Day
  Date.new(2025, 6, 8),   # Whitsun
  Date.new(2025, 6, 9),   # Whit Monday
  Date.new(2025, 6, 20),  # Midsummer Eve
  Date.new(2025, 6, 21),  # Midsummer Day
  Date.new(2025, 11, 1),  # All Saints' Day
  Date.new(2025, 12, 24), # Christmas Eve
  Date.new(2025, 12, 25), # Christmas Day
  Date.new(2025, 12, 26), # Boxing Day
  Date.new(2025, 12, 31)  # New Year's Eve
]

def is_peak_hour?(datetime, holidays)
  # Summer months (Apr-Oct) have NO peak pricing
  return false unless [1, 2, 3, 11, 12].include?(datetime.month)

  # Weekends have NO peak pricing
  return false if [0, 6].include?(datetime.wday)  # Sunday=0, Saturday=6

  # Holidays have NO peak pricing
  date_only = Date.new(datetime.year, datetime.month, datetime.day)
  return false if holidays.include?(date_only)

  # Peak hours: 06:00-22:00 (local time)
  datetime.hour >= 6 && datetime.hour < 22
end

# Analyze February 2025 (peak winter month)
feb_data = data.select { |h| DateTime.parse(h['date']).month == 2 && DateTime.parse(h['date']).year == 2025 }

peak_kwh = 0.0
offpeak_kwh = 0.0
peak_hours_count = 0
offpeak_hours_count = 0

feb_data.each do |hour|
  dt = DateTime.parse(hour['date'])
  consumption = hour['consumption'].to_f

  if is_peak_hour?(dt, holidays_2025)
    peak_kwh += consumption
    peak_hours_count += 1
  else
    offpeak_kwh += consumption
    offpeak_hours_count += 1
  end
end

total_kwh = peak_kwh + offpeak_kwh

puts "=== FEBRUARI 2025 FÖRBRUKNINGSANALYS ==="
puts ""
puts "Total förbrukning: #{total_kwh.round(1)} kWh"
puts ""
puts "Höglasttid (peak):"
puts "  Timmar: #{peak_hours_count} (#{(peak_hours_count.to_f / feb_data.size * 100).round(1)}%)"
puts "  Förbrukning: #{peak_kwh.round(1)} kWh (#{(peak_kwh / total_kwh * 100).round(1)}%)"
puts ""
puts "Låglasttid (off-peak):"
puts "  Timmar: #{offpeak_hours_count} (#{(offpeak_hours_count.to_f / feb_data.size * 100).round(1)}%)"
puts "  Förbrukning: #{offpeak_kwh.round(1)} kWh (#{(offpeak_kwh / total_kwh * 100).round(1)}%)"
puts ""

# Constants from electricity_projector.rb
GRID_PEAK = 0.536  # kr/kWh excl VAT
GRID_OFFPEAK = 0.214  # kr/kWh excl VAT
VAT = 1.25

grid_diff_incl_vat = (GRID_PEAK - GRID_OFFPEAK) * VAT

puts "=== BESPARINGSPOTENTIAL ==="
puts ""
puts "Överföringskostnad skillnad (inkl moms): #{(grid_diff_incl_vat * 1000).round(2)} öre/kWh"
puts ""

# Heating assumption: 75% of consumption is heating (from HeatingCostCalculator)
heating_fraction = 0.75
heating_kwh = total_kwh * heating_fraction
other_kwh = total_kwh * (1 - heating_fraction)

puts "Antagande: #{(heating_fraction * 100).round}% av förbrukningen är uppvärmning"
puts "  Uppvärmning: #{heating_kwh.round(1)} kWh"
puts "  Övrigt (disk, dammsugare, dator, etc): #{other_kwh.round(1)} kWh"
puts ""

# Current situation: heating follows same peak/offpeak distribution as total consumption
heating_peak_ratio = peak_kwh / total_kwh
heating_currently_peak = heating_kwh * heating_peak_ratio
heating_currently_offpeak = heating_kwh * (1 - heating_peak_ratio)

puts "Nuvarande situation (värme följer total fördelning):"
puts "  Värme under höglast: #{heating_currently_peak.round(1)} kWh"
puts "  Värme under låglast: #{heating_currently_offpeak.round(1)} kWh"
puts ""

# Scenario 1: Move ALL heating to off-peak
savings_per_month_max = heating_currently_peak * grid_diff_incl_vat

puts "SCENARIO 1: Flytta ALL uppvärmning till låglast"
puts "  Besparing per månad (feb nivå): #{savings_per_month_max.round} kr"
puts ""

# Scenario 2: Move 80% of heating to off-peak (realistic with temperature constraints)
realistic_shift = 0.80
heating_shiftable = heating_currently_peak * realistic_shift
savings_per_month_realistic = heating_shiftable * grid_diff_incl_vat

puts "SCENARIO 2: Flytta 80% av uppvärmningen till låglast (realistiskt)"
puts "  (20% måste köras höglast för temperatur/varmvatten)"
puts "  Besparing per månad (feb nivå): #{savings_per_month_realistic.round} kr"
puts ""

# Calculate for all peak months (Jan, Feb, Mar, Nov, Dec)
# Use seasonal multipliers to estimate other months
# Feb is the peak at 2.04x, we'll use that as baseline
puts "=== ÅRLIG BESPARING (5 VINTERMÅNADER) ==="
puts ""

# Estimate based on Feb being highest consumption month
# Jan, Nov, Dec: ~70% of Feb consumption
# Mar: ~95% of Feb consumption
# Average across 5 months: ~84% of Feb consumption

winter_months_avg_factor = 0.84
avg_winter_savings_realistic = savings_per_month_realistic * winter_months_avg_factor

puts "Genomsnittlig vintermånad (84% av feb-nivå):"
puts "  Scenario 1 (100% flyttad): #{(savings_per_month_max * winter_months_avg_factor).round} kr/mån"
puts "  Scenario 2 (80% flyttad): #{avg_winter_savings_realistic.round} kr/mån"
puts ""
puts "Årlig besparing (5 månader):"
puts "  Scenario 1: #{(savings_per_month_max * winter_months_avg_factor * 5).round} kr/år"
puts "  Scenario 2: #{(avg_winter_savings_realistic * 5).round} kr/år"
puts ""

# Per person (4 roommates)
savings_per_person_year = (avg_winter_savings_realistic * 5) / 4.0

puts "Per person (4 hyresgäster):"
puts "  Scenario 2: #{savings_per_person_year.round} kr/år (#{(savings_per_person_year / 12).round} kr/mån)"
puts ""

puts "=== PRAKTISKA BEGRÄNSNINGAR ==="
puts ""
puts "Thermiq värmepump optimering:"
puts "  • EVU låsning: Kan förhindra kompressor under dyra timmar"
puts "  • Varmvatten: Måste produceras regelbundet (kan inte vänta 16+ timmar)"
puts "  • Temperatur-override: Node-RED säkerhet håller +20°C minimum"
puts "  • Realistiskt: 70-90% av uppvärmning kan flyttas till låglast"
puts ""
puts "Scenario 2 (80% flytt) är konservativ uppskattning med god marginal."

require 'json'
require 'colorize'
require 'awesome_print'

# Fasta kostnader
KALLHYRA = 24530

EL = 2103 + 1074 # Vattenfall + Fortum (förfallodatum sista juni)
BREDBAND = 400
VATTENAVGIFT = 375
VA = 300
LARM = 150
SOP_SACKAR = 570

# Skriv in totalen från ev räkning från Bostadsagenturen de månader sådan kommer (kvartalsvis)
DRIFT_RAKNING = nil # 2612
DRIFT = EL + BREDBAND + SOP_SACKAR + (DRIFT_RAKNING || (VATTENAVGIFT + VA + LARM))

ROOMIES = ['Fredrik', 'Elvira', 'Rasmus', 'Adam']
ROOMIES_COUNT = ROOMIES.length

SALDO_INNAN = 0
EXTRA_IN = 0 # Amandas van

# Metod för att beräkna den totala hyran
def calculate_total_rent
  (KALLHYRA + DRIFT) - SALDO_INNAN - EXTRA_IN
end

# Metod fr att beräkna hyran per rumskamrat
def rent_per_roomie
  total_rent = calculate_total_rent
  # Dela upp hyran jämnt mellan rumskamraterna...

  base_rent_per_roomie = total_rent / ROOMIES_COUNT
  adjusted_rent = {}
  ROOMIES.each do |roomie|
    adjusted_rent[roomie] = base_rent_per_roomie
  end
  adjusted_rent
end

# Metod som returnerar en detaljerad uppdelning av hyran i JSON-format
def rent_breakdown
  {
    'Kallhyra' => KALLHYRA,
    'El' => EL,
    'Bredband' => BREDBAND,
    'Vattenavgift' => VATTENAVGIFT,
    'VA (Avloppsavgift)' => VA,
    'Larm' => LARM,
    'Drift total' => DRIFT,
    'Total' => calculate_total_rent,
    'Rent per roomie' => rent_per_roomie
  }
end

ap rent_breakdown

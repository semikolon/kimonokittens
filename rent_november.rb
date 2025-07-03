require 'json'
require 'colorize'
require 'awesome_print'

# Fasta kostnader
KALLHYRA = 24530

EL = 1324 + 276 #Nov
#Dec 1727 + 482
#Max 3300 + 3017
BREDBAND = 400
VATTENAVGIFT = 375
VA = 300
LARM = 150

# Skriv in totalen från ev räkning från Bostadsagenturen de månader sådan kommer (kvartalsvis)
DRIFT_RAKNING = 2612
DRIFT = EL + BREDBAND + (DRIFT_RAKNING || (VATTENAVGIFT + VA + LARM))

ROOMIES = ['Fredrik', 'Rasmus', 'Frans-Lukas', 'Astrid', 'Malin']
ROOMIES_COUNT = ROOMIES.length

SALDO_INNAN = 400
EXTRA_IN = 0 # Amandas van

# Metod för att beräkna den totala hyran
def calculate_total_rent
  (KALLHYRA + DRIFT) - SALDO_INNAN - EXTRA_IN
end

# Metod fr att beräkna hyran per rumskamrat
def rent_per_roomie
  total_rent = calculate_total_rent
  # Dela upp hyran jämnt mellan rumskamraterna...
  # Förutom Astrid som ska få ett avdrag på 1400 kr
  # eftersom hennes rum inte har god ventilation osv
  deduction_astrid = 1400
  deduction_malin = 1900

  base_rent_per_roomie = (total_rent + deduction_astrid + deduction_malin) / ROOMIES_COUNT
  adjusted_rent = {}
  ROOMIES.each do |roomie|
    if roomie == 'Astrid'
      adjusted_rent[roomie] = base_rent_per_roomie - deduction_astrid
    elsif roomie == 'Malin'
      adjusted_rent[roomie] = base_rent_per_roomie - deduction_malin  
    else
      adjusted_rent[roomie] = base_rent_per_roomie
    end
  end
  if (adjusted_rent['Fredrik'] - adjusted_rent['Astrid']) != deduction_astrid
    puts "Error: The difference between Fredrik's and Astrid's rent should be #{deduction} SEK."
  end
  # Adding Amanda as a temporary roomie with her EXTRA_IN rent
  adjusted_rent['Amanda'] = EXTRA_IN
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

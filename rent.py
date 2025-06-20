params = {}
# "params" are all the user inputs
# "steps" are all the inputs and outputs from previous steps
# There are several functions prepackaged in this code
# Documentation: https://relevanceai.com/docs/tool/tool-steps/python-code/code-python-helper-functions

# Make sure your code includes a return at the end if you want to use 
# the output in subsequent steps.

electricity_bills_max = 3300 + 3017
params['electricity_bills'] = params.get('electricity_bills', electricity_bills_max / 2)
params['drift_bill_this_month'] = params.get('drift_bill_this_month', None)

# Fasta kostnader
KALLHYRA = 24530

EL = params['electricity_bills']
BREDBAND = 428
VATTENAVGIFT = 375
VA = 300
LARM = 150

# Skriv in totalen från ev räkning från Bostadsagenturen de månader sådan kommer (kvartalsvis)
DRIFT = EL + BREDBAND + (params['drift_bill_this_month'] or (VATTENAVGIFT + VA + LARM))

ROOMIES = ['Fredrik', 'Malin', 'Rasmus', 'Frans-Lukas', 'Astrid']
ROOMIES_COUNT = len(ROOMIES)

SALDO_INNAN = 0
EXTRA_IN = 0 # Amandas van

# Metod för att beräkna den totala hyran
def calculate_total_rent():
  return (KALLHYRA + DRIFT) - SALDO_INNAN - EXTRA_IN


# Metod fr att beräkna hyran per rumskamrat
def rent_per_roomie():
  total_rent = calculate_total_rent()
  # Dela upp hyran jämnt mellan rumskamraterna...
  # Förutom Astrid som ska få ett avdrag på 1400 kr
  # eftersom hennes rum inte har god ventilation osv
  deduction = 1400

  base_rent_per_roomie = (total_rent + deduction) / ROOMIES_COUNT
  adjusted_rent = {}
  for roomie in ROOMIES:
    if roomie == 'Astrid':
      adjusted_rent[roomie] = base_rent_per_roomie - deduction
    else:
      adjusted_rent[roomie] = base_rent_per_roomie
    
  
  if (adjusted_rent['Fredrik'] - adjusted_rent['Astrid']) != deduction:
    print("Error: The difference between Fredrik's and Astrid's rent should be #{deduction} SEK.")
  
  # Adding Amanda as a temporary roomie with her EXTRA_IN rent
  adjusted_rent['Amanda'] = EXTRA_IN
  return adjusted_rent

# Metod som returnerar en detaljerad uppdelning av hyran i JSON-format
def rent_breakdown():
  return {
    'Kallhyra': KALLHYRA,
    'El': EL,
    'Bredband': BREDBAND,
    'Vattenavgift': VATTENAVGIFT,
    'VA (Avloppsavgift)': VA,
    'Larm': LARM,
    'Drift total': DRIFT,
    'Total': calculate_total_rent(),
    'Rent per roomie': rent_per_roomie()
  }

print(rent_breakdown())
#return {"params" : params, "steps": steps, "rent_breakdown": rent_breakdown()}
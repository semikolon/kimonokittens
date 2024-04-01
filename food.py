vikt_kg = 105
hojd_cm = 185
alder_ar = 37  # Uppdaterad ålder
aktivitetsfaktor_mattlig = 1.4  # Antagande om måttlig aktivitet

# Låg aktivitet (lätt eller ingen träning): BMR x 1.2
# Lätt aktivitet (lätt träning/sport 1-3 dagar/vecka): BMR x 1.375
# Måttlig aktivitet (måttlig träning/sport 3-5 dagar/vecka): BMR x 1.55
# Hög aktivitet (hård träning/sport 6-7 dagar i veckan): BMR x 1.725
# Mycket hög aktivitet (mycket hård träning/sport och fysiskt arbete): BMR x 1.9

# Beräkna BMR och TDEE
BMR = 10 * vikt_kg + 6.25 * hojd_cm - 5 * alder_ar + 5
TDEE_mattlig = BMR * aktivitetsfaktor_mattlig

# Antagande: 2 fasta dagar per vecka
fasta_dagar_per_vecka = 2
veckans_dagar = 7

# Calculate non-fasting-adjusted weekly TDEE for comparison
non_fasting_adjusted_weekly_TDEE = TDEE_mattlig * veckans_dagar

# Justera TDEE för fasta (anta att du inte konsumerar något under fastedagar)
justerat_kaloriintag_per_atdag = (TDEE_mattlig * veckans_dagar) / (veckans_dagar - fasta_dagar_per_vecka)
justerat_TDEE = justerat_kaloriintag_per_atdag * (veckans_dagar - fasta_dagar_per_vecka)

print(f"Beräknad BMR: {BMR:.2f} kalorier per dag")
print(f"Beräknad TDEE med måttlig aktivitet: {TDEE_mattlig:.2f} kalorier per dag")

# Print the non-fasting-adjusted weekly TDEE for comparison
print(f"Non-fasting-adjusted weekly TDEE: {non_fasting_adjusted_weekly_TDEE:.2f} kalorier")

# Since the fasting-adjusted TDEE calculation already considers the total weekly intake,
# it should be the same as the non-fasting-adjusted weekly TDEE.
print(f"Fasting-adjusted weekly TDEE: {justerat_TDEE:.2f} kalorier")

print(f"Justerat kaloriintag per ätdag med hänsyn till fasta: {justerat_kaloriintag_per_atdag:.2f} kalorier")

print(f"------")

# Proteinbehov baserat på gram per kg kroppsvikt
protein_behov_per_dag = 1.3 * vikt_kg

# Kalorier från protein (1 g protein = 4 kalorier)
kalorier_protein = protein_behov_per_dag * 4


# Proportioner
prop_agg = 0.16
prop_kyckling = 0.32
prop_kalkon = 0.25
prop_notkott = 0.27

# Antag att övriga kalorier fördelas mellan fett och kolhydrater med hänsyn till makronutrienter.

# Information om proteininnehåll i olika livsmedel (g per portion)
protein_per_agg = 6
protein_per_kyckling = 30
protein_per_kalkon = 29
protein_per_notkott = 26

# Beräkna mängden av varje proteinkälla per dag
agg_behov_per_dag = (protein_behov_per_dag * prop_agg) / protein_per_agg
kyckling_behov_per_dag_g = (protein_behov_per_dag * prop_kyckling) / protein_per_kyckling * 100
kalkon_behov_per_dag_g = (protein_behov_per_dag * prop_kalkon) / protein_per_kalkon * 100
notkott_behov_per_dag_g = (protein_behov_per_dag * prop_notkott) / protein_per_notkott * 100

kyckling_behov_enbart_per_dag_g = protein_behov_per_dag / protein_per_kyckling * 100
notkott_behov_enbart_per_dag_g = protein_behov_per_dag / protein_per_notkott * 100


# Beräkna återstående kalorier för fett och kolhydrater
aterstaende_kalorier = justerat_kaloriintag_per_atdag - kalorier_protein

# Fördelning av återstående kalorier mellan fett och kolhydrater
prop_fett = 0.30  # 30% av de återstående kalorierna till fett
prop_kolhydrater = 0.70  # 70% av de återstående kalorierna till kolhydrater

# Beräkna kalorier för fett och kolhydrater
kalorier_fett = aterstaende_kalorier * prop_fett
kalorier_kolhydrater = aterstaende_kalorier * prop_kolhydrater

# Omvandla dessa kalorier till gram
gram_fett = kalorier_fett / 9  # 1 gram fett = 9 kalorier
gram_kolhydrater = kalorier_kolhydrater / 4  # 1 gram kolhydrater = 4 kalorier



# Information om protein- och kolhydratinnehåll per 100 gram för olika baljväxter
baljvaxter = {
    'Lupinbönor': {'protein': 13, 'kolhydrater': 7},
    'Linser (röda)': {'protein': 11, 'kolhydrater': 16},
    'Pintobönor': {'protein': 9, 'kolhydrater': 15},
    'Svarta bönor': {'protein': 8, 'kolhydrater': 14},
    'Kikärtor/garbanzo bönor': {'protein': 8, 'kolhydrater': 13},
    'Gröna ärtor': {'protein': 5, 'kolhydrater': 9}
}

# Beräkna och skriv ut hur många gram av varje baljväxt som behövs för att uppnå det dagliga proteinbehovet
# samt det totala kolhydratinnehållet från dessa mängder
for baljvaxt, innehall in baljvaxter.items():
    behov_per_dag_g = (protein_behov_per_dag / innehall['protein']) * 100
    totala_kolhydrater = (behov_per_dag_g / 100) * innehall['kolhydrater']
    print(f"Behov av {baljvaxt} per dag för att möta proteinbehovet: {behov_per_dag_g:.2f} gram, vilket ger {totala_kolhydrater:.2f} gram kolhydrater")

print(f"------")


print(f"Behov av ägg per dag för att möta proteinbehovet: {agg_behov_per_dag:.2f} stora ägg")
print(f"Behov av kyckling per dag för att möta proteinbehovet: {kyckling_behov_per_dag_g:.2f} gram")
print(f"Behov av kalkon per dag för att möta proteinbehovet: {kalkon_behov_per_dag_g:.2f} gram")
print(f"Behov av nötkött per dag för att möta proteinbehovet: {notkott_behov_per_dag_g:.2f} gram")
print(f"Behov av ENBART kyckling per dag för att möta proteinbehovet: {kyckling_behov_enbart_per_dag_g:.2f} gram")
print(f"Behov av ENBART nötkött per dag för att möta proteinbehovet: {notkott_behov_enbart_per_dag_g:.2f} gram")

print(f"------")

# Skriv ut rekommenderade mängder
print(f"Rekommenderat proteinintag per ätdag: {protein_behov_per_dag:.2f} gram ({kalorier_protein:.2f} kalorier)")
print(f"Rekommenderat fettintag per ätdag: {gram_fett:.2f} gram ({kalorier_fett:.2f} kalorier)")
print(f"Rekommenderat kolhydratintag per ätdag: {gram_kolhydrater:.2f} gram ({kalorier_kolhydrater:.2f} kalorier)")

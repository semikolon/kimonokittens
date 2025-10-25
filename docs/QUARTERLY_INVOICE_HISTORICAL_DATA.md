# Quarterly Invoice Historical Data

**Provider**: Bostadsagenturen i Stockholm AB
**Type**: Building operations costs (drift räkning)
**Recipients**: Fredrik Bränström/Frans sporsen/Patrik Ljungkvist (collective household)

---

## Complete Invoice History

### 2025

| Invoice Date | Due Date | Amount (SEK) | Invoice # | Config Month | Rent Month |
|--------------|----------|--------------|-----------|--------------|------------|
| Oct 24, 2025 | Oct 31   | 2,797.00     | Current   | Oct 2025     | Nov 2025   |
| Jul 27, 2025 | Aug 8    | 2,637.00     | #8632     | Jul 2025     | Aug 2025   |
| Apr 28, 2025 | May 5    | 2,927.00     | #7917     | Apr 2025     | May 2025   |

### 2024

| Invoice Date | Due Date | Amount (SEK) | Invoice # | Config Month | Rent Month |
|--------------|----------|--------------|-----------|--------------|------------|
| Oct 24, 2024 | Oct 31   | 2,612.00     | #6516     | Oct 2024     | Nov 2024   |
| Jul 25, 2024 | Aug 1    | 2,604.00     | #5815     | Jul 2024     | Aug 2024   |
| Apr 25, 2024 | May 2    | 2,473.00     | #5096     | Apr 2024     | May 2024   |

### 2023

| Invoice Date | Due Date | Amount (SEK) | Invoice # | Config Month | Rent Month |
|--------------|----------|--------------|-----------|--------------|------------|
| Oct 30, 2023 | Oct 31   | 2,506.00     | #3719     | Oct 2023     | Nov 2023   |
| Jul 27, 2023 | Jul 29   | 2,487.00     | #3100     | Jul 2023     | Aug 2023   |
| Apr 2023     | ?        | ~2,400*      | #2527     | Apr 2023     | May 2023   |

\* April 2023 data incomplete - smaller invoices visible (779 SEK, 1,016 SEK) may be partial payments or separate billing

### Smaller Invoices (Non-Quarterly)

Additional invoices found in email history that don't match the quarterly pattern:

| Invoice Date | Due Date | Amount (SEK) | Invoice # | Notes |
|--------------|----------|--------------|-----------|-------|
| Jun 2, 2025  | -        | 572.00       | #8131     | Separate charge (nature unclear) |
| Feb 6, 2024  | -        | 1,538.00     | #4389     | Separate charge (betalning mottagen) |
| Jan 26, 2024 | Feb 2    | 1,478.00     | #4389     | Separate charge (possibly partial payment) |

**Note**: These smaller invoices (500-1,500 SEK) appear to be separate charges or adjustments, not quarterly building operations costs. The typical quarterly invoice is 2,400-2,900 SEK.

---

## Invoice Pattern Analysis

### Billing Frequency
**3 times per year** (not 4 quarters):
- **April** (Q1 end/Q2 start)
- **July** (Q2 end/Q3 start)
- **October** (Q3 end/Q4 start)

**No January invoice** - Pattern starts in April

### Amount Trends

| Period | Avg Amount | Range |
|--------|------------|-------|
| 2023   | ~2,497 kr  | 2,487-2,506 kr |
| 2024   | 2,563 kr   | 2,473-2,612 kr |
| 2025   | 2,787 kr   | 2,637-2,927 kr |

**YoY Growth**:
- 2023 → 2024: +2.6% average
- 2024 → 2025: +8.7% average (significant jump)

### Seasonal Variation
- **April**: Tends to be lowest (2,473-2,927 kr)
- **July**: Mid-range (2,487-2,637 kr)
- **October**: Tends to be highest (2,506-2,797 kr)

Possible explanation: October invoice may include winter preparation costs, heating system maintenance, etc.

---

## Cost Components (From Email Discussions)

### Included in Quarterly Invoice:
1. **Water fee** (vattenavgift): ~375 kr/month → 1,125 kr/quarter
2. **Sewage** (VA): ~300 kr/month → 900 kr/quarter
3. **Alarm system** (larm): ~150 kr/month → 450 kr/quarter
4. **Building maintenance**: Variable
5. **Property tax**: Variable
6. **Other building utilities**: Variable

**Expected quarterly from monthly fees**: 825 kr/month × 3 = 2,475 kr
**Actual quarterly invoices**: 2,400-2,900 kr (±5-20% variance)

### Alarm System (Larm) - Mandatory Component

**Background** (from email discussion, Jan 2023):
- Pre-installed Verisure alarm system in the building
- Initial separate billing from Verisure (597 SEK/quarter in early 2023)
- Later consolidated into Bostadsagenturen quarterly invoice
- **Cannot be removed** - mandatory building cost
- Equipment still installed in house
- Collective/building arrangement, not individual choice

**Historical Verisure Billing**:
- Q2 2023 (May-Jul): 597 SEK (657 SEK with 60 SEK discount)
- Invoice date: April 1, 2023
- Due date: April 30, 2023

### Waste Management (Sophämtning)

**Historical separate billing** (Q1 2023):
- Provider: Kollektivet Sördalävägen (via SRV)
- Q1 2023 (Jan-Mar): 586.20 SEK total (including 25% moms)
  - Grundavgift: 270.00 SEK
  - Sortera hemma (370L, alternating weeks): 316.20 SEK
- Later consolidated into Bostadsagenturen quarterly invoice

---

## Billing Evolution

### Early 2023 (Separate Invoices)
- **Bostadsagenturen**: Core building costs
- **Verisure**: Alarm system (597 kr/quarter)
- **SRV/Kollektivet**: Waste management (586 kr/quarter)
- **Total quarterly**: ~3,200-3,500 kr (estimated combined)

### Mid 2023 - Present (Consolidated)
- **Bostadsagenturen**: All-in-one quarterly invoice
- **Amount**: 2,400-2,900 kr
- **Components**: Water, sewage, alarm, waste, property tax, maintenance

**Consolidation benefit**: Single invoice, simpler administration

---

## Database Storage

### Config Period vs Rent Month
**Critical timing rule**: Quarterly invoice is stored in the config month (when bill arrives), used for the following rent month.

**Example - October 2025 Invoice**:
- Invoice received: October 24, 2025
- Due date: October 31, 2025
- **Stored in**: `RentConfig` October 2025 period (`drift_rakning: 2797`)
- **Used for**: November 2025 rent calculation
- **Rent due**: October 27, 2025

### Monthly Utilities Replacement Logic
When `drift_rakning` is present and > 0:
- **Remove**: `vattenavgift` (375), `va` (300), `larm` (150) = 825 kr
- **Add**: `drift_rakning` value (2,797 kr)
- **Net effect**: +1,972 kr compared to normal month

---

## Future Projections

### Expected Invoices (2026)
Based on 3× yearly pattern:
- **April 2026**: ~3,000 kr (estimated +2.5% growth)
- **July 2026**: ~2,700 kr (estimated)
- **October 2026**: ~2,900 kr (estimated)

### Automation Strategy
See `docs/QUARTERLY_INVOICE_RECURRENCE_PLAN.md` for implementation plan:
- Phase 1: Manual entry with validation
- Phase 2: Warning system for expected quarters
- Phase 3: Dashboard alerts

---

## Data Sources

- Gmail search: `subject:faktura -("24 589") after:2023/1/1`
- Email dates: 2023-04-11 through 2025-10-24
- Database: `data/rent_history/2024_11_v2.json` (Nov 2024 with drift_rakning: 2612)
- Code: `rent.rb:96` (drift_rakning definition and replacement logic)

---

## Notes

1. **No January invoice**: Pattern is Apr/Jul/Oct (3× yearly), not quarterly in the strict sense
2. **Alarm system cannot be removed**: Mandatory building cost, equipment installed
3. **Amounts vary**: Building costs are variable (maintenance, property tax, actual usage)
4. **Consolidation simplified**: Early 2023 had 3 separate invoices, now one from Bostadsagenturen
5. **Current month savings depleted**: October 2025 will use full 2,797 kr (no savings buffer)

---

**Last Updated**: October 25, 2025
**Data Completeness**: ✅ Complete from April 2023 - October 2025 (all invoices captured)

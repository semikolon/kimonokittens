# Fortum Scraper Implementation Plan

**Created:** October 24, 2025
**Status:** In Progress

---

## OBJECTIVES

1. Create `fortum.rb` scraper for Fortum elhandel invoices
2. Store bills in database via `ApplyElectricityBill` service
3. Add COMPARE_HISTORY mode for verification
4. Update cron deployment to run both scrapers daily

---

## ARCHITECTURE (Clone vattenfall.rb structure)

**Phase 1: Core Scraper (fortum.rb)**
```ruby
Class: FortumScraper
├── Login flow (SSO portal)
├── Navigate to invoices page
├── Extract invoice data (amount, due date, status)
├── Apply via ApplyElectricityBill service
└── COMPARE_HISTORY mode (debug/verification)
```

**Phase 2: Cron Integration**
- Run daily (not hourly - bills arrive monthly)
- Stagger with Vattenfall to avoid resource conflicts

---

## IMPLEMENTATION STEPS

### **Step 1: Clone & Adapt Structure** (15 min)
- Copy `vattenfall.rb` → `fortum.rb`
- Update constants: Provider name, URLs, credentials
- Adapt login flow for Fortum SSO portal

### **Step 2: Login Flow** (20 min)
- Navigate to: `https://sso.fortum.com/am/XUI/?realm=/alpha&locale=sv&authIndexType=service&authIndexValue=SeB2COGWLogin#/`
- Fill credentials (FORTUM_ID, FORTUM_PW)
- Handle 2FA/verification if present
- Wait for redirect to authenticated state

### **Step 3: Invoice Extraction** (30 min)
- Navigate to: `https://www.fortum.com/se/el/inloggad/fakturor`
- Inspect DOM structure (similar to Vattenfall mobile components?)
- Extract: amount, due date, status
- Apply filter interactions if needed (period, status)

### **Step 4: Database Integration** (10 min)
- Call `ApplyElectricityBill.call()` with extracted data
- Provider: "Fortum"
- Deduplication handled by service layer

### **Step 5: COMPARE_HISTORY Mode** (15 min)
- Clone comparison logic from vattenfall.rb
- Parse Fortum section from electricity_bills_history.txt
- Compare scraped vs historical vs database

### **Step 6: Testing** (20 min)
- Run scraper in debug mode
- Verify invoice extraction
- Test COMPARE_HISTORY mode
- Confirm database writes

### **Step 7: Cron Setup** (10 min)
- Update cron schedule with daily runs

---

## CRON DEPLOYMENT STRATEGY

**Current State** (PI_MIGRATION_MAP.md):
```bash
# Every 2 hours: Vattenfall scraper
0 0,2,4,6,8,10,12,14,16,18,20,22 * * * bundle exec ruby vattenfall.rb
```

**Proposed State** (Dell - Daily runs):
```bash
# Daily at 3am: Vattenfall (elnät)
0 3 * * * cd /home/kimonokittens/Projects/kimonokittens && bundle exec ruby vattenfall.rb

# Daily at 4am: Fortum (elhandel)
0 4 * * * cd /home/kimonokittens/Projects/kimonokittens && bundle exec ruby fortum.rb
```

**Rationale:**
- **Daily runs sufficient** - bills arrive monthly, not hourly
- **1-hour stagger** prevents concurrent browser instances
- **3am/4am timing** - off-peak, low network interference
- **Clean separation** - each scraper has dedicated time slot

---

## CREDENTIALS

**Environment variables (in .env):**
- `FORTUM_ID` - Email address
- `FORTUM_PW` - Password

**Login URL:**
- `https://sso.fortum.com/am/XUI/?realm=/alpha&locale=sv&authIndexType=service&authIndexValue=SeB2COGWLogin#/`

**Invoices URL:**
- `https://www.fortum.com/se/el/inloggad/fakturor`

---

## FILE STRUCTURE

```
/Users/fredrikbranstrom/Projects/kimonokittens/
├── vattenfall.rb (existing - elnät invoices)
├── fortum.rb (new - elhandel invoices)
├── lib/
│   ├── persistence.rb
│   ├── services/apply_electricity_bill.rb
│   └── models/electricity_bill.rb
└── electricity_bills_history.txt (legacy reference only)
```

---

## DATA FLOW

1. **Scraper runs** → Logs in to Fortum portal
2. **Extracts invoices** → Amount, due date, status
3. **Calls service** → `ApplyElectricityBill.call(provider: 'Fortum', ...)`
4. **Service layer**:
   - Calculates bill period (arrival month logic)
   - Checks for duplicates
   - Stores in ElectricityBill table
   - Aggregates period total
   - Upserts RentConfig (key='el')
5. **Rent calculator** → Uses aggregated RentConfig data

---

## VERIFICATION

**ElectricityProjector confirmed to use database only:**
- Source: `lib/electricity_projector.rb:111`
- Method: `repo.all_for_key('el')` - queries RentConfig table
- Text file (`electricity_bills_history.txt`) is legacy/deployment-only

**Database priority:**
- ✅ ElectricityProjector reads from database
- ✅ ApplyElectricityBill writes to database
- ✅ Text file NOT used in production code

---

## PROGRESS UPDATE (Oct 24, 2025)

### Completed ✅
1. **Login flow** - Working perfectly with Fortum SSO portal
   - Credentials: FORTUM_ID (email) and FORTUM_PW (password)
   - SSO URL navigates correctly, authentication succeeds
   - Cookie consent handled (accepts "Acceptera alla" button)

2. **Page navigation** - Successfully navigates to invoice page
   - URL: https://www.fortum.com/se/el/inloggad/fakturor
   - Page loads with complete invoice history visible

3. **Data discovery** - Found invoice data structure using JavaScript evaluation
   - Two formats discovered: 2025 (newline-separated) vs 2024 (concatenated)
   - 2025 format: `"Januari 2025\nBetald\n1 845,00 kr"` (3 lines)
   - 2024 format: `"december 2024BetaldVisa PDF1 757,00 krBetald"` (1 line)
   - Invoice containers identified: `<div>` with 5 children

4. **Invoice extraction** - Working successfully! ✅
   - Extracted 10 invoices (all of 2025: Jan-Oct)
   - Handles 2025 format with proper newlines
   - Stores in database via ApplyElectricityBill service
   - RentConfig aggregation working correctly
   - Example output: `✓ Fortum 792,00 kr → period 2025-09 (RentConfig updated | total 3216 kr)`
   - **Note**: 2024 historical data (12 invoices) uses different DOM format, but daily runs only need current year

5. **Database integration** - Working! ✅
   - Bills stored with correct periods (arrival month logic)
   - RentConfig 'el' aggregation functional
   - Deduplication working (skips existing bills)

6. **COMPARE_HISTORY mode** - Working! ✅
   - Compares scraped invoices against database
   - All 10 scraped invoices match database exactly ✓
   - Expected periods match actual database periods ✓
   - Database has 41 Fortum bills total (all years)
   - Example output: `Historical file: ✗ | Database: ✓ (period: 2025-09)`
   - Note: Historical file ✗ is expected (database is source of truth)

### In Progress 🚧
7. **Cron deployment** - Ready to deploy

### Not Started ⏳
None - core implementation complete!

## SUCCESS CRITERIA

- [x] Fortum scraper extracts invoices successfully ✅
- [x] Bills stored in database with correct periods ✅
- [x] COMPARE_HISTORY mode shows ✓ matches ✅
- [ ] Cron jobs staggered and non-conflicting (READY TO DEPLOY)
- [ ] Both scrapers coexist without interference (READY TO TEST)
- [x] No duplication in RentConfig aggregation ✅

---

## TESTING CHECKLIST

**Before deployment:**
1. Run `ruby fortum.rb` manually
2. Verify invoice extraction in logs
3. Check database for new ElectricityBill records
4. Verify RentConfig aggregation is correct
5. Run `COMPARE_HISTORY=1 ruby fortum.rb`
6. Compare results with historical file
7. Test deduplication (run twice, second should skip)

**After deployment:**
1. Monitor cron logs for successful runs
2. Verify bills appear in database next day
3. Check RentConfig updates match expectations
4. Confirm no conflicts with Vattenfall scraper

---

## RELATED DOCUMENTATION

- `vattenfall.rb` - Reference implementation
- `lib/services/apply_electricity_bill.rb` - Service layer
- `lib/models/electricity_bill.rb` - Domain model (arrival month logic)
- `docs/PI_MIGRATION_MAP.md` - Cron migration context
- `CLAUDE.md` - Electricity bill timing documentation

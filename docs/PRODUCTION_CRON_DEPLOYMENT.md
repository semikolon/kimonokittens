# Production Cron Deployment Guide

**Date**: October 24, 2025 (Updated for dual-scraper setup)
**Target**: Dell Optiplex kiosk (`kimonokittens` user)
**Purpose**: Automated daily electricity invoice fetching (Vattenfall + Fortum)

---

## Prerequisites Check

All model migrations and code changes are already deployed via webhook.

**Verify database schema:**
```bash
echo "SELECT COUNT(*) FROM ElectricityBill;" | psql $DATABASE_URL
# Should return a count (0 or more - table exists)
```

**Verify environment variables:**
```bash
grep -E "VATTENFALL_ID|VATTENFALL_PW|FORTUM_ID|FORTUM_PW|AZURE_SUBSCRIPTION_KEY" /home/kimonokittens/.env
# Should show all five variables with values
```

---

## Installation Steps

### 1. Create Cron Wrapper Scripts (OUTDATED - See Note Below)

**⚠️ NOTE (Oct 26, 2025):** These wrapper scripts are **NOT used in production**. Cron jobs call the scrapers directly with `bundle exec`. This section is preserved for reference only. See "Production Verification" section below for actual cron configuration.

**Vattenfall scraper (elnät - grid costs):**
```bash
cat > /home/kimonokittens/Projects/kimonokittens/bin/fetch_vattenfall_data.sh << 'EOF'
#!/bin/bash
# Vattenfall electricity invoice fetching (elnät - grid costs)
# Runs daily at 3am via cron
# Integrates with ApplyElectricityBill service for automatic RentConfig updates

cd /home/kimonokittens/Projects/kimonokittens

# Use rbenv ruby (same as production server)
/home/kimonokittens/.rbenv/shims/ruby vattenfall.rb >> logs/vattenfall_fetcher.log 2>&1

# Exit with the script's exit code
exit $?
EOF

chmod +x /home/kimonokittens/Projects/kimonokittens/bin/fetch_vattenfall_data.sh
```

**Fortum scraper (elhandel - consumption costs):**
```bash
cat > /home/kimonokittens/Projects/kimonokittens/bin/fetch_fortum_data.sh << 'EOF'
#!/bin/bash
# Fortum electricity invoice fetching (elhandel - consumption costs)
# Runs daily at 4am via cron (1-hour stagger from Vattenfall)
# Integrates with ApplyElectricityBill service for automatic RentConfig updates

cd /home/kimonokittens/Projects/kimonokittens

# Use rbenv ruby (same as production server)
/home/kimonokittens/.rbenv/shims/ruby fortum.rb >> logs/fortum_fetcher.log 2>&1

# Exit with the script's exit code
exit $?
EOF

chmod +x /home/kimonokittens/Projects/kimonokittens/bin/fetch_fortum_data.sh
```

### 2. Create Log Directory

```bash
mkdir -p /home/kimonokittens/Projects/kimonokittens/logs
touch /home/kimonokittens/Projects/kimonokittens/logs/vattenfall_fetcher.log
touch /home/kimonokittens/Projects/kimonokittens/logs/fortum_fetcher.log
```

### 3. Add Cron Entries (as kimonokittens user)

```bash
# Add both scrapers to crontab (idempotent - won't duplicate)
# Staggered timing: 3am (Vattenfall) and 4am (Fortum) to avoid resource conflicts

(crontab -l 2>/dev/null | grep -q "fetch_vattenfall_data.sh") || \
(crontab -l 2>/dev/null; echo "0 3 * * * /home/kimonokittens/Projects/kimonokittens/bin/fetch_vattenfall_data.sh") | crontab -

(crontab -l 2>/dev/null | grep -q "fetch_fortum_data.sh") || \
(crontab -l 2>/dev/null; echo "0 4 * * * /home/kimonokittens/Projects/kimonokittens/bin/fetch_fortum_data.sh") | crontab -
```

### 4. Verify Cron Installation

```bash
# Check crontab entries
crontab -l | grep electricity

# Should output:
# 0 3 * * * /home/kimonokittens/Projects/kimonokittens/bin/fetch_vattenfall_data.sh
# 0 4 * * * /home/kimonokittens/Projects/kimonokittens/bin/fetch_fortum_data.sh
```

---

## Testing

### Manual Test Run - Vattenfall

```bash
cd /home/kimonokittens/Projects/kimonokittens
ruby vattenfall.rb
```

**Expected output (first run):**
```
📊 Invoice Summary:
  Total invoices scraped: 1
  1. 1 685,69 kr due 2025-11-03 (Obetald)

💾 JSON backup: electricity_invoices.json

💾 Storing invoices in database...
  ✓ Inserted: 1
  ⊘ Skipped (duplicates): 0

✅ Successfully fetched 9745 hours consumption data
```

**Expected output (subsequent runs):**
```
📊 Invoice Summary:
  Total invoices scraped: 1
  1. 1 685,69 kr due 2025-11-03 (Obetald)

💾 JSON backup: electricity_invoices.json

💾 Storing invoices in database...
  ⊘ Skipped (duplicates): 1  ← Normal! Invoices arrive monthly
  ✓ Inserted: 0

✅ Successfully fetched 9745 hours consumption data
```

### Manual Test Run - Fortum

```bash
cd /home/kimonokittens/Projects/kimonokittens
ruby fortum.rb
```

**Expected output (first run):**
```
🔍 Scraping invoices from Fortum...
✓ Fortum 792,00 kr → period 2025-09 (RentConfig updated | total 3216 kr)
✓ Fortum 408,00 kr → period 2025-08 (RentConfig updated | total 3011 kr)
... (8 more invoices from 2025)

💾 JSON backup: fortum_invoices.json

✓ Stored 10 invoices in database
```

**Expected output (subsequent runs):**
```
🔍 Scraping invoices from Fortum...
⊘ Fortum 792,00 kr → period 2025-09 (duplicate, preserved)
⊘ Fortum 408,00 kr → period 2025-08 (duplicate, preserved)
... (8 more duplicates from 2025)

💾 JSON backup: fortum_invoices.json

⊘ All invoices already in database (0 inserted, 10 preserved)
```

### Check Log Output

```bash
# Vattenfall logs
tail -50 /home/kimonokittens/Projects/kimonokittens/logs/vattenfall_fetcher.log

# Fortum logs
tail -50 /home/kimonokittens/Projects/kimonokittens/logs/fortum_fetcher.log
```

### Verify Database Integration

```bash
# Check if invoice was stored
ruby -e "
require 'dotenv/load'
require_relative 'lib/persistence'

bills = Persistence.electricity_bills.all
puts \"Total bills in database: #{bills.length}\"
bills.each { |b| puts \"  - #{b.provider} #{b.amount} kr (#{b.bill_period})\" }
"
```

### Production Verification (Oct 26, 2025) ✅

**Complete end-to-end flow tested and verified in production.**

#### Critical Fix: Bundle Exec Requirement

**Problem discovered:** Cron jobs were failing with "cannot load such file -- ferrum" error.

**Root cause:** Cron environment doesn't have bundler gem path in load path.

**Fix applied:** Updated crontab entries to use `bundle exec`:
```bash
# Correct cron configuration (Oct 26, 2025)
0 3 * * * cd /home/kimonokittens/Projects/kimonokittens && bundle exec ruby vattenfall.rb >> logs/vattenfall_fetcher.log 2>&1
0 4 * * * cd /home/kimonokittens/Projects/kimonokittens && bundle exec ruby fortum.rb >> logs/fortum_fetcher.log 2>&1
```

**Note:** The wrapper scripts mentioned earlier in this document (`bin/fetch_*_data.sh`) are not used in production. Cron jobs call the scrapers directly with `bundle exec`.

#### End-to-End Testing Method

**Test procedure** (verified Oct 26, 2025):
1. **Delete latest bills** from database to simulate new invoice arrival
2. **Run both scrapers** manually with bundle exec
3. **Verify re-insertion** of bills with correct amounts
4. **Verify aggregation** to RentConfig with correct totals
5. **Verify WebSocket** broadcast of rent_data_updated event

**Commands used:**
```bash
# Delete latest bills (Sept 2025 consumption period)
ruby -e "require 'dotenv/load'; require_relative 'lib/persistence'; \
  Persistence.electricity_bills.delete_by_period(Date.new(2025, 9, 1))"

# Run scrapers (bundle exec required in cron environment)
cd /home/kimonokittens/Projects/kimonokittens
bundle exec ruby vattenfall.rb
bundle exec ruby fortum.rb

# Verify results
ruby -e "require 'dotenv/load'; require_relative 'lib/persistence'; \
  bills = Persistence.electricity_bills.find_by_period(Date.new(2025, 9, 1)); \
  bills.each { |b| puts \"#{b.provider}: #{b.amount} kr\" }; \
  puts \"Total: #{bills.sum(&:amount)} kr\""
```

**Verified results:**
```
Vattenfall: 1685.69 kr  (Sept 2025 grid costs - elnät)
Fortum: 896.0 kr        (Sept 2025 consumption - elhandel)
Total: 2581.69 kr       (Aggregated to RentConfig for Oct rent calculation)
```

**Database verification:**
- ✅ Both bills inserted with correct amounts
- ✅ Deduplication working (subsequent runs skip duplicates)
- ✅ RentConfig `el` key updated to 2,581 kr (rounded)
- ✅ WebSocket broadcast triggered (dashboard auto-refreshed)

**Cron verification:**
```bash
# Check cron is running both scrapers daily
sudo -u kimonokittens crontab -l | grep bundle

# View recent cron execution logs
grep CRON /var/log/syslog | grep "vattenfall\|fortum" | tail -10

# Check scraper output logs
tail -50 /home/kimonokittens/Projects/kimonokittens/logs/vattenfall_fetcher.log
tail -50 /home/kimonokittens/Projects/kimonokittens/logs/fortum_fetcher.log
```

**Status:** ✅ **PRODUCTION READY** - Both scrapers running daily at 3am/4am with complete integration

---

## Expected Behavior

### Daily Runs (Normal Operation)

- **Time**: 3:00 AM (Vattenfall) and 4:00 AM (Fortum) daily
- **Duration**: ~3 seconds per scraper (headless browser automation)
- **Stagger reason**: 1-hour gap prevents concurrent browser instances
- **New invoices**: Usually skipped as duplicates (invoices arrive monthly)
- **Consumption data**: Vattenfall fetches hourly consumption to `electricity_usage.json`
- **Database updates**: Only when new invoice arrives from either provider

### When New Invoice Arrives

1. **Scraper**: Detects new invoice on provider website (Vattenfall or Fortum)
2. **Storage**: Stores in ElectricityBill table (deduplication via semantic key)
3. **Aggregation**: Sums all bills for the consumption period (both providers)
4. **RentConfig**: Updates `el` key with aggregated total
5. **WebSocket**: Broadcasts `rent_data_updated` to dashboard
6. **Dashboard**: Auto-refreshes rent calculation

### Deduplication Logic

**Semantic key: `(provider, billPeriod)` - one bill per provider per config month**

- **Same invoice scraped again**: Skipped (duplicate preserved)
- **Due date variation** (e.g., Sept 30 vs Oct 1): UPDATE existing bill (same config month)
- **New month's invoice**: Inserted as new bill
- **Historical bills** (past months): READ-ONLY, never updated
- **Current/future bills**: Updateable (handles corrections)

**Why provider+period, not provider+due_date+amount:**
- Due dates can vary by 1 day (end-of-month vs 1st of next month)
- Only ONE bill per provider per config month should exist
- Updates allowed for corrections, but historical data is preserved

---

## Monitoring

### Check Cron Execution

```bash
# View recent cron runs (from syslog)
grep CRON /var/log/syslog | grep "fetch_.*_data" | tail -20

# Vattenfall runs (3am)
grep CRON /var/log/syslog | grep fetch_vattenfall_data | tail -10

# Fortum runs (4am)
grep CRON /var/log/syslog | grep fetch_fortum_data | tail -10
```

### View Logs

```bash
# Live monitoring (run at 3am/4am to watch execution)
tail -f /home/kimonokittens/Projects/kimonokittens/logs/vattenfall_fetcher.log
tail -f /home/kimonokittens/Projects/kimonokittens/logs/fortum_fetcher.log

# Last 50 lines of each
tail -50 /home/kimonokittens/Projects/kimonokittens/logs/vattenfall_fetcher.log
tail -50 /home/kimonokittens/Projects/kimonokittens/logs/fortum_fetcher.log
```

### Check Database State

```bash
# View recent electricity bills
ruby -e "
require 'dotenv/load'
require_relative 'lib/persistence'

bills = Persistence.electricity_bills.all.sort_by(&:due_date).reverse.take(5)
bills.each do |b|
  puts \"#{b.due_date.strftime('%Y-%m-%d')}: #{b.provider} #{b.amount} kr (period: #{b.bill_period.strftime('%Y-%m')})\"
end
"
```

---

## Troubleshooting

### Cron Not Running

```bash
# Check cron service is running
systemctl status cron

# Check user has cron access
ls -la /var/spool/cron/crontabs/kimonokittens
```

### Script Errors

```bash
# Run manually with debug output
cd /home/kimonokittens/Projects/kimonokittens

# Vattenfall debugging
DEBUG=1 ruby vattenfall.rb

# Fortum debugging
DEBUG=1 ruby fortum.rb
```

### Database Connection Issues

```bash
# Verify DATABASE_URL is accessible
ruby -e "require 'dotenv/load'; puts ENV['DATABASE_URL']"

# Test database connection
ruby -e "require 'dotenv/load'; require 'sequel'; DB = Sequel.connect(ENV['DATABASE_URL']); puts DB.test_connection ? 'OK' : 'FAIL'"
```

### Browser Issues

```bash
# Show browser window for debugging
cd /home/kimonokittens/Projects/kimonokittens

# Vattenfall browser debugging
SHOW_BROWSER=1 ruby vattenfall.rb

# Fortum browser debugging
SHOW_BROWSER=1 ruby fortum.rb
```

---

## Log Rotation (Optional)

Add logrotate configuration for log file management:

```bash
sudo tee /etc/logrotate.d/kimonokittens-electricity << EOF
/home/kimonokittens/Projects/kimonokittens/logs/vattenfall_fetcher.log
/home/kimonokittens/Projects/kimonokittens/logs/fortum_fetcher.log {
    daily
    missingok
    rotate 30
    compress
    delaycompress
    notifempty
    create 0644 kimonokittens kimonokittens
}
EOF
```

---

## Historical Data

**Complete historical invoice data available**: `electricity_bills_history.txt` contains verified due dates and amounts for all past Fortum and Vattenfall bills.

**Import script**: `import_fortum_historical.rb` can re-import historical Fortum data if needed (deletes existing Fortum bills and re-imports from text file).

**Note**: Historical data was already imported during initial deployment. The text file serves as backup/reference.

---

## Future Enhancements

- **Email alerts**: Notify when new invoice detected or scraper fails
- **Price API**: Integrate spot price data for cost forecasting
- **Retry logic**: Auto-retry on transient network errors

---

## Architecture Notes

- **No database migrations needed**: Schema already deployed via webhook
- **No environment changes needed**: All credentials in `/home/kimonokittens/.env`
- **Idempotent**: Safe to run multiple times (deduplication prevents duplicates)
- **WebSocket integration**: Dashboard auto-updates when new invoices arrive
- **Service architecture**: Uses ApplyElectricityBill service for atomic transactions

---

**End of Deployment Guide**

# Production Cron Deployment Guide

**Date**: October 23, 2025
**Target**: Dell Optiplex kiosk (`kimonokittens` user)
**Purpose**: Automated daily electricity invoice fetching

---

## Prerequisites Check

All model migrations and code changes are already deployed via webhook (commits d96d76f, d7b75ec, 7df8296, bff1e1b).

**Verify database schema:**
```bash
echo "SELECT COUNT(*) FROM ElectricityBill;" | psql $DATABASE_URL
# Should return a count (0 or more - table exists)
```

**Verify environment variables:**
```bash
grep -E "VATTENFALL_ID|VATTENFALL_PW|AZURE_SUBSCRIPTION_KEY" /home/kimonokittens/.env
# Should show all three variables with values
```

---

## Installation Steps

### 1. Create Cron Wrapper Script

```bash
cat > /home/kimonokittens/Projects/kimonokittens/bin/fetch_electricity_data.sh << 'EOF'
#!/bin/bash
# Automated electricity invoice fetching via Ferrum browser automation
# Runs daily at 3am to fetch latest invoices and consumption data
# Integrates with ApplyElectricityBill service for automatic RentConfig updates

cd /home/kimonokittens/Projects/kimonokittens

# Use rbenv ruby (same as production server)
/home/kimonokittens/.rbenv/shims/ruby vattenfall.rb >> logs/electricity_fetcher.log 2>&1

# Exit with the script's exit code
exit $?
EOF

chmod +x /home/kimonokittens/Projects/kimonokittens/bin/fetch_electricity_data.sh
```

### 2. Create Log Directory

```bash
mkdir -p /home/kimonokittens/Projects/kimonokittens/logs
touch /home/kimonokittens/Projects/kimonokittens/logs/electricity_fetcher.log
```

### 3. Add Cron Entry (as kimonokittens user)

```bash
# Add to crontab (idempotent - won't duplicate)
(crontab -l 2>/dev/null | grep -q "fetch_electricity_data.sh") || \
(crontab -l 2>/dev/null; echo "0 3 * * * /home/kimonokittens/Projects/kimonokittens/bin/fetch_electricity_data.sh") | crontab -
```

### 4. Verify Cron Installation

```bash
# Check crontab entry
crontab -l | grep electricity
# Should output: 0 3 * * * /home/kimonokittens/Projects/kimonokittens/bin/fetch_electricity_data.sh
```

---

## Testing

### Manual Test Run

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

### Check Log Output

```bash
tail -50 /home/kimonokittens/Projects/kimonokittens/logs/electricity_fetcher.log
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

---

## Expected Behavior

### Daily Runs (Normal Operation)

- **Time**: 3:00 AM daily
- **Duration**: ~3 seconds (headless browser automation)
- **New invoices**: Usually skipped as duplicates (invoices arrive monthly)
- **Consumption data**: Fetched and saved to `electricity_usage.json`
- **Database updates**: Only when new invoice arrives

### When New Invoice Arrives

1. **Scraper**: Detects new invoice on Vattenfall website
2. **Storage**: Stores in ElectricityBill table (deduplication via composite key)
3. **Aggregation**: Sums all bills for the consumption period
4. **RentConfig**: Updates `el` key with aggregated total
5. **WebSocket**: Broadcasts `rent_data_updated` to dashboard
6. **Dashboard**: Auto-refreshes rent calculation

### Deduplication Logic

Composite key: `(provider, billDate, amount)`

- Same invoice scraped again = skipped (duplicate)
- New invoice from same provider = inserted (different amount or date)
- Multiple providers same day = both inserted (different provider)

---

## Monitoring

### Check Cron Execution

```bash
# View recent cron runs (from syslog)
grep CRON /var/log/syslog | grep fetch_electricity_data | tail -10
```

### View Logs

```bash
# Live monitoring (run at 3am to watch execution)
tail -f /home/kimonokittens/Projects/kimonokittens/logs/electricity_fetcher.log

# Last 50 lines
tail -50 /home/kimonokittens/Projects/kimonokittens/logs/electricity_fetcher.log
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
DEBUG=1 ruby vattenfall.rb
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
SHOW_BROWSER=1 ruby vattenfall.rb
```

---

## Log Rotation (Optional)

Add logrotate configuration for log file management:

```bash
sudo tee /etc/logrotate.d/kimonokittens-electricity << EOF
/home/kimonokittens/Projects/kimonokittens/logs/electricity_fetcher.log {
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

## Future Enhancements

- **Email alerts**: Notify when new invoice detected or scraper fails
- **Fortum integration**: Add second electricity provider support
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

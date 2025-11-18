# Rent Reminders Production Deployment Guide
**Date**: November 18, 2025
**Status**: Code pushed, migrations pending

---

## 🎯 WHAT'S ALREADY DONE ✅

- ✅ Code pushed to production via webhook (Nov 18, 2025)
- ✅ Template-based SMS system (dashboard-style single-line format)
- ✅ Database migrations created in codebase
- ✅ Scripts `bin/bank_sync` and `bin/rent_reminders` ready
- ✅ `state/` directory exists in dev (needs creation in prod)
- ✅ No LLM dependencies (zero OpenAI API calls needed)

---

## 🚀 PRODUCTION DEPLOYMENT TASKS

### 🤖 Tasks for Serverside CC Agent (kimonokittens user)

Connect to production via SSH and use serverside CC to execute:

#### 1. Run Database Migrations
```bash
cd /home/kimonokittens/Projects/kimonokittens
npx prisma migrate deploy
```

**Creates 4 tables:**
- `BankTransaction` - Lunch Flow transaction storage
- `RentReceipt` - Payment-to-rent-period linking
- `SmsEvent` - SMS audit log
- Extends `Tenant` - Adds `phoneE164`, `paydayStartDay`, `smsOptOut`

**Verification:**
```bash
psql -d kimonokittens_production -c "\dt" | grep -E "(BankTransaction|RentReceipt|SmsEvent)"
```

#### 2. Create State Directory
```bash
mkdir -p /home/kimonokittens/Projects/kimonokittens/state
```

**Purpose**: Stores `bank_sync.json` cursor file for incremental transaction syncing

#### 3. Validate Tenant Phone Numbers (Database Update)

**Option A: Via Ruby script** (create if needed):
```ruby
#!/usr/bin/env ruby
require 'dotenv/load'
require_relative 'lib/persistence'

Persistence.tenants.all.each do |tenant|
  next if tenant.phone_e164 # Already set

  # Convert Swedish 07xxx to +467xxx
  if tenant.phone && tenant.phone.start_with?('07')
    e164 = "+46#{tenant.phone[1..-1]}"
    Persistence.tenants.update(tenant.id, phone_e164: e164)
    puts "✓ #{tenant.name}: #{e164}"
  else
    puts "⚠️  #{tenant.name}: Manual fix needed (phone: #{tenant.phone})"
  end
end
```

**Option B: Direct SQL** (if all tenants follow 07xxx pattern):
```sql
UPDATE "Tenant"
SET "phoneE164" = CONCAT('+46', SUBSTRING(phone FROM 2))
WHERE phone ~ '^07[0-9]{8}$' AND "phoneE164" IS NULL;
```

**Set payday preferences:**
```sql
UPDATE "Tenant" SET "paydayStartDay" = 25 WHERE name = 'Sanna Juni Benemar';
UPDATE "Tenant" SET "paydayStartDay" = 27 WHERE name = 'Adam Fredriksson';
-- Repeat for other tenants
```

**Set SMS opt-in (default):**
```sql
UPDATE "Tenant" SET "smsOptOut" = false WHERE "smsOptOut" IS NULL;
```

#### 4. Dry-Run Testing
```bash
cd /home/kimonokittens/Projects/kimonokittens

# Test bank sync (preview what WOULD sync)
bundle exec ruby bin/bank_sync --dry-run

# Test rent reminders (preview who WOULD receive SMS)
bundle exec ruby bin/rent_reminders --dry-run

# Review output - should show realistic data
```

#### 5. Create Log Files
```bash
cd /home/kimonokittens/Projects/kimonokittens
touch logs/bank_sync.log logs/reminders.log
chmod 644 logs/bank_sync.log logs/reminders.log
```

---

### 👤 Tasks Requiring Manual User Action (fredrik/sudo)

These require interactive terminal access or sensitive data handling:

#### 1. Add Environment Variables

**Edit `/home/kimonokittens/.env` manually** (SSH as fredrik, then sudo):
```bash
# Add these lines (user provides actual values):
LUNCHFLOW_API_KEY=lf_live_XXXXXXXXXXXXXXXX
LUNCHFLOW_ACCOUNT_ID=4065

ELKS_USERNAME=u************
ELKS_PASSWORD=************
ELKS_SENDER=Katten

ADMIN_PHONE=+467XXXXXXXX
```

**⚠️ NO OPENAI_API_KEY NEEDED** - Template-based system requires zero LLM calls

#### 2. Add Cron Jobs

**Edit kimonokittens user's crontab** (SSH as fredrik, then):
```bash
sudo crontab -e -u kimonokittens
```

**Add these lines:**
```cron
# Hourly bank sync (5 minutes past the hour)
5 * * * * /bin/bash -l -c 'eval "$(rbenv init -)"; cd /home/kimonokittens/Projects/kimonokittens && timeout 5m bundle exec ruby bin/bank_sync >> logs/bank_sync.log 2>&1'

# Rent reminders at 09:45 and 16:45 daily
45 9 * * * /bin/bash -l -c 'eval "$(rbenv init -)"; cd /home/kimonokittens/Projects/kimonokittens && timeout 2m bundle exec ruby bin/rent_reminders >> logs/reminders.log 2>&1'
45 16 * * * /bin/bash -l -c 'eval "$(rbenv init -)"; cd /home/kimonokittens/Projects/kimonokittens && timeout 2m bundle exec ruby bin/rent_reminders >> logs/reminders.log 2>&1'
```

**Critical flags:**
- `eval "$(rbenv init -)"` - Loads Ruby environment
- `timeout Xm` - Prevents hanging processes
- `bundle exec` - Required for vendor/bundle gems
- `>> logs/*.log 2>&1` - Append stdout+stderr to logs

#### 3. Manual First Run (Supervised)

**After cron setup, trigger first sync manually to monitor:**
```bash
ssh pop
cd /home/kimonokittens/Projects/kimonokittens

# Run bank sync with live monitoring
bundle exec ruby bin/bank_sync

# Check what synced
psql -d kimonokittens_production -c "SELECT COUNT(*) FROM \"BankTransaction\";"

# Run reminders dry-run to preview
bundle exec ruby bin/rent_reminders --dry-run
```

**Wait for automatic cron execution and monitor:**
```bash
# Monitor bank sync (runs hourly at XX:05)
tail -f logs/bank_sync.log

# Monitor reminders (runs daily 09:45 and 16:45)
tail -f logs/reminders.log
```

---

## 📋 VERIFICATION CHECKLIST

After deployment, verify each component:

- [ ] **Migrations applied**: `psql -d kimonokittens_production -c "\dt" | grep BankTransaction`
- [ ] **Tenant phones E.164**: `psql -d kimonokittens_production -c "SELECT name, \"phoneE164\" FROM \"Tenant\";"`
- [ ] **Payday preferences set**: `psql -d kimonokittens_production -c "SELECT name, \"paydayStartDay\" FROM \"Tenant\";"`
- [ ] **State directory exists**: `test -d /home/kimonokittens/Projects/kimonokittens/state && echo OK`
- [ ] **Environment variables set**: `grep -q LUNCHFLOW_API_KEY /home/kimonokittens/.env && echo OK`
- [ ] **Cron jobs added**: `sudo crontab -l -u kimonokittens | grep -E "(bank_sync|rent_reminders)" && echo OK`
- [ ] **Dry-run tests pass**: `bundle exec ruby bin/bank_sync --dry-run` shows transactions
- [ ] **Logs writable**: `test -w logs/bank_sync.log && echo OK`
- [ ] **First sync successful**: Check `logs/bank_sync.log` after XX:05
- [ ] **First reminder preview**: Check `logs/reminders.log` dry-run output

---

## 🎛️ PHASED ROLLOUT (RECOMMENDED)

### Phase 1: Bank Sync Only (Week 1)
**Goal**: Verify transaction syncing and payment matching works

1. Complete tasks 1-5 (migrations, state dir, tenant data, dry-run, logs)
2. Add only bank_sync cron job (not reminders yet)
3. Monitor `logs/bank_sync.log` for 7 days
4. Verify `BankTransaction` and `RentReceipt` tables populate correctly
5. Check payment matching works: `psql -d kimonokittens_production -c "SELECT * FROM \"RentReceipt\" LIMIT 5;"`

### Phase 2: Dry-Run Reminders (Week 2)
**Goal**: Verify message generation and recipient selection

1. Add environment variables for 46elks
2. Run `bin/rent_reminders --dry-run` manually daily
3. Review message format and recipient list
4. Confirm reminder schedule logic works (day 23, payday, day 27, 28+)

### Phase 3: Live SMS (Week 3)
**Goal**: Enable actual SMS sending

1. Add reminder cron jobs (09:45 and 16:45)
2. Monitor first batch of SMS sends in `logs/reminders.log`
3. Verify 46elks delivery receipts work (SmsEvent table)
4. Watch for any errors or delivery failures

---

## 🔍 MONITORING & TROUBLESHOOTING

### Log Files
```bash
# Bank sync logs
tail -f /home/kimonokittens/Projects/kimonokittens/logs/bank_sync.log

# Reminder logs
tail -f /home/kimonokittens/Projects/kimonokittens/logs/reminders.log

# Main application logs (if needed)
journalctl -u kimonokittens-dashboard -f
```

### Database Checks
```sql
-- Recent bank transactions
SELECT * FROM "BankTransaction" ORDER BY "bookedAt" DESC LIMIT 10;

-- Recent rent receipts
SELECT * FROM "RentReceipt" ORDER BY "paidAt" DESC LIMIT 10;

-- Recent SMS events
SELECT * FROM "SmsEvent" ORDER BY "createdAt" DESC LIMIT 10;

-- Unpaid tenants for current month
SELECT t.name, rl."amountDue", COALESCE(SUM(rr.amount), 0) as paid
FROM "Tenant" t
JOIN "RentLedger" rl ON rl."tenantId" = t.id
LEFT JOIN "RentReceipt" rr ON rr."tenantId" = t.id AND rr.month = '2025-11'
WHERE rl.period = '2025-11-01'
GROUP BY t.name, rl."amountDue"
HAVING COALESCE(SUM(rr.amount), 0) < rl."amountDue";
```

### Common Issues

**Issue: Bank sync fails with "SSL verify failed"**
```ruby
# In lib/banking/lunchflow_client.rb, add to http setup:
http.verify_mode = OpenSSL::SSL::VERIFY_NONE
```

**Issue: Reminders not sending**
- Check `logs/reminders.log` for errors
- Verify ELKS_USERNAME and ELKS_PASSWORD are correct
- Test 46elks API manually: `curl -u username:password https://api.46elks.com/a1/Me`

**Issue: Payment matching not working**
- Check bank transaction description format
- Verify reference code generation (no dashes: `KK202511Sannacmhqe9enc`)
- Check phone number extraction from Swish transactions

---

## 📝 CRITICAL NOTES

1. **No LLM dependencies** - Template-based system requires zero OpenAI API calls
2. **Migrations are manual** - Webhook doesn't auto-run database migrations
3. **Cron requires bundle exec** - Essential for vendor/bundle gems
4. **Test dry-run first** - Never go live without `--dry-run` verification
5. **Monitor first runs** - Watch logs closely for initial executions
6. **Phased rollout recommended** - Start with bank sync only, add reminders later

---

## 🎯 QUICK REFERENCE: User vs Agent Tasks

### 🤖 Serverside CC Agent Can Do:
- Run migrations (`npx prisma migrate deploy`)
- Create state directory (`mkdir -p state`)
- Update tenant data (SQL or Ruby scripts)
- Run dry-run tests (`--dry-run` flags)
- Create log files (`touch logs/*.log`)
- Verify database state (psql queries)

### 👤 User Must Do Manually:
- Edit `/home/kimonokittens/.env` (sensitive credentials)
- Add cron jobs (`sudo crontab -e -u kimonokittens`)
- Monitor first live runs (tail -f logs)
- Verify cron execution (check logs after scheduled time)

---

**Last Updated**: November 18, 2025
**Implementation**: Template-based SMS (no LLM)
**Status**: Ready for production deployment

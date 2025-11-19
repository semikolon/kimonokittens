# Master Production Deployment Plan - November 2025

**Created**: November 18, 2025 at 01:50
**Status**: ✅ Ready for API/Browser Testing
**Last Updated**: November 19, 2025 at 12:30

### 🎯 CURRENT PROGRESS

✅ **Completed**:
- Prisma schema fix pushed (duplicate brace removed)
- Webhook deployment successful (12:27)
- 6 database migrations applied successfully
- Phone conversion fixed (spaces/dashes stripped)
- Code updated to use phoneE164 for SMS
- **Phone sync issue fixed** - phoneE164 auto-regenerated on update (commit 3f8afc9)
- **State directory + log files created** (Nov 19 12:18)
- **Phone E.164 conversion completed** - 3 tenants converted (Fredrik, Frida, Sanna)
- **Log file ownership corrected** - Changed to kimonokittens:kimonokittens
- **Cron jobs configured** - Bank sync 3x/day (8am, 2pm, 8pm) + reminders once daily (9:45am)

### ✅ READY FOR NEXT PHASE

**Remaining Tasks**:
- API endpoint testing (signup, rate limiting, admin leads)
- Browser testing of tenant signup + admin dashboard
- External service setup (Cloudflare Turnstile - optional)

---

## 📊 EXECUTIVE SUMMARY

This document consolidates **all outstanding deployment tasks** from the last 2-3 weeks of development work:

### ✅ Features Ready for Deployment

1. **Tenant Signup System** (PR #4 merged) - Web form + admin leads dashboard
2. **Rent Reminders System** (Template-based SMS) - Bank sync + automated SMS reminders
3. **Deposit Formula Fix** (Committed) - Split 24,884 kr evenly among tenants
4. **Gantt Timeline** (PR #3 merged) - Historic tenants timeline visualization
5. **Prisma Schema Fix** (Just pushed) - Removed duplicate closing brace blocking migrations

### 🎯 Key Findings

- **ELKS_SENDER**: NOT used in code (hardcoded as 'Katten' in `lib/sms/elks_client.rb:43`)
- **Peak/Off-Peak Pricing**: ✅ ALREADY IMPLEMENTED in electricity regression/anomaly analysis
- **Heatpump Schedule API**: Planned but not yet implemented (see Phase 7 below)

---

## 🤖 WHAT SERVERSIDE CC AGENT CAN DO (kimonokittens user)

### Phase 1: Immediate Tasks (After Webhook Completes)

#### 1.1 Monitor Webhook Deployment
```bash
# Watch webhook logs for completion
tail -f /var/log/kimonokittens/webhook.log

# Expected output:
# - git pull origin master
# - npm ci --legacy-peer-deps
# - npx vite build
# - rsync to /var/www/kimonokittens/dashboard/
# - "✅ Frontend files deployed"
```

#### 1.2 Verify Schema Fix Applied
```bash
cd /home/kimonokittens/Projects/kimonokittens
cat prisma/schema.prisma | grep -A 5 "model TenantLead"
# Should NOT show duplicate closing brace at line 116
```

#### 1.3 Run Database Migrations ⚠️ CRITICAL
```bash
cd /home/kimonokittens/Projects/kimonokittens
npx prisma migrate deploy
```

**Creates/Updates Tables:**
- `TenantLead` - Tenant signup leads tracking
- `BankTransaction` - Lunchflow bank sync storage
- `RentReceipt` - Payment-to-rent-period linking
- `SmsEvent` - SMS delivery audit log
- Extends `Tenant` - Adds `phoneE164`, `paydayStartDay`, `smsOptOut`

**Verification:**
```bash
psql -d kimonokittens_production -c "\dt" | grep -E "(TenantLead|BankTransaction|RentReceipt|SmsEvent)"

# Expected output (5 new tables):
# TenantLead
# BankTransaction
# RentReceipt
# SmsEvent
# Tenant (updated with new fields)
```

#### 1.4 Check Migration Status
```bash
npx prisma migrate status
# Expected: "Database schema is up to date!"
```

---

### Phase 2: Rent Reminders Setup

#### 2.1 Create State Directory
```bash
mkdir -p /home/kimonokittens/Projects/kimonokittens/state
```
**Purpose**: Stores `bank_sync.json` cursor for incremental transaction syncing

#### 2.2 Create Log Files
```bash
cd /home/kimonokittens/Projects/kimonokittens
touch logs/bank_sync.log logs/reminders.log
chmod 644 logs/bank_sync.log logs/reminders.log
```

#### 2.3 Update Tenant Phone Numbers (E.164 Format)

**Create script**: `/home/kimonokittens/Projects/kimonokittens/scripts/update_tenant_phones.rb`

```ruby
#!/usr/bin/env ruby
require 'dotenv/load'
require_relative '../lib/persistence'

puts "Updating tenant phone numbers to E.164 format..."

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

puts "\nSetting default payday preferences..."
# Set payday start days per tenant preference
# (User will provide specific values)
```

**Run script:**
```bash
bundle exec ruby scripts/update_tenant_phones.rb
```

#### 2.4 Dry-Run Testing (Preview Behavior)
```bash
cd /home/kimonokittens/Projects/kimonokittens

# Test bank sync (preview what WOULD sync)
bundle exec ruby bin/bank_sync --dry-run

# Test rent reminders (preview who WOULD receive SMS)
bundle exec ruby bin/rent_reminders --dry-run

# Review output - should show realistic data
```

---

### Phase 3: API Endpoint Testing (After Backend Restart)

#### 3.1 Test Tenant Signup API
```bash
# Successful submission
curl -X POST http://localhost:3001/api/signup \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Test Person",
    "contactMethod": "email",
    "contactValue": "test@example.com",
    "moveInFlexibility": "immediate"
  }'

# Expected: 200 OK with success message
```

#### 3.2 Test Rate Limiting
```bash
# Run 3 times from same IP
for i in {1..3}; do
  curl -X POST http://localhost:3001/api/signup \
    -H "Content-Type: application/json" \
    -d "{\"name\":\"Test$i\",\"contactMethod\":\"email\",\"contactValue\":\"test$i@example.com\",\"moveInFlexibility\":\"immediate\"}"
  echo "\n---"
done

# Third request should return 429 Too Many Requests
```

#### 3.3 Test Admin Leads API
```bash
# Get all leads (requires admin PIN)
curl http://localhost:3001/api/admin/leads \
  -H "X-Admin-Token: YOUR_PIN"

# Expected: JSON array of tenant leads
```

---

### Phase 4: Service Monitoring & Verification

#### 4.1 Monitor Backend Service Logs
```bash
# Check for startup errors after restart
journalctl -u kimonokittens-dashboard -n 50 | grep -E "(error|ERROR|failed)"

# Monitor real-time logs
journalctl -u kimonokittens-dashboard -f
```

#### 4.2 Verify Database State
```bash
# Check tenant lead records
psql -d kimonokittens_production -c "SELECT COUNT(*) FROM \"TenantLead\";"

# Check bank transactions (after first sync)
psql -d kimonokittens_production -c "SELECT COUNT(*) FROM \"BankTransaction\";"

# Check SMS events (after first reminder run)
psql -d kimonokittens_production -c "SELECT COUNT(*) FROM \"SmsEvent\";"
```

#### 4.3 Restart Kiosk Service (User Service)
```bash
systemctl --user restart kimonokittens-kiosk
systemctl --user status kimonokittens-kiosk
```

---

## 👤 WHAT USER MUST DO MANUALLY (fredrik/sudo)

### Phase 1: Initial Deployment (YOU - Mac Development Machine)

#### 1.1 Push Schema Fix ✅ DONE
```bash
cd ~/Projects/kimonokittens
git push origin master  # Triggers webhook deployment
```

**Status**: ✅ Completed at 01:45

#### 1.2 Wait for Webhook to Complete
- Monitor: `tail -f /var/log/kimonokittens/webhook.log`
- Confirm: npm ci, vite build, rsync all complete
- Look for: "✅ Frontend files deployed"

---

### Phase 2: Backend Service Restart (Requires Sudo)

#### 2.1 Restart Backend Service
```bash
sudo systemctl restart kimonokittens-dashboard
sudo systemctl status kimonokittens-dashboard
```

**Why**: Backend needs to load new code (signup handlers, rent reminder scripts)

#### 2.2 Verify Service Started Successfully
```bash
sudo systemctl status kimonokittens-dashboard
# Expected: "active (running)"

# Check for startup errors
journalctl -u kimonokittens-dashboard -n 100 | grep -E "(error|ERROR|failed)"
```

---

### Phase 3: Environment Variables Setup

#### 3.1 Edit Production .env File ✅ DONE
```bash
ssh pop
sudo nano /home/kimonokittens/.env
```

**Add/Verify:**
```bash
# Rent Reminders - Bank Sync
LUNCHFLOW_API_KEY=lf_live_XXXXXXXXXXXXXXXX
LUNCHFLOW_ACCOUNT_ID=4065

# Rent Reminders - SMS (46elks)
ELKS_USERNAME=u************
ELKS_PASSWORD=************
# Note: ELKS_SENDER not used - hardcoded as 'Katten' in lib/sms/elks_client.rb:43

# Admin notifications
ADMIN_PHONE=+467XXXXXXXX

# Tenant Signup - CAPTCHA (optional for now)
TURNSTILE_SECRET_KEY=<from Cloudflare>
```

**Status**: ✅ User confirmed all env vars added

---

### Phase 4: Cloudflare Turnstile (Optional - For CAPTCHA)

#### 4.1 Create Cloudflare Account
- Visit: https://dash.cloudflare.com
- Sign up / log in

#### 4.2 Add Site
- Site: kimonokittens.com
- Get `siteKey` and `secretKey`

#### 4.3 Update Frontend
```bash
# Edit www/signup.html (around line 180)
# Update: data-sitekey="YOUR_SITE_KEY"
```

#### 4.4 Update Backend
```bash
# Already in .env (from Phase 3):
TURNSTILE_SECRET_KEY=<secretKey>
```

#### 4.5 Push Changes
```bash
git add www/signup.html
git commit -m "feat: add Cloudflare Turnstile CAPTCHA to signup form"
git push origin master  # Triggers webhook redeploy
```

---

### Phase 5: Cron Jobs (Rent Reminders)

#### 5.1 Add Cron Jobs to kimonokittens User ✅ COMPLETED (Nov 19, 2025)
```bash
sudo crontab -e -u kimonokittens
```

**Added:**
```cron
# Bank sync 3x daily (morning, midday, evening) - Lunchflow syncs once per 24h
5 8,14,20 * * * /bin/bash -l -c 'eval "$(rbenv init -)"; cd /home/kimonokittens/Projects/kimonokittens && timeout 5m bundle exec ruby bin/bank_sync >> logs/bank_sync.log 2>&1'

# Rent reminders once daily at 09:45 - Per CODE_REVIEW decision (twice daily rejected)
45 9 * * * /bin/bash -l -c 'eval "$(rbenv init -)"; cd /home/kimonokittens/Projects/kimonokittens && timeout 2m bundle exec ruby bin/rent_reminders >> logs/reminders.log 2>&1'
```

**Frequency rationale:**
- **Bank sync 3x/day** (not hourly): Lunchflow syncs once per 24h, 3x polling captures transactions with <8h lag
- **Reminders once daily** (not twice): Second reminder same day has no new payment data (Lunchflow constraint)
- Per CODE_REVIEW_RENT_REMINDERS_REWORK.md (Nov 17, 2025) superseding earlier twice-daily plan

**Critical flags explained:**
- `eval "$(rbenv init -)"` - Loads Ruby environment
- `timeout Xm` - Prevents hanging processes (5min for sync, 2min for reminders)
- `bundle exec` - Required for vendor/bundle gems
- `>> logs/*.log 2>&1` - Append stdout+stderr to logs

#### 5.2 Verify Cron Jobs Added ✅ COMPLETED
```bash
sudo crontab -l -u kimonokittens | grep -E "(bank_sync|rent_reminders)"
# Should show 2 cron jobs (bank_sync, rent_reminders)
```

#### 5.3 Test Cron Execution (Schedule at Specific Time)

**Strategy**: Set cron to run 2-3 minutes from now, monitor logs

**Example** (if current time is 14:20):
```bash
sudo crontab -e -u kimonokittens

# Add temporary test job (run at 14:23):
23 14 * * * /bin/bash -l -c 'eval "$(rbenv init -)"; cd /home/kimonokittens/Projects/kimonokittens && timeout 5m bundle exec ruby bin/bank_sync >> logs/bank_sync.log 2>&1'
```

**Monitor:**
```bash
# Watch for cron execution
tail -f /home/kimonokittens/Projects/kimonokittens/logs/bank_sync.log

# Check syslog for cron triggers
grep -i "bank_sync\|rent.*reminder" /var/log/syslog | tail -20
```

**After verification**: Remove test job, keep production schedule

---

### Phase 6: Browser Testing (End-to-End)

#### 6.1 Tenant Signup Form
- [ ] Visit https://kimonokittens.com/meow (or /curious, /signup)
- [ ] Verify form renders correctly
- [ ] Test form submission with valid data
- [ ] Verify success modal appears
- [ ] Test CAPTCHA widget (after Turnstile setup)
- [ ] Test rate limiting (3rd request from same IP should fail)

#### 6.2 Admin Leads Dashboard
- [ ] Press Tab key to enter admin view
- [ ] Enter admin PIN
- [ ] Verify "Intressenter" section appears
- [ ] Verify new lead from signup test appears
- [ ] Test status changes (pending → reviewing → approved/rejected)
- [ ] Test adding notes to leads
- [ ] Test "Convert to Tenant" button
- [ ] Test delete lead button

#### 6.3 Gantt Timeline
- [ ] In admin view, verify historic tenants timeline displays
- [ ] Verify correct date ranges for past tenants
- [ ] Verify overlapping periods displayed correctly

#### 6.4 Take Screenshots for Verification
```bash
# Capture dashboard after testing
curl -s http://localhost:3001/api/screenshot/capture
curl -s http://localhost:3001/api/screenshot/latest > /tmp/dashboard_after_deployment.png
```

---

### Phase 7: Heatpump Schedule API Implementation (Future Work)

**Status**: Planned but NOT yet implemented
**Documentation**: `docs/HEATPUMP_SCHEDULE_API_PLAN.md`

**Goal**: Replace invalid Tibber API with Dell-based elprisetjustnu.se pricing + peak/off-peak logic for Node-RED heatpump scheduling

#### 7.1 Implementation Checklist (Dell API Endpoint)

**Reference**: Lines 188-287 in HEATPUMP_SCHEDULE_API_PLAN.md

- [ ] Create `handlers/heatpump_price_handler.rb`
- [ ] Copy `is_peak_hour?` method from `electricity_stats_handler.rb:479-497`
- [ ] Copy `swedish_holidays` method from `electricity_stats_handler.rb:418-470`
- [ ] Copy constants (GRID_TRANSFER_*, ENERGY_TAX_EXCL_VAT, VAT_MULTIPLIER)
- [ ] Add route to `puma_server.rb`:
  ```ruby
  map '/api/heatpump/prices' do
    run lambda { |env|
      electricity_price_handler = ElectricityPriceHandler.new
      heatpump_price_handler = HeatpumpPriceHandler.new(electricity_price_handler)
      heatpump_price_handler.call(Rack::Request.new(env))
    }
  end
  ```
- [ ] Test endpoint: `curl http://localhost:3001/api/heatpump/prices | jq`
- [ ] Verify 48 hours returned (today + tomorrow)
- [ ] Verify peak detection (spot-check 5 dates)
- [ ] Verify holiday detection (Christmas, Easter, Midsummer)
- [ ] Compare prices with electricity_stats_handler (should match)
- [ ] Commit to git
- [ ] Push to GitHub (triggers webhook deployment)

#### 7.2 Node-RED Flow Modification (Requires Dell + Pi Access)

**Reference**: Lines 289-342 in HEATPUMP_SCHEDULE_API_PLAN.md

**Requires**: Claude Code session on Dell with SSH access to Pi

- [ ] Backup current flows: `ssh pi@192.168.4.66 "cat ~/.node-red/flows.json" > flows-backup-$(date +%Y%m%d-%H%M).json`
- [ ] Access Node-RED UI: http://192.168.4.66:1880
- [ ] Create test tab: "Elpriset Testing"
- [ ] Add HTTP request node (Dell API at `http://192.168.4.84:3001/api/heatpump/prices`)
- [ ] Wire test flow: inject → http request → debug
- [ ] Verify response format matches ps-strategy-lowest-price expectations
- [ ] Clone ps-strategy-lowest-price to test tab (same config: 11hrs, 2.2kr max)
- [ ] Wire test schedule: http → ps-strategy → debug
- [ ] Test with manual inject
- [ ] Verify 11 cheapest hours selected

#### 7.3 Shadow Mode Testing (3 Days Minimum)

- [ ] Run test flow every 20 mins (parallel to production)
- [ ] Production flow still controls heatpump (safety)
- [ ] Log both schedules side-by-side
- [ ] Compare: Are test schedules reasonable?
- [ ] Check: Does peak avoidance work correctly?

#### 7.4 Production Cutover (When Validated)

- [ ] Disable Tibber flow (don't delete yet - rollback safety)
- [ ] Copy test flow nodes to production tab
- [ ] Wire: cronplus → http → ps-strategy → temperature-override → MQTT
- [ ] Deploy and monitor
- [ ] Monitor indoor temperature for 24 hours (should stay ≥ target)
- [ ] Monitor hot water temp (should stay ≥ 40°C)
- [ ] Verify heatpump uptime ~11 hours/day
- [ ] Document lessons learned

**Timeline**: 1-2 weeks implementation + 1 week testing
**Priority**: Medium (current system broken but heatpump manually controllable)

---

## 📋 PHASED ROLLOUT STRATEGY (RECOMMENDED)

### Week 1: Tenant Signup + Core Infrastructure

**Focus**: Get signup system live, database migrations applied

1. ✅ Push schema fix (DONE)
2. Wait for webhook completion
3. Restart backend service
4. Run database migrations
5. Test signup API endpoints
6. Browser testing of signup form
7. Monitor for 2-3 days

**Success Criteria**:
- Migrations applied successfully
- Signup form accessible at /meow
- Admin leads dashboard shows new signups
- Rate limiting works (3rd request blocked)

### Week 2: Rent Reminders - Bank Sync Only

**Focus**: Verify transaction syncing and payment matching

1. Create state directory + log files
2. Update tenant phone numbers (E.164)
3. Add ONLY bank_sync cron job (not reminders yet)
4. Monitor `logs/bank_sync.log` for 7 days
5. Verify `BankTransaction` and `RentReceipt` tables populate correctly
6. Check payment matching works

**Success Criteria**:
- Hourly syncs run without errors
- Bank transactions appear in database
- Payment matching correctly identifies Swish/reference payments

### Week 3: Rent Reminders - Dry-Run Testing

**Focus**: Verify message generation and recipient selection

1. Run `bin/rent_reminders --dry-run` manually daily
2. Review message format (dashboard-style templates)
3. Confirm recipient list matches expectations
4. Verify reminder schedule logic (day 23, payday, day 27, 28+)

**Success Criteria**:
- Dry-run output shows realistic reminders
- Message format matches dashboard style
- Recipient selection follows payday preferences

### Week 4: Rent Reminders - Live SMS

**Focus**: Enable actual SMS sending

1. Add reminder cron jobs (09:45 and 16:45)
2. Monitor first batch of SMS sends
3. Verify 46elks delivery receipts (SmsEvent table)
4. Watch for errors or delivery failures
5. Confirm no spam complaints from tenants

**Success Criteria**:
- SMS sent at scheduled times
- Delivery receipts logged correctly
- Tenants receive reminders as expected
- Zero complaints about message frequency/content

### Week 5-6: Heatpump Schedule API (If Time Permits)

**Focus**: Replace Tibber with Dell API + Node-RED integration

1. Implement Dell API endpoint
2. Test price calculations (peak/off-peak)
3. Node-RED shadow mode (3 days)
4. Production cutover
5. Monitor temperatures and heatpump behavior

**Success Criteria**:
- API returns 48h prices with peak/off-peak rates
- Node-RED accepts format, generates schedules
- Indoor temp stable, hot water ≥ 40°C
- Heatpump runs ~11 hours/day

---

## 🔍 MONITORING & TROUBLESHOOTING

### Log Files

```bash
# Webhook deployment logs
tail -f /var/log/kimonokittens/webhook.log

# Backend service logs (application logs)
journalctl -u kimonokittens-dashboard -f

# Bank sync logs
tail -f /home/kimonokittens/Projects/kimonokittens/logs/bank_sync.log

# Reminder logs
tail -f /home/kimonokittens/Projects/kimonokittens/logs/reminders.log

# Kiosk service logs
journalctl --user -u kimonokittens-kiosk -f
```

### Database Health Checks

```sql
-- Recent tenant leads
SELECT * FROM "TenantLead" ORDER BY "createdAt" DESC LIMIT 10;

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

### Common Issues & Solutions

#### Issue: Migrations fail with duplicate closing brace
**Solution**: ✅ Fixed - schema pushed, webhook deploying

#### Issue: Bank sync fails with "SSL verify failed"
**Solution**:
```ruby
# In lib/banking/lunchflow_client.rb, add to http setup:
http.verify_mode = OpenSSL::SSL::VERIFY_NONE
```

#### Issue: Reminders not sending
**Checks**:
- Verify ELKS_USERNAME and ELKS_PASSWORD in .env
- Test 46elks API: `curl -u username:password https://api.46elks.com/a1/Me`
- Check `logs/reminders.log` for errors
- Verify tenant `phoneE164` fields populated

#### Issue: Payment matching not working
**Checks**:
- Verify reference code format (no dashes: `KK202511Sannacmhqe9enc`)
- Check Swish transaction phone extraction
- Review bank transaction descriptions in database

#### Issue: Signup form shows 500 error
**Checks**:
- Backend service running: `sudo systemctl status kimonokittens-dashboard`
- Migrations applied: `npx prisma migrate status`
- Check backend logs: `journalctl -u kimonokittens-dashboard -n 50`

---

## ✅ VERIFICATION CHECKLIST

### Migrations & Database

- [ ] Prisma schema has no syntax errors
- [ ] `npx prisma migrate deploy` completed successfully
- [ ] `npx prisma migrate status` shows "up to date"
- [ ] TenantLead table exists: `psql -d kimonokittens_production -c "\dt TenantLead"`
- [ ] BankTransaction table exists
- [ ] RentReceipt table exists
- [ ] SmsEvent table exists
- [ ] Tenant table has new fields (phoneE164, paydayStartDay, smsOptOut)

### Tenant Signup System

- [ ] Signup form loads at /meow endpoint
- [ ] Form submission creates TenantLead records
- [ ] Admin dashboard shows leads in real-time
- [ ] Rate limiting works (3rd request blocked)
- [ ] CAPTCHA validates (after Turnstile setup)

### Rent Reminders System

- [ ] State directory exists: `/home/kimonokittens/Projects/kimonokittens/state`
- [ ] Log files exist and are writable: `logs/bank_sync.log`, `logs/reminders.log`
- [ ] Tenant phone numbers in E.164 format
- [ ] Payday preferences set per tenant
- [ ] Dry-run tests pass without errors
- [ ] Cron jobs added to kimonokittens user
- [ ] First bank sync successful (check logs after XX:05)
- [ ] First reminder preview looks correct (dry-run)

### Services & Infrastructure

- [ ] Backend service running: `sudo systemctl status kimonokittens-dashboard`
- [ ] Kiosk service running: `systemctl --user status kimonokittens-kiosk`
- [ ] Webhook service running: `sudo systemctl status kimonokittens-webhook`
- [ ] No errors in backend logs (journalctl)
- [ ] Frontend deployed to `/var/www/kimonokittens/dashboard/`
- [ ] Environment variables set in `/home/kimonokittens/.env`

### End-to-End Testing

- [ ] Signup form accessible and functional
- [ ] Admin leads dashboard displays correctly
- [ ] Gantt timeline shows historic tenants
- [ ] Bank sync populates transactions
- [ ] Rent reminders generate realistic messages
- [ ] SMS delivery receipts logged (after going live)

---

## 🚨 CRITICAL NOTES

1. **ELKS_SENDER NOT USED**: Hardcoded as 'Katten' in `lib/sms/elks_client.rb:43` - env var is documentation only
2. **Peak/Off-Peak Pricing ALREADY WORKS**: ✅ Implemented in electricity_stats_handler.rb:84 - regression/anomaly bar uses correct pricing
3. **Migrations are manual**: Webhook doesn't auto-run database migrations - must run `npx prisma migrate deploy`
4. **Cron requires bundle exec**: Essential for vendor/bundle gems
5. **Test dry-run first**: Never go live without `--dry-run` verification
6. **Phased rollout recommended**: Start with signup + bank sync, add SMS later
7. **Heatpump API is future work**: Not yet implemented, see Phase 7 above

---

## 📚 REFERENCE DOCUMENTATION

- **Tenant Signup**: `docs/TENANT_SIGNUP_IMPLEMENTATION_SUMMARY.md`
- **Rent Reminders**: `docs/PRODUCTION_DEPLOYMENT_RENT_REMINDERS.md`
- **Rent Reminders Code Review**: `docs/CODE_REVIEW_RENT_REMINDERS_REWORK.md`
- **Deployment Tasks**: `docs/TENANT_SIGNUP_DEPLOYMENT_TASKS.md`
- **Heatpump Schedule API**: `docs/HEATPUMP_SCHEDULE_API_PLAN.md`
- **General Deployment**: `DELL_OPTIPLEX_KIOSK_DEPLOYMENT.md`
- **Database Migration Protocol**: `CLAUDE.md` (lines 86-155)

---

## 🎯 SUCCESS METRICS

### Technical Metrics (2 Weeks Post-Deployment)

- ✅ All migrations applied successfully
- ✅ Zero database errors in logs
- ✅ Signup form conversion rate > 50% (test submissions successful)
- ✅ Admin dashboard real-time updates working
- ✅ Bank sync uptime ≥ 99% (max 1 hour downtime)
- ✅ SMS delivery rate ≥ 95%
- ✅ Zero rate limit false positives

### Operational Metrics (1 Month Post-Deployment)

- ✅ Tenant signups tracked successfully
- ✅ Rent reminders sent on schedule
- ✅ Payment matching accuracy ≥ 90%
- ✅ Zero manual intervention needed for rent tracking
- ✅ SMS opt-out system working (if tenants request)

### Financial Metrics (After Heatpump API Deployment)

- ✅ Peak hour avoidance > 50% of heating during off-peak
- ✅ Electricity cost reduction: Target 10-15% vs Tibber baseline
- ✅ Monthly savings: ~400-500 kr (from peak avoidance optimization)

---

**Next Action**: Wait for webhook deployment to complete, then proceed with Phase 1.3 (Run Database Migrations).

**Deployment Owner**: Fredrik (user)
**Assistant**: Serverside CC Agent (kimonokittens user)
**Timeline**: 4-6 weeks for complete rollout (phased approach)

---

## 📋 APPENDIX: RentLedger Period Migration (November 19, 2025)

### Status: ✅ COMPLETED IN PRODUCTION

**Context:** Discovered architectural inconsistency while implementing December rent ledger population.

**The Issue:**
- RentConfig.period = config month (Nov config → Dec rent) ✅
- RentLedger.period = rent month (Dec ledger = Dec rent) ❌
- **Problem:** Same field name, different semantics → confusion for devs/agents

**Decision:** Unify semantics - both should use config month for coherence.

**Migration Completed:**
1. ✅ Database: All 40 RentLedger entries shifted -1 month (Nov → Oct for Dec rent)
2. ✅ RentLedger model: Added `config_to_rent_month()` and `swedish_rent_month()` helpers
3. ✅ bin/populate_monthly_ledger: Updated to use rent month for display, fixed >= bug
4. ✅ bin/rent_reminders: Converts config → rent month for SMS
5. ✅ handlers/elks_webhooks.rb: Uses `period_swedish` for SMS replies
6. ✅ Verified: apply_bank_payment, admin_contracts_handler, rent_calculator_handler (no changes needed)
7. ✅ Merged to master and pushed to GitHub

**Next Steps (Post-Migration):**
1. Run migration on Mac dev environment: `bundle exec ruby bin/migrate_rent_ledger_periods`
2. Run full test suite on Mac
3. Create December 2025 rent ledger entries: `bundle exec ruby bin/populate_monthly_ledger 2025 11`
4. Decide Rasmus departure date (Nov 30 vs Dec 1)
5. Fill historical gaps (Sept, Oct 2025 ledgers) if needed

**Migration Details:** See `docs/RENT_LEDGER_PERIOD_MIGRATION_PLAN.md` for complete documentation.

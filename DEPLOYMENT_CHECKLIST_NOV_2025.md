# Deployment Checklist - November 2025

## Overview

This document compiles all outstanding deployment tasks from the last 2-3 weeks of development work. Tasks are organized by who can execute them and in what order.

---

## 📊 Features Ready for Deployment

### 1. **Tenant Signup System** ✅ Code Complete (PR #4 merged)
- **Status**: Merged to master (commit 8ca3ed2), needs production deployment
- **Components**:
  - Frontend signup form (`www/signup.html`)
  - Backend API (`handlers/tenant_signup_handler.rb`)
  - Admin leads dashboard (`dashboard/src/components/admin/LeadsSection.tsx`)
  - Rate limiting (2 requests per IP per hour)
  - Database model: `TenantLead`
- **Migration**: `20251117200951_add_tenant_lead_model`
- **Pending**: Cloudflare Turnstile setup, SMS notifications (optional)

### 2. **Rent Reminders System** ✅ Code Complete
- **Status**: Fully implemented with LLM integration
- **Components**:
  - Lunchflow API integration (`lib/lunchflow_client.rb`)
  - Bank transaction tracking (`lib/models/bank_transaction.rb`)
  - SMS event logging (`lib/models/sms_event.rb`)
  - Rent receipt tracking (`lib/models/rent_receipt.rb`)
  - Message composer with GPT-5-mini (`lib/message_composer.rb`)
- **Migrations**: 5 migrations (20251115005500-20251115010000)
- **Pending**: Lunchflow API credentials, 46elks SMS API setup

### 3. **Deposit Formula Fix** ✅ Complete
- **Status**: Fixed and tested (commit 681ff6a)
- **Change**: Split fixed total deposit (24,884 kr) evenly among tenants
- **No deployment needed**: Pure code fix, already in master

### 4. **Gantt Timeline for Historic Tenants** ✅ Complete
- **Status**: Merged (PR #3), should be deployed
- **Component**: `dashboard/src/components/admin/HistoricTenantsTimeline.tsx`
- **No migration needed**: Frontend-only feature

### 5. **Prisma Schema Fix** 🔧 Just Fixed
- **Status**: Duplicate closing brace removed (commit 3a3579c)
- **Impact**: Unblocks all Prisma operations
- **Needs**: Push to trigger webhook deployment

---

## 🎯 Deployment Tasks Breakdown

### PHASE 1: Schema Fix & Infrastructure (IMMEDIATE)

#### Manual Tasks (YOU):
1. **Push schema fix to production**
   ```bash
   cd ~/Projects/kimonokittens  # On Mac
   git push origin master  # Triggers webhook
   ```

#### Assisted Tasks (I can help):
2. **Verify webhook deployment**
   - Monitor: `tail -f /var/log/kimonokittens/webhook.log`
   - Confirm: npm ci, vite build, rsync all complete

3. **Verify schema fix**
   ```bash
   cd /home/kimonokittens/Projects/kimonokittens
   npx prisma migrate status  # Should work now
   ```

---

### PHASE 2: Database Migrations (CRITICAL)

#### Assisted Tasks (I can help):
1. **Run pending migrations**
   ```bash
   cd /home/kimonokittens/Projects/kimonokittens
   npx prisma migrate deploy
   ```

2. **Verify migrations applied**
   ```bash
   npx prisma migrate status  # Should show all up to date
   psql $DATABASE_URL -c "\dt" | grep -E "TenantLead|BankTransaction|SmsEvent|RentReceipt"
   ```

3. **Check for migration errors**
   ```bash
   journalctl -u kimonokittens-dashboard -n 100 | grep -i "prisma\|migration\|error"
   ```

---

### PHASE 3: External Service Setup (MANUAL)

#### Manual Tasks (YOU):
1. **Cloudflare Turnstile (for tenant signup CAPTCHA)**
   - [ ] Create account: https://dash.cloudflare.com
   - [ ] Add site: kimonokittens.com
   - [ ] Copy `siteKey` → Update `www/signup.html` line ~180
   - [ ] Copy `secretKey` → Add to `/home/kimonokittens/.env` as `TURNSTILE_SECRET_KEY=...`
   - [ ] Push changes (triggers webhook redeploy)

2. **Lunchflow API (for rent reminders - bank sync)**
   - [ ] Get API credentials from Lunchflow
   - [ ] Add to `/home/kimonokittens/.env`:
     ```
     LUNCHFLOW_API_KEY=your_key_here
     LUNCHFLOW_ACCOUNT_ID=your_account_id
     ```

3. **46elks SMS API (for rent reminders - optional)**
   - [ ] Create account: https://46elks.com
   - [ ] Get API credentials
   - [ ] Add to `/home/kimonokittens/.env`:
     ```
     ELKS_USERNAME=your_username
     ELKS_PASSWORD=your_password
     ```

---

### PHASE 4: Service Restarts & Verification

#### Manual Tasks (YOU - requires sudo):
1. **Restart backend service**
   ```bash
   sudo systemctl restart kimonokittens-dashboard
   sudo systemctl status kimonokittens-dashboard  # Verify running
   ```

#### Assisted Tasks (I can help):
2. **Restart kiosk display**
   ```bash
   systemctl --user restart kimonokittens-kiosk
   ```

3. **Check for startup errors**
   ```bash
   journalctl -u kimonokittens-dashboard -n 50 | grep -E "(error|ERROR|failed)"
   ```

---

### PHASE 5: End-to-End Testing

#### Manual Tests (YOU - requires browser):

**Tenant Signup Form:**
1. [ ] Visit https://kimonokittens.com/meow (or /curious, /signup)
2. [ ] Verify form renders correctly
3. [ ] Test form submission with valid data
4. [ ] Verify success modal appears
5. [ ] Verify CAPTCHA widget (after Turnstile setup)
6. [ ] Test rate limiting (3rd request from same IP should fail)

**Admin Leads Dashboard:**
7. [ ] Press Tab key to enter admin view
8. [ ] Enter admin PIN
9. [ ] Verify "Intressenter" section appears
10. [ ] Verify new lead from signup test appears
11. [ ] Test status changes (pending → reviewing → approved/rejected)
12. [ ] Test adding notes to leads
13. [ ] Test "Convert to Tenant" button
14. [ ] Test delete lead button

**Gantt Timeline:**
15. [ ] In admin view, verify historic tenants timeline displays
16. [ ] Verify correct date ranges for past tenants
17. [ ] Verify overlapping periods displayed correctly

#### Assisted API Tests (I can help):

**Signup Endpoint:**
```bash
# Test successful submission
curl -X POST http://localhost:3001/api/signup \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Test Person",
    "contactMethod": "email",
    "contactValue": "test@example.com",
    "moveInFlexibility": "immediate",
    "turnstileToken": "dummy_token_for_testing"
  }'

# Test rate limiting (run 3 times)
for i in {1..3}; do
  curl -X POST http://localhost:3001/api/signup \
    -H "Content-Type: application/json" \
    -d '{"name":"Test'$i'","contactMethod":"email","contactValue":"test'$i'@example.com","moveInFlexibility":"immediate"}'
  echo "\n---"
done
# Third request should return 429 Too Many Requests
```

**Admin Leads Endpoint:**
```bash
# Get all leads (requires PIN)
curl http://localhost:3001/api/admin/leads \
  -H "X-Admin-Token: YOUR_PIN"

# Update lead status
curl -X PATCH http://localhost:3001/api/admin/leads/LEAD_ID \
  -H "Content-Type: application/json" \
  -H "X-Admin-Token: YOUR_PIN" \
  -d '{"status": "reviewing"}'
```

---

### PHASE 6: Cron Jobs Setup & Testing (FUTURE - for rent reminders)

#### Manual Tasks (YOU - requires sudo):

1. **Install cron jobs** (when ready to activate rent reminders)
   ```bash
   # Daily Lunchflow sync (fetch bank transactions)
   sudo crontab -e -u kimonokittens
   # Add:
   0 8 * * * cd /home/kimonokittens/Projects/kimonokittens && bundle exec ruby scripts/sync_lunchflow.rb >> /var/log/kimonokittens/lunchflow-sync.log 2>&1

   # Daily rent reminders check
   0 9 * * * cd /home/kimonokittens/Projects/kimonokittens && bundle exec ruby scripts/check_rent_reminders.rb >> /var/log/kimonokittens/rent-reminders.log 2>&1
   ```

2. **Test cron execution immediately**
   ```bash
   # Set cron to run 2 minutes from now
   # At HH:MM (current time + 2 min):
   MM HH * * * cd /home/kimonokittens/Projects/kimonokittens && bundle exec ruby scripts/sync_lunchflow.rb >> /var/log/kimonokittens/lunchflow-sync.log 2>&1

   # Wait 2 minutes, then check:
   tail -f /var/log/kimonokittens/lunchflow-sync.log
   # Verify no errors, transactions fetched successfully
   ```

#### Assisted Tasks (I can help):
3. **Monitor cron execution**
   ```bash
   # Check if cron ran
   grep -i "lunchflow\|rent.*reminder" /var/log/syslog | tail -20

   # Check script output
   tail -50 /var/log/kimonokittens/lunchflow-sync.log
   tail -50 /var/log/kimonokittens/rent-reminders.log
   ```

4. **Verify database updates**
   ```bash
   # Check if bank transactions were imported
   psql $DATABASE_URL -c "SELECT COUNT(*) FROM \"BankTransaction\";"

   # Check recent SMS events
   psql $DATABASE_URL -c "SELECT * FROM \"SmsEvent\" ORDER BY \"createdAt\" DESC LIMIT 5;"
   ```

---

## 🔍 Recommended Deployment Order

1. **NOW**: Push Prisma schema fix → triggers webhook
2. **AFTER webhook completes**: Run database migrations
3. **AFTER migrations**: Test tenant signup + admin leads locally (curl)
4. **WHEN READY**: Set up Cloudflare Turnstile
5. **WHEN READY**: Set up Lunchflow API + 46elks
6. **WHEN READY**: Install cron jobs for rent reminders
7. **FINAL**: End-to-end browser testing

---

## 📝 Outstanding Optional Tasks

### Low Priority:
- [ ] Extract Horsemen font from PopOS system fonts (visual polish)
- [ ] Implement log rotation for `/var/log/kimonokittens/` (disk space management)
- [ ] Logo burn-in prevention (pixel drift implementation - 5min task)
- [ ] Monitor brightness schedule verification (test during daytime)

### Deferred:
- [ ] Contract replacement workflow (delete + re-sign for completed contracts)
- [ ] Heatpump peak avoidance optimization (requires Node-RED config on Pi)
- [ ] Facebook profile pic avatars in admin UI

---

## 🚨 Known Issues to Watch

1. **Webhook self-update limitation**: If webhook code changes, manual restart required
   ```bash
   sudo systemctl restart kimonokittens-webhook
   ```

2. **Display rotation persistence**: Monitor for reset after next power outage
   - If it happens: `sudo cp /home/kimonokittens/.config/monitors.xml /etc/xdg/monitors.xml`

3. **Brightness schedule**: May be stuck at 0.7 - test during daytime (10am-4pm)

---

## 📊 Success Criteria

### Tenant Signup:
- ✅ Form loads at /meow endpoint
- ✅ Submissions create TenantLead records
- ✅ Admin dashboard shows leads in real-time
- ✅ Rate limiting works (3rd request blocked)
- ✅ CAPTCHA validates (after Turnstile setup)

### Rent Reminders:
- ✅ Cron jobs run without errors
- ✅ Bank transactions sync daily from Lunchflow
- ✅ Overdue rent detected and logged
- ✅ SMS reminders sent (after 46elks setup)
- ✅ Payment reconciliation works

### Admin Dashboard:
- ✅ Tab-key navigation works
- ✅ PIN authentication works
- ✅ Real-time WebSocket updates
- ✅ All CRUD operations functional
- ✅ Gantt timeline displays correctly

---

## 📚 Reference Documentation

- **Tenant Signup**: `docs/TENANT_SIGNUP_IMPLEMENTATION_SUMMARY.md`
- **Deployment Tasks**: `docs/TENANT_SIGNUP_DEPLOYMENT_TASKS.md`
- **Rent Reminders**: Check git log for implementation details
- **Admin Dashboard**: `docs/ZIGNED_WEBHOOK_IMPLEMENTATION_PLAN.md` (Phase 6)
- **General Deployment**: `DELL_OPTIPLEX_KIOSK_DEPLOYMENT.md`

---

**Created**: November 18, 2025 at 00:45
**Last Updated**: November 18, 2025 at 00:45

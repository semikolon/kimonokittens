# Admin Alerts: Payday-Aware Implementation Plan

**Session Date:** Nov 26, 2025
**Context:** Implementing intelligent admin alerts for unpaid rent that respect individual tenant paydays

---

## User Requirements (Verbatim)

> "I don't need to be notified when things are going smoothly. But if we're nearing deadline and are missing someone's rent or they only swished partial rent, then I need to be notified, if we're in danger of becoming later than usual in paying total house rent."

> "I have to open an email and click a button to pay house rent and then it will schedule a bank payment. That payment is rather slow, takes a bank day or so usually, and it does some kinda pre-check that the balance in the Huset account covers the transaction amount, that pre-check sometimes (always?) runs the night before the actual money is drawn, so it has historically failed if I trigger the bank payment too early (before everyone has Swished - Swish is instant) so I have made it a point to be careful to KNOW all the money is in the account before I click to pay house rent."

> "I just... knew that at least I personally always get paid my sjukpenning at midnight between the 26th/27th, so I wanted some time margin before I got alerted via SMS that I myself had not paid rent :P Maybe the system can be intelligent based on knowing our paydays, as it does?"

---

## Critical House Rent Payment Workflow

**The Process:**
1. Fredrik receives an email to pay house rent
2. Clicks button in email → triggers bank payment scheduling
3. Bank payment takes ~1 bank day to process
4. **Pre-check**: Bank verifies balance the NIGHT BEFORE drawing money
5. **Critical**: If balance insufficient during pre-check, payment FAILS
6. **Therefore**: Fredrik must KNOW all tenant payments are in before clicking button

**Timing Constraints:**
- **Ideal**: House rent paid on day 27
- **Acceptable**: House rent paid on day 28 (one day late)
- **Fredrik's payday**: Midnight between day 26/27 (Försäkringskassan sjukpenning)
- **Most tenants' payday**: Day 25 (Swedish norm)
- **Swish**: Instant payment (used by tenants)
- **Bank transfer**: Takes 1+ bank days (used for house rent)

**Why Early Alerts Matter:**
- Fredrik needs time to follow up with late-paying tenants
- If alerted on day 27 at 10am but needs to pay house rent same day, very tight window
- Pre-check failure means another day's delay
- Need buffer time before deadline to avoid house rent being late

---

## Current System Status (Nov 26, 2025)

### ✅ Working Components:
1. **Bank sync** (3x daily at 8:05, 14:05, 20:05)
   - Lunchflow API: Account ID 4653 "Huset"
   - Subscription: Active (35 EUR/year, renewed Nov 25)
   - Status: Syncing successfully
   - Last sync: 10 transactions fetched Nov 26

2. **Payment matching** (`ApplyBankPayment`)
   - 4-tier matching: reference code → phone number → amount+timing → fuzzy name
   - Real implementation: ✅ Committed (commit bf87336)
   - SMS methods: Empty stubs (no spam on payment)
   - Status: **NOT YET DEPLOYED** (needs push to master)

3. **Rent reminders** (`bin/rent_reminders`)
   - Sends reminders to TENANTS (heads_up, first_reminder, urgent, overdue)
   - Sends alerts to ADMIN when tenants unpaid
   - Status: **DISABLED** (cron commented out since Nov 26)
   - Reason: Payment detection was broken, would spam incorrect alerts

### ❌ Issues to Fix:
1. **Hour restrictions in admin alerts**
   - Current: Hour checks for urgency emoji only
   - User request: "Hour-restrictions are a bit of an overly strict idea and should be removed everywhere"
   - Action: Remove hour checks entirely

2. **No payday awareness**
   - Current: Flags ALL unpaid tenants equally on day 27+
   - Problem: Fredrik gets flagged 9 hours after midnight payday (too early)
   - Solution: Only flag tenant as unpaid AFTER their payday has passed

3. **Alert timing not optimal**
   - Current: Alerts start on day 27
   - User need: Earlier warning (day 26) for tenants who should've paid by day 25
   - Solution: Start alerts on day 26 with different urgency levels

---

## Implementation Plan: Payday-Aware Admin Alerts

### Database: Tenant.paydayStartDay
- **Fredrik**: 27 (Försäkringskassan, midnight 26/27)
- **Most others**: 25 (Swedish norm)
- **Default**: 25 (if NULL)

### Alert Logic (Pseudo-code)

```ruby
# Admin deadline alerts with payday awareness
if current_day >= 26  # Start checking from day 26

  unpaid_tenants = active_tenants.select do |tenant|
    ledger = Persistence.rent_ledger.find_by_tenant_and_period(
      tenant.id,
      Date.parse("#{current_month}-01")
    )
    next false unless ledger

    receipts = Persistence.rent_receipts.find_by_tenant(
      tenant.id,
      year: now.year,
      month: now.month
    )
    total_paid = receipts.sum(&:amount)
    remaining = ledger.amount_due - total_paid

    # PAYDAY-AWARE: Only flag as unpaid if their payday has passed
    payday = tenant.payday_start_day || 25  # Default to Swedish norm
    has_reached_payday = current_day >= payday

    # Only alert if unpaid AND past their payday
    remaining > 0 && has_reached_payday
  end

  if unpaid_tenants.any?
    names = unpaid_tenants.map(&:name).join(', ')

    # Urgency based on day (NO HOUR CHECKS)
    urgency, message_prefix = case current_day
    when 26
      ["ℹ️", "Påminnelse: "]  # Info: 24hr warning
    when 27
      ["⚠️", ""]              # Warning: Deadline day
    else  # Day 28+
      ["🚨", "SENT: "]        # Critical: House rent now late
    end

    alert_message = "#{urgency} #{message_prefix}#{names} har inte betalt än (#{current_month})"

    if dry_run
      puts "\n  📲 Would send admin alert:"
      puts "     #{alert_message}"
    else
      begin
        SmsGateway.send_admin_alert(alert_message)
        puts "  📤 Sent admin alert about #{unpaid_tenants.length} unpaid tenant(s)"
      rescue => e
        puts "  ❌ Failed to send admin alert: #{e.message}"
      end
    end
  else
    puts "  ✅ All tenants have paid (accounting for paydays) - no admin alert needed"
  end
end
```

### Expected Behavior Examples

**Scenario: November 2025**
- Current tenants: Fredrik (payday 27), Adam, Rasmus, Sanna, Frida (payday 25)

**Day 26, 9:45am:**
- Check: Who has payday ≤ 26 AND hasn't paid?
- If Adam/Rasmus/Sanna/Frida unpaid: "ℹ️ Påminnelse: Adam McCarthy, Rasmus Kasurinen, Sanna Juni Benemar, Frida Johansson har inte betalt än (2025-11)"
- Fredrik NOT included (his payday is 27, not reached yet)

**Day 27, 9:45am:**
- Check: Who has payday ≤ 27 AND hasn't paid?
- Now Fredrik's payday has passed (9 hours ago at midnight)
- If Fredrik + others unpaid: "⚠️ Fredrik Bränström, Adam McCarthy har inte betalt än (2025-11)"
- More urgent emoji, no extra prefix

**Day 28, 9:45am:**
- Check: Everyone's payday has passed
- If anyone unpaid: "🚨 SENT: Fredrik Bränström har inte betalt än (2025-11)"
- Critical emoji + "SENT" prefix (house rent is now late)

**Day 29+:**
- Same as day 28 logic, continues daily

---

## Changes to Make

### File: `bin/rent_reminders`

**Changes:**
1. Remove hour checks (`current_hour == 10`, `current_hour == 17`)
2. Start admin alerts on day 26 (not day 27)
3. Add payday awareness to unpaid tenant selection
4. Update urgency/message based on day only (not hour)

**Lines to modify:** ~200-245 (admin alert section)

### SMS Stubs in ApplyBankPayment

**Keep as empty stubs (no changes needed):**
- `send_admin_confirmation()` - NO SMS on payment received
- `check_deadline_and_alert()` - NO SMS on partial payment

**Rationale:** Admin only needs to know about MISSING payments approaching deadline, not about payments that DO arrive.

---

## Deployment Steps

1. ✅ **Bank sync with real payment matching** (committed bf87336)
   - Push to master
   - Webhook auto-deploys
   - Verify 4 November payments get matched

2. **Rent reminders with payday-aware alerts** (this document)
   - Implement changes in `bin/rent_reminders`
   - Test with `--dry-run` flag
   - Commit and push
   - Uncomment cron job: `45 9 * * * .../bin/rent_reminders`

3. **Verify end-to-end**
   - Wait for next morning (9:45am)
   - Check if admin alert respects paydays
   - Verify no spam about Fredrik before day 27

---

## Testing Commands

```bash
# Dry-run to test logic without sending SMS
bundle exec ruby bin/rent_reminders --dry-run

# Check current ledger state
bundle exec ruby -e "
require 'dotenv/load'
require_relative 'lib/persistence'
require 'date'

ledger_repo = Persistence.rent_ledger
tenant_repo = Persistence.tenants

[Date.new(2025, 11, 1)].each do |period|
  puts \"\\n=== Period: #{period.strftime('%Y-%m')} ===\"
  entries = ledger_repo.find_by_period(period)

  entries.each do |entry|
    tenant = tenant_repo.find_by_id(entry.tenant_id)
    puts \"#{tenant&.name} (payday: #{tenant&.payday_start_day || 25}):\"
    puts \"  Due: #{entry.amount_due} kr\"
    puts \"  Paid: #{entry.amount_paid || 0} kr\"
    puts \"  Status: #{entry.payment_status}\"
  end
end
"

# Check cron status
crontab -l | grep -E "bank_sync|rent_reminders"
```

---

## Documentation Updates Needed

1. **CLAUDE.md** - Update "PAYMENT DETECTION & RENT REMINDERS" section:
   - Mark payment matching as ✅ Active
   - Mark rent reminders as 🔄 Updated with payday-aware logic
   - Remove "temporarily disabled" status once re-enabled

2. **docs/RENT_REMINDERS_IMPLEMENTATION_PLAN.md**:
   - Add section on payday-aware admin alerts
   - Document the house rent payment workflow
   - Explain why early alerts matter (bank pre-check timing)

3. **TODO.md** - Update rent reminders status:
   - Mark bank sync as operational
   - Mark payment matching as deployed
   - Update rent reminders to "payday-aware logic implemented"

---

## Key Insights for Future Reference

**Why Payday Awareness Matters:**
- Tenants get paid on different days (Fredrik: 27, others: 25)
- Alerting too early = spam ("you just got paid 9 hours ago!")
- Alerting too late = no time to follow up before house rent due
- Solution: Respect individual `paydayStartDay` values

**Why Hour Checks Don't Help:**
- Cron runs once daily at 9:45am
- Hour checks (10am, 5pm) never fire because cron doesn't run then
- Hour checks were "removed for immediate testing" but lingered in code
- Better: Day-based urgency levels, run whenever cron triggers

**Why Empty SMS Stubs Are Correct:**
- Payment matching should be silent when successful
- Only alert on PROBLEMS (missing/late payments)
- Admin doesn't need confirmation spam for every Swish payment
- Scheduled reminders handle the "who hasn't paid" checking

---

## Session Context

**What triggered this work:**
1. Lunchflow subscription renewed Nov 25 (was expired)
2. Bank sync working, but payment matching was MOCKED
3. 4/5 November tenants paid (Fredrik late), sitting unmatched in DB
4. Rent reminders disabled to prevent incorrect alerts during Lunchflow outage
5. Need to re-enable with improved payday-aware logic

**Current state (Nov 26, 2025):**
- Bank sync: ✅ Active, syncing successfully
- Payment matching: ✅ Implemented, not yet deployed
- Rent reminders: ❌ Disabled, needs payday-aware upgrade
- Fredrik's rent: ❌ Still unpaid (only one missing)

**Next session should:**
1. Push payment matching to production (commit bf87336)
2. Implement payday-aware admin alerts in rent_reminders
3. Test with --dry-run
4. Deploy and re-enable cron
5. Monitor first real run (next day 9:45am)

---

**End of Brain Dump**

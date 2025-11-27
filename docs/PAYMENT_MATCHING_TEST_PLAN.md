# Payment Matching System - Complete Implementation & Test Plan

**Date:** Nov 26-27, 2025
**Status:** Ready to Implement
**Context:** TDD approach with multi-day aggregation + deposit detection + threshold rules
**Goal:** Bulletproof payment matching with complete edge case coverage
**Production Data:** `spec/fixtures/production_snapshot.json` (exported Nov 27, 2025)

---

## 🧪 Running RSpec in Claude Code Environment

**Challenge:** Claude Code shell doesn't have rbenv initialized by default, so `bundle exec rspec` fails.

**Solution:** Use full paths to Ruby 3.3.8 binaries:
```bash
/Users/fredrikbranstrom/.rbenv/versions/3.3.8/bin/ruby \
  /Users/fredrikbranstrom/.rbenv/versions/3.3.8/lib/ruby/gems/3.3.0/gems/rspec-core-3.13.5/exe/rspec \
  spec/services/payment_matching_edge_cases_spec.rb --format documentation
```

This bypasses `bundle exec` entirely but still works correctly with the test suite and database isolation.

---

## 📊 Test Data Setup

### Production Data Snapshot

**File:** `spec/fixtures/production_snapshot.json`
**Exported:** Nov 27, 2025 13:13:38 +01:00
**Contents:**
- **13 tenants** (5 active, 8 departed/inactive) with real names, phones, room assignments
- **15 rent configs** (last 3 months: Sep-Nov 2025) with actual electricity costs, utilities
- **13 rent ledgers** (last 3 months) with expected rent amounts per tenant

**Key Test Tenants:**
| Name | Phone | Room | Start Date | Payday | Expected Rent (Nov) |
|------|-------|------|------------|--------|---------------------|
| Adam McCarthy | +46760177088 | Höger uppe | 2025-03-01 | Day 25 | 6,302 kr |
| Frida Johansson | +46739764479 | Vänster nere | 2025-08-28 | Day 25 | 5,896 kr |
| Rasmus Kasurinen | +46738174974 | Vänster uppe | 2024-01-22 | Day 25 | 4,903 kr |
| Sanna Juni Benemar | +46702894437 | Höger nere | 2025-10-21 | Day 25 | 6,303 kr |
| Fredrik Bränström | +46708822234 | Höger nere | 2013-09-15 | Day 27 | 6,303 kr |

### Usage in Tests

```ruby
# spec_helper.rb - Load production snapshot before suite
RSpec.configure do |config|
  config.before(:suite) do
    data = JSON.parse(File.read('spec/fixtures/production_snapshot.json'))

    # Seed test database with production tenants
    data['tenants'].each do |tenant_data|
      Persistence.tenants.create(Tenant.new(
        id: tenant_data['id'],
        name: tenant_data['name'],
        email: tenant_data['email'],
        phone_e164: tenant_data['phone_e164'],
        room: tenant_data['room'],
        start_date: tenant_data['start_date'] ? Date.parse(tenant_data['start_date']) : nil,
        departure_date: tenant_data['departure_date'] ? Date.parse(tenant_data['departure_date']) : nil,
        room_adjustment: tenant_data['room_adjustment'],
        payday_start_day: tenant_data['payday_start_day'],
        status: tenant_data['status']
      ))
    end

    # Seed rent configs (last 3 months)
    data['rent_configs'].each do |config|
      Persistence.rent_configs.set(
        config['key'],
        config['value'],
        Date.parse(config['period'])
      )
    end

    # Seed rent ledgers
    data['rent_ledgers'].each do |ledger|
      Persistence.rent_ledger.create(RentLedger.new(
        tenant_id: ledger['tenant_id'],
        period: Date.parse(ledger['period']),
        amount_due: ledger['amount_due'],
        amount_paid: ledger['amount_paid'],
        payment_date: ledger['payment_date'] ? Date.parse(ledger['payment_date']) : nil
      ))
    end
  end
end
```

### VCR for Lunchflow API

**Cassette:** `spec/fixtures/vcr_cassettes/lunchflow/november_2025.yml`
**Contains:** Real November 2025 transaction responses from Lunchflow API

```ruby
# Record cassette once on production machine:
RSpec.describe LunchflowClient, vcr: { cassette_name: 'lunchflow/november_2025' } do
  it 'fetches November 2025 transactions' do
    response = client.fetch_transactions(
      account_id: ENV['LUNCHFLOW_ACCOUNT_ID'],
      since: '2025-11-01'
    )
    expect(response[:transactions].length).to be > 0
  end
end

# Commit cassette to git for use on Mac
```

---

## 🎯 Deterministic Transaction Interpretation Rules

**Priority order for processing each incoming Swish payment:**

```ruby
1. Is it a DEPOSIT?
   (amount matches 6,000-6,200 kr OR 2,000-2,200 kr OR 8,200-8,600 kr
   AND tenant is new/recent: within ±30 days of startDate)
   → Log: "💰 Deposition från [name]: [amount] kr"
   → Don't create receipt
   → STOP

2. Aggregate same-day payments (group by person + date)

3. Does aggregated amount >= 50% of expected rent?
   → Create receipt(s) for all payments in group
   → Mark partial if total < expected
   → STOP

4. Has reference code? (even if below threshold)
   → Create receipt
   → STOP

5. Below threshold, no reference code
   → Log: "⚠️ Liten betalning från [name]: [amount] kr (< 50% av hyra)"
   → Don't create receipt
   → STOP (informational log only - no manual verification)
```

**Multi-day aggregation runs at every bank_sync:**
- Find unmatched transactions in day 15-27 rent-paying window
- Try 2-payment and 3-payment combinations within 14 days
- If total matches expected rent (±max(100 kr, 1%)) → create receipts
- Prefer latter combinations (exact match more likely in last payment)

---

## 🎯 Core Requirements

### What SHOULD Be Matched as Rent

1. **Incoming Swish payments** ("Swish Mottagen") matching expected rent amounts
2. **Incoming bank transfers** matching expected rent amounts
3. **Partial rent payments** (tracked separately, alerts admin near deadline)
4. **Multiple payments per tenant per month** (sum to total rent)
5. **Overpayments** (excess tracked, tenant notified)

### What SHOULD NOT Be Matched as Rent

1. **Outgoing Swish payments** ("Swish Skickad") - reimbursements, house purchases
2. **Incoming Swish NOT matching rent amounts** - deposits, repayments, unrelated transfers
3. **Outgoing bank transfers** - bill payments, supplier payments
4. **Duplicate transactions** (same external_id already processed)

---

## 🧪 Test Cases

### Category 1: Transaction Direction Detection

#### Test 1.1: Incoming Swish (Rent Payment)
```ruby
# Scenario: Sanna pays November rent via Swish
transaction = {
  merchant: "Swish Mottagen",
  amount: 6303,  # Positive amount
  description: "from: +46702894437 1806326367017854, reference: 1806326367017854IN",
  counterparty: "+46702894437"
}

expected:
  - should_process?: true
  - direction: :incoming
  - tenant_match: Sanna Juni Benemar
  - create_receipt?: true
  - matched_via: "phone"
```

#### Test 1.2: Outgoing Swish (Reimbursement)
```ruby
# Scenario: Fredrik reimburses Sanna 400 kr for house supplies
transaction = {
  merchant: "Swish Skickad",
  amount: -400,  # Negative amount
  description: "to: +46702894437 1806326367017854",
  counterparty: "+46702894437"
}

expected:
  - should_process?: false
  - reason: "Outgoing Swish payment (reimbursement, not rent)"
  - create_receipt?: false
```

#### Test 1.3: Incoming Bank Transfer (Non-Swish Rent)
```ruby
# Scenario: Tenant pays rent via bank transfer
transaction = {
  merchant: "Överföring Via Internet",
  amount: 6302,
  description: "Adam McCarthy - Rent November",
  counterparty: "Adam McCarthy"  # Name from bank
}

expected:
  - should_process?: true
  - direction: :incoming
  - tenant_match: Adam McCarthy
  - matched_via: "name+amount"
```

#### Test 1.4: Outgoing Bank Transfer (Bill Payment)
```ruby
# Scenario: House pays electricity bill
transaction = {
  merchant: "Överföring Via Internet",
  amount: -1685.69,
  description: "Vattenfall invoice payment",
  counterparty: "Vattenfall AB"
}

expected:
  - should_process?: false
  - reason: "Outgoing bank transfer (bill payment, not rent)"
```

---

### Category 2: Amount Matching Edge Cases

#### Test 2.1: Exact Amount Match
```ruby
# Scenario: Rasmus pays exact rent amount
transaction = { amount: 4903 }
ledger = { tenant: "Rasmus", amount_due: 4903 }

expected:
  - amount_matches?: true
  - partial?: false
  - fully_paid?: true
```

#### Test 2.2: Partial Payment (Within Tolerance)
```ruby
# Scenario: Tenant pays 90% of rent (5000 kr of 5896 kr)
transaction = { amount: 5000 }
ledger = { tenant: "Frida", amount_due: 5896 }

expected:
  - amount_matches?: true  # Within fuzzy tolerance
  - partial?: true
  - remaining: 896
  - alert_admin?: true  # If near deadline (day 27+)
```

#### Test 2.3: Tiny Payment (Likely NOT Rent)
```ruby
# Scenario: 100 kr payment (too small for rent, likely unrelated)
transaction = { amount: 100 }
ledger = { tenant: "Sanna", amount_due: 6303 }

expected:
  - amount_matches?: false
  - reason: "Amount too far from expected rent (< 50% threshold)"
  - create_receipt?: false
```

#### Test 2.4: Overpayment
```ruby
# Scenario: Sanna pays 6703 kr for 6303 kr rent
payments = [6303, 400]  # Two transactions
ledger = { amount_due: 6303 }

expected:
  - total_paid: 6703
  - overpayment: 400
  - fully_paid?: true
  - note: "Track excess for future months or refund"
```

#### Test 2.5: Multiple Partial Payments Summing to Full
```ruby
# Scenario: Tenant pays in installments
payments = [3000, 2000, 1303]
ledger = { amount_due: 6303 }

expected:
  - receipt_count: 3
  - all_partial: [true, true, false]  # Last one completes
  - total_paid: 6303
  - fully_paid?: true
```

---

### Category 3: Phone Number Matching

#### Test 3.1: E.164 Format Match
```ruby
tenant = { phone_e164: "+46702894437" }
transaction = { counterparty: "+46702894437" }

expected:
  - phone_matches?: true
```

#### Test 3.2: User Format vs E.164
```ruby
tenant = {
  phone: "073 283 07 22",  # User-entered format
  phone_e164: "+46732830722"  # Normalized
}
transaction = { counterparty: "+46732830722" }

expected:
  - phone_matches?: true  # Must use phone_e164, not phone
```

#### Test 3.3: Missing Phone Number
```ruby
tenant = { phone_e164: nil }
transaction = { counterparty: "+46702894437" }

expected:
  - phone_matches?: false
  - fallback_to: "reference code or name matching"
```

#### Test 3.4: Extracted Phone from Description
```ruby
transaction = {
  description: "from: +46702894437 1806326367017854, reference: ...",
  counterparty: nil  # Not populated by bank_sync
}

expected:
  - extract_phone_number: "+46702894437"
  - phone_matches?: true
```

---

### Category 4: Reference Code Matching

#### Test 4.1: Full Reference Code Match
```ruby
tenant = { id: "cmhqe9enc0000wopipuxgc3kw" }  # CUID
transaction = {
  description: "KK202511Sanna0000wopipuxgc3kw"  # Last 13 chars of CUID
}

expected:
  - has_reference_code?(tenant): true
  - matched_via: "reference"
```

#### Test 4.2: Partial CUID in Description
```ruby
# Min 8 chars required for match
tenant = { id: "cmhqe9enc0000wopipuxgc3kw" }
transaction = { description: "Rent Nov - wopipuxgc3kw" }  # 13 chars

expected:
  - has_reference_code?: true
```

#### Test 4.3: Prefix Matching
```ruby
tenant = { id: "cmhqe9enc0000wopipuxgc3kw" }
transaction = { description: "cmhqe9enc - rent payment" }  # Prefix match

expected:
  - has_reference_code?: true
```

#### Test 4.4: Too Short UUID Fragment
```ruby
tenant = { id: "cmhqe9enc0000wopipuxgc3kw" }
transaction = { description: "cmhqe9e - rent" }  # Only 7 chars

expected:
  - has_reference_code?: false
  - reason: "UUID fragment too short (< 8 chars)"
```

---

### Category 5: Name Matching (Fuzzy)

#### Test 5.1: Exact Name Match
```ruby
tenant = { name: "Adam McCarthy" }
transaction = { counterparty: "Adam McCarthy" }

expected:
  - name_matches?: true
  - levenshtein_distance: 0
```

#### Test 5.2: Case Insensitive Match
```ruby
tenant = { name: "Frida Johansson" }
transaction = { counterparty: "FRIDA JOHANSSON" }

expected:
  - name_matches?: true
```

#### Test 5.3: Partial Name Match (First + Last)
```ruby
tenant = { name: "Sanna Juni Benemar" }
transaction = { counterparty: "Sanna Benemar" }  # Middle name missing

expected:
  - name_matches?: true  # First + last name match
```

#### Test 5.4: Typo Tolerance
```ruby
tenant = { name: "Rasmus Kasurinen" }
transaction = { counterparty: "Rasmus Kasurin" }  # Missing 'en'

expected:
  - name_matches?: true  # Levenshtein distance acceptable
  - max_distance_threshold: 2
```

#### Test 5.5: No Match (Different Name)
```ruby
tenant = { name: "Fredrik Bränström" }
transaction = { counterparty: "Vattenfall AB" }

expected:
  - name_matches?: false
```

---

### Category 6: 4-Tier Matching Strategy

#### Test 6.1: Tier 1 Wins (Reference Code)
```ruby
# Even if phone/name also match, reference code takes precedence
transaction = {
  description: "KK202511Sanna0000wopipuxgc3kw - rent",
  counterparty: "+46702894437"
}

expected:
  - matched_via: "reference"  # Tier 1, not phone
```

#### Test 6.2: Tier 1 Fails, Tier 2 Succeeds (Phone)
```ruby
transaction = {
  description: "Rent November",  # No reference code
  counterparty: "+46702894437"
}

expected:
  - matched_via: "phone"
```

#### Test 6.3: Tier 1-2 Fail, Tier 3 Succeeds (Amount + Name)
```ruby
transaction = {
  description: "Bank transfer from Adam",  # No reference
  counterparty: "Adam McCarthy",  # Name (not phone)
  amount: 6302
}
tenant = { name: "Adam McCarthy", phone_e164: nil }
ledger = { amount_due: 6302 }

expected:
  - matched_via: "amount+name"
```

#### Test 6.4: All Tiers Fail (No Match)
```ruby
transaction = {
  description: "Random transfer",
  counterparty: "Unknown Person",
  amount: 1234
}

expected:
  - tenant_match: nil
  - create_receipt?: false
  - log_for_manual_review: true
```

---

### Category 7: Month Period Matching

#### Test 7.1: Transaction in Current Month
```ruby
transaction = { booked_at: Date.new(2025, 11, 24) }
current_date = Date.new(2025, 11, 26)

expected:
  - period: "2025-11"
  - ledger_lookup: November 2025 ledger
```

#### Test 7.2: Transaction from Previous Month (Late Payment)
```ruby
# Oct 28 payment processed in November
transaction = { booked_at: Date.new(2025, 10, 28) }
current_date = Date.new(2025, 11, 5)

expected:
  - period: "2025-10"  # Use transaction date, not current date
  - ledger_lookup: October 2025 ledger
```

#### Test 7.3: No Ledger Exists for Period
```ruby
transaction = { booked_at: Date.new(2025, 12, 1) }
ledger_exists?: false  # December ledger not created yet

expected:
  - create_receipt?: false
  - reason: "No ledger entry for period 2025-12"
  - queue_for_retry?: true
```

---

### Category 8: Duplicate Detection

#### Test 8.1: Same External ID (Already Processed)
```ruby
# bank_sync uses upsert, so duplicate external_id updates existing row
transaction = { external_id: "abc123" }
existing_receipt = { matched_tx_id: "cmhqe9enc..." }  # Already matched

expected:
  - create_new_receipt?: false
  - reason: "Transaction already reconciled"
```

#### Test 8.2: Multiple Transactions Same Day, Different Amounts
```ruby
# Sanna pays twice on same day (rare but valid)
tx1 = { booked_at: "2025-11-24", amount: 6303 }
tx2 = { booked_at: "2025-11-24", amount: 400 }

expected:
  - receipt_count: 2
  - total_paid: 6703
```

---

### Category 9: Idempotency & State Management

#### Test 9.1: Re-running ApplyBankPayment on Same Transaction
```ruby
# Manual re-run or retry logic
ApplyBankPayment.call(transaction_id: "cmhqe9enc...")

expected:
  - create_duplicate_receipt?: false
  - check_existing_receipts_first: true
```

#### Test 9.2: RentLedger Update Only When Fully Paid
```ruby
# Partial payments don't update ledger summary
payments = [3000, 2000]  # Total 5000 of 6303
ledger = { amount_due: 6303 }

expected:
  - ledger.amount_paid: nil  # Not updated yet
  - receipts_created: 2
  - wait_for_full_payment: true
```

#### Test 9.3: Final Payment Triggers Ledger Update
```ruby
# Third payment completes rent
payments = [3000, 2000, 1303]
ledger = { amount_due: 6303 }

expected:
  - ledger.amount_paid: 6303
  - ledger.payment_status: "paid"
  - ledger.paid_at: Date of final payment
```

---

### Category 10: Admin Alerts & Notifications

#### Test 10.1: Full Payment = No Alert
```ruby
# Normal successful payment
payment = { amount: 6303, tenant: "Sanna" }
ledger = { amount_due: 6303 }

expected:
  - send_admin_confirmation?: false  # Silent success (as designed)
  - update_ledger: true
  - broadcast_websocket: true
```

#### Test 10.2: Partial Payment Near Deadline = Alert
```ruby
payment = { amount: 5000, tenant: "Frida", date: "2025-11-27" }
ledger = { amount_due: 5896 }
current_day = 27  # Deadline day

expected:
  - send_admin_alert?: true
  - alert_message: "⚠️ Frida Johansson partial payment: 5000 kr of 5896 kr (896 kr remaining)"
```

#### Test 10.3: Partial Payment Before Deadline = No Alert
```ruby
payment = { amount: 5000, tenant: "Frida", date: "2025-11-23" }
current_day = 23  # Well before deadline

expected:
  - send_admin_alert?: false  # No urgency yet
```

---

### Category 11: Real-World Edge Cases (Nov 2025)

#### Test 11.1: Sanna's Deposit Return (Incoming, Not Rent)
```ruby
# Sanna swished 400 kr deposit earlier in month (not rent)
transaction = {
  merchant: "Swish Mottagen",
  amount: 400,
  counterparty: "+46702894437",
  booked_at: "2025-11-05"
}
ledger = { tenant: "Sanna", amount_due: 6303 }

expected:
  - amount_matches?: false  # 400 << 6303 (too small)
  - create_receipt?: false
  - reason: "Amount far below expected rent (threshold not met)"
```

#### Test 11.2: Sanna's Full Rent Payment
```ruby
transaction = {
  merchant: "Swish Mottagen",
  amount: 6303,
  counterparty: "+46702894437",
  booked_at: "2025-11-24"
}

expected:
  - amount_matches?: true
  - create_receipt?: true
  - matched_via: "phone"
```

#### Test 11.3: Fredrik's Reimbursement to Sanna (Outgoing)
```ruby
transaction = {
  merchant: "Swish Skickad",  # OUTGOING
  amount: -400,
  counterparty: "+46702894437",
  booked_at: "2025-11-26"
}

expected:
  - should_process?: false
  - reason: "Outgoing Swish payment ignored (direction check)"
  - create_receipt?: false
```

---

## 🔧 Implementation Checklist

### Phase 1: Direction Detection (CRITICAL FIX)
- [ ] Add `direction` method to BankTransaction model
  - [ ] Check merchant field: "Mottagen" = incoming, "Skickad" = outgoing
  - [ ] Check amount sign: positive = incoming, negative = outgoing
  - [ ] For bank transfers: only positive amounts
- [ ] Update `swish_payment?` to `incoming_swish_payment?`
- [ ] Add filter in bank_sync: only process incoming transactions
- [ ] Write specs for direction detection

### Phase 2: Amount Matching Thresholds
- [ ] Define minimum amount threshold (e.g., 50% of expected rent)
- [ ] Define maximum overpayment tolerance (e.g., 150% of expected rent)
- [ ] Implement `amount_plausible_as_rent?` check
- [ ] Write specs for amount edge cases

### Phase 3: Duplicate Prevention
- [ ] Check if RentReceipt already exists for transaction
- [ ] Add `find_by_matched_tx_id` to RentReceiptRepository
- [ ] Implement idempotency in ApplyBankPayment
- [ ] Write specs for re-runs and duplicates

### Phase 4: Multi-Payment Support
- [ ] Sum existing receipts before creating new one
- [ ] Track partial vs full payment state correctly
- [ ] Update ledger only when fully paid
- [ ] Write specs for installment payments

### Phase 5: Comprehensive Test Suite
- [ ] Unit tests for BankTransaction matching methods
- [ ] Integration tests for ApplyBankPayment service
- [ ] End-to-end tests for bank_sync → payment matching → ledger update
- [ ] Edge case regression tests (this document)

---

## 📊 Test Data Setup

### Tenants (November 2025)
```ruby
tenants = [
  { name: "Fredrik Bränström", phone_e164: "+46738307222", rent: 6303 },
  { name: "Sanna Juni Benemar", phone_e164: "+46702894437", rent: 6303 },
  { name: "Adam McCarthy", phone_e164: "+46760177088", rent: 6302 },
  { name: "Rasmus Kasurinen", phone_e164: "+46738174974", rent: 4903 },
  { name: "Frida Johansson", phone_e164: "+46739764479", rent: 5896 }
]
```

### Test Transactions
```ruby
transactions = [
  # Valid rent payments
  { date: "2025-11-24", merchant: "Swish Mottagen", amount: 6303, counterparty: "+46702894437" },
  { date: "2025-11-24", merchant: "Swish Mottagen", amount: 4903, counterparty: "+46738174974" },
  { date: "2025-11-25", merchant: "Swish Mottagen", amount: 6302, counterparty: "+46760177088" },
  { date: "2025-11-25", merchant: "Swish Mottagen", amount: 5896, counterparty: "+46739764479" },

  # Edge cases
  { date: "2025-11-05", merchant: "Swish Mottagen", amount: 400, counterparty: "+46702894437" },  # Too small
  { date: "2025-11-26", merchant: "Swish Skickad", amount: -400, counterparty: "+46702894437" }, # Outgoing
  { date: "2025-11-27", merchant: "Överföring Via Internet", amount: -1685, counterparty: "Vattenfall" }, # Bill
]
```

---

## 🎯 Success Criteria

A fully tested payment matching system should:

1. ✅ **Only process incoming transactions** (ignore outgoing)
2. ✅ **Match rent payments accurately** via 4-tier strategy
3. ✅ **Reject implausible amounts** (too small/large for rent)
4. ✅ **Handle multiple payments per tenant** (installments, overpayments)
5. ✅ **Prevent duplicate receipts** (idempotent operations)
6. ✅ **Update ledger only when fully paid**
7. ✅ **Alert admin on partial payments near deadline**
8. ✅ **Stay silent on successful full payments** (no spam)
9. ✅ **Broadcast WebSocket updates** after state changes
10. ✅ **Handle edge cases gracefully** (missing data, wrong periods, etc.)

---

### Category 12: Deposit Detection (NEW - Nov 27, 2025)

#### Test 12.1: New Tenant - First Month Deposit
```ruby
# Scenario: Sanna pays first month deposit (6,000 kr) on Oct 21 (move-in day)
tenant = {
  name: "Sanna Juni Benemar",
  start_date: Date.new(2025, 10, 21),
  phone_e164: "+46702894437"
}

transaction = {
  merchant: "Swish Mottagen",
  amount: 6000,  # Within DEPOSIT_FIRST_MONTH_RANGE (6000-6200)
  description: "from: +46702894437 ...",
  counterparty: "+46702894437",
  booked_at: Date.new(2025, 10, 21)  # Same day as move-in
}

expected:
  - deposit_payment?: true (within ±30 days of startDate)
  - create_receipt?: false
  - admin_alert: "💰 Deposition: Sanna Juni Benemar betalade 6000 kr"
```

#### Test 12.2: New Tenant - Composite Deposit
```ruby
# Scenario: New tenant pays full deposit in one payment (8,400 kr)
transaction = {
  amount: 8400,  # Within DEPOSIT_COMPOSITE_RANGE (8200-8600)
  booked_at: tenant.start_date + 5.days  # Within 30-day window
}

expected:
  - deposit_payment?: true
  - create_receipt?: false
  - admin_alert: "💰 Deposition: [name] betalade 8400 kr"
```

#### Test 12.3: Old Tenant - NOT a Deposit
```ruby
# Scenario: Existing tenant pays 6,000 kr (happens to match deposit range)
tenant = {
  start_date: Date.new(2024, 1, 1),  # 22 months ago
}

transaction = {
  amount: 6000,
  booked_at: Date.new(2025, 11, 24)  # 693 days after move-in
}

expected:
  - deposit_payment?: false (outside ±30 day window)
  - create_receipt?: true (matches as partial rent)
```

#### Test 12.4: Deposit Completion (Small Payment)
```ruby
# Scenario: Sanna paid 8,000 kr on Oct 21, now pays 400 kr to complete deposit
previous_deposit = 8000  # Oct 21
transaction = {
  amount: 400,  # Not in any deposit range
  booked_at: Date.new(2025, 11, 18)  # 28 days after move-in
}

expected:
  - deposit_payment?: false (amount doesn't match deposit patterns)
  - below_threshold?: true (400 < 50% of 6,303 kr)
  - create_receipt?: false
  - admin_alert: "⚠️ Liten betalning från Sanna Juni Benemar: 400 kr (under 50% av hyra)"
```

---

### Category 13: Payment Amount Thresholds (NEW - Nov 27, 2025)

#### Test 13.1: Payment Meets 50% Threshold
```ruby
# Scenario: Tenant pays 3,500 kr (>50% of 6,303 kr expected)
expected_rent = 6303
threshold = expected_rent * 0.5  # 3,151.5

transaction = {
  amount: 3500  # > threshold
}

expected:
  - meets_threshold?: true
  - create_receipt?: true
  - partial: true (3,500 < 6,303)
```

#### Test 13.2: Payment Below 50% Threshold
```ruby
# Scenario: Tenant pays 3,000 kr (<50% of 6,303 kr expected)
transaction = {
  amount: 3000  # < 3,151.5 threshold
}

expected:
  - meets_threshold?: false
  - has_reference_code?: false
  - create_receipt?: false
  - admin_alert: "⚠️ Liten betalning från [name]: 3000 kr (under 50% av hyra)"
```

#### Test 13.3: Reference Code Override (Below Threshold)
```ruby
# Scenario: Tenant pays 2,000 kr with reference code (bypasses threshold)
transaction = {
  amount: 2000,  # < 50% threshold
  description: "Swish från ... KK202511Sannacmhqe9enc"  # Has reference code
}

expected:
  - meets_threshold?: false
  - has_reference_code?: true
  - create_receipt?: true (reference code overrides threshold)
  - partial: true
```

---

### Category 14: Same-Day Payment Aggregation (NEW - Nov 27, 2025)

#### Test 14.1: Two Payments Same Day - Both Pass Individually
```ruby
# Scenario: Tenant sends rent in two installments, both >50% threshold
payments = [
  { amount: 5000, booked_at: Date.new(2025, 11, 24) },  # 79% of rent
  { amount: 1689, booked_at: Date.new(2025, 11, 24) }   # 27% of rent
]

total = 6689  # > expected 6,303

expected:
  - aggregated_amount: 6689
  - both_meet_threshold?: true (when checked individually)
  - create_receipts?: 2 receipts created
  - partial?: false (total >= expected)
```

#### Test 14.2: Two Payments Same Day - Second Fails Without Aggregation
```ruby
# Scenario: Historical case from Feb 2024
payments = [
  { amount: 3000, booked_at: Date.new(2024, 2, 26) },  # 50% of 6,053
  { amount: 3053, booked_at: Date.new(2024, 2, 26) }   # 50% of 6,053
]

expected_rent = 6053
first_threshold = 3000 >= 3026.5  # false
total = 6053

expected:
  - WITHOUT aggregation: First payment would FAIL threshold
  - WITH aggregation: Both payments create receipts
  - total_matches_rent?: true
```

#### Test 14.3: Three Payments Same Day
```ruby
# Scenario: Tenant splits rent into three parts (unusual but valid)
payments = [
  { amount: 2000, booked_at: Date.new(2025, 11, 24) },
  { amount: 2000, booked_at: Date.new(2025, 11, 24) },
  { amount: 2303, booked_at: Date.new(2025, 11, 24) }
]

total = 6303

expected:
  - aggregated_amount: 6303
  - all_meet_threshold?: false (individually all < 50%)
  - create_receipts?: 3 receipts created (via aggregation)
  - total_matches_rent?: true
```

---

### Category 15: Multi-Day Payment Aggregation (NEW - Nov 27, 2025)

#### Test 15.1: Two Payments Within 14 Days (Matching Rent)
```ruby
# Scenario: Tenant pays on two different paydays
payments = [
  { amount: 3000, booked_at: Date.new(2025, 11, 18) },  # Mid-month payday
  { amount: 4303, booked_at: Date.new(2025, 11, 24) }   # Standard payday
]

days_apart = 6
total = 7303
expected_rent = 7303
tolerance = [100, 7303 * 0.01].max  # 100

expected:
  - within_time_window?: true (6 days < 14 days)
  - total_matches_rent?: true (diff = 0 <= 100)
  - create_receipts?: 2 receipts
  - admin_alert: "💰 Delbetalningar matchade: [name] betalade 2 gånger (totalt 7303 kr av 7303 kr)"
```

#### Test 15.2: Two Payments Too Far Apart (>14 Days)
```ruby
# Scenario: Payments 20 days apart
payments = [
  { amount: 3000, booked_at: Date.new(2025, 11, 10) },
  { amount: 3303, booked_at: Date.new(2025, 11, 30) }
]

days_apart = 20

expected:
  - within_time_window?: false (20 days > 14 days max)
  - aggregate?: false
  - create_receipts?: 0 (both below 50% threshold individually)
```

#### Test 15.3: Three Payments Within Window
```ruby
# Scenario: Tenant pays in three installments over 10 days
payments = [
  { amount: 2000, booked_at: Date.new(2025, 11, 18) },
  { amount: 2000, booked_at: Date.new(2025, 11, 22) },
  { amount: 2303, booked_at: Date.new(2025, 11, 28) }
]

date_span = 10.days
total = 6303

expected:
  - within_time_window?: true (10 days < 14 days)
  - total_matches_rent?: true
  - create_receipts?: 3 receipts
```

#### Test 15.4: Multiple Valid Combinations - Prefer Latter
```ruby
# Scenario: Three payments, two valid combinations
payments = [
  { amount: 3000, booked_at: Date.new(2025, 11, 18) },
  { amount: 3000, booked_at: Date.new(2025, 11, 20) },
  { amount: 3303, booked_at: Date.new(2025, 11, 22) }
]

expected_rent = 6303

valid_combinations = [
  [payments[0], payments[2]],  # Day 18 + 22 = 6,303 (exact)
  [payments[1], payments[2]]   # Day 20 + 22 = 6,303 (exact)
]

expected:
  - choose_combination: [payments[1], payments[2]]  # LATTER combo
  - reason: "Last payment (3,303) exactly completes rent"
```

#### Test 15.5: Tolerance Check (±100 kr or 1%)
```ruby
# Scenario: Two payments slightly over expected rent
payments = [
  { amount: 3200, booked_at: Date.new(2025, 11, 18) },
  { amount: 3200, booked_at: Date.new(2025, 11, 24) }
]

total = 6400
expected_rent = 6303
diff = 97  # Within 100 kr tolerance

expected:
  - within_tolerance?: true (97 <= 100)
  - create_receipts?: 2 receipts
```

#### Test 15.6: Outside Rent-Paying Window (Day 15-27)
```ruby
# Scenario: Payments outside the rent-paying window
payments = [
  { amount: 3000, booked_at: Date.new(2025, 11, 10) },  # Day 10 (too early)
  { amount: 3303, booked_at: Date.new(2025, 11, 30) }   # Day 30 (too late)
]

expected:
  - in_rent_window?: false (day 10 < day 15 start)
  - aggregate?: false
  - reason: "Outside rent-paying window (day 15-27)"
```

---

## 🏗️ Implementation Guide

### Architecture Changes

**Files to Modify:**

1. **`bin/bank_sync`** - Add aggregation logic before `ApplyBankPayment.call()`
2. **`lib/services/apply_bank_payment.rb`** - Add deposit detection, threshold checks
3. **`lib/models/bank_transaction.rb`** - Add helper methods for deposit detection
4. **New file: `lib/services/payment_aggregator.rb`** - Multi-day aggregation logic

**Database Schema:**

**No changes needed** - use existing `BankTransaction` and `RentReceipt` tables.

---

### Phase 1: Deposit Detection

**Constants (add to `ApplyBankPayment`):**

```ruby
# Deposit amount patterns (Swedish rental law: 1-2 months rent)
DEPOSIT_FIRST_MONTH_RANGE = (6000..6200)   # First month rent
DEPOSIT_SECOND_MONTH_RANGE = (2000..2200)  # Two months rent
DEPOSIT_COMPOSITE_RANGE = (8200..8600)     # Total deposit

NEW_TENANT_WINDOW_DAYS = 30  # ± days from startDate
```

**Implementation:**

```ruby
def call
  return unless @transaction
  return unless @transaction.incoming_swish_payment?

  # NEW: Check for deposit before matching
  if deposit_payment?
    log_deposit_to_admin
    return nil  # Don't create rent receipt
  end

  # Existing matching logic...
  tenant, match_method = find_matching_tenant
  # ...
end

private

def deposit_payment?
  return false unless tenant = find_matching_tenant&.first

  # Check if amount matches deposit pattern
  amount_matches = DEPOSIT_FIRST_MONTH_RANGE.include?(@transaction.amount) ||
                   DEPOSIT_SECOND_MONTH_RANGE.include?(@transaction.amount) ||
                   DEPOSIT_COMPOSITE_RANGE.include?(@transaction.amount)

  return false unless amount_matches

  # Check if tenant is new (within ±30 days of startDate)
  return false unless tenant.start_date

  days_since_start = (@transaction.booked_at.to_date - tenant.start_date).abs
  days_since_start <= NEW_TENANT_WINDOW_DAYS
end

def log_deposit_to_admin
  tenant = find_matching_tenant&.first
  SmsGateway.send_admin_alert(
    "💰 Deposition: #{tenant.name} betalade #{@transaction.amount.to_i} kr"
  )
end
```

---

### Phase 2: Same-Day Aggregation

**Implementation in `bin/bank_sync`:**

```ruby
# After fetching transactions, BEFORE calling ApplyBankPayment:

# Group incoming Swish by date + counterparty
incoming_swish = response[:transactions].select do |tx|
  tx[:merchant]&.include?('Mottagen')
end

grouped = incoming_swish.group_by do |tx|
  [Date.parse(tx[:date]), tx[:counterparty]]
end

# Process each group
grouped.each do |(date, person), transactions|
  # Upsert all transactions first
  bank_txs = transactions.map do |tx|
    Persistence.bank_transactions.upsert(
      external_id: tx[:id],
      account_id: account_id,
      booked_at: DateTime.parse(tx[:date]),
      amount: tx[:amount],
      currency: tx[:currency],
      description: tx[:description],
      counterparty: tx[:counterparty],
      raw_json: tx
    )
  end

  # Calculate total for group
  total = bank_txs.sum(&:amount)

  # Try to match group (ApplyBankPayment will handle threshold)
  bank_txs.each do |bank_tx|
    ApplyBankPayment.call(
      transaction_id: bank_tx.id,
      same_day_total: total  # NEW parameter
    )
  end
end
```

**Modify `ApplyBankPayment` to accept group total:**

```ruby
def initialize(transaction_id:, same_day_total: nil)
  @transaction = Persistence.bank_transactions.find_by_id(transaction_id)
  @same_day_total = same_day_total || @transaction&.amount  # Use group total if provided

  tx_date = @transaction&.booked_at || Time.now
  @current_month = tx_date.strftime('%Y-%m')
  # ...
end

def call
  # ... existing checks ...

  # Check threshold using same_day_total
  expected_rent = ledger.amount_due
  min_amount = expected_rent * 0.5

  if @same_day_total >= min_amount
    create_receipt  # Passes threshold
  elsif @transaction.has_reference_code?(tenant)
    create_receipt  # Reference code override
  else
    log_small_payment_to_admin
    return nil
  end

  # ... rest of logic ...
end

def log_small_payment_to_admin
  tenant = find_matching_tenant&.first
  SmsGateway.send_admin_alert(
    "⚠️ Liten betalning från #{tenant.name}: #{@transaction.amount.to_i} kr " \
    "(under 50% av hyra)"
  )
end
```

---

### Phase 3: Multi-Day Aggregation

**New Service: `lib/services/payment_aggregator.rb`:**

```ruby
require_relative '../persistence'

# PaymentAggregator finds multi-day partial payment combinations
# that sum to expected rent amount.
#
# Handles cases like:
# - Nov 18: 3,000 kr (partial)
# - Nov 24: 4,303 kr (completing)
# - Total: 7,303 kr = full rent
#
# @example
#   PaymentAggregator.find_partial_groups(tenant, Date.new(2025, 11, 1))
class PaymentAggregator
  RENT_PAYING_WINDOW_START = 15  # Day of month
  RENT_PAYING_WINDOW_END = 27
  MAX_DAYS_BETWEEN_PAYMENTS = 14

  def self.find_partial_groups(tenant, month_start)
    new(tenant, month_start).find_groups
  end

  def initialize(tenant, month_start)
    @tenant = tenant
    @month_start = month_start
    @month_end = month_start + 1.month - 1.day
  end

  def find_groups
    unmatched = get_unmatched_transactions
    return [] if unmatched.empty?

    expected_rent = get_expected_rent
    return [] unless expected_rent

    tolerance = [100, expected_rent * 0.01].max

    matched_groups = []

    # Try 2-payment combinations
    unmatched.combination(2).each do |tx1, tx2|
      next unless within_time_window?(tx1, tx2)

      total = tx1.amount + tx2.amount
      diff = (total - expected_rent).abs

      if diff <= tolerance
        matched_groups << [tx1, tx2]
      end
    end

    # Remove matched transactions from pool
    matched_groups.each do |group|
      unmatched -= group
    end

    # Try 3-payment combinations (remaining unmatched)
    unmatched.combination(3).each do |tx1, tx2, tx3|
      next unless within_time_window?(tx1, tx2, tx3)

      total = tx1.amount + tx2.amount + tx3.amount
      diff = (total - expected_rent).abs

      if diff <= tolerance
        matched_groups << [tx1, tx2, tx3]
      end
    end

    # Prefer latter combinations (exact match more likely in last payment)
    matched_groups.sort_by do |group|
      total = group.sum(&:amount)
      exact_match = (total - expected_rent).abs < 1
      [exact_match ? 0 : 1, group.last.booked_at]
    end
  end

  private

  def get_unmatched_transactions
    # Get all incoming Swish in rent-paying window (day 15-27)
    start_date = @month_start + (RENT_PAYING_WINDOW_START - 1).days
    end_date = @month_start + (RENT_PAYING_WINDOW_END - 1).days

    all_txs = Persistence.bank_transactions.all.select do |tx|
      tx.incoming_swish_payment? &&
      tx.booked_at >= start_date &&
      tx.booked_at <= end_date &&
      tx.counterparty == @tenant.phone_e164
    end

    # Filter out already matched transactions
    all_txs.reject do |tx|
      receipt = RentDb.instance.class.db[:RentReceipt]
        .where(matchedTxId: tx.id)
        .first
      receipt
    end
  end

  def get_expected_rent
    ledger = Persistence.rent_ledger.find_by_tenant_and_period(
      @tenant.id,
      @month_start
    )
    ledger&.amount_due
  end

  def within_time_window?(*transactions)
    dates = transactions.map { |tx| tx.booked_at.to_date }
    date_range = dates.max - dates.min
    date_range <= MAX_DAYS_BETWEEN_PAYMENTS
  end
end
```

**Integration in `bin/bank_sync`:**

```ruby
# After same-day aggregation, run multi-day aggregation:

active_tenants = Persistence.tenants.all.select(&:active?)

active_tenants.each do |tenant|
  # Current month
  month_start = Date.new(Date.today.year, Date.today.month, 1)

  groups = PaymentAggregator.find_partial_groups(tenant, month_start)

  groups.each do |transactions|
    total = transactions.sum(&:amount)
    expected = Persistence.rent_ledger.find_by_tenant_and_period(
      tenant.id, month_start
    )&.amount_due

    # Create receipts for all transactions in group
    transactions.each do |tx|
      ApplyBankPayment.call(
        transaction_id: tx.id,
        same_day_total: total  # Use group total for threshold
      )
    end

    # Log successful aggregation (Swedish)
    SmsGateway.send_admin_alert(
      "💰 Delbetalningar matchade: #{tenant.name} betalade #{transactions.length} gånger " \
      "(totalt #{total.to_i} kr av #{expected.to_i} kr)"
    )
  end
end
```

---

### Phase 4: Swedish SMS Translations

**Update all admin alerts:**

```ruby
# Bank sync failure (bin/bank_sync)
SmsGateway.send_admin_alert("⚠️ Banksynk misslyckades: #{e.message}")

# Deposit detection (ApplyBankPayment)
SmsGateway.send_admin_alert(
  "💰 Deposition: #{tenant.name} betalade #{amount} kr"
)

# Small payment below threshold (ApplyBankPayment)
SmsGateway.send_admin_alert(
  "⚠️ Liten betalning från #{tenant.name}: #{amount} kr (under 50% av hyra)"
)

# Multi-day aggregation success (bin/bank_sync)
SmsGateway.send_admin_alert(
  "💰 Delbetalningar matchade: #{tenant.name} betalade #{count} gånger " \
  "(totalt #{total} kr av #{expected} kr)"
)

# Unpaid rent alerts (bin/rent_reminders) - ALREADY IN SWEDISH ✅
```

---

## 📋 Decision Log

### Question 1: New Tenant Identification
**Decision:** Use `startDate ±30 days` (Option A)
**Rationale:** Simple, clear rule. Tenant might pay first rent before deposits, so can't rely on "no receipts = new tenant"

### Question 2: Cross-Month Partial Payments
**Decision:** NO - don't check previous month
**Rationale:** Historical data shows NO examples of partial rent spanning months. All cross-month patterns are full rent + small adjustments.

### Question 3: Multiple Valid Combinations
**Decision:** Take LATTER combination (prefers exact match)
**Rationale:** Last payment in series will exactly complete rent amount with 99% certainty

### Question 4: Multi-Day Tolerance
**Decision:** `max(100 kr, expected_rent × 1%)`
**Rationale:**
- 6,303 kr rent → 100 kr tolerance (larger of 100 or 63)
- 15,000 kr rent → 150 kr tolerance (larger of 100 or 150)

---

## ⚡ Performance Considerations

**Combination search complexity:**
- Typical case: 2-5 unmatched transactions per tenant
- Worst case: 10 unmatched transactions
  - 2-combos: C(10,2) = 45
  - 3-combos: C(10,3) = 120
  - Total: 165 checks
- 5 tenants × 165 = 825 checks per bank_sync
- **Performance impact: Negligible** (< 1ms)

---

## 🚀 Deployment Plan

1. ✅ **Export production data** to `spec/fixtures/production_snapshot.json`
2. ✅ **Update documentation** - consolidated into this single plan
3. ⏳ **Implement code changes** on Mac (TDD approach)
4. ⏳ **Run full test suite** - ensure all 50+ test cases pass
5. ⏳ **Commit and push** to production
6. ⏳ **Monitor first bank_sync run** with new logic
7. ⏳ **Verify admin SMS alerts** in Swedish

---

## ✅ Success Criteria

- ✅ Same-day installment payments automatically matched (5,000 kr + 689 kr)
- ✅ Multi-day partial payments aggregated (3,000 kr + 4,303 kr over 6 days)
- ✅ Deposits correctly detected and skipped (6,000 kr, 2,000 kr, 8,400 kr)
- ✅ Small non-rent payments rejected (400 kr without reference code)
- ✅ Reference code override works (even below 50% threshold)
- ✅ All admin SMS in Swedish
- ✅ No false positives (adjustments not matched as rent)
- ✅ Historical data patterns handled correctly

---

## 📝 Next Steps

1. **Implement code changes** on Mac using TDD approach
2. **Write failing tests** for all 15 categories (50+ test cases)
3. **Implement features** to make tests pass (4 phases)
4. **Add idempotency checks** (prevent duplicates)
5. **Run full test suite** and verify all green
6. **Deploy to production** with confidence
7. **Monitor first real bank sync** (tomorrow 8:05am)

---

**End of Test Plan**

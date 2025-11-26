# Payment Matching System - Comprehensive Test Plan

**Date:** Nov 26, 2025
**Context:** TDD approach to payment matching after discovering outgoing Swish bug
**Goal:** Bulletproof payment matching with complete edge case coverage

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

## 📝 Next Steps

1. **Write failing tests** for all categories above
2. **Fix direction detection bug** (incoming vs outgoing)
3. **Implement amount thresholds** (min 50%, max 150%)
4. **Add idempotency checks** (prevent duplicates)
5. **Run full test suite** and verify all green
6. **Deploy to production** with confidence
7. **Monitor first real bank sync** (tomorrow 8:05am)

---

**End of Test Plan**

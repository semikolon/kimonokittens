# December 2025 Rent Chaos Resolution Plan

**Created:** Nov 23, 2025 00:30
**Status:** IN PROGRESS

---

## 🔍 ISSUE 1: Mysterious 21 kr Discrepancy

**Symptom:** "Aktuell hyra" shows 7427 kr, but ledger shows "7406 kr kvar"

**Debug Steps:**
1. [ ] Check RentCalculator API for current month
2. [ ] Check RentLedger table for December entries
3. [ ] Identify source of 21 kr difference (rounding? electricity? config?)

---

## 🧮 ISSUE 2: December 2025 Occupancy Chaos

**The Situation:**
- **Adam:** Was going to India, flip-flopped, NOW staying December → leaving early Jan
- **Rasmus:** Was leaving Dec 1, NOW staying December (taking Adam's room or attic?)
- **Frida:** Moving into Rasmus's old room in December
- **Fredrik:** Staying (always)
- **???:** Who else is in the house?

**Result:** 5 people in December (maybe?) = transition chaos + moving logistics

**Rent Philosophy (from couple discount doc):**
- Counterfactual gratitude: 5th person makes math better for everyone
- Normal: ~7,300 kr/person (4 people)
- Couple in 2-in-1 room: 5k each = 10k total (individual discount)
- **Question:** Who deserves the gratitude discount? Rasmus? Adam? Both? Everyone?

---

## 🎁 ISSUE 3: Who Gets the Discount?

**USER'S VERBATIM CLARIFICATION (Nov 23, 2025 00:57):**

> "The walk-through downside is ofc not applicable if only ONE person lives in the 2 rooms Adam has. Then it's just spacious. Haha. Both the rooms have DOORS. It's just that in order to get to the inner room, one has to walk through the outer room, and while passing, disturbing the privacy/integrity of both people. But Adam is the only one renting them currently. He and Rasmus would not be comfortable sharing those rooms though - vibes rule."

> "Rasmus should be shown gratitude. Adam still has his big room and gets to stay longer even though he indicated he might wanna leave as early as December. We appreciate him as a person, but his indecisiveness has caused a lot of turmoil and headache, honestly. He should not be rewarded for it."

**DECISION:**
- ✅ **Rasmus:** Gets gratitude discount (-800 to -1,000 kr) for flexibility
- ❌ **Adam:** No discount - indecisiveness caused problems, not reward-worthy
- **Others:** Standard rates (benefit from 5-person math)

---

## 🗓️ ISSUE 4: Auto-Created RentLedger Cleanup

**What happened:**
- Cron job ran Nov 22 (yesterday)
- Created December 2025 RentLedger entries
- Based on OLD assumptions (Rasmus leaving, 4 people, etc.)

**Action needed:**
- Delete auto-created December entries
- Recreate with corrected rent amounts

---

## 📋 RESOLUTION STEPS

### Step 1: DEBUG DISCREPANCY ⏳
- Query current rent calculations
- Query RentLedger entries
- Find 21 kr difference

### Step 2: UNDERSTAND TENANT STATE ⏳
- List all tenants + departure dates
- Confirm December occupancy
- Update departure dates if needed

### Step 3: FIND PHILOSOPHY DOC ⏳
- Search for couple discount markdown
- Extract counterfactual gratitude logic

### Step 4: CALCULATE FAIR RENT ⏳
- Decide discount strategy
- Calculate December amounts per person
- Document reasoning

### Step 5: UPDATE DATABASE ⏳
- Delete stale RentLedger entries
- Update tenant records
- Create new ledger entries
- Verify dashboard shows correct amounts

---

## 🚨 URGENT: Rent Reminder Cron Job

**USER (Nov 23, 00:58):**
> "It's too late (1am) to figure this out fully rn. I need to disable the rent reminder from sending out the wrong amount tomorrow morning, however. There's a cron job set for the 23rd, iirc. Help me identify it and temporarily disable it."

**STATUS:** ⏳ Need to find and disable rent reminder cron (runs as kimonokittens user)
**ACTION NEEDED:** Check `crontab -l` as kimonokittens user, comment out reminder job

---

## 🎯 NEXT ACTIONS

### URGENT (Before Morning)
1. ⏰ **Disable rent reminder cron** - prevents wrong amounts from being sent
2. 📝 Document cron job details for re-enabling later

### Step 1: Debug 21 kr Discrepancy ✅ COMPLETE
**ROOT CAUSE:** RentLedger entries created Nov 22 09:00 with slightly different electricity config than current API shows (7406 vs 7427 kr = 21 kr difference). Harmless - will be resolved when December ledger recreated.

### Step 2: Fix Rasmus Departure Date
- Currently: Dec 1, 2025 (wrong)
- Should be: Clear/remove (staying permanently or at least through December)

### Step 3: Calculate December Rent
**Based on user decisions:**
- Rasmus: -800 kr (gratitude discount)
- Adam: 0 kr (no discount despite indecisiveness)
- Frida: 0 kr (new tenant, standard)
- Fredrik: 0 kr (standard)
- Sanna: 0 kr (standard)

### Step 4: Create December Ledger
- Delete any auto-created entries (if exist)
- Create new entries with correct amounts
- Verify dashboard displays correctly

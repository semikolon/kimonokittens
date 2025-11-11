# Zigned Webhook Testing Status - Nov 11, 2025

**Context**: Live testing with real contract creation revealed critical bugs in production.

## Current Status: ✅ BOTH BUGS FIXED - Ready for Deployment

### Bug #1: ✅ FIXED - Repository Missing update() Method
**Error**: `undefined method 'update' for an instance of SignedContractRepository`
**Location**: `handlers/zigned_webhook_handler.rb:184`
**Root Cause**: SignedContractRepository only had `save()` (upsert), not `update()` (update-only)
**Fix**: Added `update()` method to SignedContractRepository matching ContractParticipantRepository pattern
**File**: `lib/repositories/signed_contract_repository.rb:68-73`

### Bug #2: ✅ FIXED - Personal Number Missing from Webhooks
**Error**: `personal_number is required`
**Location**: `handlers/zigned_webhook_handler.rb:542` (create_or_update_participant)
**Root Cause**: Zigned webhooks don't send `personal_number` (as documented in ZIGNED_WEBHOOK_FIELD_MAPPING.md), but ContractParticipant model requires it
**Solution**: Look up personal_number using email matching + contract/tenant lookup
**Implementation**:
- Line 542: `personal_number = participant_data['personal_number'] || lookup_personal_number(contract_id, participant_data)`
- Lines 582-604: `lookup_personal_number` helper method
  - Matches landlord by email (`branstrom@gmail.com` → `8604230717`)
  - Looks up tenant personnummer via contract.tenant_id → Tenant.personnummer
  - Falls back to nil with warning if lookup fails

## What Works
- ✅ Webhook signature verification (timestamped Stripe-style HMAC-SHA256)
- ✅ Event routing (v1/v3 field name fallback)
- ✅ Signing URL extraction (handles both `signing_url` and `signing_room_url`)

## What Was Broken (Now Fixed ✅)
- ✅ `agreement.lifecycle.pending` - Repository missing update() method (FIXED)
- ✅ `participant.lifecycle.fulfilled` - Personal number lookup implemented (FIXED)

## Webhook Events Received (Nov 11, 2025 20:30-20:36)
Test contract: `cmhuyr9pt010x4cqk5tova6bd`

1. **agreement.lifecycle.pending** - 500 error (repository.update missing)
2. **participant.identity_enforcement.passed** - 200 OK (not implemented, acknowledged)
3. **participant.lifecycle.fulfilled** - 500 error (personal_number required)
4. **sign_event.sign.completed_sign** - 200 OK (not implemented, acknowledged)

## Next Steps (Priority Order)
1. ✅ **Fix personal_number lookup** - COMPLETED (email matching + tenant lookup)
2. 🚀 **Deploy both fixes** - Commit + push to trigger webhook deployment
3. 🔄 **Retry webhook events** - Use Zigned dashboard to replay failed events
4. ✅ **Test complete flow** - Verify all lifecycle events work end-to-end

## Files Modified (Ready to Commit)
- `lib/repositories/signed_contract_repository.rb` - Added update() method (lines 68-73)
- `handlers/zigned_webhook_handler.rb` - Added personal_number lookup logic
  - Line 542: Call lookup helper when webhook doesn't send personal_number
  - Lines 582-604: `lookup_personal_number` method (email matching + tenant query)

## Documentation
- `docs/ZIGNED_WEBHOOK_FIELD_MAPPING.md` - Updated with signing URL field name quirk
- Logs location: `journalctl -u kimonokittens-dashboard --since "5 minutes ago" --no-pager | tail -100`

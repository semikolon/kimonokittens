# Phone Field Synchronization Issue

**Created**: November 18, 2025 at 13:15
**Resolved**: November 18, 2025 at 13:30
**Severity**: 🚨 CRITICAL - Will break SMS on first phone update
**Status**: ✅ FIXED - Option A implemented and tested
**Fix Commit**: 3f8afc9

---

## 🐛 THE BUG

When an admin updates a tenant's phone number through the UI or API:

1. ✅ `phone` field is updated with new value
2. ❌ `phoneE164` field stays stale (old value)
3. ❌ SMS reminders sent to wrong (old) phone number
4. ❌ Data inconsistency between two phone fields

**Example Timeline**:
```
Initial state:
  phone: '070 123 45 67'
  phoneE164: '+46701234567'  ✅ In sync

Admin updates phone to '073 999 88 77':
  phone: '073 999 88 77'      ✅ Updated
  phoneE164: '+46701234567'   ❌ STALE!

SMS reminder sent to: +46701234567 (wrong number!)
```

---

## 🔍 ROOT CAUSE ANALYSIS

### Code Flow

**handlers/admin_contracts_handler.rb:649-696** - `set_tenant_phone()`
```ruby
tenant.phone = cleaned_phone      # Updates phone field
tenant_repo.update(tenant)        # Saves to database
# phoneE164 never touched!
```

**lib/repositories/tenant_repository.rb:148-171** - `update()`
```ruby
dataset.where(id: tenant.id).update(
  phone: tenant.phone,       # Line 168: Updates phone
  # phoneE164 NOT in update hash - stays stale!
)
```

### Original Plan Intent

From `docs/RENT_REMINDERS_IMPLEMENTATION_PLAN.md`:

**Line 259**: `phoneE164 String? // "+46701234567" (validate existing phone field)"`
**Line 272**: "Migrate existing `phone` values to `phoneE164` format"

**Findings**:
- ✅ Two-field design was intentional
- ❌ No sync strategy documented
- ❌ No update hooks mentioned
- ❌ No automatic E.164 regeneration planned

**Conclusion**: Design oversight - migration covered, updates not considered.

---

## 💡 FIX OPTIONS

### Option A: Auto-Sync in Repository (Recommended)

**Approach**: Automatically regenerate `phoneE164` whenever `phone` is updated

**Implementation**:
```ruby
# lib/repositories/tenant_repository.rb
def update(tenant)
  # Generate phoneE164 from phone automatically
  phone_e164 = normalize_phone_to_e164(tenant.phone)

  dataset.where(id: tenant.id).update(
    phone: tenant.phone,
    phoneE164: phone_e164,  # Auto-sync
    # ... other fields ...
  )
end

private

def normalize_phone_to_e164(phone)
  return nil if phone.nil? || phone.empty?

  # Strip non-digits
  digits = phone.gsub(/\D/, '')

  # Swedish mobile (07xxxxxxxx)
  if digits =~ /^07\d{8}$/
    return "+46#{digits[1..-1]}"
  end

  # Already E.164 (+467xxxxxxxx)
  if digits =~ /^467\d{8}$/
    return "+#{digits}"
  end

  # Invalid format - keep null
  nil
end
```

**Pros**:
- ✅ Single source of truth (phone field)
- ✅ phoneE164 always regenerated from phone
- ✅ No manual sync needed
- ✅ Works for all update paths (admin UI, API, scripts)

**Cons**:
- ❌ Slightly more complex repository logic
- ❌ Validation in two places (handler + repository)

---

### Option B: Database Trigger

**Approach**: PostgreSQL trigger auto-updates `phoneE164` when `phone` changes

**Implementation**:
```sql
CREATE OR REPLACE FUNCTION sync_phone_e164()
RETURNS TRIGGER AS $$
BEGIN
  -- Only update phoneE164 if phone changed
  IF NEW.phone IS DISTINCT FROM OLD.phone THEN
    NEW."phoneE164" = CASE
      WHEN NEW.phone ~ '^\+467\d{8}$' THEN
        NEW.phone
      WHEN NEW.phone ~ '^07\d{8}$' THEN
        '+46' || REGEXP_REPLACE(SUBSTRING(NEW.phone FROM 2), '[^0-9]', '', 'g')
      WHEN NEW.phone IS NOT NULL THEN
        '+46' || REGEXP_REPLACE(NEW.phone, '[^0-9]', '', 'g')
      ELSE
        NULL
    END;
  END IF
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER tenant_phone_sync
  BEFORE UPDATE ON "Tenant"
  FOR EACH ROW
  EXECUTE FUNCTION sync_phone_e164();
```

**Pros**:
- ✅ Database-level guarantee (can't forget)
- ✅ Works regardless of code path
- ✅ No application code changes needed

**Cons**:
- ❌ Database logic harder to test
- ❌ Harder to debug (invisible to application)
- ❌ Requires new migration

---

### Option C: Drop phoneE164, Clean in Application

**Approach**: Keep only `phone` field, clean to E.164 format in application code when sending SMS

**Implementation**:
```ruby
# lib/sms/gateway.rb
def self.send_reminder(to:, body:, **opts)
  # Clean phone to E.164 before sending
  clean_phone = normalize_to_e164(to)

  elks_client.send_sms(
    to: clean_phone,
    body: body
  )
end

def self.normalize_to_e164(phone)
  digits = phone.to_s.gsub(/\D/, '')
  # ... normalization logic ...
  "+46#{digits}"
end
```

**Pros**:
- ✅ Single phone field (simplest data model)
- ✅ Preserves original formatting for display
- ✅ No sync issues (one source of truth)

**Cons**:
- ❌ Normalization happens at runtime (performance)
- ❌ No database validation of E.164 format
- ❌ Have to revert migration + remove phoneE164 column

---

### Option D: Make phoneE164 Read-Only (Generated Column)

**Approach**: PostgreSQL generated column computes phoneE164 from phone automatically

**Implementation**:
```sql
-- Drop existing phoneE164 column
ALTER TABLE "Tenant" DROP COLUMN "phoneE164";

-- Add as generated column
ALTER TABLE "Tenant" ADD COLUMN "phoneE164" TEXT
  GENERATED ALWAYS AS (
    CASE
      WHEN phone ~ '^\+467\d{8}$' THEN phone
      WHEN phone ~ '^07\d{8}$' THEN
        '+46' || REGEXP_REPLACE(SUBSTRING(phone FROM 2), '[^0-9]', '', 'g')
      ELSE NULL
    END
  ) STORED;
```

**Pros**:
- ✅ phoneE164 ALWAYS in sync with phone (impossible to be stale)
- ✅ Database-level guarantee
- ✅ No application code changes

**Cons**:
- ❌ PostgreSQL 12+ only (kimonokittens_production has PostgreSQL 18 ✅)
- ❌ Requires migration to drop + recreate column
- ❌ Can't manually override phoneE164 if needed

---

## 📊 RECOMMENDATION

**Option A (Auto-Sync in Repository)** is the best balance:

1. **Immediate fix** - No migration needed, just code update
2. **Explicit control** - Normalization logic visible in code
3. **Testable** - Easy to unit test normalization
4. **Flexible** - Can add special cases/overrides if needed

**Implementation Steps**:
1. Add `normalize_phone_to_e164()` helper to `TenantRepository`
2. Update `update()` method to auto-regenerate phoneE164
3. Add unit tests for normalization edge cases
4. Deploy and verify

**Timeline**: ~30 minutes to implement + test

---

## 🧪 TEST CASES NEEDED

Regardless of option chosen:

```ruby
describe 'Phone sync' do
  it 'updates phoneE164 when phone changes from Swedish to Swedish' do
    tenant.phone = '073 999 88 77'
    repo.update(tenant)
    expect(repo.find_by_id(tenant.id).phone_e164).to eq('+46739998877')
  end

  it 'updates phoneE164 when phone changes from E.164 to Swedish' do
    tenant.phone = '070 123 45 67'
    repo.update(tenant)
    expect(repo.find_by_id(tenant.id).phone_e164).to eq('+46701234567')
  end

  it 'clears phoneE164 when phone set to empty' do
    tenant.phone = ''
    repo.update(tenant)
    expect(repo.find_by_id(tenant.id).phone_e164).to be_nil
  end

  it 'handles phone with spaces and dashes' do
    tenant.phone = '073-976 44 79'
    repo.update(tenant)
    expect(repo.find_by_id(tenant.id).phone_e164).to eq('+46739764479')
  end
end
```

---

## ⚠️ IMPACT IF NOT FIXED

**Severity**: CRITICAL

**Scenario**: First phone update after deployment
```
1. Admin changes Frida's phone from 073-976 44 79 to 070 999 88 77
2. phone field updated: '070 999 88 77'
3. phoneE164 stays stale: '+46739764479' (old number!)
4. Rent reminder sent to old number (SMS fails or goes to wrong person)
5. Frida never receives rent reminder
6. Rent payment missed
7. Manual intervention required
```

**Recommendation**: Fix BEFORE deploying to production.

---

## 🎯 NEXT STEPS

**User Decision Required**:
1. Choose fix strategy (A, B, C, or D)
2. Approve implementation approach
3. Deploy fix before enabling rent reminders

**If choosing Option A (recommended)**:
- Implement in next Claude Code session (~30 min)
- Add unit tests
- Verify with dry-run rent_reminders
- Deploy via webhook

---

**Created**: November 18, 2025 at 13:15
**Discovered During**: Migration deployment + code review
**Root Cause**: Original plan oversight - migration covered, updates not considered

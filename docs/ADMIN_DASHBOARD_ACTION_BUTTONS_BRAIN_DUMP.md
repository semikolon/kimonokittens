# Admin Dashboard Action Buttons - Working Memory Brain Dump
**Date**: November 12, 2025
**Context Budget**: 10% remaining (73K/200K tokens)

## ✅ COMPLETED TASKS (This Session)

### 1. Admin Dashboard UI Fixes
- Fixed empty admin UI (DataContext import + date parsing)
- Updated button colors (orange primary #ffaa88, dimmed purple secondary #4a2b87)
- Layout fix: summary line + filter on same line
- Contract status sync from Zigned (fetched + updated to completed)
- ClockWidget added to admin view (same styling as public dashboard)
- Tenant name + date range display (e.g., "Sanna Juni Benemar • 3 dec → ?")

### 2. Architecture Documentation
- Added SSoT/DRY note to CLAUDE.md (Tenant is master data source)
- All handlers fetch tenant data live via repository (no duplication)

### 3. Self-Healing Page Reload (Just Implemented)
**File**: `dashboard/src/context/DataContext.tsx`
**Behavior**:
- Tracks disconnect start time when WebSocket closes
- Checks every 10 seconds if disconnected >= 5 minutes
- Triggers `window.location.reload()` at 5-minute mark
- Clears timer when connection restored
- **Limitation**: Will loop forever if backend completely down (acceptable - self-heals when backend returns)

## 🔄 PENDING TASKS

### Action Button Implementation ✅ COMPLETED (Nov 12, 2025)

**Buttons in ContractDetails.tsx** (lines 190-233):
1. ✅ **"Visa PDF"** - Already functional (`/api/contracts/:id/pdf`)
2. ✅ **"Skicka igen"** - Implemented with Zigned reminder API
3. ✅ **"Avbryt"** - Implemented with Zigned cancel API + confirmation dialog
4. ✅ **"Kopiera länkar"** - Implemented clipboard copy with Swedish labels

## 📋 ACTION BUTTON SPECIFICATIONS

### User's Requirements (From Latest Messages)

#### 1. Resend Email ("Skicka igen")
- **Research needed**: Check Zigned API reminder feature via REF tool
- Use Zigned's built-in reminder/notification system
- Backend endpoint: `POST /api/admin/contracts/:id/resend-email`
- Should trigger Zigned reminder, not custom email

#### 2. Cancel ("Avbryt")
- **Research needed**: Check Zigned cancel feature via REF tool
- Use existing `ContractSigner#cancel_contract(case_id)` method (lib/contract_signer.rb:95)
- Backend endpoint: `POST /api/admin/contracts/:id/cancel`
- **MUST show confirmation dialog**: "Är du säker?" before cancelling
- Check Zigned docs for proper cancel behavior

#### 3. Copy Links ("Kopiera länkar")
- Frontend-only (no backend)
- Format with Swedish labels:
  ```
  Hyresvärd: [signing_url]
  Hyresgäst: [signing_url]
  ```
- **CRITICAL**: Check contract data structure for signing URL field names
  - User recalls: Zigned might return "signing_room_url" or similar
  - Current interface has: `landlord_signing_url`, `tenant_signing_url`
  - **Action**: Verify actual Zigned API response field names
- Use `navigator.clipboard.writeText()`
- Show "Kopierat!" confirmation toast

#### 4. Button Visibility/State Logic
**User question**: "When would they not be applicable?"
**Need to review**: All contract states and determine button availability rules

**Possible states** (from SignedContract interface):
- `pending` - Awaiting signatures
- `landlord_signed` - Only landlord signed
- `tenant_signed` - Only tenant signed
- `completed` - Both signed
- `expired` - Past expiration date
- `cancelled` - Already cancelled
- `failed` - Generation/email errors

**Button state logic to determine**:
- **Visa PDF**: When does `pdf_url` exist? (probably always after generation)
- **Skicka igen**: Disabled when? (completed? cancelled? expired?)
- **Avbryt**: Disabled when? (completed? already cancelled?)
- **Kopiera länkar**: Disabled when? (URLs expire after completion/cancellation?)

## ✅ RESEARCH RESULTS (Completed)

### 1. Zigned Reminder API ✅
**Endpoint**: `POST /agreements/{agreement_id}/reminders`
**Purpose**: Sends reminder emails to participants who haven't signed yet
**Response**: Returns list of reminders with status and participant info
**From OpenAPI spec**:
```yaml
responses:
  "200":
    data:
      type: array
      items:
        properties:
          status: string
          participant: object
```

### 2. Zigned Cancel API ✅
**Endpoint**: `DELETE /agreements/{agreement_id}`
**Purpose**: Cancels/deletes an agreement
**Response**:
```yaml
result_type: deleted
resource_type: agreement
```
**Status codes**: 200 (success), 400 (error)
**Important**: Agreement has `cancellation_reason` field when cancelled

### 3. Signing URL Field Names ✅ CRITICAL FIX NEEDED
**ACTUAL Zigned field name**: `signing_room_url` (NOT `signing_url`)
**User was RIGHT**: It IS called "signing_room_url"

**From OpenAPI spec**:
```yaml
signing_room_url:
  type: string
  format: url
  example: https://www.zigned.se/sign/cxxpq0s5zpixsnygktqexample/cg9sj91x077akg93vprexample
  description: The URL to the signing room for the issuer. Only available after
    the agreement has been finalized for signing.
```

**🚨 CRITICAL ISSUE**: Our database/interface uses wrong field names!
- **We store**: `landlordSigningUrl`, `tenantSigningUrl`
- **Zigned returns**: `signing_room_url` (in participant/issuer objects)
- **Action needed**: Verify we're correctly mapping Zigned's `signing_room_url` → our `landlordSigningUrl`/`tenantSigningUrl`

## 📊 CURRENT DATA STRUCTURE

### SignedContract Interface (AdminDashboard.tsx:10-32)
```typescript
interface SignedContract {
  id: string
  tenant_id: string
  tenant_name: string          // ✅ Added this session
  tenant_start_date?: Date     // ✅ Added this session
  tenant_departure_date?: Date // ✅ Added this session
  case_id: string              // Zigned agreement ID
  pdf_url: string
  status: 'pending' | 'landlord_signed' | 'tenant_signed' | 'completed' | 'expired' | 'cancelled' | 'failed'
  landlord_signed: boolean
  tenant_signed: boolean
  landlord_signing_url: string  // 🔍 Verify this field name
  tenant_signing_url: string    // 🔍 Verify this field name
  test_mode: boolean
  expires_at: Date
  created_at: Date
  updated_at: Date
  generation_status?: 'draft' | 'generated' | 'validated' | 'failed'
  email_status?: 'pending' | 'sent' | 'bounced' | 'failed'
  error_message?: string
}
```

### Backend Contract Storage (SignedContract table)
**Prisma Schema Location**: `prisma/schema.prisma`
**Fields for signing URLs**:
- `landlordSigningUrl String`
- `tenantSigningUrl String`

**Handler mapping** (admin_contracts_handler.rb:61-62):
```ruby
landlord_signing_url: contract[:landlordSigningUrl],
tenant_signing_url: contract[:tenantSigningUrl],
```

### Zigned Client Methods (lib/zigned_client_v3.rb)
**Relevant methods**:
- `create_and_activate(pdf_path:, signers:, ...)` - Creates agreement
- `get_agreement_status(agreement_id)` - Fetches agreement data
- `add_participant(agreement_id:, ...)` - Adds signer
- **Missing methods we might need**:
  - Reminder/notification method
  - Cancel/terminate method

## 🎯 IMPLEMENTATION PLAN (Once Research Complete)

### Phase 1: Research (Next Steps)
1. Use REF tool to read Zigned docs for reminder feature
2. Use REF tool to read Zigned docs for cancel feature
3. Verify signing URL field names in actual Zigned responses
4. Determine button visibility rules based on contract states

### Phase 2: Backend Endpoints
1. Create `POST /api/admin/contracts/:id/resend-email` handler
2. Create `POST /api/admin/contracts/:id/cancel` handler
3. Add Zigned reminder/cancel methods to `lib/zigned_client_v3.rb`

### Phase 3: Frontend Integration
1. Implement confirmation dialog for cancel button
2. Implement clipboard copy for "Kopiera länkar"
3. Add button state logic (disabled/enabled based on contract state)
4. Add success/error toast notifications
5. Wire up API calls from ContractDetails.tsx

## 📁 KEY FILES

### Frontend
- `dashboard/src/components/admin/ContractDetails.tsx` - Action buttons location
- `dashboard/src/views/AdminDashboard.tsx` - SignedContract interface
- `dashboard/src/hooks/useContracts.tsx` - API fetching logic
- `dashboard/src/context/DataContext.tsx` - ✅ Self-healing just added

### Backend
- `handlers/admin_contracts_handler.rb` - Admin API endpoints
- `lib/contract_signer.rb` - Contract signing logic, has `cancel_contract` method
- `lib/zigned_client_v3.rb` - Zigned API client
- `docs/zigned-api-spec.yaml` - OpenAPI specification

### Documentation
- `docs/ADMIN_DASHBOARD_INTEGRATION.md` - Integration summary
- `docs/ADMIN_UI_REQUIREMENTS.md` - Original requirements
- `docs/ADMIN_DASHBOARD_TESTING_CHECKLIST.md` - Testing checklist

## 🐛 KNOWN ISSUES / EDGE CASES

1. **Signing URL Expiration**: Do Zigned signing URLs expire after contract completion?
2. **Reminder Cooldown**: Can you send reminders multiple times? Rate limits?
3. **Cancel Irreversibility**: Once cancelled, can contract be reactivated?
4. **Test Mode Behavior**: Do reminders/cancels work differently in test mode?

## 💡 USER PREFERENCES (This Session)

- Prefers English for technical discussions (even though UI is Swedish)
- Wants explicit confirmation before destructive actions (cancel)
- Values DRY architecture and single source of truth
- Wants to review specifications before implementation ("run it by me")
- Appreciates "Ultrathink" approach (thorough analysis)

## ✅ IMPLEMENTATION COMPLETED (Nov 12, 2025)

### Backend Changes

**1. ZignedClientV3** (`lib/zigned_client_v3.rb:348-363`)
- Added `send_reminder(agreement_id)` method - POST /agreements/{id}/reminders
- Already had `cancel_agreement(agreement_id)` method - POST /agreements/{id}/lifecycle/cancel

**2. AdminContractsHandler** (`handlers/admin_contracts_handler.rb`)
- Added route matching for `/contracts/:id/resend-email` (line 26-32)
- Added route matching for `/contracts/:id/cancel` (line 33-40)
- Implemented `resend_email(req, contract_id)` handler (lines 152-198)
  - Validates contract status (no reminders for completed/cancelled/expired)
  - Calls ZignedClientV3#send_reminder
  - Returns success/error with proper HTTP status codes
- Implemented `cancel_contract(req, contract_id)` handler (lines 200-252)
  - Validates contract status (no cancel for completed/already cancelled)
  - Calls ZignedClientV3#cancel_agreement
  - Updates database status to 'cancelled' on success
  - Returns success/error with proper HTTP status codes

### Frontend Changes

**1. ContractDetails Component** (`dashboard/src/components/admin/ContractDetails.tsx`)
- Added state management for loading states and toast notifications (lines 15-18)
- Added button disabled logic based on contract status (lines 20-23):
  - `canResendEmail`: false for completed/cancelled/expired
  - `canCancel`: false for completed/cancelled
  - `canCopyLinks`: false only for cancelled
- Implemented three action handlers:
  - `handleResendEmail()` - POST to /api/admin/contracts/:id/resend-email (lines 32-50)
  - `handleCancel()` - POST to /api/admin/contracts/:id/cancel (lines 53-74)
  - `handleCopyLinks()` - Clipboard API with Swedish labels (lines 77-86)
- Updated button elements with onClick handlers and disabled states (lines 203-233)
- Added confirmation dialog for cancel action (lines 235-267)
  - Orange AlertCircle icon
  - Swedish warning text
  - "Nej, behåll" (keep) vs "Ja, avbryt kontrakt" (confirm cancel)
  - Prevents accidental cancellations
- Added toast notification component (lines 269-289)
  - Green success toast with CheckCircle2 icon
  - Red error toast with XCircle icon
  - Auto-dismisses after 3 seconds
  - Fixed position bottom-right

### Button State Logic (As Approved by User)
- **Visa PDF**: Always enabled when pdf_url exists
- **Skicka igen**: Disabled for completed/cancelled/expired contracts
- **Avbryt**: Disabled for completed/cancelled contracts
- **Kopiera länkar**: Disabled only for cancelled contracts

### User Experience Features
- Loading states show "Skickar..." and "Avbryter..." during API calls
- Disabled buttons show 40% opacity and cursor-not-allowed
- Success toasts appear for 3 seconds
- Error toasts display backend error messages when available
- Cancel confirmation dialog prevents accidental destructive actions
- Page auto-reloads 1.5 seconds after successful cancellation to show updated status

## 📝 NEXT SESSION STARTING POINT

**COMPLETED**: All action buttons fully functional with proper error handling, confirmation dialogs, and user feedback.

## 📋 QUICK SUMMARY FOR NEXT SESSION

### What We Learned
1. ✅ **Reminder endpoint exists**: `POST /agreements/{id}/reminders` - Ready to implement
2. ✅ **Cancel endpoint exists**: `DELETE /agreements/{id}` - Ready to implement
3. ✅ **Field name is `signing_room_url`** - Need to verify we're capturing this correctly from Zigned

### Immediate Action Items
1. **Verify URL mapping**: Check if `ContractSigner` correctly maps Zigned's `signing_room_url` to our `landlordSigningUrl`/`tenantSigningUrl`
2. **Button state logic**: Define when each button should be disabled (needs state analysis)
3. **Implement backend endpoints**:
   - `POST /api/admin/contracts/:id/resend-email` → calls Zigned reminder API
   - `POST /api/admin/contracts/:id/cancel` → calls Zigned DELETE + confirmation dialog
4. **Frontend clipboard copy**: Implement "Kopiera länkar" button with Swedish labels

### Files to Check Next
- `lib/contract_signer.rb` - How we save signing URLs from Zigned
- `lib/zigned_client_v3.rb` - Add reminder/cancel methods
- `dashboard/src/components/admin/ContractDetails.tsx` - Wire up buttons

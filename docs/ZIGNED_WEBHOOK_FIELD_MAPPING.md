# Zigned Webhook Field Mapping

**Real-world webhook payload analysis** - What events actually send vs what our database can store.

**Date**: 2025-11-11
**Source**: Live webhook testing with actual payloads from Zigned API v3

---

## Database Schema vs Webhook Events

### SignedContract Lifecycle Fields

| Database Field | Currently Populated? | Could Be Populated By | Event | Field Path |
|---|---|---|---|---|
| **generationStatus** | ✅ Yes (hardcoded) | ✅ `agreement.pdf_verification.completed` | When PDF passes validation | `data.status` ("generating") |
| **generationStartedAt** | ❌ No | ⚠️ Not available | - | - |
| **generationCompletedAt** | ✅ Yes (hardcoded) | ✅ `agreement.pdf_verification.completed` | When validation passes | `data.updated_at` |
| **generationFailedAt** | ❌ No | ⚠️ Not seen yet | - | - |
| **generationError** | ❌ No | ⚠️ Not seen yet | - | - |
| **validationStatus** | ✅ Yes | ✅ `agreement.pdf_verification.completed` | When PDF validation completes | Set to 'completed' or 'failed' |
| **validationStartedAt** | ❌ No | ⚠️ Not available | - | - |
| **validationCompletedAt** | ✅ Yes | ✅ `agreement.pdf_verification.completed` | When validation passes | `data.updated_at` |
| **validationFailedAt** | ✅ Yes | ✅ `agreement.pdf_verification.failed` | When validation fails | `data.updated_at` |
| **validationErrors** | ✅ Yes | ✅ `agreement.pdf_verification.failed` | Validation error details | `data.error` or `data.validation_error` |
| **emailDeliveryStatus** | ✅ Yes | ✅ `email_event.agreement_invitation.all_delivered` | When all emails sent | Set to 'delivered' or 'failed' |
| **landlordEmailDelivered** | ✅ Yes | ✅ `email_event.agreement_invitation.delivered` | Per-participant email confirmation | Match by email (via participant) |
| **tenantEmailDelivered** | ✅ Yes | ✅ `email_event.agreement_invitation.delivered` | Per-participant email confirmation | Match by email (via participant) |
| **emailDeliveryFailedAt** | ✅ Yes | ✅ `email_event.agreement_invitation.delivery_failed` | Email bounce detection | `data.created_at` parsed |
| **emailDeliveryError** | ✅ Yes | ✅ `email_event.agreement_invitation.delivery_failed` | Email error details | `data.error` or `data.bounce_reason` |

### ContractParticipant Fields

| Database Field | Currently Populated? | Could Be Populated By | Event | Field Path |
|---|---|---|---|---|
| **id** | ✅ Yes (generated) | - | - | - |
| **contractId** | ✅ Yes | - | From agreement lookup | - |
| **participantId** | ✅ Yes | ✅ `participant.lifecycle.fulfilled` | Participant unique ID | `data.id` |
| **name** | ✅ Yes | ✅ `participant.lifecycle.fulfilled` | Full name | `data.name` |
| **email** | ✅ Yes | ✅ `participant.lifecycle.fulfilled` | Email address | `data.email` |
| **personalNumber** | ❌ **NOT IN WEBHOOK!** | ⚠️ Must extract from initial contract creation | - | **Not sent by Zigned** |
| **role** | ✅ Yes | ✅ `participant.lifecycle.fulfilled` | "signer" / "observer" | `data.role` |
| **status** | ✅ Yes | ✅ `participant.lifecycle.fulfilled` | "pending" / "fulfilled" | `data.status` |
| **signingUrl** | ✅ Yes | ✅ `participant.lifecycle.fulfilled` | Unique signing room URL | `data.signing_room_url` (or `signing_url`) |
| **signedAt** | ✅ Yes | ✅ `participant.lifecycle.fulfilled` | BankID signature timestamp | `data.signed_at` |
| **emailDelivered** | ✅ Yes | ✅ `email_event.agreement_invitation.delivered` | Email confirmation | Set to `true` when event received |
| **emailDeliveredAt** | ✅ Yes | ✅ `email_event.agreement_invitation.delivered` | When email delivered | `data.created_at` |
| **emailDeliveryFailed** | ✅ Yes | ✅ `email_event.agreement_invitation.delivery_failed` | Email bounce | Set to `true` when event received |
| **emailDeliveryError** | ✅ Yes | ✅ `email_event.agreement_invitation.delivery_failed` | Error message | `data.error` or `data.bounce_reason` |
| **identityEnforcementPassed** | ✅ Yes | ✅ `participant.identity_enforcement.passed` | Swedish personnummer verified | Set to `true` when passed |
| **identityEnforcementFailedAt** | ✅ Yes | ✅ `participant.identity_enforcement.failed` | Identity check failed | `Time.now` when failed |

---

## Webhook Events We Receive (Real Payloads)

### ✅ Critical Lifecycle Events (Currently Handled)

#### 1. `agreement.lifecycle.pending`
**When**: Agreement activated, ready for signing
**Current handling**: Set lifecycle status, log participant IDs
**What we could add**:
- Extract participant count
- Store expires_at timestamp
- Track test_mode flag

**Payload structure**:
```json
{
  "event": "agreement.lifecycle.pending",
  "data": {
    "id": "cmhupv03i09q8liy4ht8y67i4",
    "title": "Fredrik Bränström Hyresavtal 2023-02-01",
    "test_mode": true,
    "status": "pending",
    "participants": ["cmhupv1jl...", "cmhupv1jf..."],  // Array of IDs only
    "expires_at": null,
    "created_at": "2025-11-11T15:18:51.966Z",
    "updated_at": "2025-11-11T15:18:54.277Z"
  }
}
```

**Rich data available but NOT stored**:
- `issuer.name`, `issuer.email`, `issuer.role`
- `documents.original_documents.main.data.filename`
- `communication.send_emails`, `communication.default_locale`

---

#### 2. `participant.lifecycle.fulfilled`
**When**: Individual signer completes signing
**Current handling**: Create/update participant record, set signed_at, update legacy landlord/tenant flags
**What we could add**:
- Store `signing_room_url` (unique per participant)
- Extract signature method (`se_bid` = Swedish BankID)
- Extract identity enforcement details
- Extract IP address and user agent (audit trail)

**Payload structure**:
```json
{
  "event": "participant.lifecycle.fulfilled",
  "data": {
    "id": "cmhupv1jl09qfliy49bzyqp0g",
    "name": "Fredrik Mats Bränström",
    "email": "branstrom@gmail.com",
    "status": "fulfilled",
    "agreement": "cmhupv03i09q8liy4ht8y67i4",
    "signing_room_url": "https://www.zigned.se/sign/...",
    "role": "signer",
    "signed_at": "2025-11-11T18:20:30.000Z",
    "signature": {
      "method": "se_bid",  // Swedish BankID
      "data": {
        "name": "FREDRIK MATS BRÄNSTRÖM",
        "document_hash": "mmAScRNyMLCG9JtctakS1ETOtEBZOrMIun2PLKRObrU=",
        "status": "complete"
      }
    },
    "identity_enforcement": {
      "enabled": true,
      "status": "passed",
      "enforcement_method": "swe_pno_crosscheck"
    }
  }
}
```

**Rich data available but NOT stored**:
- `signature.method` - Could store to show how user signed (BankID, SMS, etc)
- `signature.data.document_hash` - PDF hash for audit trail
- `identity_enforcement` - Already have fields, just not populated yet!

---

#### 3. `agreement.lifecycle.fulfilled`
**When**: All signers have signed
**Current handling**: Mark landlord_signed=true, tenant_signed=true, email_delivery_status='delivered'
**What we could add**:
- Nothing really - this is just a confirmation event

**Payload structure**:
```json
{
  "event": "agreement.lifecycle.fulfilled",
  "data": {
    "id": "cmhupv03i09q8liy4ht8y67i4",
    "title": "...",
    "fulfilled_at": "2025-11-11T18:21:12.000Z"
  }
}
```

---

#### 4. `agreement.lifecycle.finalized`
**When**: Signed PDF is ready for download
**Current handling**: Extract signed PDF URL, auto-download, mark status='completed'
**What we could add**:
- Store original PDF filename separately
- Store signed PDF file ID for direct API access

**Payload structure**:
```json
{
  "event": "agreement.lifecycle.finalized",
  "data": {
    "id": "cmhupv03i09q8liy4ht8y67i4",
    "status": "fulfilled",
    "documents": {
      "signed_document": {
        "data": {
          "id": "cmhuxsgh9037hjfvvm1gncn9i",
          "filename": "Fredrik_Branstrom_Hyresavtal_2023-02-01-signed-document.pdf",
          "url": "https://storage.googleapis.com/zigned-files/...",
          "created_at": "2025-11-11T19:00:50.157Z"
        }
      }
    },
    "updated_at": "2025-11-11T19:00:55.474Z"
  }
}
```

**Rich data available but NOT stored**:
- `documents.signed_document.data.id` - File ID for API access
- `documents.signed_document.data.filename` - Original filename
- `documents.original_documents.main.data.filename` - Unsigned PDF filename

---

### ⚠️ Tracking Events (NOT Currently Handled)

These events exist in database schema but we're not handling the webhook events yet!

#### 5. `participant.identity_enforcement.passed`
**When**: Swedish personnummer verification succeeds
**Database fields ready**: `identityEnforcementPassed`, `identityEnforcementFailedAt`
**Should populate**: `participant.identity_enforcement_passed = true`

**Payload structure**:
```json
{
  "event": "participant.identity_enforcement.passed",
  "data": {
    "id": "cmhupv1jf09qdliy4oxvkwmi7",
    "name": "Fredrik Mats Bränström",
    "email": "branstrom@gmail.com",
    "status": "processing",
    "agreement": "cmhupv03i09q8liy4ht8y67i4",
    "identity_enforcement": {
      "enabled": true,
      "status": "passed",
      "enforcement_method": "swe_pno_crosscheck"
    }
  }
}
```

---

#### 6. `agreement.pdf_verification.completed`
**When**: Uploaded PDF passes validation
**Database fields ready**: `validationStatus`, `validationCompletedAt`
**Should populate**: `validation_status = 'completed'`, `validation_completed_at = data.updated_at`

**Payload structure**:
```json
{
  "event": "agreement.pdf_verification.completed",
  "data": {
    "id": "cmhupv03i09q8liy4ht8y67i4",
    "status": "generating",
    "updated_at": "2025-11-11T19:00:42.688Z"
  }
}
```

---

#### 7. Email Events (NOT Seen Yet)
**Events**:
- `email_event.agreement_invitation.delivered`
- `email_event.agreement_invitation.delivery_failed`
- `email_event.agreement_invitation.all_delivered`

**Database fields ready**:
- `landlordEmailDelivered`, `tenantEmailDelivered`
- `emailDeliveryFailedAt`, `emailDeliveryError`

**Waiting for real payloads to implement...**

---

### ℹ️ Informational Events (Acknowledged but Ignored)

These are fine to ignore - they're detailed activity tracking for admin dashboards:

- `sign_event.signing_room.entered` - User opened signing page
- `sign_event.signing_room.left` - User closed signing page
- `sign_event.document.loaded` - PDF rendered in browser
- `sign_event.document.scrolled_to_bottom` - User scrolled to end
- `sign_event.sign.initiated_sign` - User clicked "Sign" button
- `sign_event.sign.completed_sign` - Signature completed (duplicate of participant.lifecycle.fulfilled)

All return HTTP 200 "Event type not implemented" - perfect!

---

## Implementation Status (Nov 11, 2025)

### ✅ FULLY IMPLEMENTED - All Critical Events
- [x] **agreement.lifecycle.pending** - Sets generation/validation/email delivery status
- [x] **participant.lifecycle.fulfilled** - Creates participants, updates signatures
- [x] **agreement.lifecycle.fulfilled** - Marks both parties signed
- [x] **agreement.lifecycle.finalized** - Auto-downloads PDF, marks completed
- [x] **agreement.lifecycle.expired** - Marks contract expired
- [x] **agreement.lifecycle.cancelled** - Marks contract cancelled

### ✅ FULLY IMPLEMENTED - All Tracking Events
- [x] **participant.identity_enforcement.passed** - Sets identity verification flag
- [x] **participant.identity_enforcement.failed** - Records identity failure + timestamp
- [x] **agreement.pdf_verification.completed** - Sets validation completed
- [x] **agreement.pdf_verification.failed** - Records validation failure + errors
- [x] **email_event.agreement_invitation.delivered** - Per-participant email tracking
- [x] **email_event.agreement_invitation.all_delivered** - Contract-level email status
- [x] **email_event.agreement_invitation.delivery_failed** - Email bounce handling
- [x] **email_event.agreement_finalized.delivered** - Final PDF delivery confirmation

### ✅ FULLY IMPLEMENTED - All Database Fields
- [x] Store `signing_room_url` in participant records (handles both field name variants)
- [x] Per-participant email delivery tracking (delivered/failed/error)
- [x] Identity enforcement pass/fail tracking
- [x] PDF validation pass/fail tracking
- [x] Contract-level email delivery status
- [x] Personal number lookup (email matching + tenant query)

---

## Critical Findings

### 1. **Personal Number NOT in Webhook**
The `personal_number` field is **not sent by Zigned in any webhook event**. We must:
- Store it when creating the initial contract (from ContractSigner input)
- Look it up from existing participant records when processing fulfilled events

### 2. **Participants Array is Just IDs**
In `agreement.lifecycle.pending`, the `participants` field is an array of strings (IDs), not objects:
```json
"participants": ["cmhupv1jl09qfliy49bzyqp0g", "cmhupv1jf09qdliy4oxvkwmi7"]
```
Can't create ContractParticipant records from this - must wait for participant.lifecycle.fulfilled.

### 3. **Field Name Inconsistency**
Zigned sends v3 event names in v1 field structure:
- Field: `"event"` (v1 style)
- Values: `"participant.lifecycle.fulfilled"` (v3 names)
- Must support both `payload['event_type']` and `payload['event']`

### 4. **Nested Document Structure**
Signed PDF URL is buried deep:
```ruby
data.dig('documents', 'signed_document', 'data', 'url')
```
Not flat `data['signed_document_url']` as one might expect.

### 5. **Signing URL Field Name Inconsistency**
Zigned API uses different field names for signing URLs in different endpoints:
- **Batch participant creation** (`POST /agreements/{id}/participants/batch`): May return `signing_url`
- **Webhook participant events** (`participant.lifecycle.fulfilled`): Returns `signing_room_url`

**Solution**: Always check both field names with fallback:
```ruby
url = participant['signing_url'] || participant['signing_room_url']
```

Without this fallback, signing URLs appeared as empty strings in contract creation output and `nil` in database, even though Zigned provided them in the API response.

---

## Recommendations

1. **Add new handlers** for identity_enforcement and pdf_verification events
2. **Expand participant record** to store signing_url and signature_method
3. **Wait for email events** - haven't received any real payloads yet to reverse-engineer
4. **Document all findings** in this file as we discover more webhook quirks

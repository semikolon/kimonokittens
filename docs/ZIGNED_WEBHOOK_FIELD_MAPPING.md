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
| **validationStatus** | ✅ Yes (hardcoded) | ✅ `agreement.pdf_verification.completed` | When PDF validation completes | Implicit (event existence) |
| **validationStartedAt** | ❌ No | ⚠️ Not available | - | - |
| **validationCompletedAt** | ✅ Yes (hardcoded) | ✅ `agreement.pdf_verification.completed` | When validation passes | `data.updated_at` |
| **validationFailedAt** | ❌ No | ⚠️ Not seen yet | - | - |
| **validationErrors** | ❌ No | ⚠️ Not seen yet | - | - |
| **emailDeliveryStatus** | ✅ Yes (hardcoded) | ✅ `email_event.agreement_invitation.delivered` | When invitation emails sent | Implicit (event existence) |
| **landlordEmailDelivered** | ❌ No | ✅ `email_event.agreement_invitation.delivered` | Per-participant email confirmation | Need to match participant |
| **tenantEmailDelivered** | ❌ No | ✅ `email_event.agreement_invitation.delivered` | Per-participant email confirmation | Need to match participant |
| **emailDeliveryFailedAt** | ❌ No | ✅ `email_event.agreement_invitation.delivery_failed` | Email bounce detection | Event timestamp |
| **emailDeliveryError** | ❌ No | ✅ `email_event.agreement_invitation.delivery_failed` | Email error details | `data.error` or similar |

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
| **signingUrl** | ❌ No | ✅ `participant.lifecycle.fulfilled` | Unique signing room URL | `data.signing_room_url` |
| **signedAt** | ✅ Yes | ✅ `participant.lifecycle.fulfilled` | BankID signature timestamp | `data.signed_at` |
| **emailDelivered** | ❌ No | ✅ `email_event.agreement_invitation.delivered` | Email confirmation | Implicit (event existence) |
| **emailDeliveredAt** | ❌ No | ✅ `email_event.agreement_invitation.delivered` | When email delivered | `request_timestamp` |
| **emailDeliveryFailed** | ❌ No | ✅ `email_event.agreement_invitation.delivery_failed` | Email bounce | Implicit (event existence) |
| **emailDeliveryError** | ❌ No | ✅ `email_event.agreement_invitation.delivery_failed` | Error message | `data.error` or similar |
| **identityEnforcementPassed** | ❌ No | ✅ `participant.identity_enforcement.passed` | Swedish personnummer verified | `data.identity_enforcement.status` |
| **identityEnforcementFailedAt** | ❌ No | ✅ `participant.identity_enforcement.failed` | Identity check failed | Event timestamp |

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

## Implementation Priority

### Now (Critical for Core Flow)
- [x] agreement.lifecycle.pending
- [x] participant.lifecycle.fulfilled
- [x] agreement.lifecycle.fulfilled
- [x] agreement.lifecycle.finalized

### Next (Enhance Existing Fields)
- [ ] participant.identity_enforcement.passed - Populate identity_enforcement_passed
- [ ] agreement.pdf_verification.completed - Populate validation_status
- [ ] Store signature.method in participant record (add field?)
- [ ] Store signing_room_url in participant record

### Future (When Email Events Arrive)
- [ ] email_event.agreement_invitation.delivered - Per-participant email tracking
- [ ] email_event.agreement_invitation.delivery_failed - Email bounce handling

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

---

## Recommendations

1. **Add new handlers** for identity_enforcement and pdf_verification events
2. **Expand participant record** to store signing_url and signature_method
3. **Wait for email events** - haven't received any real payloads yet to reverse-engineer
4. **Document all findings** in this file as we discover more webhook quirks

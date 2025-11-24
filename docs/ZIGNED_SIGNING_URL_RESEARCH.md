# Zigned API v3 - Signing URL Research Report

**Date**: 2025-11-24
**Purpose**: Understand when signing URLs become available in the Zigned API v3 lifecycle
**Bug Context**: Contract invitation SMS sent without signing URLs

---

## Executive Summary

**Key Finding**: Signing URLs (`signing_room_url`) are **ONLY available AFTER the agreement has been finalized for signing**. This means:

1. ❌ **POST /agreements/:id/participants/batch** does NOT include signing URLs in the response
2. ❌ Signing URLs are NULL when agreement status is `draft`
3. ✅ Signing URLs become available AFTER **POST /agreements/:id/lifecycle** with `lifecycle_state: 'pending'`
4. ✅ Must fetch agreement again via **GET /agreements/:id** with `?expand=participants` to get signing URLs

---

## API Endpoint Analysis

### 1. POST /agreements/:id/participants/batch

**Purpose**: Add multiple participants to a draft agreement at once (introduced v3.2.2, June 2024)

**Request Body**:
```json
{
  "participants": [
    {
      "email": "tenant@example.com",
      "name": "Jane Doe",
      "role": "signer",
      "locale": "sv-SE"
    }
  ]
}
```

**Response Structure**:
```json
{
  "version": "1.0",
  "result_type": "list",
  "resource_type": "participant",
  "data": [
    {
      "id": "c4zatmug6d5jtfyl1b5example",
      "resource_type": "participant",
      "name": "Jane Doe",
      "email": "tenant@example.com",
      "status": "draft",
      "role": "signer",
      "order": 1,
      "agreement": "c9bdfuzfwkhkkcmxihbexample",
      "signing_room_url": null,  // ⚠️ NULL for draft agreements!
      "locale": "sv-SE",
      "created_at": "2024-01-01T00:00:00.000Z",
      "updated_at": "2024-01-01T00:00:00.000Z"
    }
  ]
}
```

**Critical Notes**:
- Returns full participant objects (NOT just IDs)
- `signing_room_url` field is **nullable** and **NULL** for draft agreements
- Participants have `status: "draft"` initially
- OpenAPI spec description (line 20458-20459): **"Only available after the agreement has been finalized for signing"**

---

### 2. POST /agreements/:id/lifecycle

**Purpose**: Transition agreement status from draft → pending/open

**Request Body**:
```json
{
  "lifecycle_state": "pending"  // Options: "pending", "open"
}
```

**Response**: Returns complete agreement object (same structure as GET /agreements/:id)

**Effect on Signing URLs**:
- Triggers Zigned to generate signing URLs for all participants
- Changes agreement status from `draft` → `pending` (or `open`)
- Changes participant status from `draft` → `pending`
- Makes `signing_room_url` available for participants

**Important**: Response MAY include participant data with signing URLs, BUT depends on query parameters (expand).

---

### 3. GET /agreements/:id

**Purpose**: Fetch complete agreement details including participants

**Key Query Parameter**: `?expand=participants`

**Response Structure - Participants Field**:

The `participants` field uses a **oneOf** schema with THREE possible return formats:

#### Format 1: Array of IDs only (default, when NOT expanded)
```json
{
  "participants": [
    "chdh16ordhlddmtwtueexample",
    "cjyyl51sftj7akqxa4mexample"
  ]
}
```

#### Format 2: Full participant objects (when `?expand=participants`)
```json
{
  "participants": {
    "version": "1.0",
    "result_type": "list",
    "resource_type": "participant",
    "data": [
      {
        "id": "c4zatmug6d5jtfyl1b5example",
        "resource_type": "participant",
        "name": "Jane Doe",
        "email": "tenant@example.com",
        "status": "pending",
        "role": "signer",
        "order": 1,
        "signing_room_url": "https://www.zigned.se/sign/cxxpq0s5zpixsnygktqexample/cg9sj91x077akg93vprexample",
        "locale": "sv-SE",
        "signed_at": null,
        "signature": null,
        "created_at": "2024-01-01T00:00:00.000Z",
        "updated_at": "2024-01-01T00:00:00.000Z"
      }
    ]
  }
}
```

#### Format 3: Null (if no participants)
```json
{
  "participants": null
}
```

**Critical Insight**: Without `?expand=participants`, you only get participant IDs, NOT full objects with signing URLs!

---

## Agreement Lifecycle States

**From OpenAPI spec** (lines 13091-13101, 2128-2138):

| Status | Description |
|--------|-------------|
| `draft` | Initial state - editing allowed, no signing URLs |
| `pending` | Finalized, awaiting signatures - **signing URLs available** |
| `open` | Alternative to pending for certain flows |
| `fulfilled` | All participants signed |
| `cancelled` | Agreement cancelled |
| `generating` | PDF generation in progress |
| `failed_to_generate` | PDF generation failed |
| `expired` | Signing deadline passed |

**Issuer Signing URL** (lines 337-338, 2415-2416, 13379-13380):
> "The URL to the signing room for the issuer. Only available after the agreement has been finalized for signing."

**Participant Signing URL** (lines 5217-5219, 20458-20459):
> "The URL to the signing room for the participant. Only available after the agreement has been finalized for signing."

**Observer Signing URL** (lines 8422-8423, 20973-20974):
> "The URL to the signing room for the observer. Only available after the agreement is not in draft."

---

## Participant Schema Deep Dive

**Complete Participant Object** (from schema ref `95c1af3f45da65daeedb661f70210b46b2bd71d5`):

```yaml
type: object
properties:
  id: string (cuid)
  resource_type: "participant"
  name: string (nullable)
  email: string (nullable)
  status: enum [draft, pending, initiated, processing, fulfilled, rejected]
  order: number (queue number for sequential signing)
  signing_group: string | object | null
  agreement: string (cuid - parent agreement ID)
  signing_room_url: string (url, nullable) ⭐
  locale: enum [sv-SE, en-US] (nullable)
  created_at: string (ISO datetime)
  updated_at: string (ISO datetime)

  # Role-specific fields (discriminator: role)
  role: enum [signer, approver]

  # If role = "signer":
  signed_at: string (ISO datetime, nullable)
  signature: object (nullable)

  # If role = "approver":
  decision_made_at: string (ISO datetime, nullable)

required:
  - id
  - resource_type
  - name
  - email
  - status
  - order
  - signing_group
  - agreement
  - signing_room_url  # ⚠️ Required field but can be null!
  - created_at
  - updated_at
```

**Important**: `signing_room_url` is marked as **required** in the schema, but it's **nullable** - meaning it MUST be present in the response, but its value can be `null` until the agreement is finalized.

---

## Webhook Events Related to Signing URLs

**From OpenAPI spec** (lines 19074-19079, 19097-19099):

### Agreement Lifecycle Events:
- `agreement.lifecycle.pending` - Agreement moved to pending (signing URLs generated)
- `agreement.lifecycle.fulfilled` - All participants signed
- `agreement.lifecycle.finalized` - Agreement finalized (all signatures complete)
- `agreement.lifecycle.cancelled` - Agreement cancelled
- `agreement.lifecycle.opened` - Agreement opened for signing
- `agreement.lifecycle.expired` - Agreement expired

### Participant Lifecycle Events:
- `participant.lifecycle.received_invitation` - Participant received invitation (has signing URL)
- `participant.lifecycle.fulfilled` - Participant completed signing
- `participant.lifecycle.forwarded` - Participant forwarded to next in sequence

**Recommendation**: Subscribe to `agreement.lifecycle.pending` webhook to know when signing URLs are available.

---

## Correct Implementation Flow

### Current Bug (What We're Doing Wrong):

```ruby
# 1. Create agreement
agreement = zigned_client.create_agreement(...)

# 2. Add participants via batch
response = zigned_client.add_participants_batch(agreement_id, participants)

# 3. BUG: Trying to send SMS with signing URLs from batch response
participants = response['data']
participants.each do |p|
  send_sms(p['signing_room_url'])  # ❌ NULL! Agreement still draft!
end
```

### Correct Implementation:

```ruby
# 1. Create agreement (status: draft)
agreement = zigned_client.create_agreement(
  title: "Rental Contract - #{tenant_name}",
  files: [{ id: pdf_file_id }],
  ...
)
agreement_id = agreement['data']['id']

# 2. Add participants (signing_room_url will be null)
batch_response = zigned_client.add_participants_batch(agreement_id, [
  {
    name: tenant_name,
    email: tenant_email,
    role: 'signer',
    locale: 'sv-SE'
  }
])

# Extract participant IDs for later reference
participant_ids = batch_response['data'].map { |p| p['id'] }

# 3. Activate agreement (draft → pending, generates signing URLs)
lifecycle_response = zigned_client.update_lifecycle(agreement_id, 'pending')

# 4. CRITICAL: Fetch agreement again with expanded participants
agreement_with_urls = zigned_client.get_agreement(agreement_id, expand: ['participants'])

# 5. Extract signing URLs from expanded participant data
participants_data = agreement_with_urls['data']['participants']['data']
participants_data.each do |participant|
  signing_url = participant['signing_room_url']

  if signing_url.nil?
    raise "Signing URL still null after lifecycle transition!"
  end

  # Now send SMS with actual signing URL
  send_contract_invitation_sms(
    phone: tenant_phone,
    signing_url: signing_url,
    tenant_name: participant['name']
  )
end
```

---

## API Client Method Requirements

### Current ZignedClientV3 Methods:

```ruby
# ✅ Already implemented
def create_agreement(title:, files:, trust_level: 'SES', ...)
def upload_file(file_path, filename)
def add_participants_batch(agreement_id, participants)

# ⚠️ MISSING - Need to implement
def update_lifecycle(agreement_id, lifecycle_state)
  # POST /agreements/:agreement_id/lifecycle
  # Body: { lifecycle_state: 'pending' }
end

# ⚠️ MISSING - Need to implement with expand parameter
def get_agreement(agreement_id, expand: [])
  # GET /agreements/:agreement_id?expand=participants,observers
  # Returns full agreement with expanded relations
end
```

---

## Testing Recommendations

### Unit Tests:

```ruby
describe 'Contract signing URL availability' do
  it 'returns null signing URLs for draft participants' do
    response = zigned_client.add_participants_batch(draft_agreement_id, participants)
    expect(response['data'].first['signing_room_url']).to be_nil
  end

  it 'generates signing URLs after lifecycle transition to pending' do
    # Activate agreement
    zigned_client.update_lifecycle(agreement_id, 'pending')

    # Fetch with expanded participants
    agreement = zigned_client.get_agreement(agreement_id, expand: ['participants'])
    participant = agreement['data']['participants']['data'].first

    expect(participant['signing_room_url']).to match(%r{https://www.zigned.se/sign/})
  end

  it 'raises error if trying to send SMS before lifecycle activation' do
    batch_response = zigned_client.add_participants_batch(agreement_id, participants)

    expect {
      send_contract_invitation_sms(
        signing_url: batch_response['data'].first['signing_room_url']
      )
    }.to raise_error(/Signing URL not available/)
  end
end
```

### Integration Tests:

1. Create real agreement in test mode (`test_mode: true`)
2. Add participants via batch
3. Verify signing_room_url is null
4. Transition to pending
5. Fetch agreement with expand
6. Verify signing_room_url is populated
7. Verify URL format matches expected pattern

---

## Common Pitfalls & Gotchas

### ❌ Pitfall 1: Assuming batch response includes signing URLs
**Fix**: Always transition lifecycle first, then fetch with expand.

### ❌ Pitfall 2: Forgetting `?expand=participants` query parameter
**Fix**: Without expand, you only get participant IDs (string array), not full objects.

### ❌ Pitfall 3: Not handling nullable signing_room_url
**Fix**: Check for null before sending SMS, raise meaningful error if still null after lifecycle transition.

### ❌ Pitfall 4: Caching participant data from batch response
**Fix**: Participant data changes after lifecycle transition - always fetch fresh data when you need signing URLs.

### ❌ Pitfall 5: Assuming lifecycle response includes expanded participants
**Fix**: Lifecycle POST may return agreement, but participant expansion is not guaranteed without explicit query parameter.

---

## Performance Considerations

**Question**: Is the extra GET request after lifecycle transition necessary?

**Answer**: YES, because:
1. Lifecycle POST response structure doesn't guarantee expanded participants by default
2. Signing URLs are generated asynchronously (may take seconds)
3. OpenAPI spec shows participants field as `oneOf` - could be IDs only
4. Explicit GET with expand ensures consistent response format

**Optimization**: If lifecycle POST supports `?expand=participants`, use that instead of separate GET:

```ruby
# Potential optimization (check if API supports this)
lifecycle_response = zigned_client.update_lifecycle(
  agreement_id,
  'pending',
  expand: ['participants']  # If supported
)

# Then use lifecycle_response directly without additional GET
```

**Verification needed**: Test whether POST /agreements/:id/lifecycle accepts expand parameter.

---

## Database Schema Implications

### Contract Model:

```ruby
class Contract
  # Zigned integration fields
  field :zigned_agreement_id, type: String  # Agreement ID
  field :zigned_status, type: String        # draft, pending, fulfilled, etc.
  field :signing_url, type: String          # Participant signing URL (after activation)
  field :activated_at, type: Time           # When lifecycle transitioned to pending
  field :invitation_sent_at, type: Time     # When SMS was sent with signing URL
end
```

**State Machine**:
1. `created` - Contract generated, no Zigned agreement yet
2. `uploaded` - PDF uploaded to Zigned
3. `draft` - Agreement created, participants added, but not activated
4. `pending` - Lifecycle transitioned, signing URLs available
5. `invitation_sent` - SMS sent to tenant with signing URL
6. `signed` - Tenant completed signing
7. `fulfilled` - All parties signed

---

## References

**OpenAPI Spec Sections**:
- Line 2086-2500: GET /agreements/:id response structure
- Line 5808-5870: POST /agreements/:id/participants/batch response
- Line 13050-13900: POST /agreements/:id/lifecycle endpoint
- Line 20391-20600: Participant schema definition (ref: 95c1af3f45da65daeedb661f70210b46b2bd71d5)
- Line 2433-2471: Participants field oneOf schema (ID array vs expanded objects)

**Key Descriptions**:
- Line 337-338: Issuer signing_room_url availability
- Line 5217-5219: Participant signing_room_url availability
- Line 20458-20459: Participant schema signing_room_url description

**Zigned Documentation**:
- Blog post: [Batch Participant Addition](https://docs.zigned.se/blog) (v3.2.2, June 2024)
- API Docs: https://docs.zigned.se/ (agreements, lifecycle, participants sections)

---

## Conclusion

**The bug is confirmed**: Our current implementation tries to send SMS with signing URLs immediately after adding participants via batch, but the API returns `null` for `signing_room_url` until the agreement is activated.

**Required fixes**:
1. Implement `update_lifecycle(agreement_id, 'pending')` method
2. Implement `get_agreement(agreement_id, expand: [])` method with expand support
3. Update contract creation flow to activate agreement BEFORE sending SMS
4. Add validation to ensure signing_url is present before SMS dispatch
5. Update Contract model state machine to track activation separately from creation

**Estimated impact**:
- Backend: 2 new client methods + flow refactor = ~2-3 hours
- Testing: Unit + integration tests = ~1-2 hours
- Total: ~3-5 hours to implement and test properly

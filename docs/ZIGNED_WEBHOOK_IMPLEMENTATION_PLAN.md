# Zigned Webhook Integration - Complete Implementation Plan

**Status:** 📋 PLANNED
**Priority:** 🔥 CRITICAL (Current implementation broken - v1 events don't exist in v3 API)
**Created:** November 11, 2025
**Context:** OpenAPI spec analysis + current codebase audit

---

## Executive Summary

**Current State**: Webhook handler listens for v1 events that no longer exist in v3 API
**Impact**: Zero webhook events processing - contracts stuck in "pending" forever
**Solution**: Migrate to v3 event names + add comprehensive lifecycle tracking

**Available Events:** 47 webhook event types (OpenAPI spec)
**Currently Handled:** 0 (all event names are wrong)
**Plan Coverage:** 15 critical events (32% - high-value subset)

**Testing Priority:** Fresh test contract creation (`ContractSigner.create_and_send`) preferred over curl mocking - most realistic end-to-end validation.

---

## Phase 1: Critical Fixes (IMMEDIATE - Day 1)

### 1.1 Fix Event Name Terminology ⚡ **BLOCKING**

**Problem**: All webhook event handlers use v1 terminology that doesn't exist in v3.

**File**: `handlers/zigned_webhook_handler.rb`

**Current Code** (Lines 73-86):
```ruby
case event_type
when 'case.created'      # ❌ DOES NOT EXIST IN V3
when 'case.signed'       # ❌ DOES NOT EXIST IN V3
when 'case.completed'    # ❌ DOES NOT EXIST IN V3
when 'case.expired'      # ❌ DOES NOT EXIST IN V3
when 'case.cancelled'    # ❌ DOES NOT EXIST IN V3
```

**New Code** (v3 correct events):
```ruby
case event_type
when 'agreement.lifecycle.pending'      # ✅ Agreement activated (ready for signing)
when 'participant.lifecycle.fulfilled'  # ✅ Individual signer completed
when 'agreement.lifecycle.fulfilled'    # ✅ All signatures complete
when 'agreement.lifecycle.expired'      # ✅ Agreement expired
when 'agreement.lifecycle.cancelled'    # ✅ Agreement cancelled
```

**Action Items**:
- [ ] Update `event_type` from `payload['event']` to `payload['event_type']` (line 69)
- [ ] Rename all handler methods to match v3 terminology
- [ ] Update method calls in case statement
- [ ] Update database status values to match v3 terminology

**Testing**:
```bash
# Test with existing agreement: cmhuoppfb09arliy430o6lv4q
# Webhook logs should show correct event processing
tail -f /var/log/kimonokittens/webhook.log | grep "agreement.lifecycle"
```

---

### 1.2 Fix Security Bypass ⚡ **SECURITY ISSUE**

**Problem**: Webhook accepts requests with no signature if secret is unset (fail-open).

**File**: `handlers/zigned_webhook_handler.rb` (Lines 55-60)

**Current Code**:
```ruby
if @webhook_secret
  signature = request.env['HTTP_X_ZIGNED_SIGNATURE']
  unless valid_signature?(body, signature)
    return { status: 401, message: 'Invalid webhook signature', error: true }
  end
end
# Request proceeds even if @webhook_secret is nil!
```

**Fixed Code**:
```ruby
unless @webhook_secret
  raise ArgumentError, "ZIGNED_WEBHOOK_SECRET must be configured in environment"
end

signature = request.env['HTTP_X_ZIGNED_REQUEST_SIGNATURE']  # Correct header name from spec
unless valid_signature?(body, signature)
  return { status: 401, message: 'Invalid webhook signature', error: true }
end
```

**Note**: OpenAPI spec shows header is `x-zigned-request-signature` not `x-zigned-signature`

**Action Items**:
- [ ] Add fail-closed security check at handler initialization
- [ ] Fix HTTP header name to match OpenAPI spec
- [ ] Verify ZIGNED_WEBHOOK_SECRET is set in production `.env`
- [ ] Test with incorrect signature to ensure rejection

---

### 1.3 Update Webhook Payload Structure

**Problem**: Webhook payload structure different in v3.

**OpenAPI Spec** (Webhook notification structure):
```json
{
  "version": "1.0",
  "resource_type": "agreement",
  "event_type": "agreement.lifecycle.fulfilled",
  "data": {
    "id": "agreement_id",
    "status": "fulfilled",
    "title": "Hyresavtal - Tenant Name",
    "test_mode": true,
    "participants": [
      {
        "id": "participant_id",
        "name": "Fredrik Bränström",
        "email": "branstrom@gmail.com",
        "personal_number": "8604230717",
        "role": "signer",
        "status": "fulfilled",
        "signed_at": "2025-11-11T01:15:32.000Z"
      }
    ],
    "signed_document_url": "https://...",
    "fulfilled_at": "2025-11-11T01:15:32.000Z",
    "expires_at": "2025-12-11T01:15:32.000Z"
  }
}
```

**Action Items**:
- [ ] Update payload parsing: `payload['event_type']` not `payload['event']`
- [ ] Update data access: Agreement data is in `payload['data']`
- [ ] Handle participants array structure (not flat signer object)
- [ ] Parse ISO 8601 timestamps correctly

---

## Phase 2: Database Schema Extensions (Day 1-2)

### 2.1 Add Contract Lifecycle Tracking Fields

**New Migration**: `20251111_add_contract_lifecycle_tracking.sql`

**Goal**: Track generation, validation, and email delivery states with full lifecycle visibility

**Rationale**: Admin dashboard needs real-time visibility into "PDF generating...", "Validation complete", failures, etc.

**Schema Changes**:
```sql
-- Add lifecycle event tracking
ALTER TABLE "SignedContract"
  ADD COLUMN "generationStatus" TEXT DEFAULT 'pending',
  ADD COLUMN "generationStartedAt" TIMESTAMP(3),
  ADD COLUMN "generationCompletedAt" TIMESTAMP(3),
  ADD COLUMN "generationFailedAt" TIMESTAMP(3),
  ADD COLUMN "generationError" JSONB,  -- Structured error data {code, message, details}

  ADD COLUMN "validationStatus" TEXT DEFAULT 'pending',
  ADD COLUMN "validationStartedAt" TIMESTAMP(3),
  ADD COLUMN "validationCompletedAt" TIMESTAMP(3),
  ADD COLUMN "validationFailedAt" TIMESTAMP(3),
  ADD COLUMN "validationErrors" JSONB,  -- Array of validation errors from Zigned

  ADD COLUMN "emailDeliveryStatus" TEXT DEFAULT 'pending',
  ADD COLUMN "landlordEmailDelivered" BOOLEAN DEFAULT false,
  ADD COLUMN "tenantEmailDelivered" BOOLEAN DEFAULT false,
  ADD COLUMN "emailDeliveryFailedAt" TIMESTAMP(3),
  ADD COLUMN "emailDeliveryError" TEXT;

-- Add indices for event queries
CREATE INDEX "SignedContract_generationStatus_idx" ON "SignedContract"("generationStatus");
CREATE INDEX "SignedContract_validationStatus_idx" ON "SignedContract"("validationStatus");
CREATE INDEX "SignedContract_emailDeliveryStatus_idx" ON "SignedContract"("emailDeliveryStatus");

-- Add check constraints for status values
ALTER TABLE "SignedContract"
  ADD CONSTRAINT "SignedContract_generationStatus_check"
    CHECK ("generationStatus" IN ('pending', 'started', 'completed', 'failed')),

  ADD CONSTRAINT "SignedContract_validationStatus_check"
    CHECK ("validationStatus" IN ('pending', 'started', 'completed', 'failed')),

  ADD CONSTRAINT "SignedContract_emailDeliveryStatus_check"
    CHECK ("emailDeliveryStatus" IN ('pending', 'delivering', 'delivered', 'failed'));

-- Comments for clarity
COMMENT ON COLUMN "SignedContract"."generationStatus" IS 'PDF generation lifecycle: pending → started → completed/failed';
COMMENT ON COLUMN "SignedContract"."validationStatus" IS 'Document validation lifecycle: pending → started → completed/failed';
COMMENT ON COLUMN "SignedContract"."emailDeliveryStatus" IS 'Email delivery lifecycle: pending → delivering → delivered/failed';
COMMENT ON COLUMN "SignedContract"."generationError" IS 'JSONB structured error if generation failed: {code, message, details}';
COMMENT ON COLUMN "SignedContract"."validationErrors" IS 'JSONB array of validation errors from Zigned API';
COMMENT ON COLUMN "SignedContract"."emailDeliveryError" IS 'Error message if email delivery failed';
```

**Why JSONB:** Errors from Zigned API contain structured data (error code, message, details). JSONB allows querying specific error types in admin dashboard.

**Action Items**:
- [ ] Create migration file
- [ ] Run migration in development: `npx prisma migrate dev --name add_contract_lifecycle_tracking`
- [ ] Run migration in production: `npx prisma migrate deploy`
- [ ] Verify schema with `psql` inspection

---

### 2.2 Add Participant Tracking Table

**New Migration**: `20251111_add_contract_participants.sql`

**Goal**: Track individual participant (signer) state separately from contract

**Why**:
- Future handbook feature may involve multi-tenant agreements (3-4 signers per contract)
- Remove hardcoded personnummer checks for landlord identification
- Per-participant email/identity tracking (whose email bounced? whose BankID failed?)

**Migration Strategy (Gradual)**:
- Phase 2: Add ContractParticipant table, keep existing landlord/tenant fields
- Phase 3: Webhook writes to BOTH participant table AND old fields (backwards compat)
- Phase 7: Admin dashboard fully migrated to participant table, deprecate old fields

**Schema**:
```sql
-- Track individual participants in signing workflow
CREATE TABLE "ContractParticipant" (
  "id" TEXT NOT NULL,
  "contractId" TEXT NOT NULL,
  "participantId" TEXT NOT NULL,  -- Zigned participant ID
  "name" TEXT NOT NULL,
  "email" TEXT NOT NULL,
  "personalNumber" TEXT NOT NULL,
  "role" TEXT NOT NULL DEFAULT 'signer',
  "status" TEXT NOT NULL DEFAULT 'pending',
  "signingUrl" TEXT,
  "signedAt" TIMESTAMP(3),
  "emailDelivered" BOOLEAN NOT NULL DEFAULT false,
  "emailDeliveredAt" TIMESTAMP(3),
  "emailDeliveryFailed" BOOLEAN NOT NULL DEFAULT false,
  "emailDeliveryError" TEXT,
  "identityEnforcementPassed" BOOLEAN,
  "identityEnforcementFailedAt" TIMESTAMP(3),
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMP(3) NOT NULL,

  CONSTRAINT "ContractParticipant_pkey" PRIMARY KEY ("id")
);

-- Unique constraint: one participant record per Zigned participant
CREATE UNIQUE INDEX "ContractParticipant_participantId_key" ON "ContractParticipant"("participantId");

-- Foreign key to contract
CREATE INDEX "ContractParticipant_contractId_idx" ON "ContractParticipant"("contractId");
ALTER TABLE "ContractParticipant" ADD CONSTRAINT "ContractParticipant_contractId_fkey"
  FOREIGN KEY ("contractId") REFERENCES "SignedContract"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- Query optimization indices
CREATE INDEX "ContractParticipant_personalNumber_idx" ON "ContractParticipant"("personalNumber");
CREATE INDEX "ContractParticipant_status_idx" ON "ContractParticipant"("status");

-- Check constraints
ALTER TABLE "ContractParticipant"
  ADD CONSTRAINT "ContractParticipant_status_check"
    CHECK ("status" IN ('pending', 'invited', 'viewed', 'signing', 'fulfilled', 'rejected'));

-- Comments
COMMENT ON TABLE "ContractParticipant" IS 'Individual signers in contract workflow (landlord, tenant, observers)';
COMMENT ON COLUMN "ContractParticipant"."participantId" IS 'Zigned participant ID from API';
COMMENT ON COLUMN "ContractParticipant"."personalNumber" IS 'Swedish personnummer for BankID validation';
COMMENT ON COLUMN "ContractParticipant"."status" IS 'Participant signing status from Zigned events';
```

**Action Items**:
- [ ] Create migration file
- [ ] Run migration in development
- [ ] Create `ContractParticipant` domain model in `lib/models/`
- [ ] Create `ContractParticipantRepository` in `lib/repositories/`
- [ ] Update `Persistence` module to expose participant repository

---

### 2.3 Update SignedContract Model

**File**: `lib/models/signed_contract.rb`

**New Fields**:
```ruby
attr_reader :id, :tenant_id, :case_id, :pdf_url, :status,
            :landlord_signed, :tenant_signed,
            :landlord_signed_at, :tenant_signed_at,
            :landlord_signing_url, :tenant_signing_url,
            :test_mode,
            :completed_at, :expires_at,
            :created_at, :updated_at,
            # NEW LIFECYCLE FIELDS
            :generation_status, :generation_started_at, :generation_completed_at,
            :generation_failed_at, :generation_error,
            :validation_status, :validation_started_at, :validation_completed_at,
            :validation_failed_at, :validation_errors,
            :email_delivery_status, :landlord_email_delivered, :tenant_email_delivered,
            :email_delivery_failed_at, :email_delivery_error

# Query methods
def generation_failed?
  generation_status == 'failed'
end

def validation_failed?
  validation_status == 'failed'
end

def emails_delivered?
  landlord_email_delivered && tenant_email_delivered
end

def ready_for_signing?
  generation_status == 'completed' &&
  validation_status == 'completed' &&
  email_delivery_status == 'delivered'
end
```

**Action Items**:
- [ ] Update `SignedContract` model with new fields
- [ ] Update `SignedContractRepository` hydrate/dehydrate methods
- [ ] Add query methods for lifecycle states
- [ ] Update validation logic in model

---

## Phase 3: Webhook Event Handlers (Day 2-3)

**Real-Time Updates:** ALL handlers include WebSocket broadcasts for live admin dashboard visibility. Admin sees contracts being signed, emails delivering, errors appearing - all in real-time.

### 3.1 Agreement Lifecycle Events

**Events to Handle**:
1. `agreement.lifecycle.pending` - Agreement activated
2. `agreement.lifecycle.fulfilled` - All signatures complete
3. `agreement.lifecycle.finalized` - Signed PDF ready
4. `agreement.lifecycle.expired` - Agreement expired
5. `agreement.lifecycle.cancelled` - Agreement cancelled
6. `agreement.lifecycle.opened` - Agreement opened (not sure when this fires)

**Handler Implementation**:

**File**: `handlers/zigned_webhook_handler.rb`

```ruby
# Handle agreement.lifecycle.pending (replaces case.created)
def handle_agreement_pending(data)
  agreement_id = data['id']
  title = data['title']
  test_mode = data['test_mode']
  expires_at = data['expires_at']
  participants = data['participants'] || []

  puts "📝 Agreement activated: #{agreement_id} - #{title}"
  puts "   Test mode: #{test_mode}"
  puts "   Participants: #{participants.length}"
  puts "   Expires: #{expires_at}"

  # Find contract by case_id (agreement_id in v3)
  contract = @repository.find_by_case_id(agreement_id)
  unless contract
    puts "⚠️  Warning: SignedContract record not found for agreement #{agreement_id}"
    return
  end

  # Update contract status
  contract.status = 'awaiting_signatures'
  @repository.update(contract)

  # Create participant records (if not already created)
  participants.each do |participant_data|
    create_or_update_participant(contract.id, participant_data)
  end

  # Broadcast event
  @broadcaster&.broadcast_data('contract_status', {
    case_id: agreement_id,
    event: 'pending',
    title: title,
    test_mode: test_mode,
    expires_at: expires_at,
    participant_count: participants.length,
    timestamp: Time.now.to_i
  })
end

# Handle agreement.lifecycle.fulfilled (replaces case.completed)
def handle_agreement_fulfilled(data)
  agreement_id = data['id']
  title = data['title']
  fulfilled_at = data['fulfilled_at']
  participants = data['participants'] || []

  puts "🎉 Contract fully signed: #{agreement_id} - #{title}"
  puts "   Fulfilled at: #{fulfilled_at}"

  contract = @repository.find_by_case_id(agreement_id)
  unless contract
    puts "⚠️  Warning: SignedContract record not found for agreement #{agreement_id}"
    return
  end

  # Update all participant records
  participants.each do |participant_data|
    update_participant_fulfillment(participant_data)
  end

  # Update contract status
  contract.status = 'fulfilled'  # Not 'completed' yet - waiting for finalized event
  contract.landlord_signed = true
  contract.tenant_signed = true
  @repository.update(contract)

  # Broadcast event
  @broadcaster&.broadcast_data('contract_status', {
    case_id: agreement_id,
    event: 'fulfilled',
    title: title,
    timestamp: Time.now.to_i
  })
end

# Handle agreement.lifecycle.finalized (NEW - triggers PDF download)
def handle_agreement_finalized(data)
  agreement_id = data['id']
  title = data['title']
  signed_document_url = data['signed_document_url']
  finalized_at = data['finalized_at']

  puts "📥 Contract finalized: #{agreement_id}"
  puts "   Signed PDF URL: #{signed_document_url}"

  contract = @repository.find_by_case_id(agreement_id)
  unless contract
    puts "⚠️  Warning: SignedContract record not found for agreement #{agreement_id}"
    return
  end

  # Auto-download signed PDF
  begin
    tenant = Persistence.tenants.find_by_id(contract.tenant_id)
    if tenant
      signer = ContractSigner.new(test_mode: contract.test_mode)
      signed_path = signer.download_signed_contract(agreement_id, tenant.name)

      # Update contract with signed PDF URL
      contract.pdf_url = signed_path
      contract.status = 'completed'  # NOW it's truly complete
      contract.completed_at = Time.parse(finalized_at) if finalized_at
      puts "✅ Signed PDF downloaded: #{signed_path}"
    end
  rescue => e
    puts "⚠️  Failed to auto-download signed PDF: #{e.message}"
    puts e.backtrace.join("\n")
  end

  @repository.update(contract)

  # Broadcast completion event
  @broadcaster&.broadcast_data('contract_status', {
    case_id: agreement_id,
    event: 'completed',
    title: title,
    signed_pdf_path: contract.pdf_url,
    timestamp: Time.now.to_i
  })
end

# Handle agreement.lifecycle.expired (minimal change)
def handle_agreement_expired(data)
  agreement_id = data['id']
  title = data['title']
  expired_at = data['expired_at']

  puts "⏰ Agreement expired: #{agreement_id} - #{title}"
  puts "   Expired at: #{expired_at}"

  contract = @repository.find_by_case_id(agreement_id)
  if contract
    contract.status = 'expired'
    @repository.update(contract)
  else
    puts "⚠️  Warning: SignedContract record not found for agreement #{agreement_id}"
  end

  @broadcaster&.broadcast_data('contract_status', {
    case_id: agreement_id,
    event: 'expired',
    title: title,
    expired_at: expired_at,
    timestamp: Time.now.to_i
  })
end

# Handle agreement.lifecycle.cancelled (minimal change)
def handle_agreement_cancelled(data)
  agreement_id = data['id']
  title = data['title']
  cancellation_reason = data['cancellation_reason']
  cancelled_at = data['cancelled_at']

  puts "🚫 Agreement cancelled: #{agreement_id} - #{title}"
  puts "   Reason: #{cancellation_reason}" if cancellation_reason
  puts "   Cancelled at: #{cancelled_at}"

  contract = @repository.find_by_case_id(agreement_id)
  if contract
    contract.status = 'cancelled'
    @repository.update(contract)
  else
    puts "⚠️  Warning: SignedContract record not found for agreement #{agreement_id}"
  end

  @broadcaster&.broadcast_data('contract_status', {
    case_id: agreement_id,
    event: 'cancelled',
    title: title,
    cancellation_reason: cancellation_reason,
    timestamp: Time.now.to_i
  })
end
```

**Action Items**:
- [ ] Implement all 6 lifecycle event handlers
- [ ] Update case statement to route to new handlers
- [ ] Add participant creation/update helper methods
- [ ] Test with existing agreement `cmhuoppfb09arliy430o6lv4q`

---

### 3.2 Participant Lifecycle Events

**Events to Handle**:
1. `participant.lifecycle.fulfilled` - Individual signer completed
2. `participant.lifecycle.received_invitation` - Email delivered to signer
3. `participant.lifecycle.forwarded` - Signing link forwarded

**Handler Implementation**:

```ruby
# Handle participant.lifecycle.fulfilled (replaces case.signed)
def handle_participant_fulfilled(data)
  participant_data = data['participant']
  agreement_id = data['agreement_id']

  participant_id = participant_data['id']
  name = participant_data['name']
  personal_number = participant_data['personal_number']
  signed_at = participant_data['signed_at']

  puts "✍️  Signature received: #{name} (#{personal_number}) signed"
  puts "   Participant ID: #{participant_id}"
  puts "   Signed at: #{signed_at}"

  # Update participant record
  participant_repo = Persistence.contract_participants
  participant = participant_repo.find_by_participant_id(participant_id)

  if participant
    participant.status = 'fulfilled'
    participant.signed_at = Time.parse(signed_at) if signed_at
    participant_repo.update(participant)
  else
    puts "⚠️  Warning: Participant record not found: #{participant_id}"
  end

  # Update contract record (legacy fields for backward compatibility)
  contract = @repository.find_by_case_id(agreement_id)
  if contract
    is_landlord = personal_number == '8604230717'  # TODO: Get from participant role

    if is_landlord
      contract.landlord_signed = true
      contract.landlord_signed_at = Time.parse(signed_at) if signed_at
    else
      contract.tenant_signed = true
      contract.tenant_signed_at = Time.parse(signed_at) if signed_at
    end

    @repository.update(contract)
  end

  # Broadcast event
  @broadcaster&.broadcast_data('contract_status', {
    case_id: agreement_id,
    event: 'participant_signed',
    participant_name: name,
    participant_id: participant_id,
    timestamp: Time.now.to_i
  })
end

# Handle participant.lifecycle.received_invitation
def handle_participant_invitation_received(data)
  participant_data = data['participant']
  agreement_id = data['agreement_id']

  participant_id = participant_data['id']
  name = participant_data['name']
  email = participant_data['email']

  puts "📧 Invitation received: #{name} <#{email}>"
  puts "   Participant ID: #{participant_id}"

  # Update participant record
  participant_repo = Persistence.contract_participants
  participant = participant_repo.find_by_participant_id(participant_id)

  if participant
    participant.status = 'invited'
    participant.email_delivered = true
    participant.email_delivered_at = Time.now
    participant_repo.update(participant)
  else
    puts "⚠️  Warning: Participant record not found: #{participant_id}"
  end

  # Broadcast event
  @broadcaster&.broadcast_data('contract_status', {
    case_id: agreement_id,
    event: 'invitation_delivered',
    participant_name: name,
    participant_id: participant_id,
    timestamp: Time.now.to_i
  })
end
```

**Action Items**:
- [ ] Implement participant event handlers
- [ ] Create `ContractParticipantRepository` with required query methods
- [ ] Add to webhook case statement
- [ ] Test participant-specific events

---

### 3.3 Generation & Validation Events

**Events to Handle**:
1. `agreement.generation.started` - PDF generation began
2. `agreement.generation.completed` - PDF generation succeeded
3. `agreement.generation.failed` - PDF generation failed
4. `agreement.validation.started` - Document validation began
5. `agreement.validation.completed` - Document validation succeeded
6. `agreement.validation.failed` - Document validation failed

**Handler Implementation**:

```ruby
# Handle agreement.generation.started
def handle_generation_started(data)
  agreement_id = data['id']
  started_at = data['started_at']

  puts "🔨 PDF generation started: #{agreement_id}"

  contract = @repository.find_by_case_id(agreement_id)
  if contract
    contract.generation_status = 'started'
    contract.generation_started_at = Time.parse(started_at) if started_at
    @repository.update(contract)
  end
end

# Handle agreement.generation.completed
def handle_generation_completed(data)
  agreement_id = data['id']
  completed_at = data['completed_at']

  puts "✅ PDF generation completed: #{agreement_id}"

  contract = @repository.find_by_case_id(agreement_id)
  if contract
    contract.generation_status = 'completed'
    contract.generation_completed_at = Time.parse(completed_at) if completed_at
    @repository.update(contract)
  end
end

# Handle agreement.generation.failed ⚠️ CRITICAL ERROR PATH
def handle_generation_failed(data)
  agreement_id = data['id']
  failed_at = data['failed_at']
  error_message = data['error']
  error_code = data['error_code']

  puts "❌ PDF generation FAILED: #{agreement_id}"
  puts "   Error: #{error_message}"
  puts "   Code: #{error_code}"
  puts "   Time: #{failed_at}"

  contract = @repository.find_by_case_id(agreement_id)
  if contract
    contract.generation_status = 'failed'
    contract.generation_failed_at = Time.parse(failed_at) if failed_at
    contract.generation_error = "#{error_code}: #{error_message}"
    @repository.update(contract)
  end

  # Broadcast critical error event
  @broadcaster&.broadcast_data('contract_error', {
    case_id: agreement_id,
    event: 'generation_failed',
    error: error_message,
    error_code: error_code,
    timestamp: Time.now.to_i
  })

  # TODO: Send alert to admin (email/SMS)
  # alert_admin("Contract PDF generation failed: #{agreement_id}", error_message)
end

# Handle agreement.validation.failed ⚠️ CRITICAL ERROR PATH
def handle_validation_failed(data)
  agreement_id = data['id']
  failed_at = data['failed_at']
  errors = data['errors'] || []

  puts "❌ Document validation FAILED: #{agreement_id}"
  puts "   Errors: #{errors.join(', ')}"

  contract = @repository.find_by_case_id(agreement_id)
  if contract
    contract.validation_status = 'failed'
    contract.validation_failed_at = Time.parse(failed_at) if failed_at
    contract.validation_errors = errors.to_json
    @repository.update(contract)
  end

  # Broadcast critical error event
  @broadcaster&.broadcast_data('contract_error', {
    case_id: agreement_id,
    event: 'validation_failed',
    errors: errors,
    timestamp: Time.now.to_i
  })

  # TODO: Send alert to admin
end
```

**Action Items**:
- [ ] Implement all 6 generation/validation handlers
- [ ] Add error broadcasting for critical failures
- [ ] Add TODO markers for admin alerting (future phase)
- [ ] Test generation failure scenario (manual trigger needed)

---

### 3.4 Email Delivery Events

**Events to Handle**:
1. `email_event.agreement_invitation.delivered` - Email successfully delivered
2. `email_event.agreement_invitation.delivery_failed` - Email bounce/failure
3. `email_event.agreement_invitation.all_delivered` - All emails delivered

**Handler Implementation**:

```ruby
# Handle email_event.agreement_invitation.delivered
def handle_email_delivered(data)
  agreement_id = data['agreement_id']
  recipient_email = data['recipient']['email']
  recipient_name = data['recipient']['name']
  delivered_at = data['delivered_at']

  puts "📧 Email delivered: #{recipient_name} <#{recipient_email}>"

  contract = @repository.find_by_case_id(agreement_id)
  if contract
    # Determine if landlord or tenant (use participant lookup in future)
    is_landlord = recipient_email == 'branstrom@gmail.com'  # TODO: Proper lookup

    if is_landlord
      contract.landlord_email_delivered = true
    else
      contract.tenant_email_delivered = true
    end

    # Update overall status if both delivered
    if contract.landlord_email_delivered && contract.tenant_email_delivered
      contract.email_delivery_status = 'delivered'
    end

    @repository.update(contract)
  end

  # Broadcast event
  @broadcaster&.broadcast_data('contract_status', {
    case_id: agreement_id,
    event: 'email_delivered',
    recipient: recipient_name,
    timestamp: Time.now.to_i
  })
end

# Handle email_event.agreement_invitation.delivery_failed ⚠️ CRITICAL
def handle_email_delivery_failed(data)
  agreement_id = data['agreement_id']
  recipient_email = data['recipient']['email']
  recipient_name = data['recipient']['name']
  error_message = data['error']
  failed_at = data['failed_at']

  puts "❌ Email delivery FAILED: #{recipient_name} <#{recipient_email}>"
  puts "   Error: #{error_message}"

  contract = @repository.find_by_case_id(agreement_id)
  if contract
    contract.email_delivery_status = 'failed'
    contract.email_delivery_failed_at = Time.parse(failed_at) if failed_at
    contract.email_delivery_error = "#{recipient_email}: #{error_message}"
    @repository.update(contract)
  end

  # Broadcast critical error
  @broadcaster&.broadcast_data('contract_error', {
    case_id: agreement_id,
    event: 'email_delivery_failed',
    recipient: recipient_name,
    recipient_email: recipient_email,
    error: error_message,
    timestamp: Time.now.to_i
  })

  # TODO: Alert landlord to provide alternative signing method
  # alert_landlord("Email bounced for #{recipient_name}", signing_link)
end
```

**Action Items**:
- [ ] Implement email event handlers
- [ ] Add email delivery status tracking
- [ ] Add error handling for bounced emails
- [ ] Plan manual signing link delivery workflow (future)

---

## Phase 4: Helper Methods & Utilities (Day 3)

### 4.1 Participant Management Helpers

**File**: `handlers/zigned_webhook_handler.rb`

```ruby
private

# Create or update participant record from Zigned data
def create_or_update_participant(contract_id, participant_data)
  participant_repo = Persistence.contract_participants

  participant_id = participant_data['id']
  existing = participant_repo.find_by_participant_id(participant_id)

  participant_attrs = {
    contract_id: contract_id,
    participant_id: participant_id,
    name: participant_data['name'],
    email: participant_data['email'],
    personal_number: participant_data['personal_number'],
    role: participant_data['role'] || 'signer',
    status: participant_data['status'] || 'pending',
    signing_url: participant_data['signing_url']
  }

  if existing
    # Update existing participant
    participant_attrs.each { |k, v| existing.send("#{k}=", v) if existing.respond_to?("#{k}=") }
    participant_repo.update(existing)
  else
    # Create new participant
    participant = ContractParticipant.new(**participant_attrs)
    participant_repo.save(participant)
  end
end

# Update participant fulfillment from event data
def update_participant_fulfillment(participant_data)
  participant_repo = Persistence.contract_participants

  participant_id = participant_data['id']
  participant = participant_repo.find_by_participant_id(participant_id)

  if participant
    participant.status = 'fulfilled'
    participant.signed_at = Time.parse(participant_data['signed_at']) if participant_data['signed_at']
    participant_repo.update(participant)
  else
    puts "⚠️  Warning: Participant not found: #{participant_id}"
  end
end

# Determine if participant is landlord (for legacy fields)
def is_landlord?(participant_data)
  personal_number = participant_data['personal_number']
  personal_number == '8604230717'  # TODO: Get from config or role
end
```

**Action Items**:
- [ ] Implement participant helper methods
- [ ] Replace hardcoded landlord check with role-based logic
- [ ] Add error handling for missing participant data

---

### 4.2 Event Routing Update

**File**: `handlers/zigned_webhook_handler.rb`

**Updated Case Statement**:
```ruby
def handle(request)
  # ... signature verification ...

  payload = JSON.parse(body)
  event_type = payload['event_type']  # NOT payload['event']
  event_data = payload['data']

  # Route to handler
  case event_type
  # Agreement lifecycle
  when 'agreement.lifecycle.pending'
    handle_agreement_pending(event_data)
  when 'agreement.lifecycle.fulfilled'
    handle_agreement_fulfilled(event_data)
  when 'agreement.lifecycle.finalized'
    handle_agreement_finalized(event_data)
  when 'agreement.lifecycle.expired'
    handle_agreement_expired(event_data)
  when 'agreement.lifecycle.cancelled'
    handle_agreement_cancelled(event_data)
  when 'agreement.lifecycle.opened'
    handle_agreement_opened(event_data)

  # Participant lifecycle
  when 'participant.lifecycle.fulfilled'
    handle_participant_fulfilled(event_data)
  when 'participant.lifecycle.received_invitation'
    handle_participant_invitation_received(event_data)
  when 'participant.lifecycle.forwarded'
    handle_participant_forwarded(event_data)

  # Generation & validation
  when 'agreement.generation.started'
    handle_generation_started(event_data)
  when 'agreement.generation.completed'
    handle_generation_completed(event_data)
  when 'agreement.generation.failed'
    handle_generation_failed(event_data)
  when 'agreement.validation.started'
    handle_validation_started(event_data)
  when 'agreement.validation.completed'
    handle_validation_completed(event_data)
  when 'agreement.validation.failed'
    handle_validation_failed(event_data)

  # Email delivery
  when 'email_event.agreement_invitation.delivered'
    handle_email_delivered(event_data)
  when 'email_event.agreement_invitation.delivery_failed'
    handle_email_delivery_failed(event_data)
  when 'email_event.agreement_invitation.all_delivered'
    handle_all_emails_delivered(event_data)

  else
    puts "⚠️  Unknown event type: #{event_type}"
    return { status: 400, message: "Unknown event type: #{event_type}", error: true }
  end

  { status: 200, message: 'Webhook processed successfully', event: event_type }
end
```

**Action Items**:
- [ ] Update case statement with all 15 event types
- [ ] Change `payload['event']` to `payload['event_type']`
- [ ] Add default case for unknown events (log but don't error)
- [ ] Add structured logging for each event type

---

## Phase 5: Testing & Verification (Day 4)

### 5.1 Test Existing Agreement

**Existing Test Agreement**: `cmhuoppfb09arliy430o6lv4q`
- Created: November 11, 2025
- Status: Pending (never processed due to wrong event names)
- Tenant: Fredrik Bränström (test mode)
- Landlord: Fredrik Bränström (test mode)

**Test Plan**:
1. Check current database state
2. Manually trigger webhook events (if possible via Zigned dashboard)
3. Monitor webhook logs for correct event processing
4. Verify database updates
5. Check WebSocket broadcasts to dashboard

**Commands**:
```bash
# Check current contract state
ruby -e "require 'dotenv/load'; require_relative 'lib/persistence'; contract = Persistence.signed_contracts.find_by_case_id('cmhuoppfb09arliy430o6lv4q'); puts contract.inspect"

# Monitor webhook logs
tail -f /var/log/kimonokittens/webhook.log | grep "agreement.lifecycle"

# Check participant records
ruby -e "require 'dotenv/load'; require_relative 'lib/persistence'; participants = Persistence.contract_participants.find_by_contract_id('cmhuoppfb09arliy430o6lv4q'); participants.each { |p| puts p.inspect }"
```

**Action Items**:
- [ ] Document current contract state
- [ ] Trigger test webhook events (Zigned dashboard or curl)
- [ ] Verify all event handlers process correctly
- [ ] Check database field updates
- [ ] Verify WebSocket broadcasts reach dashboard

---

### 5.2 Integration Tests

**New Spec File**: `spec/zigned_webhook_handler_spec.rb`

**Test Coverage**:
```ruby
require 'rspec'
require 'rack/test'
require_relative '../handlers/zigned_webhook_handler'

RSpec.describe ZignedWebhookHandler do
  include Rack::Test::Methods

  let(:webhook_secret) { 'test_secret_key' }
  let(:handler) { ZignedWebhookHandler.new(webhook_secret: webhook_secret) }

  describe '#handle' do
    context 'agreement.lifecycle.pending event' do
      it 'updates contract to awaiting_signatures status' do
        # Test implementation
      end

      it 'creates participant records' do
        # Test implementation
      end

      it 'broadcasts pending event via WebSocket' do
        # Test implementation
      end
    end

    context 'participant.lifecycle.fulfilled event' do
      it 'updates participant signed_at timestamp' do
        # Test implementation
      end

      it 'updates contract landlord_signed flag' do
        # Test implementation
      end
    end

    context 'agreement.generation.failed event' do
      it 'marks generation status as failed' do
        # Test implementation
      end

      it 'stores error message' do
        # Test implementation
      end

      it 'broadcasts error event' do
        # Test implementation
      end
    end

    context 'email_event.agreement_invitation.delivery_failed' do
      it 'marks email delivery as failed' do
        # Test implementation
      end

      it 'stores bounce error message' do
        # Test implementation
      end
    end

    context 'signature verification' do
      it 'rejects requests with invalid signature' do
        # Test implementation
      end

      it 'rejects requests with missing signature' do
        # Test implementation
      end

      it 'raises error if webhook secret not configured' do
        # Test implementation
      end
    end

    context 'payload structure' do
      it 'parses event_type from payload' do
        # Test implementation
      end

      it 'handles v3 participant array structure' do
        # Test implementation
      end
    end
  end
end
```

**Action Items**:
- [ ] Create comprehensive test suite
- [ ] Test all 15 event types
- [ ] Test security (signature verification, fail-closed)
- [ ] Test error paths (generation failed, email bounced)
- [ ] Test database mutations
- [ ] Test WebSocket broadcasts

---

### 5.3 Production Verification Checklist

**Pre-Deployment**:
- [ ] All migrations run in development
- [ ] All tests passing
- [ ] Webhook secret configured in production `.env`
- [ ] Zigned webhook endpoint updated (if URL changed)

**Post-Deployment**:
- [ ] Backend service restarted successfully
- [ ] Database migrations applied in production
- [ ] Webhook endpoint returns 200 OK for test payload
- [ ] Webhook logs show correct event processing
- [ ] Dashboard receives WebSocket broadcasts
- [ ] Contract status updates visible in database

**Smoke Test**:
```bash
# Send test webhook payload
curl -X POST http://localhost:49123/api/webhooks/zigned \
  -H "Content-Type: application/json" \
  -H "x-zigned-request-signature: <computed_signature>" \
  -d '{
    "version": "1.0",
    "resource_type": "agreement",
    "event_type": "agreement.lifecycle.pending",
    "data": {
      "id": "test_agreement_id",
      "title": "Test Agreement",
      "test_mode": true,
      "participants": []
    }
  }'
```

---

## Phase 6: Dashboard Admin View (FUTURE - Day 5+)

**Status**: 🔮 PLANNED (After webhook implementation complete)

### 6.1 Admin Dashboard Requirements

**Goal**: Separate admin view in existing dashboard for contract management

**Features Needed**:
1. **Contract Status Overview**
   - List all contracts (pending, signed, completed, expired, failed)
   - Filter by status, tenant, date range
   - Search by agreement ID, tenant name

2. **Contract Details View**
   - Full contract lifecycle timeline
   - Participant signing status
   - Generation/validation status
   - Email delivery status
   - Error messages if any

3. **Action Buttons**
   - Resend signing link (if email bounced)
   - Cancel contract
   - Download signed PDF
   - View contract in browser
   - Manually mark as completed (edge cases)

4. **Keyboard Navigation**
   - Press key to switch between public dashboard and admin view
   - Arrow keys to navigate contract list
   - Enter to view details
   - ESC to return to list

**UI Mockup**:
```
┌─────────────────────────────────────────────────────────────┐
│ ADMIN VIEW (Press K to return to dashboard)                 │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│ Contracts (8 total)                                          │
│                                                              │
│ ✅ Fredrik Brännström  │ 2025-11-11 │ Completed  │ Test     │
│ ⏳ Sanna Benemar       │ 2025-11-10 │ Pending    │ Prod     │
│ ❌ Adam Nilsson        │ 2025-11-09 │ Gen Failed │ Prod     │
│ ⏰ Rasmus Andersson    │ 2025-11-08 │ Expired    │ Prod     │
│                                                              │
│ [F]ilter  [S]earch  [R]efresh  [Details: Enter]             │
└─────────────────────────────────────────────────────────────┘
```

### 6.2 Implementation Tasks

**Component Structure**:
```
dashboard/src/
├── views/
│   ├── PublicDashboard.tsx  (current dashboard widgets)
│   └── AdminDashboard.tsx   (new admin view)
├── components/
│   └── admin/
│       ├── ContractList.tsx
│       ├── ContractDetails.tsx
│       ├── ContractTimeline.tsx
│       └── ContractActions.tsx
└── hooks/
    └── useKeyboardNav.tsx  (keyboard shortcut handler)
```

**API Endpoints Needed**:
```ruby
# Backend handlers
GET  /api/admin/contracts                 # List all contracts
GET  /api/admin/contracts/:id             # Contract details
POST /api/admin/contracts/:id/resend      # Resend signing link
POST /api/admin/contracts/:id/cancel      # Cancel contract
GET  /api/admin/contracts/:id/pdf         # Download PDF
```

**Action Items**:
- [ ] Design admin dashboard UI
- [ ] Implement keyboard navigation (global listener)
- [ ] Create admin API endpoints
- [ ] Build contract list component
- [ ] Build contract details component
- [ ] Add contract timeline visualization
- [ ] Implement action buttons
- [ ] Add authentication (HTTP Basic Auth for v1)

---

## Phase 7: Advanced Features (FUTURE)

### 7.1 Sign Event Tracking (Analytics)

**Available Events** (currently ignored):
- `sign_event.signing_room.entered` - Tenant viewed contract
- `sign_event.document.scrolled_to_bottom` - Tenant read entire contract
- `sign_event.sign.initiated_sign` - Tenant started BankID flow
- `sign_event.sign.completed_sign` - Tenant completed signing

**Use Cases**:
- Track engagement metrics (time to sign, read completion)
- Alert if tenant viewed but didn't sign (follow-up needed)
- Measure signing friction (how many attempts, errors)

**Implementation**: Low priority - track in separate analytics table

---

### 7.2 Admin Alerting System

**Scenarios Requiring Alerts**:
1. Generation failed → Email landlord + link to retry
2. Email bounced → SMS with manual signing link
3. Contract expiring soon → Reminder to both parties
4. Validation failed → Alert + manual review

**Implementation Options**:
- Email via Ruby `mail` gem
- SMS via Twilio API
- Dashboard notification (WebSocket)

**Action Items** (future):
- [ ] Choose alerting channels
- [ ] Implement alert dispatcher service
- [ ] Add alert preferences to admin settings
- [ ] Build alert history view

---

### 7.3 Retry & Recovery Logic

**Scenarios**:
1. Generation failed → Auto-retry 3x with exponential backoff
2. Email bounced → Try alternative email (if available)
3. Temporary Zigned API error → Queue for retry

**Implementation**: Background job system (Sidekiq or similar)

**Action Items** (future):
- [ ] Evaluate background job libraries
- [ ] Implement retry queue
- [ ] Add admin UI for manual retry
- [ ] Add circuit breaker for Zigned API

---

## Success Metrics

**Phase 1-3 Complete When**:
✅ Existing agreement `cmhuoppfb09arliy430o6lv4q` processes correctly
✅ All 15 critical events route to correct handlers
✅ Database updates for lifecycle events
✅ WebSocket broadcasts reach dashboard
✅ No errors in webhook logs
✅ Test suite passing (>80% coverage)

**Phase 4-5 Complete When**:
✅ New contracts generate and track correctly end-to-end
✅ Generation/validation failures caught and logged
✅ Email bounces detected and alerted
✅ Production deployment successful
✅ Manual testing on real tenant contract

**Phase 6-7 Complete When**:
✅ Admin dashboard functional with keyboard nav
✅ Landlord can manage contracts without CLI
✅ Alerts firing for critical errors
✅ Retry logic handling transient failures

---

## OpenAPI Spec Reference

**Critical Sections**:
- Lines 19067-19144: Webhook subscription event types (full list)
- Lines 19019-19021: Webhook signature header name (`x-zigned-request-signature`)
- Section: Webhook notification payload structure (TBD - need to find in spec)

**Action**: Reference spec frequently during implementation for exact field names

---

## Risk Mitigation

### High-Risk Changes
1. **Database migrations** - Test thoroughly in development first
2. **Event name changes** - Could break existing webhook subscriptions (verify in Zigned dashboard)
3. **Signature verification** - Wrong header name = all webhooks rejected

### Rollback Plan
1. Keep old event handlers commented out (not deleted) for 1 month
2. Database migrations reversible (add `DOWN` migrations)
3. Feature flag for new lifecycle tracking (if needed)

### Monitoring
1. Webhook error rate alert (>5% failure = investigate)
2. Contract stuck in pending alert (>24h without progress)
3. Generation failure alert (immediate notification)

---

## Timeline Estimate

**Phase 1** (Critical Fixes): 4-6 hours
**Phase 2** (Database Schema): 2-3 hours
**Phase 3** (Event Handlers): 6-8 hours
**Phase 4** (Helpers & Utils): 2-3 hours
**Phase 5** (Testing): 4-6 hours
**Phase 6** (Admin Dashboard): 12-16 hours (FUTURE)
**Phase 7** (Advanced Features): 8-12 hours (FUTURE)

**Total (Phases 1-5)**: ~20-26 hours (3-4 days)
**Total (All Phases)**: ~40-50 hours (5-7 days)

---

## Next Steps

1. Review this plan with user for approval
2. Create feature branch: `git checkout -b feature/zigned-v3-webhook-migration`
3. Start with Phase 1 (critical fixes)
4. Test incrementally after each phase
5. Deploy to production after Phase 5 complete
6. Plan Phase 6 (admin dashboard) separately

---

**Document Version:** 1.0
**Last Updated:** November 11, 2025
**Author:** Claude Code (Linux Agent)
**Review Status:** Pending User Approval

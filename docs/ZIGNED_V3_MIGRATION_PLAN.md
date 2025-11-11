# Zigned API v1 → v3 Migration Plan

**Date**: November 11, 2025
**Status**: 🔴 IN PROGRESS
**Priority**: HIGH - Blocking contract signing (413 errors on v1)

---

## Executive Summary

Current implementation uses deprecated Zigned API v1 (`/cases` endpoint with inline base64) which fails with 413 Payload Too Large at 1.5MB PDFs. Migration to modern v3 API (`/agreements` + `/files` workflow) required for production contract signing.

---

## Problem Analysis

### Current State (Broken)
```ruby
# lib/zigned_client.rb:35
BASE_URL = 'https://api.zigned.se/v1'  # ❌ Deprecated, undocumented

# create_signing_case method (line 76)
POST /cases
Body: {
  document: {
    content: "<base64_string>",  # ❌ 2MB with overhead
    content_type: "application/pdf"
  }
}
```

**Issues:**
- 413 error at 1.5MB PDF (2MB with 33% base64 overhead)
- Unknown file size limit (probably 1-2MB)
- No documentation, probably deprecated
- No error context in responses

### Target State (Working)
```ruby
# New implementation
BASE_URL = 'https://api.zigned.se/rest/v3'  # ✅ Official, documented

# Multi-step workflow:
1. POST /files (multipart/form-data) → file_id
2. POST /agreements → agreement_id
3. POST /agreements/{id}/documents/main { file_id }
4. POST /agreements/{id}/participants/batch [signers]
5. POST /agreements/{id}/lifecycle/activate
```

**Benefits:**
- 15MB file limit (documented)
- No base64 overhead (raw PDF upload)
- Official support and documentation
- Better error messages

---

## Migration Strategy

### Phase 1: Implement v3 Client ✅
**Tasks:**
1. Create `lib/zigned_client_v3.rb` (new file, keep v1 for rollback)
2. Implement multipart file upload (`upload_file`)
3. Implement agreement creation workflow
4. Implement participant management
5. Implement agreement activation
6. Add comprehensive error handling

### Phase 2: Update ContractSigner 🔄
**Tasks:**
1. Update `lib/contract_signer.rb` to use v3 client
2. Update database saves (no breaking schema changes)
3. Preserve all existing functionality
4. Add logging for migration tracking

### Phase 3: Testing 📋
**Tasks:**
1. Test on Mac with test API key (dry run)
2. Commit changes
3. Push to Dell (webhook deployment)
4. Test on Dell with test API key
5. Test on Dell with production API key
6. End-to-end contract signing verification

### Phase 4: Cleanup 🧹
**Tasks:**
1. Remove `lib/zigned_client.rb` (old v1)
2. Update documentation
3. Update CLAUDE.md references

---

## Implementation Details

### New ZignedClientV3 API

```ruby
class ZignedClientV3
  BASE_URL = 'https://api.zigned.se/rest/v3'

  # Step 1: Upload PDF
  def upload_file(pdf_path, lookup_key: nil)
    # POST /files with multipart/form-data
    # Returns: { file_id:, filename:, mime_type:, size: }
  end

  # Step 2: Create agreement
  def create_agreement(title:, test_mode: false, webhook_url: nil)
    # POST /agreements
    # Returns: { agreement_id:, status: 'draft' }
  end

  # Step 3: Attach document
  def attach_main_document(agreement_id, file_id)
    # POST /agreements/{id}/documents/main
  end

  # Step 4: Add participants (batch)
  def add_participants(agreement_id, signers:)
    # POST /agreements/{id}/participants/batch
    # Returns: { participants: [{ id:, signing_url:, ... }] }
  end

  # Step 5: Activate agreement
  def activate_agreement(agreement_id, send_emails: true)
    # POST /agreements/{id}/lifecycle/activate
    # Returns: { status: 'pending', expires_at: }
  end

  # High-level wrapper (replaces create_signing_case)
  def create_and_activate(pdf_path:, signers:, title:, webhook_url: nil, send_emails: true)
    file = upload_file(pdf_path)
    agreement = create_agreement(title: title, webhook_url: webhook_url)
    attach_main_document(agreement[:agreement_id], file[:file_id])
    participants = add_participants(agreement[:agreement_id], signers: signers)
    activate_agreement(agreement[:agreement_id], send_emails: send_emails)

    # Return format compatible with v1 (minimal changes to ContractSigner)
    {
      case_id: agreement[:agreement_id],  # Keep 'case_id' key for compatibility
      signing_links: extract_signing_links(participants),
      expires_at: agreement[:expires_at],
      status: agreement[:status]
    }
  end
end
```

### ContractSigner Changes

**Minimal changes required:**
```ruby
# lib/contract_signer.rb

# Before:
signer = ZignedClient.new(api_key: ENV['ZIGNED_API_KEY'], test_mode: test_mode)
zigned_result = signer.create_signing_case(...)

# After:
signer = ZignedClientV3.new(api_key: ENV['ZIGNED_API_KEY'], test_mode: test_mode)
zigned_result = signer.create_and_activate(...)  # Same return format
```

**Database schema:** No changes needed - v3 returns same data structure

---

## File Size & Error Handling

### Restrictions to Guard Against

1. **File Size**: 15MB maximum (v3 documented limit)
   ```ruby
   pdf_size = File.size(pdf_path)
   raise "PDF too large (#{pdf_size} bytes). Maximum: 15MB" if pdf_size > 15_728_640
   ```

2. **File Type**: PDF only for main document
   ```ruby
   raise "Only PDF files supported" unless File.extname(pdf_path).downcase == '.pdf'
   ```

3. **Multipart Upload**: Use HTTParty multipart
   ```ruby
   require 'httparty/request'
   body: { file: File.open(pdf_path, 'rb'), lookup_key: lookup_key }
   headers: { 'Content-Type' => nil }  # Let HTTParty set multipart boundary
   ```

4. **Test vs Production Keys**: Auto-detect from API response
   ```ruby
   # v3 responses include test_mode flag
   agreement = create_agreement(...)
   @test_mode = agreement[:test_mode]  # Update instance variable
   ```

### Error Handling Improvements

```ruby
def handle_response(response)
  case response.code
  when 200..299
    yield response.parsed_response
  when 401
    raise "Zigned API authentication failed - check API key validity"
  when 404
    raise "Resource not found - agreement or file may not exist"
  when 413
    raise "File too large - maximum 15MB for PDF uploads"
  when 422
    errors = extract_validation_errors(response)
    raise "Validation failed: #{errors}"
  when 500..599
    raise "Zigned API server error (#{response.code}) - try again later"
  else
    error_msg = extract_error_message(response)
    raise "Zigned API error (#{response.code}): #{error_msg}"
  end
end

def extract_validation_errors(response)
  parsed = response.parsed_response
  if parsed.is_a?(Hash) && parsed['errors']
    parsed['errors'].join(', ')
  else
    'Unknown validation error'
  end
end
```

---

## Testing Checklist

### Mac (Development)
- [ ] Logo optimization complete (2000px, 1.2MB)
- [ ] Upload file to `/files` endpoint
- [ ] Create agreement with test API key
- [ ] Attach document by file_id
- [ ] Add participants (Fredrik + test tenant)
- [ ] Activate agreement
- [ ] Verify signing links returned
- [ ] Check database SignedContract record

### Dell (Production)
- [ ] Pull latest changes via webhook
- [ ] Verify ZignedClientV3 available
- [ ] Test with test API key first
- [ ] Generate contract for Frida (test mode)
- [ ] Verify webhook receives events
- [ ] Test with production API key
- [ ] Generate real contract for next tenant
- [ ] End-to-end signing workflow
- [ ] Download signed PDF

---

## Rollback Plan

If v3 migration fails:
1. Keep `lib/zigned_client.rb` (v1) in repo
2. Revert ContractSigner to use v1 client
3. Investigate v3 issues offline
4. Re-attempt after fixes

**Advantage of phased approach:**
- v1 client remains available during migration
- Can switch back instantly if needed
- Test v3 thoroughly before removing v1

---

## Success Criteria

- ✅ No 413 errors on 1.5MB PDFs
- ✅ File upload succeeds (multipart)
- ✅ Agreement creation works
- ✅ Participants added correctly
- ✅ Signing links returned
- ✅ Webhooks deliver to Dell
- ✅ Database records correct
- ✅ End-to-end signing completes
- ✅ Signed PDF downloadable

---

## Timeline

**Estimated**: 2-3 hours
- Implementation: 1-1.5 hours
- Testing (Mac): 30 minutes
- Testing (Dell): 30-45 minutes
- Documentation: 15 minutes

**Start**: Nov 11, 2025 14:30
**Target completion**: Nov 11, 2025 17:00

---

## Resources

- **OpenAPI Spec**: `~/Downloads/Zigned REST API Specification.yaml`
- **Docs**: `https://docs.zigned.se/` (use REF tool)
- **Current Client**: `lib/zigned_client.rb` (v1)
- **New Client**: `lib/zigned_client_v3.rb` (to create)
- **Integration**: `lib/contract_signer.rb` (minimal changes)

---

## Notes

- v3 API uses `agreement_id` internally but we return `case_id` for backward compatibility
- File IDs are temporary (cloned on use) - don't cache long-term
- Test mode determined by API key, not parameter
- Webhook URL configured per-agreement (not global)
- Personal number (personnummer) enforcement requires identity_enforcement object in v3

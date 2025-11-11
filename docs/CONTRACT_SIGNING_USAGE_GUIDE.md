# Contract Signing System - Usage Guide

**Status**: ✅ **INFRASTRUCTURE COMPLETE** (Nov 11, 2025) - Domain migrated, test tenant ready, awaiting Zigned webhook config

**Latest Update**: Repository error handling fixed, Fredrik's tenant record populated with all contract metadata

## Quick Start

### 1. Create Zigned Account (5 minutes)

1. Go to https://zigned.se
2. Click "Bli kund" or "Sign up"
3. Sign up with BankID (Swedish ID verification)
4. Log in to dashboard at https://app.zigned.se
5. Navigate to "API Settings" or "Inställningar"
6. Generate new API key
7. Copy the API key (save securely - shown only once)

### 2. Configure Environment

Add to `.env` file:

```bash
# Zigned API credentials
ZIGNED_API_KEY=your_api_key_here
ZIGNED_WEBHOOK_SECRET=your_webhook_secret_here

# Your domain for webhook callbacks
WEBHOOK_BASE_URL=https://kimonokittens.com
```

**Note**: Webhook secret is optional but recommended for production. Found in same API settings page.

### 3. Test in Test Mode (Free!)

```bash
# Send Sanna's contract in test mode (no real signatures, no cost)
./bin/send_contract.rb \
  --name "Sanna Juni Benemar" \
  --personnummer 8706220020 \
  --email sanna_benemar@hotmail.com \
  --phone "070 289 44 37" \
  --move-in 2025-11-01 \
  --test

# Output will show:
# - Generated PDF path
# - Case ID from Zigned
# - Signing links for both landlord and tenant
# - Expiration date (typically 30 days)
```

### 4. Check Signing Status

```bash
# Use case ID from previous output
./bin/send_contract.rb --status zcs_abc123

# Shows:
# - Current status (pending/completed/expired/cancelled)
# - Which signers have completed
# - Timestamp of signatures
```

### 5. Download Signed PDF

```bash
# When both parties have signed
./bin/send_contract.rb \
  --download zcs_abc123 \
  --tenant-name "Sanna Juni Benemar"

# Downloads to: contracts/signed/Sanna_Juni_Benemar_Hyresavtal_Signed_2025-11-08.pdf
```

---

## Production Usage

### Send Real Contract (Costs Money!)

**⚠️ WARNING**: This sends a real contract for BankID signing. Cost: ~29 SEK per contract.

```bash
./bin/send_contract.rb \
  --name "Sanna Juni Benemar" \
  --personnummer 8706220020 \
  --email sanna_benemar@hotmail.com \
  --phone "070 289 44 37" \
  --move-in 2025-11-01

# Script will ask for confirmation before sending
```

---

## Webhook Integration

### How Webhooks Work

Zigned sends HTTP POST requests to your webhook endpoint when events occur:

- **case.created** - Contract sent successfully
- **case.signed** - One party signed (landlord or tenant)
- **case.completed** - Both parties signed (auto-downloads PDF)
- **case.expired** - Contract expired before all signatures
- **case.cancelled** - Contract was cancelled

### Configure Webhook in Zigned

1. Log in to https://app.zigned.se
2. Go to "API Settings" > "Webhooks"
3. Add new webhook URL: `https://kimonokittens.com/api/webhooks/zigned`
4. Save webhook secret (optional but recommended for production)
5. Add secret to `.env` as `ZIGNED_WEBHOOK_SECRET`

### Test Webhook Locally

```bash
# Start local server
npm run dev

# In another terminal, simulate webhook
curl -X POST http://localhost:3001/api/webhooks/zigned \
  -H "Content-Type: application/json" \
  -d '{
    "event": "case.signed",
    "data": {
      "id": "zcs_test123",
      "signer": {
        "name": "Test Person",
        "personal_number": "8604230717",
        "signed_at": "2025-11-08T12:00:00Z"
      }
    }
  }'

# Check logs for webhook processing confirmation
```

---

## File Structure

All contracts are organized in the `contracts/` directory:

```
contracts/
├── generated/               # PDFs ready for signing
│   └── Sanna_Benemar_Hyresavtal_2025-11-01.pdf
├── signed/                  # Completed, signed PDFs
│   └── Sanna_Juni_Benemar_Hyresavtal_Signed_2025-11-08.pdf
└── metadata/                # JSON tracking files
    ├── Sanna_Juni_Benemar_contract_metadata.json
    └── Frida_Johansson_partial.json
```

### Metadata Format

Each contract has a metadata JSON file:

```json
{
  "tenant_name": "Sanna Juni Benemar",
  "tenant_personnummer": "8706220020",
  "tenant_email": "sanna_benemar@hotmail.com",
  "tenant_phone": "070 289 44 37",
  "move_in_date": "2025-11-01",
  "pdf_path": "contracts/generated/Sanna_Benemar_Hyresavtal_2025-11-01.pdf",
  "case_id": "zcs_abc123",
  "status": "pending",
  "created_at": "2025-11-08 12:00:00",
  "expires_at": "2025-12-08T12:00:00Z",
  "test_mode": false,
  "signing_links": {
    "8604230717": "https://sign.zigned.se/...",
    "8706220020": "https://sign.zigned.se/..."
  }
}
```

---

## Common Workflows

### Scenario 1: Send Test Contract

**Goal**: Test the entire flow without spending money or requiring real BankID.

```bash
# 1. Send contract in test mode
./bin/send_contract.rb \
  --name "Test Person" \
  --personnummer 8604230717 \
  --email test@example.com \
  --phone "070 123 45 67" \
  --move-in 2025-12-01 \
  --test

# 2. Copy the signing links from output
# 3. Open links in browser (no real BankID required in test mode)
# 4. Click through signing UI
# 5. Check status
./bin/send_contract.rb --status zcs_test123

# 6. Download signed PDF when complete
./bin/send_contract.rb --download zcs_test123 --tenant-name "Test Person"
```

### Scenario 2: Send Sanna's Real Contract

**Goal**: Send production contract for real BankID signing.

```bash
# 1. Verify Sanna's information is correct
cat contracts/metadata/Sanna_Juni_Benemar_partial.json

# 2. Send contract (production mode)
./bin/send_contract.rb \
  --name "Sanna Juni Benemar" \
  --personnummer 8706220020 \
  --email sanna_benemar@hotmail.com \
  --phone "070 289 44 37" \
  --move-in 2025-11-01

# 3. Zigned sends emails to both parties with signing links
# 4. Both parties sign with BankID
# 5. Webhook receives completion event
# 6. Signed PDF auto-downloads to contracts/signed/

# 7. Verify signed contract
ls -lh contracts/signed/Sanna_Juni_Benemar_Hyresavtal_Signed_*.pdf
```

### Scenario 3: Generate Frida's Contract

**Goal**: Generate contract when Frida provides her email and phone.

```bash
# 1. Update Frida's partial metadata with contact info
# (You can manually edit contracts/metadata/Frida_Johansson_partial.json)

# 2. Send contract
./bin/send_contract.rb \
  --name "Frida Johansson" \
  --personnummer 890622-3386 \
  --email frida@example.com \
  --phone "070 987 65 43" \
  --move-in 2025-12-03

# 3. Follow same workflow as Sanna
```

---

## Troubleshooting

### "ZIGNED_API_KEY not set" Error

**Solution**: Add your API key to `.env` file:

```bash
echo "ZIGNED_API_KEY=your_key_here" >> .env
```

### "Invalid webhook signature" Error

**Cause**: Webhook secret mismatch or not configured.

**Solution**: Either:
- Remove `ZIGNED_WEBHOOK_SECRET` from `.env` to disable signature checking (development only!)
- OR ensure secret in `.env` matches secret in Zigned dashboard

### Case Status Shows "Expired"

**Cause**: Zigned cases expire after 30 days by default.

**Solution**:
1. Check expiration date: `./bin/send_contract.rb --status zcs_abc123`
2. If expired, cancel old case: `./bin/send_contract.rb --cancel zcs_abc123`
3. Send new contract: `./bin/send_contract.rb --name "..." ...`

### PDF Generation Fails

**Cause**: Missing Prawn gem or logo file.

**Solution**:
```bash
# Install dependencies
bundle install

# Verify logo exists
ls -lh dashboard/public/logo.png

# If missing, contract will generate without logo (still works)
```

### Webhook Not Receiving Events

**Checklist**:
1. ✅ Webhook endpoint deployed to production
2. ✅ URL configured in Zigned dashboard
3. ✅ Production server accessible from internet
4. ✅ Firewall allows incoming HTTPS on port 443
5. ✅ Check webhook logs: `journalctl -u kimonokittens-dashboard -f | grep webhook`

---

## Cost Estimation

### Zigned Pricing (Pay-per-use)

- Base cost: **19 SEK per case**
- Per signer: **5 SEK per signature**
- Typical contract: **29 SEK** (1 landlord + 1 tenant)

### Monthly Costs

**Scenario**: 2 new contracts per year (avg)

- Yearly: 2 contracts × 29 SEK = **58 SEK/year**
- Monthly: **~5 SEK/month average**

**Comparison to Scrive**:
- Scrive Essentials: **2,490 SEK/month** (minimum)
- Savings: **2,485 SEK/month** with Zigned pay-per-use

---

## Next Steps

1. **Create Zigned account** (5 min with BankID)
2. **Get API key** from dashboard
3. **Add to `.env`** file
4. **Test with Sanna** in test mode (`--test` flag)
5. **Send real contract** when ready (production mode)
6. **Configure webhook** for automatic signed PDF downloads
7. **Deploy to production** (webhook endpoint already in puma_server.rb)

---

## Support & Documentation

- **Zigned API Docs**: https://docs.zigned.se
- **Zigned Support**: support@zigned.se
- **Implementation Plan**: `docs/CONTRACT_SIGNING_IMPLEMENTATION_PLAN.md`
- **Code Reference**:
  - ZignedClient: `lib/zigned_client.rb`
  - ContractSigner: `lib/contract_signer.rb`
  - CLI Script: `bin/send_contract.rb`
  - Webhook Handler: `handlers/zigned_webhook_handler.rb`

---

## November 11, 2025 Status Update

### Infrastructure Deployment Complete ✅

**Domain Migration:**
- kimonokittens.com → Dell Optiplex (192.168.4.84)
- SSL certificates active (expires 2026-02-08)
- Nginx configured with webhook routing
- External accessibility verified

**Database Schema:**
- 6 migrations applied to production
- SignedContract table ready
- Tenant contract fields populated
- Test tenant ready: Fredrik Bränström (cmcp56en7000myzpivjxfmxcc)

**Webhook Endpoints:**
- `https://kimonokittens.com/api/webhooks/zigned` → localhost:3001 (main Puma)
- Externally accessible and ready to receive events
- DataBroadcaster properly injected into handler

**Code Quality Fixes (Nov 11):**
- Repository error handling: All update() methods validate database operations
- Clear error messages: Distinguish "not found" vs "update rejected"
- Tenant model: Added setters for contract field updates

### Current Test Workflow Available

**Safe test mode (no emails, free signatures):**
```ruby
require_relative 'lib/persistence'
require_relative 'lib/services/contract_signer'

# Test with Fredrik's tenant record
result = ContractSigner.create_and_send(
  tenant_id: 'cmcp56en7000myzpivjxfmxcc',  # Fredrik Bränström
  test_mode: true,
  send_emails: false
)

# Returns:
# - case_id: Zigned case identifier
# - signing_links: Hash of personnummer → URL
# - pdf_path: Generated contract path
```

**What this tests:**
1. ✅ Database tenant loading
2. ✅ Contract generation with correct rent calculation
3. ✅ PDF upload to Zigned API
4. ✅ Case creation with 2 signers
5. ✅ Signing link generation
6. ✅ Test mode works (development API key)

**What requires Zigned webhook config:**
- Signature event reception (case.signed)
- Completion event reception (case.completed)
- Automatic signed PDF download
- Database tracking of signature status

### Pre-Testing Checklist

**Before running ContractSigner.create_and_send():**
1. ✅ Domain migration complete
2. ✅ SSL certificates installed
3. ✅ Database schema up to date
4. ✅ Test tenant populated with metadata
5. ✅ Repository error handling fixed
6. ⏳ Verify Zigned credentials in `/home/kimonokittens/.env`:
   - `ZIGNED_CLIENT_ID` (development or production)
   - `ZIGNED_API_KEY` (corresponding key)
7. ⏳ Configure Zigned webhook in admin dashboard:
   - URL: `https://kimonokittens.com/api/webhooks/zigned`
   - Events: case.created, case.signed, case.completed
   - Secret: Match `ZIGNED_WEBHOOK_SECRET` in .env

### Testing Sequence (Recommended)

**Phase 1: Local Generation Test**
```bash
# SSH to production
ssh pop

# Verify environment
grep ZIGNED /home/kimonokittens/.env

# Run test contract generation (Ruby console)
cd /home/kimonokittens/Projects/kimonokittens
ruby -e "
require 'dotenv/load'
require_relative 'lib/persistence'
require_relative 'lib/services/contract_signer'

result = ContractSigner.create_and_send(
  tenant_id: 'cmcp56en7000myzpivjxfmxcc',
  test_mode: true,
  send_emails: false
)

puts '✅ Contract generated!'
puts 'Case ID: ' + result[:case_id]
puts 'PDF: ' + result[:pdf_path]
puts 'Signing links: ' + result[:signing_links].inspect
"
```

**Phase 2: Webhook Event Test**
- Configure webhook URL in Zigned admin
- Trigger test event from Zigned dashboard
- Monitor logs: `tail -f /var/log/kimonokittens/webhook.log | grep zigned`
- Verify handler processes event correctly

**Phase 3: End-to-End Test**
- Send contract to Fredrik (test mode, no emails)
- Open signing link in browser
- Complete test signature
- Verify webhook receives case.signed event
- Verify database tracking updates

**Phase 4: Production Test**
- Switch to production API key
- Send contract to Fredrik (real BankID signature)
- Complete signing flow
- Verify signed PDF downloads automatically

### Known Limitations

**File-based metadata no longer needed:**
- Old workflow used `contracts/metadata/*.json` files
- New workflow uses database (SignedContract table)
- Webhook handler queries database by case_id, not filesystem

**Cross-machine testing:**
- Mac development can test contract generation
- Full webhook flow requires production Dell (database access)
- Incremental testing approach recommended (see CONTRACT_SIGNING_STATUS.md)

### Next Steps

1. User verifies Zigned environment variables in production
2. User configures webhook URL in Zigned admin interface
3. Run Phase 1 test (local generation)
4. Run Phase 2 test (webhook events)
5. Run Phase 3 test (end-to-end with test signatures)
6. Run Phase 4 test (production signatures)
7. Document results in CONTRACT_SIGNING_STATUS.md

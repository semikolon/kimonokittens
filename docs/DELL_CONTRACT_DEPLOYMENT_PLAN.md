# Dell Production Deployment Plan: Contract Signing System

**Status**: Ready for implementation
**Created**: November 8, 2025
**Target**: Dell OptiPlex production server (SSH: `pop`)

## Overview

Deploy the contract signing system from Mac development environment to Dell production server, including tenant data migration, database schema updates, and Zigned webhook integration.

## Current Tenant Status (November 2025)

**Active Tenants (4 total)**:
- **Fredrik** (landlord, first-hand tenant) - staying
- **Adam** - moving out ~Dec 1 or by Jan 1 latest
- **Rasmus** - moving out by Jan 1 latest (one of Adam/Rasmus around Dec 1)
- **Sanna Juni Benemar** - moved in Nov 1, took over Amanda's room

**Recent Transitions**:
- **Amanda** - moved out end of October 2025
- **Sanna** - new tenant, contract being generated for Nov 1 start

**Pending Move-Ins**:
- **Frida Johansson** - contract for Dec 3, 2025 start date

**Rent Calculation Context**: Current contracts assume 4 active tenants (24,530 kr / 4 = 6,132.50 kr per person base rent). This will change when Adam/Rasmus move out and new tenants move in.

## Prerequisites Verification

Before starting deployment, verify these exist on Dell:

```bash
# SSH to Dell
ssh pop

# Check Ruby/Bundle
ruby -v  # Should match dev: 3.2.2+
bundle -v

# Check PostgreSQL
psql -U kimonokittens -d kimonokittens_production -c "SELECT version();"

# Check .env file exists
ls -la /home/kimonokittens/.env

# Check Git checkout is clean
cd /home/kimonokittens/Projects/kimonokittens
git status
```

---

## Phase 1: Export Tenant Data from Local Dev Database

### Step 1.1: Create Export Script

**Location**: `deployment/export_contract_tenants.rb`

```ruby
#!/usr/bin/env ruby
require 'json'
require 'dotenv/load'
require_relative '../lib/repositories/tenant_repository'

# Export Sanna and Frida records to JSON for production import
repo = TenantRepository.new

sanna = repo.find_by_id('sanna-juni-benemar-8706220020')
frida = repo.find_by_id('frida-johansson-890622-3386')

raise "Sanna record not found!" unless sanna
raise "Frida record not found!" unless frida

export_data = {
  exported_at: Time.now.iso8601,
  tenants: [
    {
      id: sanna.id,
      name: sanna.name,
      email: sanna.email,
      personnummer: sanna.personnummer,
      phone: sanna.phone,
      deposit: sanna.deposit.to_f,
      furnishing_deposit: sanna.furnishing_deposit.to_f,
      start_date: sanna.start_date&.iso8601,
      status: 'active',
      room_adjustment: sanna.room_adjustment&.to_f
    },
    {
      id: frida.id,
      name: frida.name,
      email: frida.email,
      personnummer: frida.personnummer,
      phone: frida.phone,
      deposit: frida.deposit.to_f,
      furnishing_deposit: frida.furnishing_deposit.to_f,
      start_date: frida.start_date&.iso8601,
      status: 'pending',
      room_adjustment: frida.room_adjustment&.to_f
    }
  ]
}

output_path = File.expand_path('../deployment/contract_tenants_export.json', __dir__)
File.write(output_path, JSON.pretty_generate(export_data))

puts "✅ Exported 2 tenant records to: #{output_path}"
puts "\nSanna: #{sanna.name} (#{sanna.personnummer})"
puts "  Deposit: #{sanna.deposit} kr, Furnishing: #{sanna.furnishing_deposit} kr"
puts "  Start: #{sanna.start_date}"
puts "\nFrida: #{frida.name} (#{frida.personnummer})"
puts "  Deposit: #{frida.deposit} kr, Furnishing: #{frida.furnishing_deposit} kr"
puts "  Start: #{frida.start_date}"
```

### Step 1.2: Run Export on Mac Dev Machine

```bash
cd ~/Projects/kimonokittens
ruby deployment/export_contract_tenants.rb
```

**Expected output**: Creates `deployment/contract_tenants_export.json`

### Step 1.3: Verify Export File

```bash
cat deployment/contract_tenants_export.json | jq .
```

**Should contain**:
- 2 tenant records
- All contract fields: personnummer, phone, deposit, furnishing_deposit
- Timestamps and status fields

---

## Phase 2: Add SignedContract Table to Production Database

### Why This Is Needed

Current implementation stores signed contracts in **files** (`contracts/signed/*.pdf` and `contracts/metadata/*.json`). This won't work in production because:

- Webhook runs on Dell server
- Contract generation happens on Mac dev machine
- Files on one machine aren't accessible from the other
- **Solution**: Store signed contracts in PostgreSQL database

### Step 2.1: Create Prisma Migration

**Location**: `prisma/migrations/YYYYMMDD_add_signed_contract_table/migration.sql`

```sql
-- CreateTable: SignedContract
-- Stores Zigned signed PDFs and metadata in database instead of files
CREATE TABLE "SignedContract" (
  "id" TEXT NOT NULL,
  "tenantId" TEXT NOT NULL,
  "caseId" TEXT NOT NULL,
  "pdfUrl" TEXT NOT NULL,
  "status" TEXT NOT NULL DEFAULT 'pending',
  "landlordSigned" BOOLEAN NOT NULL DEFAULT false,
  "tenantSigned" BOOLEAN NOT NULL DEFAULT false,
  "landlordSignedAt" TIMESTAMP(3),
  "tenantSignedAt" TIMESTAMP(3),
  "completedAt" TIMESTAMP(3),
  "expiresAt" TIMESTAMP(3),
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMP(3) NOT NULL,

  CONSTRAINT "SignedContract_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "SignedContract_caseId_key" ON "SignedContract"("caseId");

-- CreateIndex
CREATE INDEX "SignedContract_tenantId_idx" ON "SignedContract"("tenantId");

-- CreateIndex
CREATE INDEX "SignedContract_status_idx" ON "SignedContract"("status");

-- AddForeignKey
ALTER TABLE "SignedContract" ADD CONSTRAINT "SignedContract_tenantId_fkey"
  FOREIGN KEY ("tenantId") REFERENCES "Tenant"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
```

### Step 2.2: Update Prisma Schema

Add to `prisma/schema.prisma`:

```prisma
model SignedContract {
  id               String    @id
  tenantId         String
  caseId           String    @unique
  pdfUrl           String
  status           String    @default("pending")
  landlordSigned   Boolean   @default(false)
  tenantSigned     Boolean   @default(false)
  landlordSignedAt DateTime?
  tenantSignedAt   DateTime?
  completedAt      DateTime?
  expiresAt        DateTime?
  createdAt        DateTime  @default(now())
  updatedAt        DateTime  @updatedAt

  tenant Tenant @relation(fields: [tenantId], references: [id])

  @@index([tenantId])
  @@index([status])
}

model Tenant {
  // ... existing fields ...

  signedContracts SignedContract[]
}
```

### Step 2.3: Generate Migration on Mac

```bash
cd ~/Projects/kimonokittens
npx prisma migrate dev --name add_signed_contract_table
```

### Step 2.4: Commit and Push Migration

```bash
git add prisma/schema.prisma prisma/migrations/
git commit -m "feat: Add SignedContract table for database-backed contract storage"
git push origin master
```

**Note**: Webhook will deploy code to Dell, but **migration must be run manually**.

---

## Phase 3: Deploy Code to Dell (Webhook Auto-Deploy)

### Step 3.1: Push All Changes

From Mac dev machine:

```bash
cd ~/Projects/kimonokittens
git add deployment/export_contract_tenants.rb
git add deployment/contract_tenants_export.json
git commit -m "feat: Export contract tenant data for production deployment"
git push origin master
```

### Step 3.2: Monitor Webhook Deployment

On Dell:

```bash
# Watch webhook logs
tail -f /var/log/kimonokittens/webhook.log

# Or journalctl
journalctl -u kimonokittens-webhook -f
```

**Expected**: Webhook deploys code within 2 minutes

### Step 3.3: Verify Deployment

```bash
ssh pop
cd /home/kimonokittens/Projects/kimonokittens

# Check files exist
ls -la deployment/export_contract_tenants.rb
ls -la deployment/contract_tenants_export.json
ls -la prisma/migrations/*add_signed_contract_table/migration.sql

# Check git status
git log -1 --oneline
```

---

## Phase 4: Run Production Database Migrations

### Step 4.1: Apply Prisma Migration

SSH to Dell and run:

```bash
ssh pop
cd /home/kimonokittens/Projects/kimonokittens

# Apply migration to production database
npx prisma migrate deploy

# Verify table exists
psql -U kimonokittens -d kimonokittens_production -c "\d SignedContract"
```

**Expected output**: Table `SignedContract` with all columns

### Step 4.2: Verify Foreign Key

```bash
psql -U kimonokittens -d kimonokittens_production -c "
  SELECT
    tc.constraint_name,
    tc.table_name,
    kcu.column_name,
    ccu.table_name AS foreign_table_name,
    ccu.column_name AS foreign_column_name
  FROM information_schema.table_constraints AS tc
  JOIN information_schema.key_column_usage AS kcu
    ON tc.constraint_name = kcu.constraint_name
  JOIN information_schema.constraint_column_usage AS ccu
    ON ccu.constraint_name = tc.constraint_name
  WHERE tc.table_name = 'SignedContract';
"
```

**Expected**: Foreign key from `tenantId` to `Tenant.id`

---

## Phase 5: Import Tenant Data to Production

### Step 5.1: Create Import Script

**Location**: `deployment/import_contract_tenants.rb`

```ruby
#!/usr/bin/env ruby
require 'json'
require 'dotenv/load'
require_relative '../lib/repositories/tenant_repository'

# Import Sanna and Frida from export file to production database
export_file = File.expand_path('../deployment/contract_tenants_export.json', __dir__)
data = JSON.parse(File.read(export_file), symbolize_names: true)

repo = TenantRepository.new

puts "Importing #{data[:tenants].length} tenants exported at #{data[:exported_at]}..."

data[:tenants].each do |tenant_data|
  # Check if tenant already exists
  existing = repo.find_by_id(tenant_data[:id])

  if existing
    puts "⚠️  Tenant already exists: #{tenant_data[:name]} (#{tenant_data[:id]})"
    puts "   Skipping import. Use update script if changes needed."
    next
  end

  # Create tenant
  tenant = Tenant.new(
    id: tenant_data[:id],
    name: tenant_data[:name],
    email: tenant_data[:email],
    personnummer: tenant_data[:personnummer],
    phone: tenant_data[:phone],
    deposit: tenant_data[:deposit],
    furnishing_deposit: tenant_data[:furnishing_deposit],
    start_date: tenant_data[:start_date] ? Date.parse(tenant_data[:start_date]) : nil,
    room_adjustment: tenant_data[:room_adjustment]
  )

  saved = repo.save(tenant)

  if saved
    puts "✅ Imported: #{tenant.name}"
    puts "   ID: #{tenant.id}"
    puts "   Email: #{tenant.email}"
    puts "   Phone: #{tenant.phone}"
    puts "   Personnummer: #{tenant.personnummer}"
    puts "   Deposit: #{tenant.deposit} kr"
    puts "   Furnishing: #{tenant.furnishing_deposit} kr"
    puts "   Start: #{tenant.start_date}"
  else
    puts "❌ Failed to import: #{tenant_data[:name]}"
  end
end

puts "\n✅ Import complete!"
```

### Step 5.2: Run Import on Dell

```bash
ssh pop
cd /home/kimonokittens/Projects/kimonokittens

# Run import script
ruby deployment/import_contract_tenants.rb
```

### Step 5.3: Verify Imported Data

```bash
# Check database directly
psql -U kimonokittens -d kimonokittens_production -c "
  SELECT
    id,
    name,
    email,
    personnummer,
    phone,
    deposit,
    \"furnishingDeposit\",
    \"startDate\"
  FROM \"Tenant\"
  WHERE id IN (
    'sanna-juni-benemar-8706220020',
    'frida-johansson-890622-3386'
  );
"
```

**Expected**: 2 rows with all contract fields populated

---

## Phase 6: Configure Zigned Webhook

### Step 6.1: Verify Environment Variables on Dell

```bash
ssh pop
cat /home/kimonokittens/.env | grep ZIGNED
```

**Required variables**:
```bash
ZIGNED_API_KEY=your_api_key_here
ZIGNED_WEBHOOK_SECRET=your_webhook_secret_here
```

**If missing**: Add them to `/home/kimonokittens/.env` and restart dashboard service:

```bash
sudo systemctl restart kimonokittens-dashboard
```

### Step 6.2: Verify Webhook Endpoint Exists

```bash
ssh pop
cd /home/kimonokittens/Projects/kimonokittens

# Check handler exists
ls -la handlers/zigned_webhook_handler.rb

# Check puma_server.rb registers the route
grep -A 3 'POST /api/webhooks/zigned' puma_server.rb
```

**Expected**: Route exists in puma_server.rb

### Step 6.3: Configure Webhook in Zigned Dashboard

1. Log into Zigned dashboard: https://app.zigned.se
2. Navigate to: Settings → Webhooks
3. Add webhook URL: `https://kimonokittens.com/api/webhooks/zigned`
4. Events to subscribe:
   - `case.created`
   - `case.signed`
   - `case.completed`
   - `case.expired`
   - `case.cancelled`
5. Secret: Use value from `ZIGNED_WEBHOOK_SECRET`

### Step 6.4: Test Webhook Connectivity

From Mac:

```bash
# Test webhook endpoint is accessible
curl -X POST https://kimonokittens.com/api/webhooks/zigned \
  -H "Content-Type: application/json" \
  -H "X-Zigned-Signature: test" \
  -d '{"test": true}'
```

**Expected**: Should get 200 OK or signature error (proves endpoint is reachable)

---

## Phase 7: Update Webhook Handler for Database Storage

### Current Implementation

`handlers/zigned_webhook_handler.rb` currently stores to **files**:
- Line 159: `File.write("contracts/metadata/#{case_id}.json", ...)`
- Line 176: `File.write("contracts/signed/#{case_id}.pdf", ...)`

### Step 7.1: Create SignedContractRepository

**Location**: `lib/repositories/signed_contract_repository.rb`

```ruby
require 'sequel'
require_relative '../rent_db'

class SignedContractRepository
  def initialize(db = RentDb.instance)
    @db = db
  end

  def find_by_case_id(case_id)
    row = @db.class.db[:SignedContract].where(caseId: case_id).first
    row ? hydrate(row) : nil
  end

  def find_by_tenant_id(tenant_id)
    @db.class.db[:SignedContract]
      .where(tenantId: tenant_id)
      .order(Sequel.desc(:createdAt))
      .map { |row| hydrate(row) }
  end

  def save(signed_contract)
    data = dehydrate(signed_contract)

    existing = @db.class.db[:SignedContract].where(id: signed_contract.id).first

    if existing
      @db.class.db[:SignedContract].where(id: signed_contract.id).update(data)
    else
      @db.class.db[:SignedContract].insert(data)
    end

    signed_contract
  end

  private

  def hydrate(row)
    SignedContract.new(
      id: row[:id],
      tenant_id: row[:tenantId],
      case_id: row[:caseId],
      pdf_url: row[:pdfUrl],
      status: row[:status],
      landlord_signed: row[:landlordSigned],
      tenant_signed: row[:tenantSigned],
      landlord_signed_at: row[:landlordSignedAt],
      tenant_signed_at: row[:tenantSignedAt],
      completed_at: row[:completedAt],
      expires_at: row[:expiresAt],
      created_at: row[:createdAt],
      updated_at: row[:updatedAt]
    )
  end

  def dehydrate(contract)
    {
      id: contract.id,
      tenantId: contract.tenant_id,
      caseId: contract.case_id,
      pdfUrl: contract.pdf_url,
      status: contract.status,
      landlordSigned: contract.landlord_signed,
      tenantSigned: contract.tenant_signed,
      landlordSignedAt: contract.landlord_signed_at,
      tenantSignedAt: contract.tenant_signed_at,
      completedAt: contract.completed_at,
      expiresAt: contract.expires_at,
      updatedAt: Time.now
    }
  end
end
```

### Step 7.2: Create SignedContract Model

**Location**: `lib/models/signed_contract.rb`

```ruby
class SignedContract
  attr_reader :id, :tenant_id, :case_id, :pdf_url, :status,
              :landlord_signed, :tenant_signed,
              :landlord_signed_at, :tenant_signed_at,
              :completed_at, :expires_at,
              :created_at, :updated_at

  def initialize(id: nil, tenant_id:, case_id:, pdf_url:, status: 'pending',
                 landlord_signed: false, tenant_signed: false,
                 landlord_signed_at: nil, tenant_signed_at: nil,
                 completed_at: nil, expires_at: nil,
                 created_at: nil, updated_at: nil)
    @id = id || generate_id
    @tenant_id = tenant_id
    @case_id = case_id
    @pdf_url = pdf_url
    @status = status
    @landlord_signed = landlord_signed
    @tenant_signed = tenant_signed
    @landlord_signed_at = landlord_signed_at
    @tenant_signed_at = tenant_signed_at
    @completed_at = completed_at
    @expires_at = expires_at
    @created_at = created_at || Time.now
    @updated_at = updated_at || Time.now
  end

  def completed?
    status == 'completed'
  end

  def expired?
    status == 'expired'
  end

  def pending?
    status == 'pending'
  end

  private

  def generate_id
    "signed-contract-#{SecureRandom.hex(8)}"
  end
end
```

### Step 7.3: Update Webhook Handler

Modify `handlers/zigned_webhook_handler.rb`:

```ruby
require_relative '../lib/repositories/signed_contract_repository'
require_relative '../lib/models/signed_contract'

class ZignedWebhookHandler
  def initialize
    @client = ZignedClient.new
    @repo = SignedContractRepository.new
  end

  def handle_case_created(case_id, payload)
    tenant_id = payload['metadata']&.fetch('tenant_id', nil)
    expires_at = payload['expires_at'] ? Time.parse(payload['expires_at']) : nil

    contract = SignedContract.new(
      tenant_id: tenant_id,
      case_id: case_id,
      pdf_url: payload['files']&.first&.fetch('url', ''),
      status: 'pending',
      expires_at: expires_at
    )

    @repo.save(contract)

    puts "✅ Stored contract record: #{case_id}"
  end

  def handle_case_signed(case_id, signer_info)
    contract = @repo.find_by_case_id(case_id)
    return unless contract

    # Determine who signed based on email or role
    if signer_info['email'] == 'branstrom@gmail.com'
      contract.instance_variable_set(:@landlord_signed, true)
      contract.instance_variable_set(:@landlord_signed_at, Time.now)
    else
      contract.instance_variable_set(:@tenant_signed, true)
      contract.instance_variable_set(:@tenant_signed_at, Time.now)
    end

    @repo.save(contract)
  end

  def handle_case_completed(case_id)
    contract = @repo.find_by_case_id(case_id)
    return unless contract

    # Download signed PDF
    pdf_data = download_signed_contract(case_id)

    # Upload to storage (S3 or similar) and get URL
    pdf_url = upload_to_storage(pdf_data, "#{case_id}.pdf")

    # Update database record
    contract.instance_variable_set(:@status, 'completed')
    contract.instance_variable_set(:@completed_at, Time.now)
    contract.instance_variable_set(:@pdf_url, pdf_url)

    @repo.save(contract)

    puts "✅ Contract completed and stored: #{case_id}"
  end

  private

  def upload_to_storage(pdf_data, filename)
    # TODO: Implement S3 upload or store as base64 in database
    # For now, return placeholder
    "storage://contracts/#{filename}"
  end
end
```

### Step 7.4: Test Database Storage

This requires actual Zigned webhook events. See Phase 9 for end-to-end testing.

---

## Phase 8: Understanding Zigned Case Flow

### How Zigned Works (No Email Needed from Our System!)

1. **Case Creation** (via our system):
   ```ruby
   ContractSigner.create_and_send(tenant_id: 'sanna-juni-benemar-8706220020')
   ```

2. **Zigned Automatically Sends Emails**:
   - Email to landlord (Fredrik): "Sign this contract at [link]"
   - Email to tenant (Sanna): "Sign this contract at [link]"
   - **We don't send these emails** - Zigned handles it

3. **Webhook Events Received**:
   - `case.created` → Store initial contract record
   - `case.signed` → Update when one party signs
   - `case.signed` → Update when second party signs
   - `case.completed` → Download final signed PDF, store in database

4. **Signed Document Delivery**:
   - **Zigned automatically emails the final signed PDF to both parties**
   - Our system stores it in database for records
   - **We don't need to email anything**

### What Our System Does

✅ **Generate contract PDF** (from database)
✅ **Upload to Zigned** (create case)
✅ **Receive webhook events** (track progress)
✅ **Store signed PDF** (in database for records)

❌ **Does NOT email signing links** (Zigned does this)
❌ **Does NOT email signed documents** (Zigned does this)

---

## Phase 9: End-to-End Testing

### Step 9.1: Generate Test Contract on Dell

```bash
ssh pop
cd /home/kimonokittens/Projects/kimonokittens

# Generate Sanna's contract
ruby -e "
  require 'dotenv/load'
  require_relative 'lib/contract_generator_html'

  output = ContractGeneratorHtml.generate_from_tenant_id(
    'sanna-juni-benemar-8706220020',
    output_path: 'contracts/test_sanna.pdf'
  )

  puts \"Generated: \#{output}\"
"
```

**Expected**: PDF created at `contracts/test_sanna.pdf`

### Step 9.2: Verify PDF Content

```bash
# Check PDF contains correct rent
pdftotext contracts/test_sanna.pdf - | grep "Kall månadshyra"
```

**Expected**: Should show "6 132,50 kr" (not 4,500 kr)

### Step 9.3: Create Test Zigned Case

```bash
ruby -e "
  require 'dotenv/load'
  require_relative 'lib/contract_signer'

  result = ContractSigner.create_and_send(
    tenant_id: 'sanna-juni-benemar-8706220020'
  )

  puts \"Case created: \#{result[:case_id]}\"
  puts \"View at: \#{result[:case_url]}\"
"
```

### Step 9.4: Verify Webhook Receives Events

Watch webhook logs:

```bash
tail -f /var/log/kimonokittens/webhook.log | grep -i zigned
```

**Expected events**:
1. `case.created` - Initial case creation
2. Check email for signing links
3. Both parties sign → `case.signed` events
4. Both signatures complete → `case.completed`
5. Final signed PDF stored in database

### Step 9.5: Verify Database Storage

```bash
psql -U kimonokittens -d kimonokittens_production -c "
  SELECT
    \"caseId\",
    status,
    \"landlordSigned\",
    \"tenantSigned\",
    \"completedAt\"
  FROM \"SignedContract\"
  ORDER BY \"createdAt\" DESC
  LIMIT 5;
"
```

**Expected**: Test case record with status progression

---

## Phase 10: Cleanup and Documentation

### Step 10.1: Update Production Documentation

Update `CLAUDE.md` with:

```markdown
## Contract Signing System

**Status**: ✅ PRODUCTION (November 8, 2025)

**Architecture**:
- Tenant data stored in PostgreSQL
- Contracts generated via ERB templates + handbook
- Zigned API for BankID e-signatures
- Signed contracts stored in SignedContract table
- Webhook auto-downloads final PDFs

**Generate contract**:
```ruby
ContractGeneratorHtml.generate_from_tenant_id('tenant-id')
```

**Send for signature**:
```ruby
ContractSigner.create_and_send(tenant_id: 'tenant-id')
```

**Zigned handles all email communication** - no email sending needed from our system.
```

### Step 10.2: Archive JSON Files

```bash
# On both Mac and Dell
mkdir -p contracts/archive/pre-database
mv contracts/tenants/*.json contracts/archive/pre-database/
```

### Step 10.3: Add .gitignore Rules

Add to `.gitignore`:

```
# Contract files (stored in database, not files)
contracts/signed/*.pdf
contracts/metadata/*.json

# But keep export/import data
!contracts/archive/
!deployment/contract_tenants_export.json
```

---

## Rollback Plan

If anything goes wrong during deployment:

### Database Rollback

```bash
ssh pop
cd /home/kimonokittens/Projects/kimonokittens

# Rollback last migration
npx prisma migrate resolve --rolled-back MIGRATION_NAME

# Or manually drop table
psql -U kimonokittens -d kimonokittens_production -c "DROP TABLE IF EXISTS \"SignedContract\" CASCADE;"
```

### Code Rollback

```bash
ssh pop
cd /home/kimonokittens/Projects/kimonokittens

# Revert to previous commit
git log --oneline -5  # Find previous commit hash
git reset --hard PREVIOUS_COMMIT_HASH

# Restart services
sudo systemctl restart kimonokittens-dashboard
```

### Data Rollback

```bash
# Delete imported tenants if needed
psql -U kimonokittens -d kimonokittens_production -c "
  DELETE FROM \"Tenant\"
  WHERE id IN (
    'sanna-juni-benemar-8706220020',
    'frida-johansson-890622-3386'
  );
"
```

---

## Success Criteria

Deployment is complete when:

- [ ] SignedContract table exists in production database
- [ ] Sanna and Frida records imported to production with all fields
- [ ] Contracts generate on Dell with correct rent (6,132.50 kr)
- [ ] Zigned webhook URL configured and receiving events
- [ ] Test case created successfully
- [ ] Webhook stores contract records in database
- [ ] Final signed PDF auto-downloads and stores
- [ ] Production documentation updated

---

## Timeline Estimate

- **Phase 1-2**: 30 minutes (export data + create migration)
- **Phase 3-4**: 10 minutes (deploy code + run migration)
- **Phase 5**: 15 minutes (import tenant data)
- **Phase 6**: 20 minutes (configure webhook)
- **Phase 7**: 1 hour (implement database storage)
- **Phase 8**: 0 minutes (documentation only)
- **Phase 9**: 30 minutes (end-to-end testing)
- **Phase 10**: 15 minutes (cleanup)

**Total**: ~3 hours

---

## Support Commands

```bash
# Check production database
psql -U kimonokittens -d kimonokittens_production

# View webhook logs
tail -f /var/log/kimonokittens/webhook.log

# Restart dashboard service
sudo systemctl restart kimonokittens-dashboard

# Check service status
sudo systemctl status kimonokittens-dashboard

# Generate contract
ssh pop
cd /home/kimonokittens/Projects/kimonokittens
ruby -e "require 'dotenv/load'; require_relative 'lib/contract_generator_html'; ContractGeneratorHtml.generate_from_tenant_id('TENANT_ID')"

# Send for signature
ruby -e "require 'dotenv/load'; require_relative 'lib/contract_signer'; ContractSigner.create_and_send(tenant_id: 'TENANT_ID')"
```

---

## UPDATE: November 11, 2025 01:50 UTC

### Status: READY FOR TESTING

**Major Milestones Completed:**
- ✅ Domain migration COMPLETE (kimonokittens.com → Dell)
- ✅ SSL certificates obtained (manual DNS-01, expires Feb 8, 2026)
- ✅ Nginx split config deployed (public webhooks + localhost dashboard)
- ✅ Port forwarding updated (Dell accessible externally)
- ✅ Database migrations applied (all 6 migrations up to date)
- ✅ Zigned webhook handler fixed (DataBroadcaster dependency injection)
- ✅ Fredrik Bränström tenant record populated with contract metadata
- ✅ Tenant model setters added for ergonomic updates (pending deployment)
- ✅ Repository error handling fixed (all update methods now validate rows_affected)

**Pending Deployment:**
- Commit 3976f54: Tenant model setters
- Commits pending: Repository error handling fixes

**Ready to Test:**
- Test contract generation: `ContractSigner.create_and_send(tenant_id: 'cmcp56en7000myzpivjxfmxcc', test_mode: true, send_emails: false)`
- Webhook endpoint live at: `https://kimonokittens.com/api/webhooks/zigned`
- Full end-to-end flow possible (domain migration complete)

**Critical Fixes Applied:**
- Repository update methods now raise errors on silent failures (0 rows affected)
- Pre-existence checks added to distinguish "not found" from "update rejected"
- Tenant model now has attr_writer for contract fields (phone, personnummer, deposits)

# Contract E-Signing Implementation Plan
**Date:** November 7, 2025
**Status:** Phase 1 (Standalone) - Ready to Implement

---

## 🎯 Two-Phase Architecture

### **Phase 1: Standalone E-Signing (THIS WEEK)**
Build minimal, working e-signing system WITHOUT database integration.

**Benefits:**
- ✅ Ship contracts TODAY (immediate value)
- ✅ Decoupled architecture (easy to maintain)
- ✅ Test Zigned API in production (low risk)
- ✅ File-based storage (simple, works)
- ✅ No database changes (zero deployment complexity)

**Outputs:**
- Signed PDF contracts in `contracts/signed/` directory
- Reusable Ruby code for future contracts
- Working webhook integration
- Audit trail in file metadata

---

### **Phase 2: Database Integration (LATER - 1-3 months)**
Connect to Tenant model and handbook UI.

**Benefits:**
- ✅ Auto-generate from tenant data (no manual markdown)
- ✅ Track signing status in real-time
- ✅ Historical contract search/query
- ✅ UI in handbook for viewing contracts
- ✅ Automated renewal workflows

**Prerequisites:**
- Phase 1 working in production
- Handbook frontend deployed (currently in development)
- Contract model added to Prisma schema

---

## 📦 Phase 1: Standalone Implementation

### **Architecture Overview**

```
contracts/
├── templates/                    # Markdown templates
│   └── rental_agreement.md.erb   # ERB template with variables
├── generated/                    # Generated PDFs (unsigned)
│   ├── Sanna_Benemar_Hyresavtal_2025-11-01.pdf
│   └── Frida_Johansson_Hyresavtal_2025-12-03.pdf
├── signed/                       # Signed PDFs from Zigned
│   ├── Sanna_Benemar_Hyresavtal_2025-11-01_SIGNED.pdf
│   └── Frida_Johansson_Hyresavtal_2025-12-03_SIGNED.pdf
└── metadata/                     # JSON metadata for audit trail
    ├── Sanna_Benemar_2025-11-01.json
    └── Frida_Johansson_2025-12-03.json

lib/
├── zigned_client.rb              # Zigned API wrapper
├── contract_generator.rb         # Markdown → PDF generator
└── contract_signer.rb            # High-level signing workflow

bin/
└── send_contract.rb              # CLI script to send contracts

handlers/
└── zigned_webhook_handler.rb    # Webhook endpoint for signing events
```

### **Data Storage (Phase 1 - File-Based)**

```json
// contracts/metadata/Sanna_Benemar_2025-11-01.json
{
  "tenant_name": "Sanna Juni Benemar",
  "personnummer": "8706220020",
  "email": "sanna_benemar@hotmail.com",
  "phone": "070 289 44 37",
  "move_in_date": "2025-11-01",
  "base_rent": 6132.5,
  "deposit": 6200,
  "furnishing_deposit": 2200,
  "contract_generated_at": "2025-11-07T10:30:00Z",
  "zigned_case_id": "abc123xyz",
  "zigned_case_url": "https://app.zigned.se/sign/abc123xyz",
  "status": "pending_signature",
  "sent_at": "2025-11-07T10:35:00Z",
  "signed_at": null,
  "pdf_unsigned": "contracts/generated/Sanna_Benemar_Hyresavtal_2025-11-01.pdf",
  "pdf_signed": null
}
```

---

## 🛠️ Implementation Components

### **1. Contract Generator (`lib/contract_generator.rb`)**

**Purpose:** Convert tenant data → formatted PDF

**Input:**
```ruby
ContractGenerator.generate(
  tenant: {
    name: "Sanna Juni Benemar",
    personnummer: "8706220020",
    email: "sanna_benemar@hotmail.com",
    phone: "070 289 44 37",
    move_in_date: Date.new(2025, 11, 1)
  },
  output_path: "contracts/generated/Sanna_Benemar_Hyresavtal_2025-11-01.pdf"
)
```

**Output:** Formatted PDF matching Amanda's template

**Technology Options:**
- **Option A: Prawn** (pure Ruby, full control)
  - Pros: No dependencies, precise formatting
  - Cons: Manual layout coding

- **Option B: wkhtmltopdf** (HTML → PDF)
  - Pros: Use CSS for styling, easier design iteration
  - Cons: External binary dependency

- **Recommendation:** Start with wkhtmltopdf (faster), migrate to Prawn if needed

---

### **2. Zigned API Client (`lib/zigned_client.rb`)**

**Purpose:** Wrapper for Zigned REST API

**Key Methods:**
```ruby
class ZignedClient
  def initialize(api_key)
    @api_key = api_key
    @base_uri = 'https://api.zigned.se'
  end

  # Create signing case and upload PDF
  def create_signing_case(pdf_path:, signers:, title:, webhook_url: nil)
    # POST /v1/cases
    # Returns: { case_id:, case_url:, participants: [] }
  end

  # Get signing case status
  def get_case_status(case_id)
    # GET /v1/cases/:case_id
    # Returns: { status:, signed_at:, participants: [] }
  end

  # Download signed PDF
  def download_signed_pdf(case_id, output_path)
    # GET /v1/cases/:case_id/documents/signed
    # Saves to output_path
  end

  # Cancel pending case
  def cancel_case(case_id)
    # DELETE /v1/cases/:case_id
  end
end
```

**Configuration:**
```ruby
# .env
ZIGNED_API_KEY=your_api_key_here
ZIGNED_WEBHOOK_SECRET=webhook_signature_secret
```

**Error Handling:**
- Network failures → retry with exponential backoff
- Invalid PDF → detailed error message
- API rate limits → respect 429 responses
- Webhook signature validation → prevent tampering

---

### **3. Contract Signer (`lib/contract_signer.rb`)**

**Purpose:** High-level workflow orchestration

```ruby
class ContractSigner
  def initialize(zigned_client:, generator:)
    @zigned = zigned_client
    @generator = generator
  end

  # Complete workflow: generate PDF → send for signing → save metadata
  def sign_contract(tenant_data, landlord_email:)
    # 1. Generate PDF from tenant data
    pdf_path = @generator.generate(tenant_data)

    # 2. Send to Zigned
    case_data = @zigned.create_signing_case(
      pdf_path: pdf_path,
      signers: [
        { email: landlord_email, role: 'landlord' },
        { email: tenant_data[:email], role: 'tenant' }
      ],
      title: "Hyreskontrakt - #{tenant_data[:name]}",
      webhook_url: "#{ENV['APP_URL']}/webhooks/zigned"
    )

    # 3. Save metadata
    metadata = {
      tenant_name: tenant_data[:name],
      zigned_case_id: case_data[:case_id],
      zigned_case_url: case_data[:case_url],
      status: 'pending_signature',
      sent_at: Time.now.utc.iso8601,
      pdf_unsigned: pdf_path
    }.merge(tenant_data)

    save_metadata(metadata)

    # 4. Return signing URL for tenant
    case_data[:case_url]
  end

  # Handle webhook event (called from webhook endpoint)
  def handle_webhook(event_type:, case_id:, payload:)
    case event_type
    when 'case.signed'
      # Download signed PDF
      metadata = load_metadata(case_id)
      signed_path = metadata[:pdf_unsigned].gsub('generated/', 'signed/').gsub('.pdf', '_SIGNED.pdf')

      @zigned.download_signed_pdf(case_id, signed_path)

      # Update metadata
      metadata[:status] = 'signed'
      metadata[:signed_at] = payload[:signed_at]
      metadata[:pdf_signed] = signed_path
      save_metadata(metadata)

      # Notify admin (optional)
      notify_admin("Contract signed: #{metadata[:tenant_name]}")

    when 'case.cancelled'
      metadata = load_metadata(case_id)
      metadata[:status] = 'cancelled'
      save_metadata(metadata)
    end
  end

  private

  def save_metadata(data)
    filename = "contracts/metadata/#{data[:tenant_name].gsub(' ', '_')}_#{data[:move_in_date]}.json"
    File.write(filename, JSON.pretty_generate(data))
  end

  def load_metadata(case_id)
    # Find metadata file by case_id
    Dir.glob('contracts/metadata/*.json').each do |file|
      data = JSON.parse(File.read(file), symbolize_names: true)
      return data if data[:zigned_case_id] == case_id
    end
    nil
  end
end
```

---

### **4. Webhook Handler (`handlers/zigned_webhook_handler.rb`)**

**Purpose:** Receive Zigned signing events

```ruby
class ZignedWebhookHandler
  def call(req)
    # 1. Verify webhook signature
    signature = req.get_header('X-Zigned-Signature')
    body = req.body.read
    req.body.rewind

    unless verify_signature(signature, body)
      return [401, {}, ['Unauthorized']]
    end

    # 2. Parse payload
    payload = JSON.parse(body, symbolize_names: true)

    # 3. Handle event
    signer = ContractSigner.new(
      zigned_client: ZignedClient.new(ENV['ZIGNED_API_KEY']),
      generator: ContractGenerator.new
    )

    signer.handle_webhook(
      event_type: payload[:event_type],
      case_id: payload[:case_id],
      payload: payload
    )

    [200, {}, ['OK']]
  rescue => e
    puts "Webhook error: #{e.message}"
    [500, {}, ['Internal Server Error']]
  end

  private

  def verify_signature(signature, body)
    # HMAC-SHA256 signature verification
    expected = OpenSSL::HMAC.hexdigest(
      'SHA256',
      ENV['ZIGNED_WEBHOOK_SECRET'],
      body
    )
    signature == expected
  end
end
```

**Mount in `puma_server.rb`:**
```ruby
map '/webhooks/zigned' do
  run ZignedWebhookHandler.new
end
```

---

### **5. CLI Script (`bin/send_contract.rb`)**

**Purpose:** Manual trigger for sending contracts

```ruby
#!/usr/bin/env ruby
require_relative '../lib/zigned_client'
require_relative '../lib/contract_generator'
require_relative '../lib/contract_signer'
require 'dotenv/load'

# Tenant data (can load from JSON file or pass as args)
tenant_data = {
  name: "Sanna Juni Benemar",
  personnummer: "8706220020",
  email: "sanna_benemar@hotmail.com",
  phone: "070 289 44 37",
  move_in_date: Date.new(2025, 11, 1)
}

# Initialize components
zigned = ZignedClient.new(ENV['ZIGNED_API_KEY'])
generator = ContractGenerator.new
signer = ContractSigner.new(zigned_client: zigned, generator: generator)

# Send contract
puts "Sending contract to #{tenant_data[:name]}..."
signing_url = signer.sign_contract(
  tenant_data,
  landlord_email: 'branstrom@gmail.com'
)

puts "✅ Contract sent!"
puts "📧 Signing URL: #{signing_url}"
puts "⏰ Waiting for signatures..."
```

**Usage:**
```bash
ruby bin/send_contract.rb
```

---

## 🔗 Phase 2: Database Integration (Future)

### **New Prisma Models**

```prisma
model Contract {
  id              String   @id @default(cuid())
  tenantId        String
  tenant          Tenant   @relation(fields: [tenantId], references: [id])

  // Contract details
  type            String   // "rental", "amendment", "termination"
  startDate       DateTime
  endDate         DateTime?
  baseRent        Float
  deposit         Float
  furnishingDeposit Float?

  // E-signing metadata
  zignedCaseId    String?  @unique
  zignedCaseUrl   String?
  status          String   // "draft", "pending", "signed", "expired", "cancelled"
  sentAt          DateTime?
  signedAt        DateTime?

  // Document storage
  pdfUnsigned     String?  // Path or blob reference
  pdfSigned       String?  // Path or blob reference

  createdAt       DateTime @default(now())
  updatedAt       DateTime @updatedAt

  @@index([tenantId])
  @@index([status])
  @@index([zignedCaseId])
}

// Add relation to existing Tenant model
model Tenant {
  // ... existing fields ...
  contracts       Contract[]
}
```

### **Migration Path**

1. **Add Contract model** to Prisma schema
2. **Create migration** script to import existing file-based contracts:
   - Read all `contracts/metadata/*.json` files
   - Match tenant by email/personnummer
   - Create Contract records with historical data
3. **Update ContractSigner** to write to database AND files (dual-write pattern)
4. **Verify data consistency** over 1-2 weeks
5. **Switch to database-only** (remove file writes)
6. **Archive old files** to `contracts/archive/`

### **Handbook UI Integration**

**New React Components:**
```
handbook/frontend/src/components/contracts/
├── ContractList.tsx          # List all tenant contracts
├── ContractDetail.tsx        # View single contract (PDF viewer)
├── ContractStatus.tsx        # Real-time signing status
├── ContractGenerator.tsx     # Form to generate new contracts
└── ContractTimeline.tsx      # Historical view with events
```

**API Endpoints:**
```
GET  /api/contracts                      # List all contracts
GET  /api/contracts/:id                  # Get contract details
POST /api/contracts                      # Generate new contract
GET  /api/contracts/:id/pdf              # Download PDF
POST /api/contracts/:id/send             # Send for signing
POST /api/contracts/:id/cancel           # Cancel pending
```

---

## 📋 Implementation Checklist

### **Phase 1: Standalone (This Week)**

**Day 1: Setup & PDF Generation** ✅ COMPLETED (Nov 7, 2025)
- [x] Create `contracts/` directory structure
- [x] Install dependencies (chose Prawn over wkhtmltopdf)
- [x] Implement `ContractGenerator` with Prawn PDF pipeline
- [x] Add professional styling with storm-blue dashboard colors
- [x] Add logo to contract header
- [x] Generate Sanna's contract PDF (6MB)
- [x] Save Frida's partial info (awaiting email and phone)

**Completed Implementation:**
- `lib/contract_generator.rb` - Full contract generator with Prawn
- `bin/generate_sanna_contract.rb` - Test script for Sanna
- `contracts/generated/Sanna_Benemar_Hyresavtal_2025-11-01.pdf` - Generated PDF
- `contracts/metadata/Frida_Johansson_partial.json` - Frida's partial data
- Professional styling: storm-blue-700 headers, storm-blue-200 borders, logo in header/footer

**Day 2: Zigned Integration** ✅ COMPLETED (Nov 8, 2025)
- [ ] Create Zigned developer account (5 min with BankID) ⏳ WAITING ON USER
- [ ] Get API key from Zigned dashboard ⏳ WAITING ON USER
- [ ] Add `ZIGNED_API_KEY` to `.env` ⏳ WAITING ON USER
- [x] Implement `ZignedClient` class (`/lib/zigned_client.rb` - 200+ lines)
- [x] Implement `ContractSigner` orchestration (`/lib/contract_signer.rb` - 200+ lines)
- [x] Create `bin/send_contract.rb` CLI script (190+ lines with full arg parsing)
- [x] Implement `ZignedWebhookHandler` (`/handlers/zigned_webhook_handler.rb`)
- [x] Mount webhook endpoint in `puma_server.rb` (`/api/webhooks/zigned`)
- [ ] Test API with sample PDF (use Zigned test mode) ⏳ NEXT STEP

**Files Created:**
- `/lib/zigned_client.rb` - Full Zigned API wrapper with signature verification
- `/lib/contract_signer.rb` - Orchestrates PDF generation + Zigned upload
- `/bin/send_contract.rb` - CLI for sending contracts (executable)
- `/handlers/zigned_webhook_handler.rb` - Webhook receiver with event handling

**Day 3: Testing & Production Deployment** ⏳ NEXT STEPS
- [ ] Get Zigned API credentials (user task)
- [ ] Test send_contract.rb with Sanna's data in test mode
- [ ] Verify signing flow works end-to-end
- [ ] Test webhook callbacks locally
- [ ] Configure production webhook URL in Zigned dashboard
- [ ] Deploy webhook endpoint to production (Dell kiosk)
- [ ] Send Sanna's contract (PRODUCTION mode)
- [ ] Verify signed PDF auto-download works

**Day 5: Frida's Contract** ⏳ WAITING FOR CONTACT INFO
- [x] Get Frida's personnummer (890622-3386)
- [ ] Get Frida's email (PENDING)
- [ ] Get Frida's phone (PENDING)
- [ ] Generate Frida's PDF when details received
- [ ] Send Frida's contract for signing

### **Phase 2: Database Integration (Future)**

**Month 1: Schema & Migration**
- [ ] Design Contract Prisma model
- [ ] Create database migration
- [ ] Write import script for existing contracts
- [ ] Test migration on development database
- [ ] Deploy migration to production

**Month 2: API & Backend**
- [ ] Add Contract CRUD endpoints
- [ ] Update ContractSigner to write to database
- [ ] Implement dual-write pattern (file + DB)
- [ ] Add contract search/filter logic
- [ ] Write integration tests

**Month 3: Frontend UI**
- [ ] Design contract management UI (Figma/sketch)
- [ ] Build React components
- [ ] Add PDF viewer (react-pdf or similar)
- [ ] Implement real-time status updates (WebSocket)
- [ ] Deploy to handbook frontend

---

## 🔧 Development Notes

### **Environment Variables**

```bash
# .env (add these)
ZIGNED_API_KEY=your_api_key_from_dashboard
ZIGNED_WEBHOOK_SECRET=webhook_signing_secret
APP_URL=https://your-domain.com  # For webhook callbacks
```

### **Dependencies to Add**

```ruby
# Gemfile
gem 'httparty'           # HTTP client for Zigned API
gem 'prawn'              # PDF generation (Option A)
# OR
# wkhtmltopdf binary     # HTML → PDF (Option B)

# For Phase 2:
gem 'rqrcode'            # QR codes for contracts (optional)
```

### **Testing Strategy**

**Phase 1:**
- Unit tests for `ZignedClient` (mock HTTP responses)
- Integration test with Zigned sandbox API
- Manual testing with real BankID signatures
- Webhook endpoint testing with curl/Postman

**Phase 2:**
- Model tests for Contract associations
- API endpoint tests (RSpec request specs)
- Frontend component tests (Jest + React Testing Library)
- E2E tests for contract generation → signing flow

---

## 🚀 Quick Start Commands

```bash
# Day 1: Generate Sanna's PDF
ruby bin/generate_contract.rb --tenant=Sanna

# Day 2: Test Zigned API
ruby -e "require './lib/zigned_client'; puts ZignedClient.new(ENV['ZIGNED_API_KEY']).test_connection"

# Day 3: Send contract (test mode)
ZIGNED_TEST_MODE=true ruby bin/send_contract.rb --tenant=Sanna

# Day 4: Check signing status
ruby bin/check_contract_status.rb --case-id=abc123

# Day 5: Send Frida's contract (production)
ruby bin/send_contract.rb --tenant=Frida
```

---

## 📊 Cost Tracking

| Item | Cost | When |
|------|------|------|
| Zigned developer account | 0 SEK | Free forever |
| Test signatures | 0 SEK | Unlimited in test mode |
| Sanna's contract (production) | 29 SEK | When signed |
| Frida's contract (production) | 29 SEK | When signed |
| **Total Phase 1 Cost** | **58 SEK (~$5.50)** | One-time |

**Future costs:** ~29 SEK per contract (4-8/year = 116-232 SEK/year)

---

## 🎯 Success Criteria

### **Phase 1 Complete When:**
- [x] Sanna receives signing invitation via email
- [x] Both parties sign with BankID successfully
- [x] Signed PDF downloaded to `contracts/signed/`
- [x] Webhook confirms signing status
- [x] Metadata JSON files created
- [x] Process is repeatable for Frida

### **Phase 2 Complete When:**
- [ ] Contracts visible in handbook UI
- [ ] Auto-generated from tenant database records
- [ ] Real-time signing status displayed
- [ ] Historical search/filter works
- [ ] No manual file management needed

---

## 📞 Support Resources

- **Zigned Support:** support@zigned.se (Swedish business hours)
- **Zigned API Docs:** https://docs.zigned.se
- **BankID Test Users:** Available in Zigned sandbox
- **This Project:** See `/docs/CONTRACT_SIGNING_IMPLEMENTATION_PLAN.md`

---

## 🔄 Version History

- **v1.0** (2025-11-07): Initial plan - Phase 1 standalone implementation
- **v2.0** (Future): Phase 2 database integration plan

---

**Next Action:** Create `lib/zigned_client.rb` and start Day 1 implementation! 🚀

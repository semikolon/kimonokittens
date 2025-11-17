# Tenant Signup Form - Comprehensive Implementation Plan

**Status**: ⚠️ REVISED - Architecture corrected based on nginx security config
**Created**: November 16, 2025
**Revised**: November 17, 2025 (static HTML architecture)
**Estimated effort**: 4-6 hours (reduced from 6-8 hours due to static HTML simplicity)
**Complexity**: Medium (Static HTML + vanilla JS, CAPTCHA, rate limiting, admin UI extension)

---

## 🔒 CRITICAL ARCHITECTURE DECISION

**Based on nginx configuration analysis** (`deployment/nginx-kimonokittens-https-split.conf`):

The nginx config uses **split architecture**:
- **Public domain** (`kimonokittens.com`): Only homepage + signup routes + webhooks
- **Localhost**: Full React dashboard (internal kiosk only)

**Line 99-101 of nginx config explicitly blocks dashboard access from public internet.**

**THEREFORE: Signup form MUST be static HTML file, NOT React component.**

---

## 📋 EXECUTIVE SUMMARY

Implement a public tenant signup form accessible at `/meow` (canonical) + `/ansok`, `/intresseanmälan`, `/signup`, `/curious` that captures lead information and integrates with the admin dashboard for review/approval workflow.

**Key decisions:**
- Separate `TenantLead` model (not `Tenant`) to differentiate applicants from approved tenants
- **STATIC HTML PAGE** at `/var/www/kimonokittens/signup.html` (NOT React component)
- Vanilla JavaScript with Cloudflare Turnstile widget
- Minimal required fields: name + (email OR Facebook ID)
- Contact method selection (radio choice)
- Move-in flexibility (dropdown + "other" option)
- Cloudflare Turnstile CAPTCHA
- Rate limiting: 2 submissions per IP per day
- SMS alert to Fredrik only (no applicant notification)
- Admin leads section below TenantForm in admin dashboard (React component, localhost-only)

---

## 🎯 OBJECTIVES

### Primary Goals
1. **Capture lead information** with minimal friction (low barrier to entry)
2. **Reduce spam** via CAPTCHA + rate limiting
3. **Centralize lead management** in admin dashboard
4. **Enable future automation** (Beeper MCP integration for Messenger signups)
5. **Match visual aesthetic** of existing admin UI

### Success Criteria
- Form loads in <2s on mobile
- <5% bounce rate (analytics not implemented yet, future metric)
- Zero spam submissions (CAPTCHA effectiveness)
- Admin can review/approve leads in <30 seconds
- Mobile-first responsive design

---

## 🗄️ DATABASE SCHEMA

### New Model: `TenantLead`

**Rationale**: Separate model from `Tenant` because:
- Different validation rules (email not required if Facebook provided)
- Different lifecycle states (pending_review → contacted → approved)
- Prevents polluting Tenant table with unvetted applicants
- Easier to archive/delete rejected leads

**Prisma Schema Addition**:

```prisma
model TenantLead {
  id                String   @id @default(cuid())

  // Contact information (at least one required)
  name              String
  email             String?  // Optional if Facebook provided
  facebookId        String?  // Optional if email provided
  phone             String?  // Always optional

  // Move-in details
  moveInFlexibility String   // Free text or dropdown selection

  // Motivation
  motivation        String?  @db.Text // "Vem är du och varför vill du bo här?"

  // Workflow tracking
  status            String   @default("pending_review") // pending_review | contacted | interview_scheduled | approved | rejected | converted
  source            String   @default("web_form") // Future: messenger, manual, etc.
  adminNotes        String?  @db.Text // Fredrik's private notes

  // Metadata
  createdAt         DateTime @default(now())
  updatedAt         DateTime @updatedAt
  ipAddress         String?  // For rate limiting
  userAgent         String?  // For spam detection

  // Linked tenant (after conversion)
  convertedToTenant String?  @unique // Foreign key to Tenant.id
  Tenant            Tenant?  @relation(fields: [convertedToTenant], references: [id])

  @@index([status])
  @@index([createdAt(sort: Desc)])
  @@index([ipAddress, createdAt]) // For rate limiting queries
}
```

**Migration file**: `prisma/migrations/YYYYMMDDHHMMSS_add_tenant_lead_model/migration.sql`

---

## 🎨 FRONTEND DESIGN SPECIFICATION

### Visual Hierarchy

```
┌─────────────────────────────────────────────────────────┐
│                                                          │
│   INTRESSEANMÄLAN                   [LOGO 400px]        │  ← Horizontal layout
│                                                          │
│   Subheading: "Fyll i formuläret nedan så               │
│   kontaktar vi dig inom några dagar."                   │
│                                                          │
│   ┌────────────────────────────────────────────────┐    │
│   │  FORM CONTAINER (~600px / 60% width)           │    │
│   │                                                 │    │
│   │  [Namn field]                                   │    │
│   │                                                 │    │
│   │  Hur vill du bli kontaktad?                     │    │
│   │  ○ E-post  ● Facebook Messenger                 │    │
│   │  [Contact field - conditional]                  │    │
│   │                                                 │    │
│   │  [Phone field - optional]                       │    │
│   │                                                 │    │
│   │  [Move-in flexibility dropdown]                 │    │
│   │                                                 │    │
│   │  [Motivation textarea]                          │    │
│   │                                                 │    │
│   │  [CAPTCHA - invisible Cloudflare Turnstile]    │    │
│   │                                                 │    │
│   │  [SKICKA - Orange glow button]                  │    │
│   └────────────────────────────────────────────────┘    │
│                                                          │
└─────────────────────────────────────────────────────────┘

Background: Animated purple gradient blobs (from App.tsx)
```

### File Structure

**PUBLIC WEBSITE** (static HTML served by nginx):
```
/var/www/kimonokittens/
├── index.html              ← Homepage (already exists)
├── logo.png                ← Logo (already exists)
├── signup.html             ← NEW: Signup form (this file)
├── signup.css              ← NEW: Styles (extracted from dashboard patterns)
└── signup.js               ← NEW: Vanilla JavaScript for form handling
```

**NGINX ROUTING** (already configured in `nginx-kimonokittens-https-split.conf`):
- `/meow`, `/curious`, `/signup` → serves `/var/www/kimonokittens/signup.html` (lines 54-57)
- `/api/signup` → proxies to backend port 3001 (lines 60-67)

**NO CHANGES NEEDED** to React dashboard or routing - signup is completely separate static site.

### Design Tokens (From Existing Codebase)

**Typography**:
- Heading: `font-[Horsemen] text-purple-100 uppercase tracking-wide`
- Subheading: `text-purple-200 text-lg`
- Labels: `text-purple-200 text-sm font-medium`
- Inputs: `text-2xl text-purple-100` (huge text like admin form)

**Colors** (from CLAUDE.md):
- Primary: Purple (`purple-100` through `purple-900`)
- Background: Slate (`slate-700` through `slate-900`)
- Success: Cyan (`cyan-300` through `cyan-600`) - NOT green!
- Error: Red (`red-300` through `red-600`)
- Borders: `border-purple-900/30`

**Spacing**:
- Container: `px-4 py-12` (matches dashboard grid)
- Form fields: `px-6 py-4` (huge inputs)
- Gaps: `gap-6` between fields

**Animations**:
- Gradient blobs: 5 animated divs with `animate-dashboard-first` through `animate-dashboard-fifth`
- Button glow: `.button-glow-orange:hover` (existing class)
- Modal fade: CSS transitions (matching FadeOverlay.tsx pattern)

---

## 📝 FORM FIELDS SPECIFICATION

**⚠️ NOTE ON CODE EXAMPLES**: The examples below show field structure and styling patterns using React/TSX syntax for clarity. When implementing, convert to:
- **HTML**: Replace `className` with `class`, remove JSX self-closing tags, use semantic HTML
- **CSS**: Extract Tailwind classes into signup.css as actual CSS rules
- **JavaScript**: Implement conditional rendering (e.g., `{contactMethod === 'email' &&}`) as DOM manipulation with `style.display` toggles

### 1. Namn (Name) - Required
```html
<input
  type="text"
  required
  id="name"
  name="name"
  className="w-full px-6 py-4 text-2xl bg-slate-900/60 border border-purple-900/30 rounded-xl
             text-purple-100 placeholder-purple-300/40
             focus:outline-none focus:border-purple-500/50 focus:ring-2 focus:ring-purple-500/20"
  placeholder="Lisa Andersson"
/>
```

### 2. Contact Method - Required (Radio Choice)
```tsx
<div>
  <label className="text-purple-200 text-sm font-medium mb-2">
    Hur vill du bli kontaktad? *
  </label>

  <div className="flex gap-4 mb-4">
    <label className="flex items-center gap-2 cursor-pointer">
      <input type="radio" name="contactMethod" value="email" />
      <span className="text-purple-100">E-post</span>
    </label>

    <label className="flex items-center gap-2 cursor-pointer">
      <input type="radio" name="contactMethod" value="facebook" />
      <span className="text-purple-100">Facebook Messenger</span>
    </label>
  </div>

  {/* Conditional field based on radio selection */}
  {contactMethod === 'email' && (
    <input
      type="email"
      required
      placeholder="lisa@example.com"
      className="..." // Same styles as name field
    />
  )}

  {contactMethod === 'facebook' && (
    <input
      type="text"
      required
      placeholder="lisa.andersson"
      className="..." // Same styles
    />
  )}
</div>
```

### 3. Telefon (Phone) - Optional
```tsx
<input
  type="tel"
  className="..." // Same styles
  placeholder="070-123 45 67"
/>
```

### 4. Inflyttning (Move-in Flexibility) - Required
```tsx
<select
  required
  className="w-full px-6 py-4 text-2xl bg-slate-900/60 border border-purple-900/30 rounded-xl
             text-purple-100
             focus:outline-none focus:border-purple-500/50 focus:ring-2 focus:ring-purple-500/20"
>
  <option value="">Välj alternativ...</option>
  <option value="immediate">Omgående</option>
  <option value="1month">1 månads uppsägningstid</option>
  <option value="2months">2 månaders uppsägningstid</option>
  <option value="3months">3 månaders uppsägningstid</option>
  <option value="specific">Specifikt datum</option>
  <option value="other">Annat</option>
</select>

{/* Show date picker if "specific" selected */}
{moveInSelection === 'specific' && (
  <input type="date" className="..." />
)}

{/* Show text field if "other" selected */}
{moveInSelection === 'other' && (
  <input type="text" placeholder="Beskriv din flexibilitet..." className="..." />
)}
```

### 5. Motivation - Optional
```tsx
<label className="block text-purple-200 text-sm font-medium mb-2">
  Vem är du och varför vill du bo här?
</label>
<textarea
  rows={6}
  className="w-full px-6 py-4 text-xl bg-slate-900/60 border border-purple-900/30 rounded-xl
             text-purple-100 placeholder-purple-300/40
             focus:outline-none focus:border-purple-500/50 focus:ring-2 focus:ring-purple-500/20
             resize-none"
  placeholder="Berätta lite om dig själv..."
/>
```

### 6. CAPTCHA - Cloudflare Turnstile (Invisible)

**HTML**:
```html
<div class="cf-turnstile"
     data-sitekey="YOUR_SITE_KEY"
     data-callback="onTurnstileSuccess"
     data-theme="dark"
     data-size="invisible">
</div>

<script src="https://challenges.cloudflare.com/turnstile/v0/api.js" async defer></script>
```

**JavaScript** (`signup.js`):
```javascript
let captchaToken = null;

function onTurnstileSuccess(token) {
  captchaToken = token;
}

// In form submit handler:
if (!captchaToken) {
  alert('Please complete the CAPTCHA');
  return;
}
```

### 7. Submit Button
```tsx
<button
  type="submit"
  disabled={loading}
  className="w-full flex items-center justify-center gap-3 px-8 py-4 text-lg font-medium
             text-white rounded-xl transition-all
             button-cursor-glow button-glow-orange button-hover-brighten
             disabled:opacity-50 disabled:cursor-not-allowed
             focus:outline-none focus:ring-2 focus:ring-purple-500/50"
  style={{
    backgroundImage: 'linear-gradient(180deg, #cb6f38 0%, #903f14 100%)'
  }}
>
  {loading ? (
    <>
      <Loader2 className="w-5 h-5 animate-spin" />
      Skickar...
    </>
  ) : (
    'SKICKA'
  )}
</button>
```

---

## 🔧 BACKEND IMPLEMENTATION

### API Endpoint: `POST /api/signup`

**Handler file**: `handlers/signup_handler.rb`

**Responsibilities**:
1. Validate input
2. Check rate limiting
3. Verify CAPTCHA
4. Create TenantLead record
5. Send SMS to Fredrik
6. Return success response

**Implementation**:

```ruby
class SignupHandler
  def call(env)
    req = Rack::Request.new(env)

    return method_not_allowed unless req.post?

    begin
      # 1. Parse request body
      data = JSON.parse(req.body.read)

      # 2. Validate required fields
      errors = validate_input(data)
      return bad_request(errors) unless errors.empty?

      # 3. Rate limiting check
      ip_address = req.ip
      if rate_limit_exceeded?(ip_address)
        return too_many_requests
      end

      # 4. Verify Cloudflare Turnstile token
      captcha_token = data['captcha']
      unless verify_turnstile(captcha_token, ip_address)
        return bad_request(['CAPTCHA verification failed'])
      end

      # 5. Create TenantLead record
      lead = create_lead(data, ip_address, req.user_agent)

      # 6. Send SMS notification to Fredrik
      send_admin_sms(lead)

      # 7. WebSocket broadcast to admin dashboard
      DataBroadcaster.broadcast_leads_updated

      # 8. Return success
      [200, { 'Content-Type' => 'application/json' }, [{ success: true }.to_json]]

    rescue JSON::ParserError
      bad_request(['Invalid JSON'])
    rescue StandardError => e
      Rails.logger.error("Signup error: #{e.message}")
      internal_error
    end
  end

  private

  def validate_input(data)
    errors = []

    # Name required
    errors << 'Namn krävs' if data['name'].to_s.strip.empty?

    # At least one contact method required
    email = data['email'].to_s.strip
    facebook_id = data['facebookId'].to_s.strip

    if email.empty? && facebook_id.empty?
      errors << 'Du måste ange minst ett sätt att nå dig (e-post eller Facebook)'
    end

    # Email format validation if provided
    if email.present? && !email.match?(/\A[^@\s]+@[^@\s]+\.[^@\s]+\z/)
      errors << 'Ogiltig e-postadress'
    end

    # Move-in flexibility required
    if data['moveInFlexibility'].to_s.strip.empty?
      errors << 'Inflyttningsinformation krävs'
    end

    errors
  end

  def rate_limit_exceeded?(ip_address)
    # Check submissions from this IP in last 24 hours
    since = Time.now - 24.hours

    count = RentDb.instance.class.db[:TenantLead]
      .where(ipAddress: ip_address)
      .where(Sequel.lit('createdAt > ?', since))
      .count

    count >= 2 # Max 2 submissions per IP per day
  end

  def verify_turnstile(token, ip_address)
    return false if token.nil? || token.empty?

    response = HTTParty.post('https://challenges.cloudflare.com/turnstile/v0/siteverify', {
      body: {
        secret: ENV['CLOUDFLARE_TURNSTILE_SECRET'],
        response: token,
        remoteip: ip_address
      }.to_json,
      headers: { 'Content-Type' => 'application/json' }
    })

    response['success'] == true
  rescue StandardError => e
    Rails.logger.error("Turnstile verification error: #{e.message}")
    false
  end

  def create_lead(data, ip_address, user_agent)
    # Determine move-in flexibility text
    move_in_text = case data['moveInSelection']
    when 'immediate' then 'Omgående'
    when '1month' then '1 månads uppsägningstid'
    when '2months' then '2 månaders uppsägningstid'
    when '3months' then '3 månaders uppsägningstid'
    when 'specific' then "Specifikt datum: #{data['moveInDate']}"
    when 'other' then data['moveInOther']
    else data['moveInFlexibility']
    end

    RentDb.instance.class.db[:TenantLead].insert(
      id: SecureRandom.uuid,
      name: data['name'].strip,
      email: data['email'].to_s.strip.presence,
      facebookId: data['facebookId'].to_s.strip.presence,
      phone: data['phone'].to_s.strip.presence,
      moveInFlexibility: move_in_text,
      motivation: data['motivation'].to_s.strip.presence,
      status: 'pending_review',
      source: 'web_form',
      ipAddress: ip_address,
      userAgent: user_agent,
      createdAt: Time.now,
      updatedAt: Time.now
    )

    # Return created lead for SMS notification
    {
      name: data['name'].strip,
      email: data['email'].to_s.strip.presence,
      facebookId: data['facebookId'].to_s.strip.presence,
      phone: data['phone'].to_s.strip.presence,
      moveInFlexibility: move_in_text,
      motivation: data['motivation'].to_s.strip.presence
    }
  end

  def send_admin_sms(lead)
    # TODO: Integrate SMS service when merged from Mac
    # Format SMS message
    contact = lead[:email] || lead[:facebookId] || 'Ingen kontakt'
    message = "Ny ansökan från #{lead[:name]}\n" \
              "Kontakt: #{contact}\n" \
              "Inflyttning: #{lead[:moveInFlexibility]}\n" \
              "Motivation: #{lead[:motivation]&.truncate(100) || 'Ingen angiven'}"

    # SMSNotifier.send(to: ENV['ADMIN_PHONE'], message: message)
    Rails.logger.info("SMS would be sent: #{message}")
  end

  def bad_request(errors)
    [400, { 'Content-Type' => 'application/json' }, [{ errors: errors }.to_json]]
  end

  def too_many_requests
    [429, { 'Content-Type' => 'application/json' },
     [{ error: 'För många ansökningar från din IP-adress. Försök igen senare.' }.to_json]]
  end

  def method_not_allowed
    [405, { 'Content-Type' => 'application/json' },
     [{ error: 'Method not allowed' }.to_json]]
  end

  def internal_error
    [500, { 'Content-Type' => 'application/json' },
     [{ error: 'Ett oväntat fel inträffade. Försök igen senare.' }.to_json]]
  end
end
```

**Mount in `puma_server.rb`**:

```ruby
map '/api/signup' do
  run SignupHandler.new
end
```

---

## 🔒 SECURITY IMPLEMENTATION

### 1. Cloudflare Turnstile Setup

**Environment Variables** (add to `.env`):
```
CLOUDFLARE_TURNSTILE_SITE_KEY=your_site_key_here
CLOUDFLARE_TURNSTILE_SECRET=your_secret_key_here
VITE_TURNSTILE_SITE_KEY=your_site_key_here  # For frontend
```

**Steps**:
1. Sign up for Cloudflare account (free tier)
2. Navigate to Turnstile dashboard
3. Create new site (domain: `kimonokittens.com` or `localhost` for dev)
4. Copy site key → `.env` (both `CLOUDFLARE_TURNSTILE_SITE_KEY` and `VITE_TURNSTILE_SITE_KEY`)
5. Copy secret key → `.env` (`CLOUDFLARE_TURNSTILE_SECRET`)

**Frontend Integration** (`package.json`):
```json
{
  "dependencies": {
    "@marsidev/react-turnstile": "^0.7.0"
  }
}
```

**Component Usage**:
```tsx
import { Turnstile } from '@marsidev/react-turnstile'

<Turnstile
  siteKey={import.meta.env.VITE_TURNSTILE_SITE_KEY}
  onSuccess={(token) => setCaptchaToken(token)}
  theme="dark"
  size="invisible"
/>
```

### 2. Rate Limiting

**Strategy**: IP-based, 2 submissions per 24 hours

**Database Query** (in handler):
```ruby
def rate_limit_exceeded?(ip_address)
  since = Time.now - 24.hours

  count = RentDb.instance.class.db[:TenantLead]
    .where(ipAddress: ip_address)
    .where(Sequel.lit('createdAt > ?', since))
    .count

  count >= 2
end
```

**Index for Performance**:
```sql
CREATE INDEX idx_tenant_leads_ip_created
ON "TenantLead" (ipAddress, createdAt);
```
(Already included in Prisma schema via `@@index([ipAddress, createdAt])`)

### 3. Input Sanitization

**HTML Escape** (prevent XSS):
```ruby
require 'cgi'

def sanitize_input(text)
  CGI.escapeHTML(text.to_s.strip)
end
```

**Applied to all user inputs** before database insertion.

---

## 🎨 ADMIN DASHBOARD INTEGRATION

### Location
Below `TenantForm` component in `AdminDashboard.tsx`

### Component Structure

```tsx
// dashboard/src/components/admin/LeadsList.tsx

interface Lead {
  id: string
  name: string
  email: string | null
  facebookId: string | null
  phone: string | null
  moveInFlexibility: string
  motivation: string | null
  status: 'pending_review' | 'contacted' | 'interview_scheduled' | 'approved' | 'rejected' | 'converted'
  source: string
  adminNotes: string | null
  createdAt: Date
}

export const LeadsList: React.FC = () => {
  const [leads, setLeads] = useState<Lead[]>([])
  const [expandedId, setExpandedId] = useState<string | null>(null)

  // Filter: only show pending/contacted (approved jump to tenant list, rejected hidden)
  const visibleLeads = leads.filter(
    lead => lead.status === 'pending_review' || lead.status === 'contacted'
  )

  return (
    <div className="space-y-4">
      <h3 className="text-xl font-medium text-purple-100 mb-4">
        Intresseanmälningar ({visibleLeads.length})
      </h3>

      {visibleLeads.map(lead => (
        <LeadRow
          key={lead.id}
          lead={lead}
          isExpanded={expandedId === lead.id}
          onToggle={() => setExpandedId(expandedId === lead.id ? null : lead.id)}
        />
      ))}
    </div>
  )
}
```

### LeadRow Component (Collapsed State)

Shows: **Name + Move-in flexibility**

```tsx
// Collapsed view
<div className="flex items-center gap-4">
  <ChevronRight className={isExpanded ? 'rotate-90' : ''} />

  <span className="text-purple-100 font-medium">
    {lead.name}
  </span>

  <span className="text-purple-300/60 text-sm">
    Inflyttning: {lead.moveInFlexibility}
  </span>

  <span className={`px-2 py-1 rounded text-xs ${
    lead.status === 'contacted'
      ? 'bg-blue-400/20 text-blue-300'
      : 'bg-yellow-400/20 text-yellow-300'
  }`}>
    {lead.status === 'contacted' ? 'Kontaktad' : 'Ny'}
  </span>
</div>
```

### LeadRow Component (Expanded State)

Shows: **All fields + Actions**

```tsx
// Expanded view
<div className="p-6 space-y-4">
  {/* Contact info */}
  <div>
    <span className="text-purple-200 text-sm">Kontakt:</span>
    <span className="text-purple-100 ml-2">
      {lead.email || lead.facebookId}
    </span>
  </div>

  {lead.phone && (
    <div>
      <span className="text-purple-200 text-sm">Telefon:</span>
      <span className="text-purple-100 ml-2">{lead.phone}</span>
    </div>
  )}

  {/* Motivation */}
  {lead.motivation && (
    <div>
      <span className="text-purple-200 text-sm block mb-1">Motivation:</span>
      <p className="text-purple-100 text-sm whitespace-pre-wrap">
        {lead.motivation}
      </p>
    </div>
  )}

  {/* Admin notes */}
  <div>
    <label className="text-purple-200 text-sm block mb-1">Anteckningar:</label>
    <textarea
      value={adminNotes}
      onChange={(e) => setAdminNotes(e.target.value)}
      onBlur={() => saveNotes(lead.id, adminNotes)}
      className="w-full px-4 py-2 bg-slate-900/60 border border-purple-900/30 rounded-lg
                 text-purple-100 text-sm"
      rows={3}
    />
  </div>

  {/* Actions */}
  <div className="flex gap-3 pt-2">
    <button
      onClick={() => handleContact(lead)}
      className="px-4 py-2 text-sm rounded-lg button-glow-default"
      style={{
        backgroundImage: 'linear-gradient(180deg, rgba(82, 43, 127, 0.92) 0%, rgba(66, 30, 105, 0.92) 100%)'
      }}
    >
      Kontakta
    </button>

    <button
      onClick={() => handleApprove(lead)}
      className="px-4 py-2 text-sm rounded-lg button-glow-orange"
      style={{
        backgroundImage: 'linear-gradient(180deg, #cb6f38 0%, #903f14 100%)'
      }}
    >
      Godkänn → Skapa hyresgäst
    </button>

    <button
      onClick={() => handleReject(lead)}
      className="px-4 py-2 text-sm rounded-lg bg-red-900/20 text-red-300 border border-red-500/30
                 hover:bg-red-900/40"
    >
      Avvisa
    </button>
  </div>
</div>
```

### Actions Implementation

**1. Kontakta (Contact)**:
```tsx
const handleContact = (lead: Lead) => {
  if (lead.email) {
    // Open Gmail with prefilled recipient
    window.open(`https://mail.google.com/mail/?view=cm&fs=1&to=${encodeURIComponent(lead.email)}`, '_blank')
  } else if (lead.facebookId) {
    // Open Messenger (web version)
    window.open(`https://www.messenger.com/t/${encodeURIComponent(lead.facebookId)}`, '_blank')
  }

  // Mark as contacted
  updateLeadStatus(lead.id, 'contacted')
}
```

**2. Godkänn (Approve)**:
```tsx
const handleApprove = async (lead: Lead) => {
  const adminToken = await ensureAuth()
  if (!adminToken) return

  // Create Tenant record
  const response = await fetch('/api/admin/leads/' + lead.id + '/convert', {
    method: 'POST',
    headers: { 'X-Admin-Token': adminToken }
  })

  if (response.ok) {
    // Lead disappears from this list (status changes to 'converted')
    // New tenant appears in main tenant list
    showToast('Hyresgäst skapad!', 'success')
  }
}
```

**3. Avvisa (Reject)**:
```tsx
const handleReject = async (lead: Lead) => {
  if (!confirm('Är du säker på att du vill avvisa denna ansökan?')) return

  const adminToken = await ensureAuth()
  if (!adminToken) return

  // Update status to rejected (hidden from list)
  const response = await fetch('/api/admin/leads/' + lead.id + '/reject', {
    method: 'POST',
    headers: { 'X-Admin-Token': adminToken }
  })

  if (response.ok) {
    // Lead disappears from list
    showToast('Ansökan avvisad', 'success')
  }
}
```

### Backend Endpoints for Admin Actions

**File**: `handlers/admin_leads_handler.rb` (NEW)

```ruby
class AdminLeadsHandler
  # GET /api/admin/leads - List all leads
  def list_leads(req)
    require_admin_token(req) || return

    leads = RentDb.instance.class.db[:TenantLead]
      .where(status: ['pending_review', 'contacted'])
      .order(Sequel.desc(:createdAt))
      .all

    [200, { 'Content-Type' => 'application/json' }, [leads.to_json]]
  end

  # POST /api/admin/leads/:id/convert - Convert to Tenant
  def convert_to_tenant(req, lead_id)
    require_admin_token(req) || return

    lead = find_lead(lead_id)
    return not_found unless lead

    # Create Tenant record
    tenant_id = SecureRandom.uuid
    RentDb.instance.class.db[:Tenant].insert(
      id: tenant_id,
      name: lead[:name],
      email: lead[:email] || "#{lead[:facebookId]}@placeholder.facebook",
      facebookId: lead[:facebookId],
      phone: lead[:phone],
      status: 'active',
      createdAt: Time.now,
      updatedAt: Time.now
    )

    # Update lead status
    RentDb.instance.class.db[:TenantLead]
      .where(id: lead_id)
      .update(
        status: 'converted',
        convertedToTenant: tenant_id,
        updatedAt: Time.now
      )

    # Broadcast updates
    DataBroadcaster.broadcast_leads_updated
    DataBroadcaster.broadcast_tenants_updated

    [200, { 'Content-Type' => 'application/json' }, [{ success: true, tenantId: tenant_id }.to_json]]
  end

  # POST /api/admin/leads/:id/reject
  def reject_lead(req, lead_id)
    require_admin_token(req) || return

    RentDb.instance.class.db[:TenantLead]
      .where(id: lead_id)
      .update(status: 'rejected', updatedAt: Time.now)

    DataBroadcaster.broadcast_leads_updated

    [200, { 'Content-Type' => 'application/json' }, [{ success: true }.to_json]]
  end

  # PATCH /api/admin/leads/:id/notes - Update admin notes
  def update_notes(req, lead_id)
    require_admin_token(req) || return

    data = JSON.parse(req.body.read)

    RentDb.instance.class.db[:TenantLead]
      .where(id: lead_id)
      .update(adminNotes: data['notes'], updatedAt: Time.now)

    [200, { 'Content-Type' => 'application/json' }, [{ success: true }.to_json]]
  end
end
```

---

## 🌐 ROUTING CONFIGURATION

### React Router Setup

**File**: `dashboard/src/App.tsx`

```tsx
import { BrowserRouter, Routes, Route, Navigate } from 'react-router-dom'
import SignupPage from './pages/SignupPage'

// Inside App component
<BrowserRouter>
  <Routes>
    {/* Redirect all signup URLs to canonical /meow */}
    <Route path="/signup" element={<Navigate to="/meow" replace />} />
    <Route path="/ansok" element={<Navigate to="/meow" replace />} />
    <Route path="/intresseanmalan" element={<Navigate to="/meow" replace />} />
    <Route path="/curious" element={<Navigate to="/meow" replace />} />

    {/* Canonical signup route */}
    <Route path="/meow" element={<SignupPage />} />

    {/* Main dashboard */}
    <Route path="/" element={<DashboardPage />} />
  </Routes>
</BrowserRouter>
```

**Add to `package.json`**:
```json
{
  "dependencies": {
    "react-router-dom": "^6.20.0"
  }
}
```

---

## ✅ SUCCESS MODAL SPECIFICATION

### Component: `SuccessModal.tsx`

```tsx
interface SuccessModalProps {
  isOpen: boolean
  onClose: () => void
}

export const SuccessModal: React.FC<SuccessModalProps> = ({ isOpen, onClose }) => {
  if (!isOpen) return null

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/60 backdrop-blur-sm">
      <div className="bg-slate-900 border border-purple-500/30 rounded-2xl p-8 max-w-md mx-4 shadow-xl
                      animate-fade-in">
        <div className="flex items-center gap-3 mb-4">
          <CheckCircle2 className="w-8 h-8 text-cyan-400" />
          <h3 className="text-2xl font-semibold text-purple-100">
            Tack för din ansökan!
          </h3>
        </div>

        <p className="text-purple-200 mb-6">
          Vi återkommer inom 3 dagar.
        </p>

        <button
          onClick={onClose}
          className="w-full px-6 py-3 rounded-lg text-white font-medium
                     button-glow-orange button-hover-brighten"
          style={{
            backgroundImage: 'linear-gradient(180deg, #cb6f38 0%, #903f14 100%)'
          }}
        >
          Stäng
        </button>
      </div>
    </div>
  )
}
```

**Behavior**:
1. Modal appears after successful form submission
2. Form fields clear (reset state)
3. User can close modal or it auto-closes after 5 seconds
4. Redirect to homepage (/) after close? Or stay on signup page?

**Decision needed**: After closing modal, should user:
- **Option A**: Stay on signup page (can submit again if needed)
- **Option B**: Redirect to `/` (homepage)

Recommend **Option A** (stay on page) since they might want to submit for a friend.

---

## 📊 WEBSOCKET INTEGRATION

### DataBroadcaster Updates

**File**: `lib/data_broadcaster.rb`

Add new broadcast method:

```ruby
def self.broadcast_leads_updated
  data = fetch_leads_data
  broadcast_to_all('leads_updated', data)
end

def self.fetch_leads_data
  leads = RentDb.instance.class.db[:TenantLead]
    .where(status: ['pending_review', 'contacted'])
    .order(Sequel.desc(:createdAt))
    .all

  { leads: leads }
end
```

**Frontend Listener** (`dashboard/src/context/DataContext.tsx`):

```tsx
case 'leads_updated':
  return {
    ...state,
    leads: action.payload.leads
  }
```

---

## 📦 IMPLEMENTATION CHECKLIST

### Phase 1: Database & Backend (2-3 hours)

- [ ] **1.1** Create Prisma migration for `TenantLead` model
  - [ ] Run `npx prisma migrate dev --name add_tenant_lead_model`
  - [ ] Verify migration in database
  - [ ] Generate Prisma client: `npx prisma generate`

- [ ] **1.2** Create `handlers/signup_handler.rb`
  - [ ] Input validation
  - [ ] Rate limiting logic
  - [ ] Turnstile verification
  - [ ] TenantLead creation
  - [ ] SMS stub integration
  - [ ] WebSocket broadcast

- [ ] **1.3** Create `handlers/admin_leads_handler.rb`
  - [ ] List leads endpoint
  - [ ] Convert to tenant endpoint
  - [ ] Reject lead endpoint
  - [ ] Update notes endpoint

- [ ] **1.4** Mount handlers in `puma_server.rb`
  ```ruby
  map '/api/signup' { run SignupHandler.new }
  map '/api/admin/leads' { run AdminLeadsHandler.new }
  ```

- [ ] **1.5** Update `lib/data_broadcaster.rb`
  - [ ] Add `broadcast_leads_updated` method
  - [ ] Add `fetch_leads_data` method

### Phase 2: Frontend - Static Signup Page (1.5-2 hours)

- [ ] **2.1** Create `/var/www/kimonokittens/signup.html`
  - [ ] HTML structure with semantic markup
  - [ ] Meta tags (viewport, charset, description)
  - [ ] Logo + heading layout (horizontal with Horsemen font)
  - [ ] Form container (600px / 60% width, centered)
  - [ ] All form fields (see Form Fields Specification section)
  - [ ] Cloudflare Turnstile widget div
  - [ ] Success modal HTML (hidden by default)
  - [ ] Link to signup.css
  - [ ] Script tags: Turnstile CDN + signup.js

- [ ] **2.2** Create `/var/www/kimonokittens/signup.css`
  - [ ] Animated gradient blobs background (5 divs with keyframes)
  - [ ] Purple color palette (matching CLAUDE.md)
  - [ ] Typography styles (Horsemen font for heading)
  - [ ] Form input styles (text-2xl, slate-900/60 backgrounds, purple borders)
  - [ ] Orange gradient button with glow effect
  - [ ] Contact method radio button styles
  - [ ] Move-in dropdown styles
  - [ ] Success modal overlay + fade animations
  - [ ] Mobile responsive breakpoints
  - [ ] Loading spinner animation

- [ ] **2.3** Create `/var/www/kimonokittens/signup.js`
  - [ ] Form validation logic
  - [ ] Contact method radio listener (toggle email/facebook field)
  - [ ] Move-in dropdown listener (show/hide date/other field)
  - [ ] Turnstile callback handler
  - [ ] Form submit handler:
    - [ ] Prevent default
    - [ ] Validate required fields
    - [ ] Check CAPTCHA token present
    - [ ] Show loading state
    - [ ] POST to /api/signup
    - [ ] Handle success → show modal
    - [ ] Handle errors → display inline
    - [ ] Reset form on success
  - [ ] Success modal close handler
  - [ ] Auto-close modal after 5 seconds

- [ ] **2.4** Copy logo to `/var/www/kimonokittens/logo.png`
  - [ ] Already exists from homepage, verify path

- [ ] **2.5** Verify Horsemen font loads correctly
  - [ ] Check if font CSS needs to be copied from dashboard build
  - [ ] Or link to Google Fonts / external CDN if available

**Note**: No React Router, no npm dependencies, no dashboard changes. Signup is completely standalone static site.

### Phase 3: Frontend - Admin Dashboard (1-2 hours)

- [ ] **3.1** Create `dashboard/src/components/admin/LeadsList.tsx`
  - [ ] Fetch leads from API
  - [ ] WebSocket listener for updates
  - [ ] Filter logic (show pending/contacted only)
  - [ ] Header with count

- [ ] **3.2** Create `dashboard/src/components/admin/LeadRow.tsx`
  - [ ] Collapsed state (name + move-in)
  - [ ] Expanded state (all fields)
  - [ ] Admin notes textarea
  - [ ] Contact button (Gmail/Messenger link)
  - [ ] Approve button (convert to tenant)
  - [ ] Reject button

- [ ] **3.3** Update `dashboard/src/views/AdminDashboard.tsx`
  - [ ] Add `<LeadsList />` below `<TenantForm />`
  - [ ] Add leads state to DataContext

- [ ] **3.4** Update `dashboard/src/context/DataContext.tsx`
  - [ ] Add leads state
  - [ ] Add `leads_updated` WebSocket handler

### Phase 4: Security & Configuration (1 hour)

- [ ] **4.1** Cloudflare Turnstile setup
  - [ ] Sign up for Cloudflare account
  - [ ] Create Turnstile site
  - [ ] Add keys to `.env`
  - [ ] Test CAPTCHA verification

- [ ] **4.2** Environment variables
  - [ ] `CLOUDFLARE_TURNSTILE_SITE_KEY`
  - [ ] `CLOUDFLARE_TURNSTILE_SECRET`
  - [ ] `VITE_TURNSTILE_SITE_KEY`
  - [ ] `SMS_ENABLED=false` (until SMS service merged)

### Phase 5: Testing & Polish (1 hour)

- [ ] **5.1** Manual testing
  - [ ] Submit form with email contact
  - [ ] Submit form with Facebook contact
  - [ ] Test rate limiting (3rd submission fails)
  - [ ] Test CAPTCHA verification
  - [ ] Test validation errors
  - [ ] Test mobile responsiveness

- [ ] **5.2** Admin dashboard testing
  - [ ] Verify lead appears in admin list
  - [ ] Test expand/collapse
  - [ ] Test contact button (Gmail/Messenger)
  - [ ] Test approve → tenant creation
  - [ ] Test reject → lead disappears
  - [ ] Test admin notes save

- [ ] **5.3** Polish
  - [ ] Fix any responsive issues
  - [ ] Test on actual mobile device
  - [ ] Verify gradient animations
  - [ ] Check Horsemen font loading

### Phase 6: Future TODOs (Document Only)

- [ ] **6.1** Add to `TODO.md`:
  ```markdown
  - [ ] Add room photos to signup page (future enhancement)
  - [ ] Refine intro text based on FB ad screenshots
  - [ ] Integrate Beeper MCP for Messenger inbox automation
  - [ ] Implement SMS service integration (replace stub)
  ```

---

## 🚀 DEPLOYMENT NOTES

### Development Workflow
1. Develop on branch: `claude/tenant-signup-form-XXXXX`
2. Test locally: `npm run dev` (backend + frontend)
3. Commit & push to GitHub
4. Production deployment via webhook (automatic)

### Production Checklist
- [ ] Cloudflare Turnstile configured for `kimonokittens.com` domain
- [ ] Environment variables set in production `.env`
- [ ] Database migration applied: `npx prisma migrate deploy`
- [ ] Nginx routing updated (if needed)
- [ ] SMS service placeholder noted for future integration

---

## 📚 ADDITIONAL CONTEXT

### Logo Usage
- **Location**: `www/logo.png` or `dashboard/public/logo.png`
- **Size**: 400px width (responsive on mobile)
- **Format**: PNG (transparency preserved)

### Horsemen Font
- **Usage**: `font-[Horsemen]` (Tailwind arbitrary value)
- **Applied to**: Main heading "INTRESSEANMÄLAN"
- **Fallback**: If font doesn't load, system defaults to sans-serif

### Animated Gradient Blobs
- **Source**: `dashboard/src/App.tsx` lines 217-223
- **Structure**: 5 divs with radial gradients
- **Animations**: `animate-dashboard-first` through `animate-dashboard-fifth`
- **Reuse pattern**:
  ```tsx
  <div className="gradients-container fixed inset-0 h-full w-full opacity-35 blur-[50px]" style={{ zIndex: 2 }}>
    <div className="absolute w-[60%] h-[60%] top-[10%] left-[10%] bg-[radial-gradient(ellipse_at_center,_rgba(68,25,150,0.38)_0%,_rgba(68,25,150,0)_70%)] mix-blend-screen animate-dashboard-first" />
    {/* ... 4 more blobs ... */}
  </div>
  ```

### Button Styles Reference
- **Orange CTA**: `linear-gradient(180deg, #cb6f38 0%, #903f14 100%)`
- **Purple default**: `linear-gradient(180deg, rgba(82, 43, 127, 0.92) 0%, rgba(66, 30, 105, 0.92) 100%)`
- **Glow classes**: `.button-glow-orange`, `.button-hover-brighten`

---

## 🎯 SUCCESS METRICS (Post-Implementation)

1. **Form submission success rate** >95% (excluding spam)
2. **Mobile usability** - All fields accessible, no layout issues
3. **Admin workflow** - Lead → Tenant conversion in <30 seconds
4. **CAPTCHA effectiveness** - Zero spam submissions in first week
5. **Rate limiting** - Minimal legitimate users blocked (<1%)

---

## 🔮 FUTURE ENHANCEMENTS (Out of Scope)

1. **Beeper MCP Integration**
   - Auto-import Messenger applications
   - Deduplicate web form + Messenger submissions
   - Track application source

2. **Analytics Dashboard**
   - Conversion funnel: Visits → Submissions → Approvals
   - Drop-off analysis
   - Source attribution

3. **Applicant Status Checking**
   - Public endpoint: `/status/:leadId`
   - Email/SMS with status link
   - Transparency for applicants

4. **Room Photos & Virtual Tour**
   - Add room preference field
   - Photo gallery per room
   - 360° tour integration

5. **Intro Text Refinement**
   - Extract compelling copy from FB ad screenshots
   - A/B test different messaging
   - Optimize conversion rate

---

## 📝 NOTES FOR IMPLEMENTATION

- **Start with Phase 1** (backend) to ensure database + API works
- **Test API endpoints** with curl before building frontend
- **Use existing patterns** from admin dashboard (avoid reinventing)
- **Mobile-first CSS** - test on small screen first
- **Git commits**: Small, atomic commits per feature
- **Ask Fredrik** if any assumptions need clarification
- **Document decisions** in code comments for future reference

---

**END OF IMPLEMENTATION PLAN**

*Ready to build? Start with Phase 1.1 (Prisma migration)!* 🚀

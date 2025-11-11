# Admin Dashboard UI Requirements for Magic MCP

## Overview

Build a keyboard-navigable admin view within the existing hallway dashboard for contract management. The admin view should match the existing dashboard's visual style while providing comprehensive contract lifecycle tracking.

## Context: Existing Dashboard Design

**Current Dashboard Pattern** (from `dashboard/src/App.tsx`):
- Dark glass-morphism aesthetic with backdrop blur
- Purple/slate color scheme (`bg-purple-900/30`, `bg-slate-900/40`)
- Rounded widgets with `rounded-2xl` borders
- Subtle borders: `border-purple-900/10`
- Typography: Purple text tones (`text-purple-100`, `text-purple-200`)
- Widget component structure with title, optional accent styling

**Widget Component Pattern to Match:**
```typescript
<Widget
  title="Widget Title"
  accent={true}  // Purple accent variant
  className="..."
>
  {content}
</Widget>
```

## 1. View Toggle (Tab Key)

**Requirement**: Press **Tab key** to switch between public dashboard and admin view

**Behavior**:
- Tab key toggles between two views (not opens menu)
- Public dashboard is default view (hallway display)
- Admin view replaces entire dashboard content when active
- Visual indicator shows which view is active
- Smooth transition animation between views

**Component**: `useKeyboardNav.tsx` hook
```typescript
// Should handle:
const [viewMode, setViewMode] = useState<'public' | 'admin'>('public')
// Tab key: toggle between modes
// ESC key: return to public view from anywhere in admin
```

## 2. Admin View Layout

**CRITICAL: Use existing Widget component structure**

The admin view should be wrapped in the same `<Widget>` component used by WeatherWidget, TrainWidget, etc.:

```typescript
<Widget
  title="Kontrakt"  // Swedish title
  horsemenFont={true}  // Use Horsemen font for title
  className="..."
>
  {/* Contract list accordion here */}
</Widget>
```

**Language**: All text in Swedish (matching existing dashboard widgets)

**Match existing widgets exactly:**
- Same outer container styling (glass-morphism, rounded-2xl, backdrop-blur)
- Same padding (p-8)
- Same title styling with Horsemen font
- Same accent colors option if needed

**Expandable row accordion** (collapsed by default, arrow keys or click to expand):
```
┌─────────────────────────────────────────────────────────────┐
│ Kontrakt                                                     │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  [Alla] [Aktiva]    ← Filter pills (capitalized)            │
│                                                              │
│  ┌────────────────────────────────────────────────────────┐ │
│  │ ► [icon] Fredrik Brännström      11 november  Klar    │ │ ← Collapsed
│  ├────────────────────────────────────────────────────────┤ │
│  │ ▼ [icon] Sanna Juni Benemar     10 november  Väntar  │ │ ← Expanded
│  │                                                         │ │
│  │   E-poststatus:                                        │ │
│  │   ✓ Hyresvärd: Levererad (10 november 12:36)          │ │
│  │   ✓ Hyresgäst: Levererad (10 november 12:36)          │ │
│  │                                                         │ │
│  │   Signeringsstatus:                                    │ │
│  │   ✓ Fredrik Brännström - Signerad (10 november 14:22) │ │
│  │   ⏳ Sanna Juni Benemar - Väntar (30 dagar kvar)      │ │
│  │                                                         │ │
│  │   Tidslinje:                                           │ │
│  │   10 november 12:34  Kontrakt genererat                │ │
│  │   10 november 12:35  Överenskommelse skapad (Zigned)  │ │
│  │   10 november 12:36  E-post skickad                    │ │
│  │   10 november 14:22  Hyresvärd signerade               │ │
│  │                                                         │ │
│  │   [Skicka Om E-post] [Avbryt] [Kopiera Länkar]        │ │
│  ├────────────────────────────────────────────────────────┤ │
│  │ ► [icon] Adam Nilsson            9 november  Misslyckad│ │ ← Collapsed
│  │   Fel: PDF-generering timeout                          │ │
│  └────────────────────────────────────────────────────────┘ │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

**Navigation:**
- **Arrow Up/Down**: Navigate between contracts (highlight row)
- **Enter or Click**: Expand/collapse selected contract
- **Mouse**: Click anywhere on row to expand/collapse

## 3. Contract List Component

**Data Structure** (from `SignedContract` model):
```typescript
interface SignedContract {
  id: string                    // UUID
  tenant_id: string            // Foreign key to tenant
  case_id: string              // Zigned agreement ID
  pdf_url: string              // Generated PDF path
  status: 'pending' | 'landlord_signed' | 'tenant_signed' | 'completed' | 'expired' | 'cancelled' | 'failed'
  landlord_signed: boolean
  tenant_signed: boolean
  landlord_signing_url: string
  tenant_signing_url: string
  test_mode: boolean
  expires_at: Date
  created_at: Date
  updated_at: Date

  // Webhook lifecycle tracking (future)
  generation_status?: 'draft' | 'generated' | 'validated' | 'failed'
  email_status?: 'pending' | 'sent' | 'bounced' | 'failed'
  error_message?: string
}
```

**List Item States**:

**Collapsed state** (default):
```
► [CheckCircle2] Fredrik Brännström      11 november   Klar  Test
```

**Expanded state** (when selected):
```
▼ [CheckCircle2] Fredrik Brännström      11 november   Klar  Test

  E-poststatus:
  ✓ Hyresvärd: Levererad (11 november 12:36)
  ✓ Hyresgäst: Levererad (11 november 12:36)

  Signeringsstatus:
  ✓ Fredrik Brännström - Signerad (11 november 14:22)
  ✓ Hyresgäst - Signerad (11 november 15:45)

  Tidslinje:
  11 november 12:34  Kontrakt genererat
  11 november 12:35  Överenskommelse skapad (Zigned)
  11 november 12:36  E-post skickad
  11 november 14:22  Hyresvärd signerade
  11 november 15:45  Hyresgäst signerade
  11 november 15:46  Kontrakt fullt

  [Visa PDF] [Skicka igen] [Avbryt] [Kopiera länkar]
```

**With errors** (show brief error in collapsed state):
```
► [XCircle] Adam Nilsson               9 november   Misslyckad
  Fel: PDF generation timeout after 30s
```

**Data to display**:
- **Email Status**: Per-participant delivery tracking from `ContractParticipant.emailDelivered`
- **Signing Status**: Per-participant signing progress from `ContractParticipant.status` and `signedAt`
- **Timeline**: Lifecycle events from `SignedContract` timestamps:
  - `generationCompletedAt` → "Contract generated"
  - Agreement created timestamp
  - `emailDeliveredAt` → "Emails sent"
  - Each participant's `signedAt` → "X signed"
  - Contract fulfilled timestamp
- **Errors**: Brief messages from `generationError`, `validationErrors`, `emailDeliveryError`

**Filter behavior**:
- **All**: Shows all contracts (completed, pending, failed, cancelled, expired)
- **Active Only**: Shows only pending contracts (awaiting signatures)

**Status Icons** (using Lucide React like WeatherWidget):
```typescript
import { CheckCircle2, Clock, XCircle, Ban, AlertTriangle, UserCheck } from 'lucide-react'
```
- `CheckCircle2` - Klar (both signed)
- `Clock` - Väntar (awaiting signatures)
- `UserCheck` - Hyresvärd Signerad (landlord signed only)
- `UserCheck` - Hyresgäst Signerad (tenant signed only, different color)
- `XCircle` - Misslyckad (generation/email errors)
- `Ban` - Avbruten (cancelled)
- `AlertTriangle` - Utgången (expired, past expiration date)

**Status Label Translations** (Swedish):
```typescript
completed: 'Klar'
pending: 'Väntar'
landlord_signed: 'Hyresvärd Signerad'
tenant_signed: 'Hyresgäst Signerad'
failed: 'Misslyckad'
cancelled: 'Avbruten'
expired: 'Utgången'
```

## 4. Keyboard Navigation

**Global shortcuts**:
- **Tab**: Toggle between public dashboard and admin view
- **ESC**: Return to public dashboard (or collapse expanded row if in admin)

**List navigation**:
- **Arrow Up/Down**: Navigate between contracts (highlight current row)
- **Enter or Right Arrow**: Expand/collapse selected contract
- **Left Arrow**: Collapse expanded contract
- **ESC**: Collapse expanded contract (return to list view)

**Interaction**:
- Mouse click anywhere on row: Expand/collapse
- Action buttons: Click to trigger (resend email, cancel, etc.)

## 5. Real-time Updates

**WebSocket Integration Points**:
```typescript
// Subscribe to contract status updates
useEffect(() => {
  const ws = new WebSocket('ws://localhost:3001')

  ws.onmessage = (event) => {
    const data = JSON.parse(event.data)

    if (data.type === 'zigned_webhook_event') {
      // Update contract status in real-time
      updateContractStatus(data.case_id, data.event_type)
    }

    if (data.type === 'contract_list_changed') {
      // Refresh contract list
      refreshContracts()
    }
  }

  return () => ws.close()
}, [])
```

**Event types to handle**:
- `agreement.pending` - Contract activated, awaiting signatures
- `agreement.signature` - Participant signed
- `agreement.fulfilled` - All signatures complete
- `agreement.cancelled` - Contract cancelled
- `agreement.expired` - Contract expired without completion
- `generation.failed` - PDF generation error
- `email.bounced` - Email delivery failure

## 7. Example Data

**Sample contract objects for UI design**:

```typescript
const sampleContracts: SignedContract[] = [
  {
    id: 'contract-001',
    tenant_id: 'tenant-001',
    case_id: 'agr_abc123def456',
    pdf_url: '/contracts/generated/Sanna_Benemar_Hyresavtal_2025-11-01.pdf',
    status: 'pending',
    landlord_signed: true,
    tenant_signed: false,
    landlord_signing_url: 'https://app.zigned.se/sign/landlord-abc123',
    tenant_signing_url: 'https://app.zigned.se/sign/tenant-def456',
    test_mode: false,
    expires_at: new Date('2025-12-10'),
    created_at: new Date('2025-11-10T12:34:56Z'),
    updated_at: new Date('2025-11-10T14:22:11Z'),
    generation_status: 'validated',
    email_status: 'sent'
  },
  {
    id: 'contract-002',
    tenant_id: 'tenant-002',
    case_id: 'agr_test789xyz',
    pdf_url: '/contracts/generated/Test_Tenant_Hyresavtal_2025-11-11.pdf',
    status: 'completed',
    landlord_signed: true,
    tenant_signed: true,
    landlord_signing_url: 'https://app.zigned.se/sign/test-landlord',
    tenant_signing_url: 'https://app.zigned.se/sign/test-tenant',
    test_mode: true,
    expires_at: new Date('2025-12-11'),
    created_at: new Date('2025-11-11T09:15:00Z'),
    updated_at: new Date('2025-11-11T10:30:00Z'),
    generation_status: 'validated',
    email_status: 'sent'
  },
  {
    id: 'contract-003',
    tenant_id: 'tenant-003',
    case_id: 'agr_failed123',
    pdf_url: null,
    status: 'failed',
    landlord_signed: false,
    tenant_signed: false,
    landlord_signing_url: null,
    tenant_signing_url: null,
    test_mode: false,
    expires_at: null,
    created_at: new Date('2025-11-09T16:45:00Z'),
    updated_at: new Date('2025-11-09T16:45:30Z'),
    generation_status: 'failed',
    email_status: 'pending',
    error_message: 'PDF generation timeout: Failed to render contract template'
  }
]
```

## 6. Component File Structure

**Accordion pattern structure**:
```
dashboard/src/
├── views/
│   ├── PublicDashboard.tsx        # Existing dashboard widgets
│   └── AdminDashboard.tsx         # NEW: Admin view container
├── components/
│   └── admin/
│       ├── ContractList.tsx       # NEW: List with filter + keyboard nav
│       ├── ContractRow.tsx        # NEW: Collapsible row with expand/collapse
│       ├── ContractDetails.tsx    # NEW: Expanded content (email, signing, timeline)
│       └── ContractTimeline.tsx   # NEW: Event timeline display
└── hooks/
    ├── useKeyboardNav.tsx         # NEW: Tab + arrow keys + Enter/ESC
    └── useContracts.tsx           # NEW: Contract data fetching + participants
```

**State management**:
- `selectedContractId` - Currently highlighted contract
- `expandedContractId` - Currently expanded contract (null if all collapsed)
- Arrow keys update `selectedContractId`
- Enter toggles `expandedContractId` for selected contract

## 7. API Endpoints

Backend will provide these endpoints (Dell agent implementing):

```typescript
// Contract list with optional filters
GET /api/admin/contracts?status=pending&test_mode=false

// Single contract details
GET /api/admin/contracts/:id

// Contract actions
POST /api/admin/contracts/:id/resend-email
POST /api/admin/contracts/:id/cancel
GET  /api/admin/contracts/:id/pdf

// Statistics
GET /api/admin/contracts/stats
```

**Response format**:
```typescript
interface ContractsResponse {
  contracts: SignedContract[]
  total: number
  statistics: {
    pending: number
    completed: number
    failed: number
    expired: number
  }
}
```

## 8. Design Tokens

**Match existing dashboard styling**:
```typescript
const adminTheme = {
  // Background colors (glass morphism)
  bgPrimary: 'bg-slate-900/40',
  bgAccent: 'bg-purple-900/30',
  bgHover: 'hover:bg-purple-900/20',

  // Text colors
  textPrimary: 'text-purple-100',
  textAccent: 'text-purple-200',
  textMuted: 'text-purple-300/60',

  // Borders
  border: 'border-purple-900/10',
  borderAccent: 'border-purple-500/30',

  // Shadows and effects
  shadow: 'shadow-md',
  blur: 'backdrop-blur-sm',
  rounded: 'rounded-2xl',
  roundedSmall: 'rounded-lg',

  // Status colors
  statusSuccess: 'text-green-400',
  statusPending: 'text-yellow-400',
  statusError: 'text-red-400',
  statusWarning: 'text-orange-400'
}
```

## 9. Performance

- Simple list rendering (only 4-5 contracts expected)
- WebSocket updates for real-time status changes
- No complex optimizations needed

## 10. Success Criteria

✅ Admin view accessible via Tab key
✅ **Uses existing Widget component** (same as WeatherWidget/TrainWidget)
✅ **Title uses Horsemen font** with same styling as other widgets
✅ **Exact padding/margins** match existing widgets (p-8)
✅ Glass-morphism aesthetic (purple/slate, backdrop-blur, rounded-2xl)
✅ Expandable rows with arrow key navigation (Up/Down, Enter/Right to expand, Left/ESC to collapse)
✅ Email status, signing status, and timeline visible when expanded
✅ Lucide React icons for status indicators
✅ Single filter toggle: Alla vs Aktiva (capitalized Swedish)
✅ Real-time WebSocket updates for contract status changes
✅ **All UI text in Swedish** (E-poststatus, Signeringsstatus, Tidslinje, status labels)
✅ **Full month names** in dates (11 november, not nov.)
✅ **Action buttons**: Visa PDF, Skicka igen, Avbryt, Kopiera länkar
✅ **PDF viewer button** only appears when contract has PDF

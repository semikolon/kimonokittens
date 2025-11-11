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

**Simple single-list view** (no expandable rows, all info always visible):
```
┌─────────────────────────────────────────────────────────────┐
│ Contract Management                                          │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  [All] [Active Only]    ← Single filter toggle              │
│                                                              │
│  ┌──────────────────────────────────────────────────────┐   │
│  │ All contract rows fully expanded (4-5 contracts max) │   │
│  │ - Status with icon                                   │   │
│  │ - Tenant name, date, test/prod flag                  │   │
│  │ - Signing status (landlord/tenant)                   │   │
│  │ - Action buttons inline                              │   │
│  └──────────────────────────────────────────────────────┘   │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

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

**List Item Design** (fully expanded, no click-to-expand):
```
┌──────────────────────────────────────────────────────────────┐
│ [CheckCircle2] Fredrik Brännström              2025-11-11   │
│ Completed • Test Mode                                        │
│ ✓ Landlord signed  ✓ Tenant signed                           │
│ [View PDF] [Copy Links]                                      │
├──────────────────────────────────────────────────────────────┤
│ [Clock] Sanna Juni Benemar                     2025-11-10   │
│ Pending • Production                                         │
│ ✓ Landlord signed  ⏳ Tenant pending (30 days left)         │
│ [Resend Email] [Cancel] [Copy Links]                         │
├──────────────────────────────────────────────────────────────┤
│ [XCircle] Adam Nilsson                         2025-11-09   │
│ Failed • Production                                          │
│ Generation error: PDF timeout                                │
│ [Retry] [View Logs]                                          │
└──────────────────────────────────────────────────────────────┘
```

**Filter behavior**:
- **All**: Shows all contracts (completed, pending, failed, cancelled, expired)
- **Active Only**: Shows only pending contracts (awaiting signatures)

**Status Icons** (using Lucide React like WeatherWidget):
```typescript
import { CheckCircle2, Clock, XCircle, Ban, AlertTriangle, UserCheck } from 'lucide-react'
```
- `CheckCircle2` - Completed (both signed)
- `Clock` - Pending (awaiting signatures)
- `UserCheck` - Landlord signed only
- `UserCheck` - Tenant signed only (different color)
- `XCircle` - Failed (generation/email errors)
- `Ban` - Cancelled
- `AlertTriangle` - Expired (past expiration date)

## 4. Keyboard Navigation

**Simple shortcuts**:
- **Tab**: Toggle between public dashboard and admin view
- **ESC**: Return to public dashboard

(No complex navigation needed - all contracts visible, click buttons directly)

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

**Simplified structure** (no separate details/timeline components):
```
dashboard/src/
├── views/
│   ├── PublicDashboard.tsx        # Existing dashboard widgets
│   └── AdminDashboard.tsx         # NEW: Admin view container
├── components/
│   └── admin/
│       ├── ContractList.tsx       # NEW: Simple list with filter toggle
│       └── ContractRow.tsx        # NEW: Fully expanded row with inline actions
└── hooks/
    ├── useKeyboardNav.tsx         # NEW: Tab/ESC shortcuts only
    └── useContracts.tsx           # NEW: Contract data fetching
```

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
✅ Matches existing dashboard visual style (purple/slate glass-morphism)
✅ All contracts visible with status icons (Lucide React)
✅ Single filter toggle: All vs Active Only
✅ Action buttons inline per contract (no separate details view)
✅ Real-time WebSocket updates for contract status changes
✅ Simple, clean layout matching Widget component pattern

# Admin Dashboard Visual Guide

## View Toggle Navigation

```
PUBLIC DASHBOARD (default)
├─ Press Tab → Switch to ADMIN VIEW
└─ [Shows normal hallway widgets]

ADMIN VIEW
├─ Press Tab → Switch back to PUBLIC DASHBOARD
├─ Press ESC → Return to PUBLIC DASHBOARD
└─ [Shows Contract Management widget]
```

## Admin View Layout

```
┌─────────────────────────────────────────────────────────────────┐
│ Contract Management                                    [Horsemen]│
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  3 contracts                         [All] / [Active Only]      │
│                                                                  │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │ ▶ ✓ tenant-001      Nov 10  [landlord_signed] [Test]     │ │  ← Collapsed
│  ├────────────────────────────────────────────────────────────┤ │
│  │ ▼ ✓ tenant-002      Nov 11  [completed] [Test]           │ │  ← Expanded (click/Enter)
│  │                                                             │ │
│  │   Email Status:                                            │ │
│  │   ✓ Landlord: Delivered (Nov 11 09:15)                   │ │
│  │   ✓ Tenant: Delivered (Nov 11 09:15)                     │ │
│  │                                                             │ │
│  │   Signing Status:                                          │ │
│  │   ✓ Fredrik Brännström - Signed (Nov 11 10:30)           │ │
│  │   ✓ Tenant - Signed (Nov 11 10:30)                       │ │
│  │                                                             │ │
│  │   Timeline:                                                │ │
│  │   ● Nov 11 09:15  Contract generated                      │ │
│  │   │                System                                  │ │
│  │   ● Nov 11 09:16  Agreement created (Zigned)             │ │
│  │   │                System                                  │ │
│  │   ● Nov 11 09:17  Emails sent                             │ │
│  │   │                System                                  │ │
│  │   ● Nov 11 10:30  Landlord signed                         │ │
│  │   │                Fredrik Brännström                      │ │
│  │   ● Nov 11 10:30  Tenant signed                           │ │
│  │                    Tenant                                  │ │
│  │                                                             │ │
│  │   [Resend Email] [Cancel] [Copy Links]                     │ │
│  ├────────────────────────────────────────────────────────────┤ │
│  │ ▶ ✗ tenant-003      Nov 09  [failed]                     │ │  ← Collapsed with error
│  │   Error: PDF generation timeout                            │ │
│  └────────────────────────────────────────────────────────────┘ │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

## Status Icons Legend

| Icon | Status | Color | Meaning |
|------|--------|-------|---------|
| ✓ (CheckCircle2) | Completed | Green | Both landlord and tenant signed |
| ⏱ (Clock) | Pending | Yellow | Awaiting signatures |
| 👤 (UserCheck) | Landlord Signed | Blue | Only landlord signed |
| 👤 (UserCheck) | Tenant Signed | Yellow | Only tenant signed |
| ✗ (XCircle) | Failed | Red | Generation/email error |
| ⊘ (Ban) | Cancelled | Red | Contract cancelled |
| ⚠ (AlertTriangle) | Expired | Orange | Past expiration date |

## Filter Toggle States

### All Contracts (Default)
Shows all contracts regardless of status:
- ✓ Completed
- ⏱ Pending
- ✗ Failed
- ⊘ Cancelled
- ⚠ Expired

### Active Only
Shows only active contracts:
- ⏱ Pending (awaiting signatures)
- 👤 Landlord Signed (tenant pending)
- 👤 Tenant Signed (landlord pending)

Hides:
- ✓ Completed
- ✗ Failed
- ⊘ Cancelled
- ⚠ Expired

## Keyboard Navigation Flow

```
START: Public Dashboard
  │
  ├─ Press TAB
  │    └─→ Admin View appears
  │         │
  │         ├─ Arrow UP/DOWN: Navigate contracts
  │         │    └─→ Visual highlight on selected row
  │         │
  │         ├─ Press ENTER: Expand/collapse
  │         │    └─→ Shows detailed info
  │         │
  │         ├─ Press ESC: Collapse all OR return to public
  │         │    └─→ Back to Public Dashboard
  │         │
  │         └─ Press TAB again
  │              └─→ Back to Public Dashboard
  │
END: Back to Public Dashboard
```

## Mouse Interaction

1. **Click anywhere on row**: Expand/collapse that contract
2. **Click filter toggle**: Switch between All/Active Only
3. **Click action buttons**: Execute action (when backend ready)

## Color Palette (Purple/Slate Theme)

### Background Colors
- Widget background: `bg-slate-900/40` (semi-transparent dark slate)
- Accent widget: `bg-purple-900/30` (semi-transparent purple)
- Hover state: `hover:bg-purple-900/10`
- Selected row: `bg-purple-900/20`

### Text Colors
- Primary text: `text-purple-100` (light purple)
- Accent text: `text-purple-200` (medium purple)
- Muted text: `text-purple-300/60` (faded purple)

### Border Colors
- Default border: `border-purple-900/10` (very subtle)
- Accent border: `border-purple-500/30` (visible)
- Selected border: `border-purple-500/50` (highlighted)

### Status Colors
- Success: `text-green-400` (completed, signed, delivered)
- Pending: `text-yellow-400` (awaiting action)
- Error: `text-red-400` (failed, cancelled)
- Warning: `text-orange-400` (expired)

## Design Details

### Typography
- **Title**: Horsemen font, 2xl size, uppercase, tracking-wide
- **Contract ID**: purple-400, semibold, small
- **Section headers**: purple-200, semibold, small
- **Body text**: purple-100, regular
- **Meta text**: purple-300/60, extra-small

### Spacing
- **Outer padding**: p-8 (matches all widgets)
- **Row padding**: p-4
- **Expanded content**: p-6
- **Section gap**: space-y-6
- **Timeline gap**: space-y-3

### Borders & Shadows
- **Widget border**: rounded-2xl + border-purple-900/10
- **Row border**: rounded-lg + border-purple-900/10
- **Shadow**: shadow-md (subtle depth)
- **Backdrop**: backdrop-blur-sm (glass effect)

## Responsive Behavior

The admin dashboard inherits the existing dashboard's responsive grid system:
- **Mobile**: Single column, full-width rows
- **Tablet**: Optimized touch targets
- **Desktop**: Full feature set with keyboard navigation

## Animation Details

### Row Expand/Collapse
- **Duration**: 200ms (smooth but quick)
- **Easing**: Default ease
- **Transform**: Height auto → 0 (collapse)

### Chevron Rotation
- **Duration**: 200ms
- **Transform**: rotate(0deg) → rotate(90deg)
- **Transition**: smooth rotation

### Timeline Dots
- **Connection line**: 1px vertical purple line
- **Dot**: 8px circle, purple-500 fill
- **Spacing**: 3 units between events

## Accessibility

- All interactive elements are keyboard-accessible
- Visual focus indicators on selected rows
- ARIA labels for screen readers (future enhancement)
- Semantic HTML structure (button, div with role="button")

## Performance Optimization

- **Simple list rendering** - no virtualization needed (4-5 contracts expected)
- **Minimal re-renders** - state isolated to ContractList component
- **WebSocket efficiency** - only refreshes on actual contract changes
- **No heavy animations** - GPU-efficient transforms only

## Integration with Existing Dashboard

The admin view:
- ✅ Uses same background (radial gradient + animated blobs)
- ✅ Uses same DeploymentBanner
- ✅ Uses same FadeOverlay (sleep schedule)
- ✅ Shares animation pause state when sleeping
- ✅ Maintains consistent z-index layering
- ✅ Respects same responsive breakpoints

## Sample Contract States

### 1. Completed Contract (Green)
```
✓ tenant-002      Nov 11  [completed] [Test]
├─ Email Status: Both delivered
├─ Signing Status: Both signed
└─ Timeline: Full lifecycle visible
```

### 2. Pending Contract (Yellow)
```
⏱ tenant-001      Nov 10  [pending]
├─ Email Status: Delivered
├─ Signing Status: Landlord signed, tenant pending (30 days left)
└─ Timeline: Partial - waiting for tenant signature
```

### 3. Failed Contract (Red)
```
✗ tenant-003      Nov 09  [failed]
├─ Error: PDF generation timeout
├─ Email Status: Pending
├─ Signing Status: Not started
└─ Timeline: Shows generation failure
```

## Future Enhancements (Post-MVP)

1. **Search bar** - Filter by tenant name, contract ID, or case ID
2. **Date range filter** - Show contracts from specific time period
3. **Batch actions** - Resend emails to multiple contracts
4. **Statistics panel** - Overview of pending/completed/failed counts
5. **Contract preview** - Inline PDF viewer
6. **Audit log** - Detailed action history
7. **Export functionality** - Download contract list as CSV/JSON

# Admin Dashboard Testing Checklist

**Status**: Ready for testing
**Date**: November 11, 2025

## Pre-Testing Setup

### 1. Dependencies Check ✅
All required dependencies already installed:
- ✅ `lucide-react@^0.544.0` - Icons
- ✅ `react@19.1.0` - Latest React
- ✅ `framer-motion@^10.16.16` - Animations (optional)

No additional `npm install` required!

### 2. Build & Start Development Server

```bash
cd /Users/fredrikbranstrom/Projects/kimonokittens
npm run dev
```

Expected output:
```
VITE v7.0.3  ready in 500 ms

  ➜  Local:   http://localhost:5175/
  ➜  Network: use --host to expose
```

### 3. Open Browser

```bash
# On Mac (from development machine)
open http://localhost:5175
```

Or with SSH port forwarding (as documented in CLAUDE.md):
```bash
# From Mac terminal
ssh -L 5175:localhost:5175 -L 3001:localhost:3001 kimonokittens
# Then open http://localhost:5175 in Mac browser
```

---

## Core Functionality Tests

### Test 1: View Toggle (Tab Key)
- [ ] **Start**: Public dashboard visible (default view)
- [ ] **Action**: Press `Tab` key once
- [ ] **Expected**: Admin dashboard appears with "Contract Management" title
- [ ] **Verify**: Title uses Horsemen font, purple/slate glass-morphism style
- [ ] **Action**: Press `Tab` key again
- [ ] **Expected**: Returns to public dashboard
- [ ] **Pass/Fail**: ___________

**Screenshot location**: Take screenshot of admin view for documentation

---

### Test 2: ESC Key Returns to Public View
- [ ] **Start**: Navigate to admin view (press Tab)
- [ ] **Action**: Press `ESC` key
- [ ] **Expected**: Immediately returns to public dashboard
- [ ] **Pass/Fail**: ___________

---

### Test 3: Summary Line Display
- [ ] **Start**: Admin view visible with contracts
- [ ] **Verify**: Summary line appears below "Kontrakt" title
- [ ] **Verify**: Displays contract statistics in Swedish
- [ ] **Examples**:
  - "3 signerade kontrakt - inväntar signaturer för 2 st"
  - "Inga kontrakt" (if empty)
  - "Inväntar signatur för ett kontrakt" (if 1 pending)
- [ ] **Verify**: Font size matches train/rent widget one-liners
- [ ] **Verify**: Text color is purple-200
- [ ] **Pass/Fail**: ___________

---

### Test 4: Filter Toggle Functionality
- [ ] **Start**: Admin view visible
- [ ] **Verify**: Default shows "All" button active
- [ ] **Verify**: Shows "3 contracts" count
- [ ] **Action**: Click "Active Only" button
- [ ] **Expected**: Button changes to active state (purple background)
- [ ] **Expected**: Hides completed/failed/expired contracts
- [ ] **Expected**: Only shows pending contracts
- [ ] **Action**: Click "All" button
- [ ] **Expected**: Shows all contracts again
- [ ] **Pass/Fail**: ___________

---

### Test 5: Keyboard Navigation (Arrow Keys)
- [ ] **Start**: Admin view with 3 contracts visible
- [ ] **Action**: Press `Arrow Down` key
- [ ] **Expected**: First contract row highlights (purple background)
- [ ] **Action**: Press `Arrow Down` again
- [ ] **Expected**: Second contract row highlights
- [ ] **Action**: Press `Arrow Up`
- [ ] **Expected**: First contract row highlights again
- [ ] **Action**: Press `Arrow Down` repeatedly
- [ ] **Expected**: Cycles through all contracts, wraps to first
- [ ] **Pass/Fail**: ___________

---

### Test 6: Expand/Collapse with Enter Key
- [ ] **Start**: Admin view, navigate to first contract (Arrow Down)
- [ ] **Action**: Press `Enter` key
- [ ] **Expected**: Contract expands showing:
  - Email Status section
  - Signing Status section
  - Timeline section
  - Action buttons
- [ ] **Verify**: Chevron rotates 90 degrees (▶ → ▼)
- [ ] **Action**: Press `Enter` again
- [ ] **Expected**: Contract collapses, details hidden
- [ ] **Pass/Fail**: ___________

---

### Test 7: Mouse Click Expand/Collapse
- [ ] **Start**: Admin view with contracts collapsed
- [ ] **Action**: Click anywhere on first contract row
- [ ] **Expected**: Contract expands with full details
- [ ] **Action**: Click row again
- [ ] **Expected**: Contract collapses
- [ ] **Action**: Click different contract
- [ ] **Expected**: Only clicked contract expands (others stay collapsed)
- [ ] **Pass/Fail**: ___________

---

## Visual Design Tests

### Test 8: Widget Styling Matches Existing Widgets
- [ ] **Compare**: Admin widget vs WeatherWidget/TrainWidget
- [ ] **Verify**: Same glass-morphism effect (backdrop-blur)
- [ ] **Verify**: Same rounded corners (rounded-2xl)
- [ ] **Verify**: Same padding (p-8)
- [ ] **Verify**: Same purple/slate color scheme
- [ ] **Verify**: Same border (border-purple-900/10)
- [ ] **Pass/Fail**: ___________

---

### Test 9: Horsemen Font Renders
- [ ] **Verify**: "Contract Management" title uses Horsemen font
- [ ] **Verify**: Font is bold, uppercase, with letter-spacing
- [ ] **Verify**: Title color is purple-200 (accent mode)
- [ ] **Pass/Fail**: ___________

---

### Test 10: Status Icons Display Correctly
- [ ] **Verify**: contract-001 shows Clock icon (pending)
- [ ] **Verify**: contract-002 shows CheckCircle2 icon (completed)
- [ ] **Verify**: contract-003 shows XCircle icon (failed)
- [ ] **Verify**: Icons have correct colors:
  - Green for completed
  - Yellow for pending
  - Red for failed
- [ ] **Pass/Fail**: ___________

---

### Test 11: Status Badges Display
- [ ] **Verify**: Each contract shows status badge
- [ ] **Verify**: Badge colors match status:
  - Blue for `landlord_signed`
  - Green for `completed`
  - Red for `failed`
- [ ] **Verify**: "Test" badge appears for test mode contracts (contract-002)
- [ ] **Pass/Fail**: ___________

---

## Expanded Content Tests

### Test 12: Email Status Section
- [ ] **Action**: Expand contract-002 (completed, test mode)
- [ ] **Verify**: "Email Status:" header visible
- [ ] **Verify**: Shows "Landlord: Delivered" with green checkmark
- [ ] **Verify**: Shows "Tenant: Delivered" with green checkmark
- [ ] **Verify**: Timestamps display in Swedish format (e.g., "nov 11 09:15")
- [ ] **Pass/Fail**: ___________

---

### Test 13: Signing Status Section
- [ ] **Action**: Expand contract-002 (completed)
- [ ] **Verify**: "Signing Status:" header visible
- [ ] **Verify**: Shows "Fredrik Brännström - Signed" with green checkmark
- [ ] **Verify**: Shows "Tenant - Signed" with green checkmark
- [ ] **Verify**: Timestamps display correctly
- [ ] **Action**: Expand contract-001 (pending)
- [ ] **Verify**: Shows "X days left" for pending signatures
- [ ] **Pass/Fail**: ___________

---

### Test 14: Timeline Section
- [ ] **Action**: Expand contract-002
- [ ] **Verify**: "Timeline:" header visible
- [ ] **Verify**: Events listed chronologically:
  - Contract generated
  - Agreement created (Zigned)
  - Emails sent
  - Landlord signed
  - Tenant signed
- [ ] **Verify**: Purple dots and connecting lines visible
- [ ] **Verify**: Actor names shown (System, Fredrik Brännström, Tenant)
- [ ] **Pass/Fail**: ___________

---

### Test 15: Error Display (Failed Contract)
- [ ] **Start**: contract-003 visible (failed status)
- [ ] **Verify**: Red XCircle icon shows
- [ ] **Verify**: Status badge shows "failed" in red
- [ ] **Verify**: Collapsed state shows error message:
  - "Error: PDF generation timeout: Failed to render contract template"
- [ ] **Pass/Fail**: ___________

---

### Test 16: Action Buttons Present
- [ ] **Action**: Expand any contract
- [ ] **Verify**: Three buttons visible at bottom:
  - "Resend Email" (purple)
  - "Cancel" (gray)
  - "Copy Links" (gray)
- [ ] **Note**: Buttons not functional yet (backend pending)
- [ ] **Pass/Fail**: ___________

---

## Responsive Design Tests

### Test 17: Browser Window Resize
- [ ] **Action**: Resize browser to narrow width (mobile simulation)
- [ ] **Verify**: Admin widget scales down gracefully
- [ ] **Verify**: Contract rows stack vertically
- [ ] **Verify**: Text remains readable
- [ ] **Action**: Resize to wide width (desktop)
- [ ] **Verify**: Layout optimizes for desktop
- [ ] **Pass/Fail**: ___________

---

## Performance Tests

### Test 18: Smooth Animations
- [ ] **Action**: Expand/collapse contracts multiple times
- [ ] **Verify**: Chevron rotation is smooth (200ms)
- [ ] **Verify**: Content expand/collapse is smooth
- [ ] **Verify**: No jank or stuttering
- [ ] **Pass/Fail**: ___________

---

### Test 19: Keyboard Navigation Performance
- [ ] **Action**: Rapidly press Arrow keys
- [ ] **Verify**: Highlight updates immediately
- [ ] **Verify**: No lag or input delay
- [ ] **Pass/Fail**: ___________

---

## Integration Tests

### Test 20: Background Animations Continue
- [ ] **Action**: Switch to admin view (Tab)
- [ ] **Verify**: Purple gradient blobs continue animating
- [ ] **Verify**: Background matches public dashboard
- [ ] **Verify**: Sleep schedule FadeOverlay still works
- [ ] **Pass/Fail**: ___________

---

### Test 21: DeploymentBanner Shows
- [ ] **Verify**: Deployment banner visible at top of admin view
- [ ] **Verify**: Banner matches public dashboard banner
- [ ] **Pass/Fail**: ___________

---

## WebSocket Tests (When Backend Ready)

### Test 22: WebSocket Connection
- [ ] **Backend Required**: Start Ruby backend server
- [ ] **Verify**: WebSocket connects to `ws://localhost:3001`
- [ ] **Verify**: No connection errors in browser console
- [ ] **Pass/Fail**: ___________

---

### Test 23: Real-time Contract Updates
- [ ] **Backend Required**: Trigger Zigned webhook event
- [ ] **Action**: Watch admin dashboard
- [ ] **Expected**: Contract list auto-refreshes
- [ ] **Expected**: Updated contract shows new status
- [ ] **Pass/Fail**: ___________

---

## Browser Console Tests

### Test 24: No JavaScript Errors
- [ ] **Action**: Open browser DevTools (F12)
- [ ] **Action**: Navigate to admin view
- [ ] **Verify**: Console tab shows no errors
- [ ] **Verify**: No 404s for missing files
- [ ] **Verify**: No TypeScript errors
- [ ] **Pass/Fail**: ___________

---

### Test 25: Component Mounting
- [ ] **Action**: Watch React DevTools (if installed)
- [ ] **Verify**: AdminDashboard component mounts
- [ ] **Verify**: ContractList → ContractRow hierarchy visible
- [ ] **Verify**: No unnecessary re-renders
- [ ] **Pass/Fail**: ___________

---

## Accessibility Tests (Future Enhancement)

### Test 26: Keyboard-Only Navigation
- [ ] **Action**: Use only keyboard (no mouse)
- [ ] **Verify**: Can toggle views with Tab
- [ ] **Verify**: Can navigate contracts with arrows
- [ ] **Verify**: Can expand/collapse with Enter
- [ ] **Verify**: Can return with ESC
- [ ] **Pass/Fail**: ___________

---

## Edge Cases

### Test 27: Empty Contract List
- [ ] **Setup**: Modify `useContracts.tsx` to return empty array
- [ ] **Verify**: Shows "0 contracts" message
- [ ] **Verify**: No JavaScript errors
- [ ] **Pass/Fail**: ___________

---

### Test 28: Many Contracts (Scroll Test)
- [ ] **Setup**: Add 10+ sample contracts to `useContracts.tsx`
- [ ] **Verify**: List scrolls correctly
- [ ] **Verify**: Filter toggle still works
- [ ] **Verify**: Keyboard navigation cycles through all
- [ ] **Pass/Fail**: ___________

---

## Known Issues / Limitations

1. **Action Buttons Non-functional**: Need backend API endpoints (resend email, cancel, copy links)
2. **No Pagination**: Will need when contract count grows
3. **No Search**: Post-MVP feature
4. **No Statistics Panel**: Post-MVP feature

## ✅ COMPLETED: Real Data Integration

- Backend API `/api/admin/contracts` implemented and working
- WebSocket real-time updates configured via `DataBroadcaster`
- Frontend fetches real contract data (no mock data)
- Summary line displays contract statistics in Swedish

---

## Testing Sign-off

**Tester Name**: _____________________
**Date**: _____________________
**Overall Result**: [ ] PASS / [ ] FAIL
**Notes**:

---

## Next Steps After Testing

1. **If all tests pass**:
   - Document any visual refinements needed
   - Proceed with backend API implementation
   - Implement action button handlers

2. **If tests fail**:
   - Document specific failures
   - Capture screenshots of issues
   - Check browser console for errors
   - Review component implementation
   - Re-test after fixes

3. **Backend Integration** (✅ COMPLETE):
   - ✅ `useContracts.tsx` updated with real API endpoint
   - ✅ WebSocket updates configured
   - TODO: Implement action button handlers
   - TODO: Test with production Zigned webhook data

---

## Quick Test Commands

```bash
# Start dev server
cd /Users/fredrikbranstrom/Projects/kimonokittens
npm run dev

# Open browser (Mac)
open http://localhost:5175

# Check for TypeScript errors
cd dashboard && npx tsc --noEmit

# Check for lint issues
npm run lint

# Build production bundle
npm run build
```

---

## Screenshots to Capture

1. [ ] Public dashboard (default view)
2. [ ] Admin dashboard with all contracts collapsed
3. [ ] Admin dashboard with one contract expanded
4. [ ] Filter toggle in "Active Only" mode
5. [ ] Failed contract with error message
6. [ ] Timeline section detail
7. [ ] Keyboard navigation highlight
8. [ ] Mobile responsive layout

**Save screenshots to**: `/docs/screenshots/admin-dashboard/`

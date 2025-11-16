# Historic Tenants Gantt Timeline - Implementation Specification

**Status**: 🚧 Implementation In Progress
**Created**: 2025-11-16
**Target**: Compress historic tenants display from ~650px to ~300px vertical space (54% reduction)

---

## 1. Overview & Goals

### Problem Statement
The current historic tenants display in the admin dashboard uses expandable `MemberRow` components, consuming significant vertical space (~60-70px per tenant). With 10+ historic tenants, this creates excessive scrolling.

### Solution
Replace historic tenants section with an accurate **horizontal Gantt timeline** showing:
- Tenant names
- Visual duration bars (proportional to actual tenure length)
- Temporal positioning (accurate dates on timeline axis)
- Minimal vertical footprint (~26px per tenant row)

### Success Criteria
- ✅ 50%+ vertical space reduction
- ✅ Accurate timeline positioning (days-to-pixels calculation)
- ✅ Handle long names (e.g., "Frans Lukas Otis Pirat Lövenvald")
- ✅ Responsive to timeline growth (3+ years)
- ✅ Hover tooltips with full details
- ✅ Preserve existing design system colors

---

## 2. Technical Specifications

### 2.1 Timeline Mathematics

**Core Calculations:**
```typescript
// 1. Find timeline bounds from all historic members
const startDate = min(historicalMembers.map(m => m.tenant_start_date))
const endDate = max(historicalMembers.map(m => m.tenant_departure_date))

// 2. Add 5% visual padding on each side
const totalDays = daysBetween(startDate, endDate)
const paddingDays = Math.floor(totalDays * 0.05)
const timelineStart = subDays(startDate, paddingDays)
const timelineEnd = addDays(endDate, paddingDays)
const totalTimelineDays = daysBetween(timelineStart, timelineEnd)

// 3. Calculate pixel-to-day ratio
const containerWidth = containerRef.current?.offsetWidth || 900
const pixelPerDay = containerWidth / totalTimelineDays

// 4. Position each tenant bar
const leftOffset = daysBetween(timelineStart, member.tenant_start_date) * pixelPerDay
const barWidth = daysBetween(member.tenant_start_date, member.tenant_departure_date) * pixelPerDay
```

**Date Utilities Needed:**
```typescript
function daysBetween(start: Date, end: Date): number {
  const msPerDay = 1000 * 60 * 60 * 24
  return Math.floor((end.getTime() - start.getTime()) / msPerDay)
}

function addDays(date: Date, days: number): Date {
  const result = new Date(date)
  result.setDate(result.getDate() + days)
  return result
}

function subDays(date: Date, days: number): Date {
  return addDays(date, -days)
}
```

### 2.2 Timeline Axis Markers

**Dynamic marker strategy** (based on total span):

| Timeline Span | Marker Interval | Example |
|---------------|-----------------|---------|
| < 2 years     | Quarterly       | Q1'22, Q2'22, Q3'22, Q4'22, Q1'23... |
| 2-5 years     | Semi-annual     | Jan'22, Jul'22, Jan'23, Jul'23... |
| > 5 years     | Annual          | 2022, 2023, 2024, 2025... |

**Implementation:**
```typescript
function getTimelineMarkers(startDate: Date, endDate: Date): TimelineMarker[] {
  const years = (endDate.getFullYear() - startDate.getFullYear())

  if (years < 2) {
    return generateQuarterlyMarkers(startDate, endDate)
  } else if (years <= 5) {
    return generateSemiAnnualMarkers(startDate, endDate)
  } else {
    return generateAnnualMarkers(startDate, endDate)
  }
}

interface TimelineMarker {
  date: Date
  label: string
  position: number // pixels from left
}
```

### 2.3 Name Placement Algorithm

**Challenge**: Long names (28+ characters) don't fit in short tenure bars (<3 months = ~81px).

**Strategy**: Dynamic placement based on available space.

```typescript
function calculateNamePlacement(
  barWidth: number,
  fullName: string,
  container: HTMLElement
): NamePlacement {
  // Measure full name width in pixels
  const fullNameWidth = measureTextWidth(fullName, '12px Inter')

  // Strategy 1: Full name inside bar
  if (barWidth >= fullNameWidth + 40) { // 40px = left+right padding
    return {
      type: 'inside',
      text: fullName,
      truncate: false
    }
  }

  // Strategy 2: Initials inside bar
  const initials = getInitials(fullName) // "Frans Lukas..." → "F.L.O.P.L."
  const initialsWidth = measureTextWidth(initials, '11px Inter')

  if (barWidth >= initialsWidth + 24) {
    return {
      type: 'inside',
      text: initials,
      truncate: false
    }
  }

  // Strategy 3: Truncated name inside
  if (barWidth >= 60) {
    const truncated = truncateToFit(fullName, barWidth - 24, '11px Inter')
    return {
      type: 'inside',
      text: truncated,
      truncate: true
    }
  }

  // Strategy 4: Name AFTER bar (outside)
  return {
    type: 'outside',
    text: fullName,
    truncate: false
  }
}

interface NamePlacement {
  type: 'inside' | 'outside'
  text: string
  truncate: boolean
}
```

**Text measurement utility:**
```typescript
function measureTextWidth(text: string, font: string): number {
  const canvas = document.createElement('canvas')
  const context = canvas.getContext('2d')!
  context.font = font
  return context.measureText(text).width
}

function getInitials(fullName: string): string {
  return fullName
    .split(' ')
    .map(word => word[0]?.toUpperCase() || '')
    .join('.')
}

function truncateToFit(text: string, maxWidth: number, font: string): string {
  if (measureTextWidth(text, font) <= maxWidth) return text

  let truncated = text
  while (truncated.length > 3 && measureTextWidth(truncated + '...', font) > maxWidth) {
    truncated = truncated.slice(0, -1)
  }
  return truncated + '...'
}
```

---

## 3. Component Architecture

### 3.1 Component Hierarchy

```
CompactTenantTimeline.tsx (main container)
├── TimelineAxis.tsx (date markers + grid lines)
├── TenantBars.tsx (stacked rows container)
│   └── TenantBar.tsx (individual tenant bar)
│       ├── BarContent (name, gradient, styling)
│       └── DurationLabel (e.g., "2y 3m")
└── TenantTooltip.tsx (hover details)
```

### 3.2 Component Props

**CompactTenantTimeline.tsx:**
```typescript
interface CompactTenantTimelineProps {
  members: Member[]           // Historic members only
  containerWidth?: number     // Optional override (defaults to auto-measure)
}
```

**TimelineAxis.tsx:**
```typescript
interface TimelineAxisProps {
  startDate: Date
  endDate: Date
  pixelPerDay: number
  containerWidth: number
}
```

**TenantBar.tsx:**
```typescript
interface TenantBarProps {
  member: Member
  timelineStart: Date
  pixelPerDay: number
  index: number              // For stacking order
  onHover?: (member: Member | null) => void
}
```

### 3.3 Data Flow

```
1. ContractList.tsx
   ↓ (filters historic members)
2. CompactTenantTimeline
   ↓ (calculates timeline bounds, pixel ratio)
3. TimelineAxis (renders date markers)
4. TenantBars
   ↓ (maps members to bars)
5. TenantBar (positions, renders each bar)
   ↓ (on hover)
6. TenantTooltip (shows full details)
```

---

## 4. Visual Design Specifications

### 4.1 Layout Dimensions

**Container:**
- Width: 100% of parent (typically ~70% of dashboard width = 900-1000px)
- Height: Dynamic based on member count
  - Timeline axis: 30px
  - Each tenant row: 26px (22px bar + 4px gap)
  - Bottom padding: 10px
  - **Total for 10 tenants**: 30 + (26 × 10) + 10 = **300px**

**Timeline Axis:**
- Height: 30px
- Background: Transparent
- Marker text: 10px, `text-purple-300/40`
- Grid lines: 1px, `border-purple-500/10`, extends down through bars

**Tenant Bar:**
- Height: 22px
- Border radius: 4px
- Margin bottom: 4px
- Minimum width: 24px (for very short stays)

### 4.2 Color System

**Bar gradients** (aligned with existing design):
```typescript
// Has completed contract
const completedGradient = 'bg-gradient-to-r from-cyan-500/80 to-cyan-600/80'
const completedBorder = 'border-t border-cyan-400/30'

// No contract (tenant only)
const noContractGradient = 'bg-gradient-to-r from-purple-500/60 to-purple-600/60'
const noContractBorder = 'border-t border-purple-400/30'

// Hover state
const hoverEffect = 'hover:brightness-110 transition-all duration-200'
```

**Text colors:**
```typescript
// Name inside bar
const nameInside = 'text-white font-medium drop-shadow-sm'

// Name outside bar (to the right)
const nameOutside = 'text-purple-200 font-normal'

// Duration label
const duration = 'text-purple-300/60 text-xs'
```

### 4.3 Typography

**Name text:**
- Inside bar: 12px, font-weight 500, white with subtle drop shadow
- Outside bar: 11px, font-weight 400, purple-200
- Font family: Inter (existing design system)

**Duration label:**
- 10px, font-weight 400, purple-300/60
- Format: "2y 3m", "8m", "15d"

**Timeline markers:**
- 10px, font-weight 400, purple-300/40
- Format depends on interval (see section 2.2)

### 4.4 Hover States

**Bar hover:**
```css
.tenant-bar:hover {
  filter: brightness(1.1);
  transform: translateY(-1px);
  box-shadow: 0 2px 8px rgba(96, 165, 250, 0.2);
  z-index: 10;
  cursor: pointer;
  transition: all 0.2s ease-in-out;
}
```

**Tooltip design:**
- Position: Absolute, above bar (or below if near top)
- Background: `bg-slate-800/95 backdrop-blur-sm`
- Border: `border border-purple-500/30`
- Padding: 12px
- Border radius: 6px
- Box shadow: `0 4px 12px rgba(0,0,0,0.3)`
- Max width: 280px

**Tooltip content:**
```
Frans Lukas Otis Pirat Lövenvald
Room B • Contract: Klar ✓
15 jan 2023 → 31 mar 2025
2 år 3 månader
```

---

## 5. Implementation Steps

### Phase 1: Core Timeline Component (Steps 1-4)

**Step 1: Create date utilities**
- File: `dashboard/src/utils/dateCalculations.ts`
- Functions: `daysBetween`, `addDays`, `subDays`
- Test with known date ranges

**Step 2: Create CompactTenantTimeline component**
- File: `dashboard/src/components/admin/CompactTenantTimeline.tsx`
- Accept `members` prop
- Calculate timeline bounds (start/end dates)
- Calculate `pixelPerDay` ratio
- Render container with background

**Step 3: Create TimelineAxis component**
- File: `dashboard/src/components/admin/TimelineAxis.tsx`
- Generate markers based on span (quarterly/semi-annual/annual)
- Render marker labels and vertical grid lines
- Position markers using absolute positioning

**Step 4: Create TenantBar component**
- File: `dashboard/src/components/admin/TenantBar.tsx`
- Calculate `leftOffset` and `barWidth` from dates
- Render colored bar with gradient
- Add duration label to the right

### Phase 2: Name Placement Logic (Steps 5-6)

**Step 5: Implement text measurement utilities**
- File: `dashboard/src/utils/textMeasurement.ts`
- Functions: `measureTextWidth`, `getInitials`, `truncateToFit`
- Use canvas context for accurate measurement

**Step 6: Implement dynamic name placement**
- In `TenantBar.tsx`
- Use `calculateNamePlacement` algorithm (see section 2.3)
- Conditionally render name inside vs outside bar
- Handle truncation and initials

### Phase 3: Interactivity (Steps 7-8)

**Step 7: Add hover effects**
- CSS transitions on bar hover
- Brightness increase, subtle lift
- Track hovered member in state

**Step 8: Create tooltip component**
- File: `dashboard/src/components/admin/TenantTooltip.tsx`
- Show on bar hover
- Display: full name, room, dates, contract status, duration
- Position above bar (flip to below if near container top)

### Phase 4: Integration (Step 9)

**Step 9: Update ContractList.tsx**
- Import `CompactTenantTimeline`
- Replace historic members `MemberRow` mapping with:
  ```tsx
  {historicalMembers.length > 0 && (
    <CompactTenantTimeline members={historicalMembers} />
  )}
  ```
- Keep current members using existing `MemberRow` (no changes)

### Phase 5: Refinement (Steps 10-12)

**Step 10: Responsive behavior**
- Add container width measurement with `useRef` + `ResizeObserver`
- Recalculate `pixelPerDay` on window resize
- Consider horizontal scroll for very wide timelines (5+ years)

**Step 11: Accessibility**
- Add `role="img"` and `aria-label` to timeline
- Ensure bars are keyboard focusable (`tabIndex={0}`)
- Show tooltip on keyboard focus, not just hover
- Add screen reader text with full details

**Step 12: Performance optimization**
- Memoize timeline calculations (`useMemo`)
- Debounce resize handler
- Virtualize bars if > 50 members (unlikely but future-proof)

---

## 6. Edge Cases & Handling

### 6.1 Data Edge Cases

**No historic members:**
- Don't render component at all
- Show existing "Inga historiska medlemmar" message

**Single historic member:**
- Timeline still renders with padding
- Shows isolated bar with full context

**Overlapping tenures:**
- Stack bars vertically (no horizontal overlap)
- Z-index on hover to bring hovered bar to top

**Very short stays (< 1 week):**
- Minimum bar width: 24px (enough to see, click, hover)
- Duration label shows days: "5d"

**Very long stays (5+ years):**
- Bar can span entire timeline width
- Name always fits inside

**Future departure dates (shouldn't happen but defensive):**
- Filter out members with `departure_date > today` before passing to component
- Or cap departure date at `today`

### 6.2 Visual Edge Cases

**Extremely long name + short stay:**
- Use "outside bar" placement
- Name appears to the right of bar
- May extend beyond container → consider truncation at container edge

**Timeline > 10 years:**
- Use annual markers only
- Consider adding zoom controls or horizontal scroll
- Or paginate timeline (e.g., show last 5 years by default)

**Container width < 600px (mobile):**
- Consider fallback to simple vertical list (not Gantt)
- Or allow horizontal scroll with touch gestures

**Too many members (20+):**
- Vertical scroll is acceptable (still more compact than old design)
- Could add "Show more/less" collapse after 15 members

### 6.3 Date Calculation Edge Cases

**Timezone issues:**
- Normalize all dates to start of day (00:00:00)
- Use `setHours(0, 0, 0, 0)` before calculations

**Daylight saving time:**
- Use day-based math, not millisecond math
- `daysBetween` function accounts for this

**Leap years:**
- JavaScript Date handles this automatically
- No special handling needed

**Missing departure_date (shouldn't happen for historic):**
- Filter out at ContractList level
- Or defensively use `today` as fallback

---

## 7. Testing Strategy

### 7.1 Unit Tests

**Date utilities (`dateCalculations.test.ts`):**
```typescript
describe('daysBetween', () => {
  it('calculates days correctly', () => {
    expect(daysBetween(new Date('2023-01-01'), new Date('2023-01-31'))).toBe(30)
  })

  it('handles leap years', () => {
    expect(daysBetween(new Date('2024-02-01'), new Date('2024-03-01'))).toBe(29)
  })
})
```

**Text utilities (`textMeasurement.test.ts`):**
```typescript
describe('getInitials', () => {
  it('generates initials from full name', () => {
    expect(getInitials('Frans Lukas Otis Pirat Lövenvald')).toBe('F.L.O.P.L.')
  })
})
```

### 7.2 Integration Tests

**Timeline calculations:**
- Verify pixel positioning for known date ranges
- Check timeline bounds calculation
- Ensure bars don't overflow container

**Name placement:**
- Test all four strategies (inside full, inside initials, inside truncated, outside)
- Verify text measurement accuracy

### 7.3 Visual Regression Testing

**Manual testing scenarios:**
1. Load admin dashboard with 5 historic members (varied tenure lengths)
2. Verify bars align with timeline axis
3. Hover each bar, verify tooltip appears with correct data
4. Resize browser window, verify recalculation
5. Check long names display correctly
6. Verify color coding (contract vs no contract)

**Test data needed:**
- Short stay (1 month)
- Medium stay (1 year)
- Long stay (3+ years)
- Very long name
- Very short name
- Overlapping tenures

---

## 8. Performance Considerations

### 8.1 Rendering Performance

**Current member count: ~10 historic**
- 10 TenantBar components
- 1 TimelineAxis
- Minimal DOM nodes per bar (~3-4)
- Total: ~40-50 DOM nodes
- **Performance impact: Negligible**

**Future scaling (50+ members):**
- Consider virtualization (react-window)
- Only render visible bars in scrollable container
- Render on-demand as user scrolls

### 8.2 Calculation Performance

**Timeline calculations run on:**
- Initial mount
- Window resize
- Members data change (rare)

**Optimization:**
```typescript
const timelineMetrics = useMemo(() => {
  return calculateTimelineMetrics(members)
}, [members])

const handleResize = useMemo(
  () => debounce(() => setContainerWidth(ref.current?.offsetWidth), 150),
  []
)
```

### 8.3 Memory Considerations

**Text measurement canvas:**
- Create once, reuse for all measurements
- Store in ref, not recreated on re-render

**Tooltip:**
- Single shared tooltip, repositioned on hover
- Not one tooltip per bar (memory waste)

---

## 9. Future Enhancements (Post-MVP)

### 9.1 Interactive Features

**Click to expand details:**
- Click bar → expand full MemberRow below timeline
- Allows editing/actions if needed in future

**Drag to filter date range:**
- Drag selection box over timeline
- Filter view to selected time period

**Room filtering:**
- Toggle buttons: "Room A", "Room B", "All"
- Highlight bars for selected room

### 9.2 Visual Enhancements

**Room color coding:**
- Subtle hue shift per room (Room A = cyan, B = purple, C = blue)
- Legend showing room colors

**Contract status indicators:**
- Small icon on bar: ✓ (completed), ⏱ (pending), ✗ (none)

**Density toggle:**
- Compact mode (current 26px rows)
- Comfortable mode (36px rows, easier to click)

### 9.3 Export/Analytics

**Export timeline as image:**
- Render to canvas, download as PNG
- Useful for reports, presentations

**Statistics overlay:**
- Show average tenure length
- Highlight gaps between tenants (vacancy periods)
- Room turnover rate

---

## 10. File Structure Summary

**New files to create:**
```
dashboard/src/
├── components/admin/
│   ├── CompactTenantTimeline.tsx      (main component)
│   ├── TimelineAxis.tsx               (date markers)
│   ├── TenantBar.tsx                  (individual bar)
│   └── TenantTooltip.tsx              (hover details)
├── utils/
│   ├── dateCalculations.ts            (date math helpers)
│   └── textMeasurement.ts             (text width, truncation)
└── __tests__/
    ├── dateCalculations.test.ts
    └── textMeasurement.test.ts
```

**Files to modify:**
```
dashboard/src/components/admin/
└── ContractList.tsx                   (replace historic section rendering)
```

---

## 11. Implementation Checklist

### Phase 1: Foundation
- [ ] Create `dateCalculations.ts` utility
- [ ] Create `CompactTenantTimeline.tsx` skeleton
- [ ] Create `TimelineAxis.tsx` with date markers
- [ ] Create `TenantBar.tsx` with basic positioning

### Phase 2: Name Placement
- [ ] Create `textMeasurement.ts` utility
- [ ] Implement `calculateNamePlacement` logic
- [ ] Add dynamic name rendering (inside/outside)
- [ ] Test with various name lengths

### Phase 3: Styling
- [ ] Apply gradient colors based on contract status
- [ ] Add hover effects to bars
- [ ] Style timeline axis and grid lines
- [ ] Add duration labels

### Phase 4: Interactivity
- [ ] Create `TenantTooltip.tsx` component
- [ ] Implement hover state tracking
- [ ] Position tooltip relative to bar
- [ ] Show full member details in tooltip

### Phase 5: Integration
- [ ] Update `ContractList.tsx` to use new component
- [ ] Test with real production data
- [ ] Handle edge cases (no data, single member, etc.)

### Phase 6: Polish
- [ ] Add responsive container width measurement
- [ ] Implement resize handling
- [ ] Add accessibility attributes
- [ ] Performance optimization (memoization)

### Phase 7: Testing
- [ ] Write unit tests for utilities
- [ ] Manual testing with various data sets
- [ ] Cross-browser testing
- [ ] Mobile/tablet testing

---

## 12. Success Metrics

**Before (current design):**
- Vertical space: ~650px for 10 historic members
- Information density: Low (one tenant per large row)
- Temporal context: Text-only dates, no visual duration

**After (Gantt timeline):**
- Vertical space: ~300px for 10 historic members (54% reduction)
- Information density: High (10 tenants in compact timeline)
- Temporal context: Visual duration bars, accurate positioning
- Hover details: Full information available on demand

**Qualitative goals:**
- ✅ Immediately see tenure patterns (who stayed longest)
- ✅ Identify gaps/overlaps between tenants
- ✅ Reduce scrolling in admin dashboard
- ✅ Maintain accessibility and usability

---

**End of Implementation Specification**
**Ready for development**: All technical details, edge cases, and implementation steps defined.
**Estimated implementation time**: 4-6 hours
**Files to create**: 6 new files
**Files to modify**: 1 existing file

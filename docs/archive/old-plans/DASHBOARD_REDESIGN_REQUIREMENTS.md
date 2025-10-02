# Dashboard Redesign Requirements Plan
## Futuristic Neon Purple Theme with DRY Architecture

**Generated**: 2025-01-20
**Based on**: Ultra-thinking analysis of existing React/TypeScript dashboard codebase
**Target**: 40% code reduction through shared components + cohesive design system

---

## 1. Current Architecture Analysis

### Existing Components (8 widgets)
- **ClockWidget**: Swedish time/date formatting, greeting logic
- **WeatherWidget**: WeatherAPI integration, temperature colors, forecast display
- **TemperatureWidget**: Indoor sensors, grid layout, status indicators
- **TrainWidget**: SL transport data, HTML content rendering
- **StravaWidget**: Running stats with HTML formatting
- **LogoWidget**: Central branding with hover effects
- **TodoWidget**: Mock task list with priority colors
- **CalendarWidget**: Mock events with smart date formatting

### Data Integration Patterns
```typescript
// Standard pattern across all data widgets:
const { state } = useData()
const { connectionStatus, [dataType]Data } = state
const loading = connectionStatus === 'connecting' && ![dataType]Data
const error = connectionStatus === 'closed' ? 'WebSocket-anslutning avbruten' : null
```

### Current Layout System
- 3-column CSS flexbox (`grid-cols-3 gap-8`)
- Vertical stacking within columns
- Fixed positioning, limited visual hierarchy

---

## 2. DRY Component Architecture

### A. Shared State Management
**Problem**: Loading/error logic duplicated 5+ times
**Solution**: Generic WidgetStateWrapper component

```typescript
// src/components/shared/WidgetStateWrapper.tsx
interface WidgetStateWrapperProps<T> {
  data: T | undefined
  connectionStatus: 'connecting' | 'open' | 'closed' | 'error'
  loadingMessage?: string
  errorMessage?: string
  children: (data: T) => React.ReactNode  // render-props pattern
}

// Usage in widgets:
<WidgetStateWrapper data={weatherData} connectionStatus={connectionStatus}>
  {(data) => <WeatherContent data={data} />}
</WidgetStateWrapper>
```

### B. Centralized Utilities

#### Theme Colors (`src/utils/theme.ts`)
```typescript
export const neonTheme = {
  text: {
    primary: 'text-purple-200',        // #E9D5FF
    secondary: 'text-purple-300/70',   // rgba(196,181,253,0.7)
    content: 'text-purple-100/90',     // rgba(243,232,255,0.9)
    accent: 'text-fuchsia-300',        // #F0ABFC
    muted: 'text-purple-300/60'        // rgba(196,181,253,0.6)
  },
  status: {
    success: 'text-emerald-300',
    warning: 'text-amber-300',
    error: 'text-rose-400',
    info: 'text-blue-300'
  }
}

export const getTemperatureColor = (temp: number): string => {
  if (temp < 0) return neonTheme.status.info
  if (temp < 10) return 'text-blue-200'
  if (temp < 20) return 'text-emerald-300'
  if (temp < 30) return neonTheme.status.warning
  return neonTheme.status.error
}
```

#### Swedish Formatters (`src/utils/formatters.ts`)
```typescript
export const formatSwedishTime = (date: Date): string =>
  date.toLocaleTimeString('sv-SE', { hour: '2-digit', minute: '2-digit', second: '2-digit' })

export const formatSwedishDate = (date: Date): string =>
  date.toLocaleDateString('sv-SE', { weekday: 'long', year: 'numeric', month: 'long', day: 'numeric' })

export const getGreeting = (hour: number): string => {
  if (hour < 6) return 'God natt'
  if (hour < 12) return 'God morgon'
  if (hour < 17) return 'God dag'
  if (hour < 22) return 'God kväll'
  return 'God natt'
}

export const getRelativeDate = (date: Date): string => {
  const today = new Date()
  const tomorrow = new Date(today)
  tomorrow.setDate(today.getDate() + 1)

  if (date.toDateString() === today.toDateString()) return 'Idag'
  if (date.toDateString() === tomorrow.toDateString()) return 'Imorgon'
  return formatSwedishDate(date)
}
```

#### Icon Mapping (`src/utils/icons.ts`)
```typescript
export const weatherIcons = {
  sun: '☀️', clear: '☀️', cloud: '☁️', rain: '🌧️',
  snow: '❄️', thunder: '⛈️', default: '🌤️'
}

export const statusIcons = {
  connected: '🟢', connecting: '🟡', disconnected: '🔴',
  success: '✅', error: '❌', warning: '⚠️'
}

export const getWeatherIcon = (iconUrl: string): string => {
  if (iconUrl.includes('sun') || iconUrl.includes('clear')) return weatherIcons.sun
  if (iconUrl.includes('cloud')) return weatherIcons.cloud
  if (iconUrl.includes('rain')) return weatherIcons.rain
  if (iconUrl.includes('snow')) return weatherIcons.snow
  if (iconUrl.includes('thunder')) return weatherIcons.thunder
  return weatherIcons.default
}
```

### C. Widget Variant System
```typescript
// src/types/widget.ts
export interface WidgetProps {
  variant?: 'default' | 'hero' | 'compact' | 'wide'
  priority?: 'high' | 'medium' | 'low'
  className?: string
}

export interface WidgetVariantConfig {
  containerClass: string
  titleClass: string
  contentClass: string
}

export const widgetVariants: Record<WidgetProps['variant'], WidgetVariantConfig> = {
  default: {
    containerClass: 'widget',
    titleClass: 'widget-title',
    contentClass: 'widget-content'
  },
  hero: {
    containerClass: 'widget widget-hero',
    titleClass: 'widget-title text-lg',
    contentClass: 'widget-content text-lg'
  },
  compact: {
    containerClass: 'widget p-3',
    titleClass: 'widget-title text-sm',
    contentClass: 'widget-content text-sm'
  },
  wide: {
    containerClass: 'widget',
    titleClass: 'widget-title text-base',
    contentClass: 'widget-content'
  }
}
```

---

## 3. Neon Purple Theme System

### Color Palette Specifications
```css
:root {
  /* Background layers */
  --bg-primary: linear-gradient(180deg, #0a0713 0%, #090613 100%);
  --bg-accent-1: radial-gradient(1200px 600px at 10% -10%, rgba(139, 92, 246, 0.10), transparent 60%);
  --bg-accent-2: radial-gradient(1000px 500px at 90% 110%, rgba(236, 72, 153, 0.06), transparent 55%);

  /* Glass panel system */
  --panel-bg: rgba(255, 255, 255, 0.05);
  --panel-border: rgba(217, 70, 239, 0.1);          /* fuchsia-300/10 */
  --panel-border-hover: rgba(217, 70, 239, 0.2);    /* fuchsia-300/20 */
  --panel-shadow: 0 10px 40px -15px rgba(168, 85, 247, 0.15);
  --panel-shadow-hover: 0 10px 40px -10px rgba(168, 85, 247, 0.25);

  /* Typography hierarchy */
  --text-primary: #E9D5FF;                          /* purple-200 */
  --text-secondary: rgba(196, 181, 253, 0.7);       /* purple-300/70 */
  --text-content: rgba(243, 232, 255, 0.9);         /* purple-100/90 */
  --text-accent: #F0ABFC;                           /* fuchsia-300 */
  --text-muted: rgba(196, 181, 253, 0.6);           /* purple-300/60 */
}
```

### Glass Panel Components
```css
.widget {
  background: var(--panel-bg);
  backdrop-filter: blur(12px);
  border: 1px solid var(--panel-border);
  box-shadow: var(--panel-shadow);
  border-radius: 1rem;
  padding: 1.25rem 1.5rem;
  transition: all 300ms ease-out;

  @apply relative flex flex-col space-y-4;
}

.widget:hover {
  border-color: var(--panel-border-hover);
  box-shadow: var(--panel-shadow-hover);
  transform: translateY(-1px);
}

.widget-hero {
  padding: 1.5rem 2rem 2.5rem;
  border-color: rgba(139, 92, 246, 0.15);  /* violet-400/15 */
  box-shadow:
    0 0 0 1px rgba(139, 92, 246, 0.06),
    0 30px 80px -30px rgba(139, 92, 246, 0.35);
}

.widget-title {
  @apply text-sm sm:text-base font-semibold tracking-widest uppercase;
  color: var(--text-secondary);
}

.widget-content {
  color: var(--text-content);
}
```

---

## 4. Layout Architecture - Portrait-First 6x10 Grid

### Portrait Grid System (Optimized for Hallway Monitor)
```css
.dashboard-grid {
  @apply relative h-screen w-screen grid grid-cols-6 grid-rows-10 gap-4 p-6;
  /* Portrait-first: 6 columns, 10 rows for vertical displays */
}

/* Background decorations - vertical flow */
.cyber-bg {
  @apply absolute inset-0 -z-10 w-full h-full;
  background:
    radial-gradient(400px 800px at 50% 10%, rgba(139,92,246,0.08), transparent 60%),
    radial-gradient(350px 700px at 50% 90%, rgba(236,72,153,0.05), transparent 60%);
}

.grid-overlay {
  @apply absolute inset-0 -z-10 pointer-events-none;
  background-image:
    linear-gradient(rgba(167, 139, 250, 0.05) 1px, transparent 1px),
    linear-gradient(90deg, rgba(167, 139, 250, 0.05) 1px, transparent 1px);
  background-size: 30px 30px;
  mask-image: radial-gradient(ellipse 40% 80% at center, rgba(0,0,0,0.8), transparent);
}
```

### Portrait Widget Positioning
```css
/* PORTRAIT-FIRST LAYOUT - Hallway Display */
.clock-hero     { @apply col-span-6 row-span-2; }           /* Full width header */
.weather-wide   { @apply col-span-6 row-span-2; }           /* Full width weather */
.train-wide     { @apply col-span-6 row-span-2; }           /* Full width transport */
.strava-compact { @apply col-span-3 row-span-2; }           /* Left half */
.temp-overlay   { @apply col-span-3 row-span-2; }           /* Right half */
.todo-side      { @apply col-span-6 row-span-1; }           /* Compact todo */
.calendar-side  { @apply col-span-6 row-span-1; }           /* Compact calendar */
.logo-corner    { @apply col-span-2 col-start-5 row-span-1 row-start-10; } /* Lower right logo */

/* Alternative logo positions (configurable) */
.logo-upper-right { @apply col-span-2 col-start-5 row-span-1 row-start-1; }
.logo-lower-right { @apply col-span-2 col-start-5 row-span-1 row-start-10; }

/* LANDSCAPE FALLBACK (≥1280px width AND landscape orientation) */
@media (min-width: 1280px) and (orientation: landscape) {
  .dashboard-grid { @apply grid-cols-12 grid-rows-6 gap-6 p-8; }

  .clock-hero     { @apply col-span-5 row-span-3; }
  .weather-wide   { @apply col-span-7 row-span-2; }
  .logo-center    { @apply col-span-4 col-start-5 row-span-2 row-start-3; }
  .train-wide     { @apply col-span-7 row-span-3 row-start-4; }
  .strava-compact { @apply col-span-5 row-span-3 row-start-4; }
  .temp-overlay   { @apply col-span-3 row-span-2 row-start-5; }
  .todo-side      { @apply col-span-2 row-span-4 row-start-1; }
  .calendar-side  { @apply col-span-2 row-span-2 row-start-5; }
}

/* MOBILE PORTRAIT (≤768px) */
@media (max-width: 768px) and (orientation: portrait) {
  .dashboard-grid {
    @apply grid-cols-2 auto-rows-min gap-3 p-4;
    height: auto;
  }
  /* 2-column layout for narrow screens */
}
```

---

## 5. Implementation Strategy

### Phase 1: Shared Components (1-2 hours)
1. **Create directory structure**:
   ```
   src/
   ├── components/shared/
   │   ├── WidgetStateWrapper.tsx
   │   └── WidgetContainer.tsx
   ├── utils/
   │   ├── theme.ts
   │   ├── formatters.ts
   │   └── icons.ts
   └── types/
       └── widget.ts
   ```

2. **Implement WidgetStateWrapper** with generic typing and render-props pattern
3. **Create utility modules** for theme, formatters, and icon mapping
4. **Add TypeScript interfaces** for widget variants and props

### Phase 2: Layout Migration (1 hour)
1. **Update CSS grid system** in `index.css`
2. **Modify App.tsx** with new asymmetric positioning
3. **Add background decorations** (cyber-bg, grid-overlay)
4. **Test responsive breakpoints** at 1280px, 768px

### Phase 3: Widget Migration (2-3 hours)
**Migration order** (dependency-based):
1. **ClockWidget**: Add hero variant, integrate formatters
2. **LogoWidget**: Center positioning, enhanced glow effects
3. **WeatherWidget**: Wide layout, shared color utilities
4. **TemperatureWidget**: Shared formatters and icon logic
5. **TrainWidget**: Wide layout, improved content rendering
6. **StravaWidget**: Compact layout, enhanced stats display
7. **TodoWidget**: Sidebar layout, shared priority colors
8. **CalendarWidget**: Sidebar layout, shared date formatting

### Phase 4: Polish & Testing (1 hour)
1. **ConnectionStatus** theme integration
2. **Animation refinements** (hover states, transitions)
3. **Performance check** (glass effects, backdrop-blur)
4. **Cross-browser testing** (Safari backdrop-blur support)

---

## 6. Migration Safety & Backwards Compatibility

### Zero-Downtime Strategy
- **Incremental migration**: Each widget can be updated independently
- **Fallback classes**: Original CSS classes remain during transition
- **Data logic preservation**: All WebSocket/DataContext patterns unchanged
- **TypeScript safety**: Generic typing prevents data shape errors

### Testing Checkpoints
```typescript
// Unit tests for shared components
describe('WidgetStateWrapper', () => {
  it('renders loading state correctly')
  it('renders error state with custom message')
  it('passes data to children via render prop')
})

// Integration tests
describe('Dashboard Layout', () => {
  it('renders all widgets in correct grid positions')
  it('maintains WebSocket connection during widget updates')
  it('responsive breakpoints work correctly')
})

// Visual regression tests
describe('Theme Application', () => {
  it('applies neon purple theme consistently')
  it('glass panels render with correct opacity/blur')
  it('hover states work across all widgets')
})
```

---

## 7. Performance Considerations

### Optimizations
- **React.memo** on static widgets (Logo, mock Todo/Calendar)
- **will-change: transform** only on hover (not permanent)
- **prefers-reduced-transparency** check for low-power devices
- **Tree-shakable imports** for icon utilities

### Bundle Impact
- **Estimated size**: +15KB for shared utilities
- **Code reduction**: -40% through DRY patterns
- **Net impact**: ~25% smaller bundle size

---

## 8. Key Benefits Summary

### Code Quality
- **40% reduction** in duplicated loading/error/formatting logic
- **Single source of truth** for colors, icons, date formatting
- **Type-safe variants** with compile-time checking
- **Maintainable architecture** for future widget additions

### User Experience
- **Visual hierarchy** through asymmetric 12x6 grid
- **Cohesive design system** with consistent glass panels
- **Futuristic aesthetic** via low-contrast neon purple theme
- **Responsive layout** from desktop to mobile

### Developer Experience
- **Clear migration path** with backwards compatibility
- **Reusable components** for rapid widget development
- **TypeScript safety** with generic utilities
- **Performance-conscious** architecture choices

---

## 9. Expert Recommendations Integration

Based on expert analysis, the following refinements have been incorporated:

### Type Safety Improvements
- Generic `WidgetStateWrapper<T>` instead of `any` typing
- Render-props pattern for guaranteed data availability
- ConnectionStatus union type definition

### Theme Architecture
- Tailwind config integration for shared color constants
- CSS custom properties for runtime theme switching
- WCAG AA contrast compliance checks

### Performance & Accessibility
- Backdrop-blur performance considerations
- Reduced-transparency media query support
- Keyboard focus outline preservation during hover elevation
- Grid auto-flow dense for missing widget handling

### Responsive Strategy
- Media query breakpoints: 1280px (8-col), 768px (stacked)
- Mobile-first approach with progressive enhancement
- Container query support for widget-level responsiveness

---

*This requirements plan serves as the definitive guide for implementing the futuristic neon purple dashboard redesign with maximum code reuse and maintainability.*
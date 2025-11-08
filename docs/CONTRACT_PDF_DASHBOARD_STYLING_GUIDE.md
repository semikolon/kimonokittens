# Contract PDF Dashboard Styling Guide

**Created**: November 8, 2025
**Purpose**: Reference guide for creating PDF contracts that match the Kimono Kittens dashboard aesthetic

## Color Palette (From Dashboard CSS + Screenshot Analysis)

### Background Colors
```ruby
# Dark gradient base (almost black with purple tint)
bg_dark: '0c0a10'      # rgb(12, 10, 16) - darkest
bg_mid: '191e1e'       # rgb(25, 20, 30) - mid gradient

# Pure black for deepest areas
bg_black: '000000'
```

### Text Colors
```ruby
# Light text on dark background
text_primary: 'ddd6fe'  # rgb(221, 214, 254) - main body text (purple-200)
text_heading: 'f8fafc'  # rgb(248, 250, 252) - almost white for headings
text_muted: '94a3b8'    # rgb(148, 163, 184) - muted gray-blue for secondary text
```

### Accent Colors (Storm-Blue Palette)
```ruby
# Purple accents (from Tailwind config)
primary: '6366f1'   # storm-blue-500 - vibrant purple
accent: '818cf8'    # storm-blue-400 - lighter purple
bright: 'a5b4fc'    # storm-blue-300 - bright purple/pink
highlight: 'c7d2fe' # storm-blue-200 - light highlight
```

### Logo Colors
```ruby
# From logo.png analysis
logo_pink: 'ff78c8'    # Hot pink outlines
logo_orange: 'ffaa5a'  # Orange outlines
logo_purple: '7c3aed'  # Deep purple fills
```

## Critical Styling Rules

### 1. Gradient Blobs - EXTREMELY SUBTLE
**Dashboard uses opacity values 10-15x lower than typical:**
```css
/* Dashboard gradient blobs (from index.css) */
rgba(139, 92, 246, 0.02)   /* Purple - barely visible */
rgba(168, 85, 247, 0.015)  /* Purple - extremely subtle */
rgba(124, 58, 237, 0.01)   /* Purple - hint of color */
```

**For PDF (Prawn transparency):**
```ruby
# CORRECT - dashboard-matching subtlety
@pdf.transparent(0.02) { ... }  # Barely visible
@pdf.transparent(0.015) { ... } # Extremely subtle
@pdf.transparent(0.01) { ... }  # Hint of color

# WRONG - what I initially did (text becomes invisible)
@pdf.transparent(0.15) { ... }  # WAY TOO OPAQUE
@pdf.transparent(0.1) { ... }   # Still too strong
```

### 2. Background Gradient
```ruby
# Base layer - almost pure black
fill_color '000000' or '0c0a10'

# Subtle purple tint via multiple overlaid ellipses
# Position them at different locations for organic feel
# Keep opacity 0.01-0.02 range
```

### 3. Text Visibility
```ruby
# Body text
fill_color 'ddd6fe'  # Light purple - clearly visible

# Headings
fill_color 'f8fafc'  # Almost white - high contrast

# Secondary text
fill_color '94a3b8'  # Muted - for metadata/dates
```

### 4. Logo Treatment
- **Size**: 200px width minimum (dashboard logo is large and prominent)
- **Position**: Centered at top of first page
- **Spacing**: Generous margins (30px+ above/below)

### 5. Section Headings
```ruby
# Heading text
fill_color 'a5b4fc'  # Bright purple (storm-blue-300)
font_size 12
style: :bold

# Accent line below heading
gradient_line(height: 1.5)  # Subtle purple glow
```

### 6. Signature Section
**REMOVE ENTIRELY** - Zigned appends its own BankID signature page with:
- Digital timestamps
- Cryptographic proof
- Swedish BankID verification

Manual signature lines are redundant and unprofessional with e-signing.

## Widget-Style Boxes (Optional Enhancement)

### Semi-Transparent Dark Boxes
```ruby
# Landlord/tenant info boxes
@pdf.transparent(0.15) do
  @pdf.fill_color 'primary'  # or 'accent'
  @pdf.fill_rectangle [x, y], width, height
end
```

**Use sparingly** - only for distinct sections like party information.

## Dos and Don'ts

### ✅ DO:
- Keep gradient blobs at 0.01-0.02 opacity
- Use light text (`ddd6fe`) on dark background
- Make logo large and prominent (200px+)
- Use purple accents sparingly for headings
- Test text visibility by converting PDF to PNG

### ❌ DON'T:
- Use opacity above 0.05 for gradient blobs (text becomes invisible)
- Use dark text colors (won't show on dark background)
- Make logo small or tucked in corner
- Overuse colored boxes (cluttered look)
- Include manual signature section (Zigned handles this)

## Testing Process

1. **Generate PDF** with updated styling
2. **Convert to PNG**: `pdftoppm -png -f 1 -l 1 -r 150 contract.pdf /tmp/page`
3. **Visual inspection**: Text should be clearly readable, blobs barely visible
4. **Compare to dashboard**: Match overall vibe and contrast levels

## Reference Files

- **Dashboard CSS**: `dashboard/src/index.css` (lines 43, 152-177)
- **Tailwind config**: `dashboard/tailwind.config.js` (storm-blue palette)
- **Logo**: `dashboard/public/logo.png`
- **Dashboard screenshot**: `.playwright-mcp/dashboard_full.png`

---

**Last Updated**: November 8, 2025
**Validated Against**: Dashboard screenshot + CSS inspection

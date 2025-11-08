# Contract PDF Dashboard Styling Guide

**Created**: November 8, 2025
**Updated**: November 8, 2025 (Deep-dive with actual code analysis)
**Purpose**: Technical reference for creating PDF contracts matching Kimono Kittens dashboard aesthetic

---

## 🎨 Complete Color Palette

### Background Colors (Extracted from index.css + index.html)
```ruby
# Primary gradient base
bg_base: '191e1e'      # rgb(25, 20, 30) - HTML fallback color
bg_dark: '0c0a10'      # rgb(12, 10, 16) - darkest gradient endpoint
bg_black: '000000'     # Pure black for deepest areas

# Gradient definition (CSS)
# background: radial-gradient(circle at center, rgb(25,20,30) 0%, rgb(12,10,16) 100%)
```

### Text Colors (Extracted from index.css line 41)
```ruby
# Body text (default)
text_body: 'ddd6fe'    # rgb(221, 214, 254) - text-purple-200 (CSS line 41)

# Heading text (from App.tsx Widget component)
text_heading_normal: 'e0e7ff'   # text-purple-100 (Tailwind purple-100)
text_heading_accent: 'c7d2fe'   # text-purple-200 (Tailwind purple-200)
text_white: 'f8fafc'            # Almost white for maximum contrast

# Muted/secondary text
text_muted: '94a3b8'   # Muted gray-blue for metadata
```

### Storm-Blue Accent Palette (Tailwind config exact values)
```ruby
# From tailwind.config.js lines 10-22
storm_blue: {
  50:  'f0f4ff',
  100: 'e0e7ff',
  200: 'c7d2fe',  # Headings (accent), light highlights
  300: 'a5b4fc',  # Bright purple/pink accents
  400: '818cf8',  # Lighter purple
  500: '6366f1',  # Primary vibrant purple
  600: '4f46e5',
  700: '4338ca',
  800: '3730a3',
  900: '312e81',  # Widget borders
  950: '1e1b4b'
}
```

### Widget Background Colors (From App.tsx lines 36-37)
```ruby
# Normal widgets
widget_normal_bg: 'rgba(15, 23, 42, 0.4)'  # bg-slate-900/40 in Tailwind
# Semi-transparent dark slate with 40% opacity

# Accent widgets
widget_accent_bg: 'rgba(88, 28, 135, 0.3)' # bg-purple-900/30 in Tailwind
# Semi-transparent purple with 30% opacity

# Widget border
widget_border: 'rgba(49, 46, 129, 0.1)'    # border-purple-900/10
# Very subtle purple border with 10% opacity
```

---

## 📐 Layout & Spacing (Extracted from App.tsx Widget component)

### Widget Box Styling
```css
/* From App.tsx lines 35-38 */
backdrop-filter: blur(8px);           /* backdrop-blur-sm */
background: rgba(15, 23, 42, 0.4);    /* bg-slate-900/40 */
border-radius: 1rem;                  /* rounded-2xl (16px) */
box-shadow: 0 4px 6px -1px rgba(0, 0, 0, 0.1),
            0 2px 4px -1px rgba(0, 0, 0, 0.06); /* shadow-md */
border: 1px solid rgba(49, 46, 129, 0.1); /* border-purple-900/10 */
```

### Padding & Spacing
```css
/* From App.tsx line 39 */
padding: 2rem;              /* p-8 in Tailwind = 32px */

/* Heading margin (line 42) */
margin-bottom: 1.5rem;      /* mb-6 in Tailwind = 24px */
```

---

## 🔤 Typography (Extracted from code + CSS)

### Font Families
```css
/* From tailwind.config.js lines 24-27 */
--font-sans: 'Galvji', sans-serif;         /* Body text */
--font-mono: 'JetBrains Mono', 'Menlo', 'Monaco', 'Consolas', monospace;
--font-heading: 'Horsemen';                /* Handwritten-style headings */

/* Note: Horsemen and Galvji are custom web fonts (loaded externally) */
/* For PDF: Use similar handwritten/graffiti font or fallback to bold sans */
```

### Font Sizes (From index.css + App.tsx)
```css
/* Body text - CRITICAL: Dashboard uses LARGE text */
body {
  font-size: 1.5rem;  /* 24px - index.css line 42 */
  /* This is 20% larger than typical web text! */
}

/* Widget headings (App.tsx line 41) */
h3 {
  font-size: 1.5rem;  /* text-2xl in Tailwind = 24px */
}

/* Subheadings (TrainWidget.tsx line 563) */
h4 {
  font-size: 1.25rem; /* text-xl in Tailwind = 20px */
}
```

### Font Styling (App.tsx Widget component lines 41-42)
```css
/* Heading styles */
font-weight: 500;              /* font-medium */
letter-spacing: 0.025em;       /* tracking-wide */
text-transform: uppercase;     /* uppercase */
```

---

## 🎭 Critical Gradient Blob Opacity

### Dashboard CSS Values (index.css lines 152-177)
```css
/* EXTREMELY subtle - barely visible purple hints */
@keyframes subtle-purple-shift {
  0% {
    background:
      radial-gradient(ellipse at 20% 50%, rgba(139, 92, 246, 0.02) 0%, transparent 60%),
      radial-gradient(ellipse at 80% 20%, rgba(168, 85, 247, 0.015) 0%, transparent 50%),
      radial-gradient(ellipse at 40% 80%, rgba(124, 58, 237, 0.01) 0%, transparent 60%),
      black;
  }
  /* ... */
}
```

### For Prawn PDF
```ruby
# Dashboard-matching subtlety (10-15x less than typical opacity)
@pdf.transparent(0.02) { ... }   # Barely visible purple hint
@pdf.transparent(0.015) { ... }  # Extremely subtle accent
@pdf.transparent(0.01) { ... }   # Hint of color

# ❌ WRONG - text becomes invisible
@pdf.transparent(0.15) { ... }   # Way too opaque!
@pdf.transparent(0.1) { ... }    # Still too strong
```

---

## 📏 PDF-Specific Adaptations

### Text Sizes for PDF (Match Dashboard Scale)
```ruby
# Body text (match dashboard 1.5rem = 24px browser → 18-20pt PDF)
body_text_size: 18      # Points (slightly smaller than screen for print)

# Section headings (match h3 1.5rem = 24px → 20-22pt)
heading_size: 20        # Points

# Subheadings (match h4 1.25rem = 20px → 16-18pt)
subheading_size: 16     # Points

# Small text (metadata, dates)
small_text_size: 12     # Points
```

### Margins & Spacing
```ruby
# Page margins
top: 60, right: 50, bottom: 60, left: 50  # Points

# Section spacing
section_spacing: 20     # Points between sections
paragraph_spacing: 10   # Points between paragraphs
heading_margin: 15      # Points after headings
```

### Widget-Style Boxes (Optional Enhancement)
```ruby
# Semi-transparent dark boxes for party info
@pdf.transparent(0.15) do
  @pdf.fill_color '0f172a'  # slate-900
  @pdf.fill_rectangle [x, y], width, height
end

# Border (very subtle)
@pdf.stroke_color '312e81'  # purple-900
@pdf.transparent(0.1) do
  @pdf.stroke_rectangle [x, y], width, height
end
```

---

## 🎯 Precise Color Usage Guide

### Background Layers (Z-index order)
1. **Base canvas**: Fill with `0c0a10` (darkest purple/black)
2. **Subtle gradient blobs**: 3-5 ellipses with 0.01-0.02 opacity
3. **Content layer**: All text and elements

### Text Color Hierarchy
```ruby
# Primary content
body_text: 'ddd6fe'           # All contract text, bullet points, body copy

# Emphasis
headings: 'e0e7ff'            # Section headings (1. Parter, 2. Objekt, etc.)
accent_headings: 'c7d2fe'     # Special emphasis (amounts, important clauses)

# De-emphasis
metadata: '94a3b8'            # Dates, footnotes, secondary info
footer: '94a3b8'              # Page numbers
```

### Widget-Inspired Colored Boxes
```ruby
# Landlord info box (subtle purple background)
@pdf.transparent(0.15) do
  @pdf.fill_color '6366f1'    # Primary purple
  @pdf.fill_rectangle [x, y], width, height
end

# Tenant info box (slightly different shade)
@pdf.transparent(0.15) do
  @pdf.fill_color '818cf8'    # Accent purple
  @pdf.fill_rectangle [x, y], width, height
end
```

---

## ✅ Implementation Checklist

### Must-Have (Core Dashboard Aesthetic)
- [x] Dark purple/black gradient background (`0c0a10` to `191e1e`)
- [x] Extremely subtle gradient blobs (0.01-0.02 opacity)
- [x] Light text on dark background (`ddd6fe` for body)
- [x] Large text size (18-20pt for body, matching dashboard 1.5rem)
- [ ] Widget-style boxes for party information (optional)
- [x] Remove signature section (Zigned handles BankID)

### Nice-to-Have (Enhanced Polish)
- [ ] Rounded corners on colored boxes (1rem radius)
- [ ] Subtle borders on boxes (purple-900 with 10% opacity)
- [ ] Backdrop blur effect on boxes (not possible in static PDF)
- [ ] Animated gradient (not possible in static PDF)
- [ ] Custom Horsemen font for headings (requires font file acquisition)

---

## 🚫 Common Pitfalls

### ❌ DON'T:
1. Use opacity above 0.05 for gradient blobs → **text becomes invisible**
2. Use small text (10-12pt) → **dashboard uses 1.5rem (24px) body text**
3. Use dark text colors → **won't show on dark background**
4. Overuse colored boxes → **cluttered, un-dashboard-like**
5. Include manual signatures → **Zigned appends BankID page**
6. Use `fill_rectangle` inside `repeat :all` → **covers all content**

### ✅ DO:
1. Keep blobs at 0.01-0.02 opacity → **barely visible purple hints**
2. Use large text (18-20pt body) → **matches dashboard readability**
3. Use light purple text (`ddd6fe`) → **clearly visible, on-brand**
4. Apply boxes sparingly (2-3 max) → **clean, focused**
5. Let Zigned handle signatures → **professional BankID verification**
6. Use `canvas` blocks for backgrounds → **layer separation**

---

## 🧪 Testing & Validation

### Visual Inspection Process
```bash
# 1. Generate PDF
ruby bin/generate_sanna_dashboard_style.rb

# 2. Convert to PNG (150 DPI)
pdftoppm -png -f 1 -l 2 -r 150 contract.pdf /tmp/page

# 3. View PNG
open /tmp/page-1.png

# 4. Compare to dashboard
open docs/images/dashboard_reference_2025-11-08.png
```

### Quality Checklist
- [ ] Text clearly visible against dark background
- [ ] Gradient blobs barely visible (subtle purple hints)
- [ ] Logo large and prominent (200px width minimum)
- [ ] Text size feels similar to dashboard (not tiny)
- [ ] Overall dark/modern vibe matches screenshot
- [ ] No blank pages or missing content

---

## 📚 Reference Files

### Code References
- **Widget component**: `dashboard/src/App.tsx` lines 16-50
- **Body text CSS**: `dashboard/src/index.css` line 42 (`font-size: 1.5rem`)
- **Background gradient**: `dashboard/src/index.css` line 43
- **Tailwind config**: `dashboard/tailwind.config.js` (storm-blue palette + fonts)
- **Gradient animation**: `dashboard/src/index.css` lines 152-177

### Visual References
- **Dashboard screenshot**: `docs/images/dashboard_reference_2025-11-08.png`
- **Logo**: `dashboard/public/logo.png`

### Implementation Files
- **PDF generator**: `lib/contract_generator_dashboard_style.rb`
- **Test script**: `bin/generate_sanna_dashboard_style.rb`
- **Styling guide**: `docs/CONTRACT_PDF_DASHBOARD_STYLING_GUIDE.md` (this file)

---

## 🔬 Technical Deep-Dive Notes

### Why Subtle Blobs Matter
Dashboard uses `rgba(139, 92, 246, 0.02)` - that's **2% opacity**. Most designs use 20-40%. This 10-20x reduction creates the sophisticated, barely-there purple glow that defines the aesthetic. In Prawn, `transparent(0.02)` achieves this.

### Why Large Text Matters
Dashboard CSS explicitly sets `font-size: 1.5rem` for body text (index.css:42). That's **50% larger** than typical web text (1rem). For PDF, this translates to 18-20pt body text instead of the typical 10-12pt legal document size. This creates the modern, readable, approachable vibe.

### Widget Background Formula
```css
backdrop-blur-sm          /* 8px blur */
+ bg-slate-900/40        /* 40% opaque dark slate */
+ border-purple-900/10   /* 10% opaque purple border */
+ rounded-2xl            /* 16px border radius */
= Dashboard widget aesthetic
```

For PDF, approximate with:
```ruby
# Background box
@pdf.transparent(0.15) do  # Slightly more opaque than dashboard for print visibility
  @pdf.fill_color '0f172a'  # slate-900
  @pdf.fill_rectangle [x, y], width, height
end

# Border
@pdf.transparent(0.1) do
  @pdf.stroke_color '312e81'  # purple-900
  @pdf.stroke_rectangle [x, y], width, height
end
```

---

**Last Updated**: November 8, 2025 (Deep code analysis with exact values)
**Validated Against**: Dashboard screenshot + source code extraction
**Status**: Production-ready reference guide

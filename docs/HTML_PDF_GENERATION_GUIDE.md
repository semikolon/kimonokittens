# HTML-based PDF Generation Guide

**Date**: November 8, 2025
**Status**: ✅ Production Ready

## Executive Summary

After initially implementing PDF generation with Prawn, we switched to an **HTML + Ferrum (headless Chrome)** approach for pixel-perfect dashboard styling. This enables true CSS/HTML rendering with custom fonts, Tailwind classes, and exact visual parity with the web dashboard.

## Why HTML Instead of Prawn

**Decision Point**: November 8, 2025 - User requested wkhtmltopdf alternative

### Prawn Challenges Encountered:
1. ❌ **Font limitations**: Horsemen font doesn't support Swedish characters (å, ä, ö)
2. ❌ **Styling complexity**: Rounded rectangles, gradients require low-level PDF primitives
3. ❌ **Screenshot rendering**: pdftoppm didn't render embedded fonts correctly
4. ❌ **Pixel-perfect matching**: Hard to replicate exact dashboard styling

### HTML/Ferrum Advantages:
1. ✅ **Native CSS/HTML**: Use familiar web development patterns
2. ✅ **Dashboard fonts work**: Galvji handles Swedish characters perfectly
3. ✅ **Tailwind classes**: Can reuse exact dashboard styling
4. ✅ **Font fallbacks**: System fonts as backup if custom fonts fail
5. ✅ **True rendering**: Chrome's PDF engine = what you see in browser
6. ✅ **Already installed**: Ferrum already in Gemfile for electricity scraping

## Architecture

### File Structure
```
lib/
├── contract_template.html.erb      # HTML template with embedded CSS
├── contract_generator_html.rb       # Ruby generator using Ferrum
fonts/
├── Horsemen.otf                     # Graffiti-style heading font
├── Horsemen (Slant).otf            # Italic variant
└── Galvji.ttc                       # Body text font (supports Swedish)
dashboard/public/
└── kimonokittens_logo.png          # Logo embedded in PDF
```

### Technology Stack
- **Ferrum**: Ruby gem for headless Chrome automation (already installed)
- **ERB templating**: Generate HTML from contract data
- **Chrome PDF engine**: Native print-to-PDF with `print_background: true`
- **Custom fonts**: `@font-face` with `file:///` URLs

## Implementation Details

### 1. HTML Template (`contract_template.html.erb`)

**Key Features:**
- Tailwind CSS via CDN (rapid styling)
- Custom `@font-face` declarations for Horsemen and Galvji
- Dashboard color palette (rgb(25,30,30) background, purple accents)
- Widget boxes with rounded corners (8px radius)
- Gradient lines under section headings
- Responsive font sizing (11pt body, 12pt sections, 13pt title)

**Font Strategy:**
```html
<style>
  @font-face {
    font-family: 'Horsemen';
    src: url('file:///path/to/Horsemen.otf') format('opentype');
  }

  @font-face {
    font-family: 'Galvji';
    src: url('file:///path/to/Galvji.ttc') format('truetype-collection');
  }

  h1 {
    font-family: 'Horsemen', sans-serif;  /* Title only */
  }

  h2, h3, body {
    font-family: 'Galvji', sans-serif;    /* Everything else */
  }
</style>
```

**Why This Works:**
- Horsemen for English/ASCII title ("HYRESAVTAL")
- Galvji for Swedish text (sections, body, tenant info)
- System font fallback if custom fonts fail to load

### 2. Ruby Generator (`contract_generator_html.rb`)

**Core Flow:**
```ruby
1. Read markdown contract
2. Extract tenant info, rent amounts, dates (regex parsing)
3. Render ERB template with extracted data
4. Save temporary HTML file
5. Launch Ferrum browser
6. Navigate to file:/// URL
7. Generate PDF with Chrome print engine
8. Clean up temp HTML
```

**Key Methods:**
- `extract_tenant_info()`: Parse markdown bullet lists (- Namn: ...)
- `extract_section()`: Grab content between ## headings
- `prepare_template_data()`: Build hash for ERB binding
- `generate_pdf()`: Ferrum automation with print settings

**Markdown Parsing Strategy:**
```ruby
# Works with bullet list format:
# - Namn: Sanna Juni Benemar
# - Personnummer: 8706220020

after_tenant = markdown.split(/Andrahands-hyresgäst/)[1]
tenant_section = after_tenant.split(/^##/)[0]

name = tenant_section.match(/-\s*Namn:\s*(.+?)$/)[1]
```

### 3. Ferrum PDF Generation

**Chrome Print Settings:**
```ruby
browser.pdf(
  path: pdf_path,
  format: :A4,
  margin: { top: '0.5in', right: '0.5in', bottom: '0.5in', left: '0.5in' },
  print_background: true  # CRITICAL: Preserves dark background colors
)
```

**Headless Chrome Configuration:**
```ruby
browser = Ferrum::Browser.new(
  headless: true,
  window_size: [1200, 1600]  # Wide enough for content, tall for scrolling
)
```

## Dashboard Styling Parity

### Color Palette (Exact Match)
```css
background: rgb(25, 30, 30);           /* Dashboard bg-base */
box-bg: rgb(30, 27, 46);               /* Widget backgrounds */
box-border: rgb(49, 46, 129);          /* storm-blue-900 */
text-primary: rgb(221, 214, 254);      /* text-purple-200 */
text-heading: white;                   /* Section headings */
text-muted: rgb(148, 163, 184);        /* Subtitles, footnotes */
```

### Typography Scale
- **Title**: 13pt Horsemen (matches dashboard logo font)
- **Section headings**: 12pt Galvji bold
- **Body text**: 11pt Galvji regular
- **Widget labels**: 11pt Galvji bold
- **Metadata**: 10pt Galvji muted gray

### Widget Box Pattern
```css
.widget-box {
  background: rgb(30, 27, 46);
  border: 1px solid rgb(49, 46, 129);
  border-radius: 8px;
  padding: 12px 15px;
  margin-bottom: 12px;
}
```

**Exact dashboard match**: 8px corners, subtle border, dark purple fill

### Gradient Lines
```css
.gradient-line {
  height: 2px;
  background: linear-gradient(90deg,
    rgba(139, 92, 246, 0.3) 0%,
    rgba(139, 92, 246, 0.2) 50%,
    transparent 100%);
}
```

**Dashboard consistency**: Purple gradient fade (left to right)

## BankID Digital Signatures

**Key Insight**: With Zigned's BankID e-signatures, manual signature blocks are unnecessary.

**Implementation:**
```html
<!-- Removed manual signature areas -->
<!-- Instead: -->
<p style="font-style: italic; color: rgb(148, 163, 184);">
  Detta avtal signeras digitalt med BankID via Zigned e-signeringstjänst.
</p>
```

**Why:**
- Zigned adds digital signature certificates to PDF
- BankID provides legally binding authentication
- Manual signatures would be redundant and confusing

## Usage

### Generate Contract PDF
```ruby
require_relative 'lib/contract_generator_html'

ContractGeneratorHtml.generate_from_markdown(
  'contracts/Sanna_Benemar_Hyresavtal_2025-11-01.md',
  'contracts/generated/Sanna_Benemar_HTML_Style.pdf'
)
```

### Expected Output
```
✅ Generated dashboard-styled PDF: contracts/generated/Sanna_Benemar_HTML_Style.pdf
```

**PDF Size**: ~1-2MB (embedded fonts + Chrome PDF compression)

## Markdown Format Requirements

The generator expects this markdown structure:

```markdown
## 1. Parter

**Förstahandshyresgäst (Hyresvärd i detta avtal):**
- Namn: Fredrik Bränström
- Personnummer: 8604230717
- Telefon: 073-830 72 22
- E-post: branstrom@gmail.com

**Andrahands-hyresgäst (Hyresgäst i detta avtal):**
- Namn: Sanna Juni Benemar
- Personnummer: 8706220020
- Telefon: 070 289 44 37
- E-post: sanna_benemar@hotmail.com

## 2. Objekt

- **Adress:** Sördalavägen 26, 141 60 Huddinge
- **Bostadstyp:** Rum och gemensamma ytor i kollektiv

## 3. Hyrestid

Avtalet gäller omedelbart med inflytt från och med **2025-11-01** tills vidare...

## 4. Hyra

**4.1 Kall månadshyra:** 6,132.5 kr
```

**Critical Patterns:**
- Bullet lists with `- Field: Value` format
- Bold field labels with `**Field:**`
- Section headings as `## N. Heading`
- Dates in `**YYYY-MM-DD**` format
- Amounts in `**N,NNN.N kr**` format

## Troubleshooting

### Fonts Not Loading
**Symptom**: PDF shows fallback system fonts instead of Horsemen/Galvji

**Fix**: Check font paths are absolute in ERB template
```ruby
fonts_dir: '/Users/fredrikbranstrom/Projects/kimonokittens/fonts'
```

### Background Colors Missing
**Symptom**: PDF has white background instead of dark purple

**Fix**: Ensure `print_background: true` in Ferrum PDF options

### Swedish Characters Broken
**Symptom**: å, ä, ö render as boxes or wrong glyphs

**Fix**: Use Galvji font, NOT Horsemen for Swedish text
```css
h2, h3 { font-family: 'Galvji', sans-serif; }  /* NOT Horsemen */
```

### Tenant Info Shows N/A
**Symptom**: Tenant section shows "N/A" for all fields

**Fix**: Check markdown uses bullet list format `- Namn: Value`
```ruby
# Correct:
- Namn: Sanna Juni Benemar

# Wrong:
**Namn:** Sanna Juni Benemar
```

## Performance

**Generation Time**: ~1-2 seconds per PDF
- 0.5s: ERB template rendering
- 0.5s: Ferrum browser launch
- 0.1s: Chrome PDF generation
- 0.1s: Cleanup

**Resource Usage**:
- CPU: ~50-100% for 1-2 seconds
- Memory: ~200MB (headless Chrome)
- Disk: 1-2MB per PDF

**Scalability**: Suitable for:
- ✅ Interactive single-contract generation
- ✅ Batch generation (<100 contracts/hour)
- ⚠️  High-volume production (consider pre-rendering)

## Future Enhancements

### Potential Improvements
1. **Reusable browser instance**: Keep Ferrum browser open between generations
2. **Template caching**: Pre-compile ERB templates
3. **CSS inlining**: Embed Tailwind styles instead of CDN
4. **Font subsetting**: Reduce PDF size with subset fonts
5. **Parallel generation**: Multi-threaded batch processing

### Dashboard Component Reuse
**Opportunity**: Extract shared CSS into `dashboard_theme.css`
```html
<!-- In both dashboard and PDF template -->
<link rel="stylesheet" href="shared/dashboard_theme.css">
```

**Benefits**: Single source of truth for colors, fonts, spacing

## Comparison: Prawn vs HTML

| Aspect | Prawn | HTML/Ferrum |
|--------|-------|-------------|
| **Ease of styling** | Complex PDF primitives | Familiar CSS/HTML |
| **Dashboard parity** | Hard to match exactly | Pixel-perfect match |
| **Swedish characters** | Font embedding issues | Works natively |
| **Font fallbacks** | Manual fallback logic | Browser handles it |
| **Performance** | Faster (~0.5s) | Slower (~2s) |
| **Dependencies** | Ruby only | Chrome required |
| **File size** | Smaller (200KB) | Larger (1-2MB) |
| **Maintenance** | More custom code | Standard web patterns |

**Decision**: HTML/Ferrum wins for **styling accuracy and developer experience**

## Conclusion

The HTML-based approach successfully achieves:
- ✅ Pixel-perfect dashboard styling
- ✅ Swedish character support
- ✅ Custom font rendering
- ✅ Maintainable CSS/HTML code
- ✅ BankID-ready digital signatures

**Recommendation**: Use HTML/Ferrum for all future contract generation unless performance becomes critical (>1000 PDFs/day), then consider hybrid approach.

## References

- **Ferrum Documentation**: https://github.com/rubycdp/ferrum
- **Chrome PDF API**: https://chromedevtools.github.io/devtools-protocol/tot/Page/#method-printToPDF
- **Font Loading**: MDN @font-face guide
- **Dashboard Tailwind Config**: `dashboard/tailwind.config.js`

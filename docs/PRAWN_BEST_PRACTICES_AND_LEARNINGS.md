# Prawn PDF Best Practices & Learnings

## Research Summary (November 8, 2025)

This document captures key learnings from implementing dashboard-styled PDF contracts and researching Prawn documentation.

## Key Prawn Capabilities

### 1. Font Management

**Built-in Fonts** (Current Implementation):
- Using Helvetica (built-in PDF font)
- Pros: No file dependencies, universal compatibility
- Cons: Limited to standard PDF fonts, can't match dashboard's custom "Horsemen" font

**Custom TrueType Fonts** (Potential Enhancement):
```ruby
# Embed custom TTF font
font_families.update(
  "Horsemen" => {
    normal: "path/to/Horsemen-Regular.ttf",
    bold: "path/to/Horsemen-Bold.ttf"
  }
)

# Use in document
font "Horsemen" do
  text "KIMONOKITTENS", size: 48
end
```

**Recommendation**: If "Horsemen" font files are available, embedding them would achieve perfect dashboard-logo parity.

### 2. Color Management Best Practices

**✅ Current Implementation (Correct)**:
```ruby
def apply_page_background
  tmp_color = @pdf.fill_color  # Save current state

  @pdf.canvas do
    @pdf.fill_color COLORS[:bg_dark]
    # ... drawing operations
  end

  @pdf.fill_color COLORS[:text_primary]  # Restore to text color
end
```

**Why This Works**:
- Canvas blocks don't automatically restore fill_color
- Explicitly restoring prevents color bleed between elements
- Standard Prawn pattern confirmed by documentation

### 3. Canvas & Layering

**✅ Current Implementation (Correct)**:
```ruby
@pdf.canvas do
  # Background drawn at bottom layer
  @pdf.fill_rectangle [bounds.left, bounds.top], bounds.right, bounds.top

  # Gradient overlays with transparency
  @pdf.transparent(0.02) do
    @pdf.fill_ellipse [100, 600], 200, 150
  end
end
```

**Key Insights**:
- `canvas` blocks draw in Z-order (first drawn = bottom layer)
- Perfect for backgrounds that shouldn't obscure content
- Transparency works correctly inside canvas blocks
- Using `bounds` coordinates ensures proper page sizing

### 4. Page Creation Callbacks

**✅ Current Implementation (Correct)**:
```ruby
@pdf.on_page_create { apply_page_background }  # Future pages
setup_footer                                    # One-time setup
apply_page_background                          # Initial page (callback doesn't fire for first page)
```

**Critical Discovery**:
- `on_page_create` does NOT fire for the initial page created during `Prawn::Document.new`
- Must manually call background method for first page
- This is documented Prawn behavior, not a bug

### 5. Transparency & Opacity

**✅ Current Implementation (Optimal)**:
```ruby
@pdf.transparent(0.02) do   # Very subtle (dashboard uses 0.01-0.02)
  @pdf.fill_color COLORS[:primary]
  @pdf.fill_ellipse [100, 600], 200, 150
end
```

**Research Finding**:
- Dashboard uses extremely subtle gradients (0.01-0.02 opacity)
- Higher opacity (0.15+) looks too prominent
- Current implementation matches dashboard aesthetic

## Potential Improvements

### 1. Custom Font Embedding (High Value)

**Current State**: Using Helvetica-Bold for logo text
**Enhancement**: Embed dashboard's "Horsemen" graffiti font

**Steps**:
1. Locate "Horsemen" TTF files in dashboard assets
2. Add to `font_families` hash
3. Update logo rendering to use custom font
4. Test PDF file size impact (TTF embedding adds ~100-500KB typically)

**Trade-off**: File size vs visual authenticity

### 2. Color Constant Organization

**Current State**: Colors defined at top of class
```ruby
COLORS = {
  bg_dark: '0c0a10',
  primary: '8b5cf6',
  # ...
}
```

**Enhancement**: Extract to shared constant file
```ruby
# lib/constants/dashboard_colors.rb
module DashboardColors
  BG_DARK = '0c0a10'
  PRIMARY = '8b5cf6'
  # ...
end
```

**Benefit**: Reusable across other PDF generators, easier maintenance

### 3. Gradient Line Optimization

**Current State**: Multiple transparent rectangles for gradient effect
```ruby
def gradient_line(height: 2)
  @pdf.transparent(0.3) { @pdf.fill_rectangle [...] }
  @pdf.transparent(0.2) { @pdf.fill_rectangle [...] }
  @pdf.fill_color COLORS[:text_primary]
end
```

**Research Finding**: This is the correct approach - Prawn doesn't have native gradient fills for rectangles. Multiple overlaid shapes with varying transparency is the standard pattern.

### 4. Performance Considerations

**Current Implementation Analysis**:
- ✅ Using built-in fonts (fast)
- ✅ Minimal transparency operations (3 ellipses per page)
- ✅ Simple vector shapes (rectangles, ellipses)
- ✅ No heavy image processing

**Potential Issue**: If embedding custom fonts, test generation time with large contracts

**Optimization Strategy**:
```ruby
# If custom fonts are slow, lazy-load them
@custom_font_loaded ||= begin
  font_families.update("Horsemen" => { ... })
  true
end
```

## Documentation Research Findings

### Official Prawn Resources

1. **Manual**: [prawnpdf.org](https://prawnpdf.org/) - Generated examples showcasing features
2. **API Docs**: [rubydoc.info/gems/prawn](https://www.rubydoc.info/gems/prawn)
3. **Source**: [github.com/prawnpdf/prawn](https://github.com/prawnpdf/prawn)

### Key Manual Topics Referenced

- **Color Management**: `fill_color`, `stroke_color`, RGB/HEX support
- **Canvas Operations**: Z-ordering, coordinate systems
- **Text Rendering**: Font switching, inline formatting (limited)
- **Images**: PNG/JPG embedding (we're using this for logo)
- **Transparency**: `transparent` block usage

### Community Patterns

**Background Implementation** (StackOverflow):
```ruby
# Standard pattern confirmed by multiple sources
pdf.canvas do
  pdf.fill_color 'XXXXXX'
  pdf.fill_rectangle [bounds.left, bounds.top], bounds.right, bounds.top
end
```

**Multi-page Backgrounds** (GitHub Issues):
```ruby
# Hook + manual call pattern (exactly what we implemented)
pdf.on_page_create { apply_background }
apply_background  # First page
```

## What We Got Right

1. ✅ **Canvas layering** for backgrounds
2. ✅ **Color state management** (save/restore pattern)
3. ✅ **Page callback strategy** (hook + manual first page)
4. ✅ **Subtle transparency** (matching dashboard 0.01-0.02 opacity)
5. ✅ **Coordinate system** (using `bounds` for page dimensions)
6. ✅ **Typography scaling** (18pt body = dashboard's 1.5rem)

## What Could Be Enhanced

1. 🔧 **Custom font embedding** for perfect logo match
2. 🔧 **Color constants extraction** for reusability
3. 🔧 **Font file management** if adding TTF fonts
4. 📊 **Performance testing** with large multi-page contracts

## Font Research Findings

**"Horsemen" Font Investigation** (November 8, 2025):
- Dashboard uses `font-[Horsemen]` via Tailwind arbitrary font values
- **No font files found in project** (no TTF/OTF in dashboard/public)
- **No @font-face declarations** in CSS
- **No font imports** in index.html or main.tsx
- **Conclusion**: "Horsemen" is a **system font installed on the kiosk**

**Implications for PDF**:
- Cannot embed "Horsemen" font without obtaining TTF files
- Current Helvetica-Bold is acceptable fallback
- If user provides TTF files, embedding is straightforward (see Custom Font Embedding section above)

## Implementation Priorities

### High Priority (Perfect Dashboard Match)
- [x] ~~Locate "Horsemen" font files in dashboard assets~~ (NOT IN PROJECT - system font)
- [ ] If user provides "Horsemen" TTF files: Test embedding with sample PDF
- [ ] If embedding fonts: Compare file sizes (with/without custom fonts)

### Medium Priority (Code Quality)
- [ ] Extract colors to shared constant module
- [ ] Add inline documentation for canvas/layering patterns
- [ ] Create Prawn helper module for reusable patterns

### Low Priority (Optimization)
- [ ] Performance benchmarks with 10+ page contracts
- [ ] Memory profiling if generating many PDFs concurrently

## Conclusion

The current implementation follows Prawn best practices and produces dashboard-styled PDFs successfully. The main enhancement opportunity is **custom font embedding** to perfectly match the dashboard's "Horsemen" logo font.

All other aspects (color management, canvas layering, page callbacks, transparency) are implemented correctly according to official Prawn documentation and community patterns.

## References

- [Prawn Official Docs](https://prawnpdf.org/)
- [Prawn GitHub](https://github.com/prawnpdf/prawn)
- [RubyDoc.info Prawn API](https://www.rubydoc.info/gems/prawn)
- Research via Exa code search (November 8, 2025)
- StackOverflow background implementation patterns

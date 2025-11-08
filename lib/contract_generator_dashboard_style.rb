require 'prawn'
require 'prawn/table'
require 'date'

# Dashboard-Inspired ContractGenerator
#
# Creates bold, modern rental agreements matching the dark purple aesthetic
# of the Kimonokittens dashboard with gradient backgrounds and vibrant accents
#
# Features:
# - Deep purple gradient background (simulating dashboard's animated theme)
# - Large, prominent logo matching dashboard scale
# - Purple/pink accent colors from storm-blue palette
# - Modern, bold typography with light text on dark background
# - Gradient accent bars instead of plain lines
#
# Usage: Same as ContractGenerator but with dashboard aesthetic
class ContractGeneratorDashboardStyle
  LANDLORD = {
    name: 'Fredrik Bränström',
    personnummer: '8604230717',
    phone: '073-830 72 22',
    email: 'branstrom@gmail.com'
  }.freeze

  PROPERTY = {
    address: 'Sördalavägen 26, 141 60 Huddinge',
    type: 'Rum och gemensamma ytor i kollektiv'
  }.freeze

  RENT_DETAILS = {
    base_rent: 6_132.5,
    utilities_estimate: 1_200,
    deposit: 6_200,
    furnishing_deposit: 2_200
  }.freeze

  # Dashboard-inspired color palette (from dashboard CSS + Tailwind config)
  COLORS = {
    # Background gradients (matching dashboard exactly)
    bg_base: '191e1e',      # rgb(25, 20, 30) - PRIMARY dashboard background
    bg_dark: '0c0a10',      # rgb(12, 10, 16) - darker areas

    # Widget box colors
    box_bg: '1e1b2e',       # Dark purple box background (semi-transparent effect)
    box_border: '312e81',   # storm-blue-900 - subtle border

    # Storm-blue accent palette
    primary: '6366f1',      # storm-blue-500 - vibrant purple
    accent: '818cf8',       # storm-blue-400 - lighter purple
    bright: 'a5b4fc',       # storm-blue-300 - bright purple/pink
    highlight: 'c7d2fe',    # storm-blue-200 - light highlight

    # Text colors (light on dark)
    text_primary: 'ddd6fe', # text-purple-200 - main text
    text_heading: 'ffffff', # WHITE - headings (like dashboard Horsemen font)
    text_muted: '94a3b8',   # Muted gray-blue

    # Graffiti logo colors
    logo_pink: 'ff78c8',    # Hot pink from logo
    logo_orange: 'ffaa5a'   # Orange from logo
  }.freeze

  LOGO_PATH = File.join(File.dirname(__FILE__), '../dashboard/public/logo.png')
  FONTS_DIR = File.join(File.dirname(__FILE__), '../fonts')

  def initialize
    @pdf = nil
  end

  def setup_fonts
    # Register dashboard fonts (Horsemen for headings, Galvji for body)
    @pdf.font_families.update(
      'Horsemen' => {
        normal: File.join(FONTS_DIR, 'Horsemen.otf'),
        italic: File.join(FONTS_DIR, 'Horsemen (Slant).otf'),
        bold: File.join(FONTS_DIR, 'Horsemen.otf'),  # Use normal for bold
        bold_italic: File.join(FONTS_DIR, 'Horsemen (Slant).otf')
      },
      'Galvji' => {
        normal: File.join(FONTS_DIR, 'Galvji.ttc'),
        italic: File.join(FONTS_DIR, 'Galvji.ttc'),  # TTC only has one variant
        bold: File.join(FONTS_DIR, 'Galvji.ttc'),
        bold_italic: File.join(FONTS_DIR, 'Galvji.ttc')
      }
    )
  end

  def generate(tenant:, output_path:)
    @tenant = tenant
    @output_path = output_path

    # Create PDF with dashboard styling
    @pdf = Prawn::Document.new(
      page_size: 'A4',
      margin: [60, 50, 60, 50]
    )

    # Setup custom dashboard fonts
    setup_fonts

    # Set default font to Galvji (dashboard body font)
    @pdf.font 'Galvji'

    # Hook to apply background to ALL future pages automatically
    @pdf.on_page_create { apply_page_background }

    # Setup footer (no header - logo will be inline)
    setup_footer

    # Apply background to FIRST page (on_page_create doesn't fire for initial page)
    apply_page_background

    # Add large prominent logo
    add_dashboard_logo

    # Generate all sections with dashboard styling
    generate_title
    generate_parties
    generate_property
    generate_lease_period
    generate_rent
    generate_utilities
    generate_deposit
    generate_furnishing_deposit
    generate_notice_period
    generate_other_terms
    generate_democratic_structure
    # Note: No signature section - Zigned appends its own BankID signature page

    # Save PDF
    @pdf.render_file(output_path)
    output_path
  end

  private

  # Apply dashboard background (lighter purple, matching screenshot)
  def apply_page_background
    # Save current fill color
    tmp_color = @pdf.fill_color

    @pdf.canvas do
      # LIGHTER purple background (rgb(25,20,30)) - matching dashboard exactly
      @pdf.fill_color COLORS[:bg_base]
      @pdf.fill_rectangle [@pdf.bounds.left, @pdf.bounds.top], @pdf.bounds.right, @pdf.bounds.top

      # Gradient effect with EXTREMELY subtle ellipses (dashboard uses 0.01-0.02 opacity)
      # These should be BARELY visible - just hints of purple color
      @pdf.transparent(0.02) do
        @pdf.fill_color COLORS[:primary]
        @pdf.fill_ellipse [100, 600], 200, 150
      end

      @pdf.transparent(0.015) do
        @pdf.fill_color COLORS[:accent]
        @pdf.fill_ellipse [@pdf.bounds.right - 150, 300], 250, 200
      end

      @pdf.transparent(0.01) do
        @pdf.fill_color COLORS[:bright]
        @pdf.fill_ellipse [300, 100], 180, 180
      end
    end

    # Restore fill color to text color
    @pdf.fill_color COLORS[:text_primary]
  end

  # Dashboard-style widget box with rounded corners and padding
  def widget_box(padding: 15)
    # Save starting position
    box_top = @pdf.cursor
    box_left = @pdf.bounds.left
    box_width = @pdf.bounds.width

    # Render content in a temporary "measure" to get height
    content_height = 0

    # Save current position
    saved_y = @pdf.cursor

    # Render content to measure height
    @pdf.transparent(0) do  # Invisible render to measure
      yield
    end

    # Calculate content height
    content_height = saved_y - @pdf.cursor
    box_height = content_height + (padding * 2)

    # Reset cursor to start
    @pdf.move_cursor_to box_top

    # Draw rounded box background with canvas (behind content)
    @pdf.canvas do
      # Box background
      @pdf.fill_color COLORS[:box_bg]
      @pdf.rounded_rectangle [box_left, box_top],
                            box_width,
                            box_height,
                            8  # 8pt corner radius like dashboard
      @pdf.fill

      # Subtle border
      @pdf.stroke_color COLORS[:box_border]
      @pdf.line_width 0.5
      @pdf.rounded_rectangle [box_left, box_top],
                            box_width,
                            box_height,
                            8
      @pdf.stroke
    end

    # Now render actual content with padding
    @pdf.bounding_box [box_left + padding, box_top - padding],
                      width: box_width - (padding * 2) do
      yield
    end

    # Move cursor past the box
    @pdf.move_cursor_to(box_top - box_height)

    # Restore colors
    @pdf.fill_color COLORS[:text_primary]
    @pdf.stroke_color '000000'
  end

  # Setup footer with page numbers
  def setup_footer
    @pdf.repeat :all do
      @pdf.bounding_box [@pdf.bounds.left, @pdf.bounds.bottom + 30], width: @pdf.bounds.width do
        # Gradient line
        gradient_line

        @pdf.move_down 8
        @pdf.fill_color COLORS[:text_muted]
        @pdf.font_size 5
        @pdf.text "Sida #{@pdf.page_number}", align: :center
        @pdf.fill_color COLORS[:text_primary]
      end
    end
  end

  # Add dashboard-scale logo (will be positioned with title)
  def add_dashboard_logo
    # Logo will be added in generate_title method to align with heading
  end

  # Draw gradient accent line (simulating purple glow)
  def gradient_line(height: 2)
    # Multiple overlaid lines for gradient effect
    @pdf.transparent(0.3) do
      @pdf.fill_color COLORS[:primary]
      @pdf.fill_rectangle [@pdf.bounds.left, @pdf.cursor], @pdf.bounds.width, height
    end

    @pdf.transparent(0.2) do
      @pdf.fill_color COLORS[:accent]
      @pdf.fill_rectangle [@pdf.bounds.left, @pdf.cursor - height], @pdf.bounds.width, height
    end

    # Reset fill_color to text color after decorative elements
    @pdf.fill_color COLORS[:text_primary]
  end

  def generate_title
    # Logo on right, title on left (same vertical alignment)
    if File.exist?(LOGO_PATH)
      # Calculate logo position (right-aligned with 20pt margin)
      logo_width = 120
      logo_x = @pdf.bounds.right - logo_width - 20
      logo_y = @pdf.cursor

      # Place logo
      @pdf.image LOGO_PATH, at: [logo_x, logo_y], width: logo_width

      # Place title on the left, vertically centered with logo
      @pdf.bounding_box [0, logo_y], width: @pdf.bounds.width - logo_width - 40 do
        @pdf.font 'Horsemen' do
          @pdf.fill_color COLORS[:text_heading]  # WHITE
          @pdf.font_size(13) do
            @pdf.text 'HYRESAVTAL – ANDRAHANDSUTHYRNING', align: :left, style: :bold
          end
        end
      end

      @pdf.move_down 10
    else
      # No logo - just title
      @pdf.font 'Horsemen' do
        @pdf.fill_color COLORS[:text_heading]  # WHITE
        @pdf.font_size(13) do
          @pdf.text 'HYRESAVTAL – ANDRAHANDSUTHYRNING', align: :center, style: :bold
        end
      end
    end

    @pdf.fill_color COLORS[:text_primary]
    @pdf.move_down 20

    # Gradient accent line
    gradient_line(height: 3)
    @pdf.move_down 20

    @pdf.font_size(11) do  # 60% of original dashboard scale
      @pdf.text 'Mellan nedanstående parter har följande avtal slutits:'
    end
    @pdf.move_down 20
  end

  def generate_parties
    section_heading('1. Parter')

    # Landlord widget box (dashboard style)
    widget_box(padding: 12) do
      @pdf.font_size(11) do
        @pdf.fill_color COLORS[:text_heading]
        @pdf.text 'Förstahandshyresgäst (Hyresvärd i detta avtal):', style: :bold
        @pdf.fill_color COLORS[:text_primary]
        @pdf.move_down 5
        @pdf.indent(10) do
          @pdf.text "Namn: #{LANDLORD[:name]}"
          @pdf.text "Personnummer: #{LANDLORD[:personnummer]}"
          @pdf.text "Telefon: #{LANDLORD[:phone]}"
          @pdf.text "E-post: #{LANDLORD[:email]}"
        end
      end
    end

    @pdf.move_down 12

    # Tenant widget box (dashboard style)
    widget_box(padding: 12) do
      @pdf.font_size(11) do
        @pdf.fill_color COLORS[:text_heading]
        @pdf.text 'Andrahands-hyresgäst (Hyresgäst i detta avtal):', style: :bold
        @pdf.fill_color COLORS[:text_primary]
        @pdf.move_down 5
        @pdf.indent(10) do
          @pdf.text "Namn: #{@tenant[:name]}"
          @pdf.text "Personnummer: #{@tenant[:personnummer]}"
          @pdf.text "Telefon: #{@tenant[:phone]}"
          @pdf.text "E-post: #{@tenant[:email]}"
        end
      end
    end

    @pdf.move_down 20
  end

  def generate_property
    section_heading('2. Objekt')

    @pdf.font_size(11) do  # 60% of original dashboard scale
      @pdf.text "Adress: #{PROPERTY[:address]}"
      @pdf.text "Bostadstyp: #{PROPERTY[:type]}"
    end

    @pdf.move_down 20
  end

  def generate_lease_period
    section_heading('3. Hyrestid')

    move_in = @tenant[:move_in_date].strftime('%Y-%m-%d')

    @pdf.font_size(11) do  # 60% of original dashboard scale
      @pdf.text "Avtalet gäller omedelbart med inflytt från och med #{move_in} tills vidare med en " \
                "uppsägningstid om två (2) månader räknat från den dag då uppsägningen skriftligen " \
                "meddelats motparten.", align: :justify
    end

    @pdf.move_down 20
  end

  def generate_rent
    section_heading('4. Hyra')

    @pdf.font_size(11) do  # 60% of original dashboard scale
      @pdf.fill_color COLORS[:text_heading]
      @pdf.text "4.1 Kall månadshyra: #{format_currency(RENT_DETAILS[:base_rent])}", style: :bold
      @pdf.fill_color COLORS[:text_primary]
      @pdf.move_down 8
      @pdf.text '4.2 I hyran ingår ej el- och nätkostnad. Se punkt 5.'
    end

    @pdf.move_down 20
  end

  def generate_utilities
    section_heading('5. Avgifter för el och nät')

    @pdf.font_size(11) do  # 60% of original dashboard scale
      @pdf.text 'Hyresgästen åtar sig att dela elkostnad, nätkostnad, vattenavgift, larm, gas och ' \
                "bredband lika med övriga medlemmar i kollektivet. Den genomsnittliga månadskostnaden " \
                "för dessa är ca. #{format_currency(RENT_DETAILS[:utilities_estimate])}.", align: :justify
      @pdf.move_down 10

      @pdf.fill_color COLORS[:accent]
      @pdf.text 'Observera att totalkostnaden varierar säsongsmässigt beroende på elförbrukning. ' \
                'Den genomsnittliga totala boendekostnaden är cirka 7,300 kr per månad, med ' \
                'maximal kostnad på cirka 7,900 kr under vinterhalvåret (uppvärmningsbehov).',
                align: :justify, style: :italic
      @pdf.fill_color COLORS[:text_primary]
    end

    @pdf.move_down 20
  end

  def generate_deposit
    section_heading('6. Deposition')

    @pdf.font_size(11) do  # 60% of original dashboard scale
      @pdf.text "Hyresgästen erlägger en deposition om en dryg (1) kall månadshyra, dvs. " \
                "#{format_currency(RENT_DETAILS[:deposit])}, som återbetalas i enlighet med hyreslagens " \
                "bestämmelser efter det att hyresobjektet återlämnats i godtagbart skick.", align: :justify
    end

    @pdf.move_down 20
  end

  def generate_furnishing_deposit
    section_heading('7. Inredningsdeposition')

    @pdf.font_size(11) do  # 60% of original dashboard scale
      @pdf.text "7.1 Vid inträde i kollektivet erlägger andrahandsgästen, utöver depositionen, en " \
                "inredningsdeposition om #{format_currency(RENT_DETAILS[:furnishing_deposit])} till den utflyttande parten.",
                align: :justify
      @pdf.move_down 10

      @pdf.text '7.2 Vid utflytt återbetalas denna inredningsdeposition på följande sätt:',
                align: :justify
      @pdf.move_down 5

      @pdf.indent(20) do
        @pdf.text '• Om det finns en efterträdande medlem överlämnar denna 2,200 kr till utflyttande part.',
                  align: :justify
        @pdf.move_down 5
        @pdf.text '• Om kollektivet upplöses återlämnas i stället motsvarande värde i de inventarier som ' \
                  'köptes för depositionens summa när kollektivet bildades.',
                  align: :justify
      end
      @pdf.move_down 10

      @pdf.text '7.3 Inredningsdepositionen utgör en delad investering i gemensamma hushållsartiklar ' \
                '(möbler, växter, prydnadsföremål, porslin, och liknande). Eventuella tvister rörande ' \
                'depositionen hanteras i god ton av kollektivets medlemmar.',
                align: :justify
    end

    @pdf.move_down 20
  end

  def generate_notice_period
    section_heading('8. Uppsägning')

    @pdf.font_size(11) do  # 60% of original dashboard scale
      @pdf.text 'Uppsägning ska ske skriftligen med minst två (2) månaders varsel. Uppsägning räknas ' \
                'från den sista dagen i den månad då uppsägningen delges motparten.',
                align: :justify
    end

    @pdf.move_down 20
  end

  def generate_other_terms
    section_heading('9. Övriga villkor')

    @pdf.font_size(11) do  # 60% of original dashboard scale
      @pdf.indent(20) do
        @pdf.text '• Hyresgästen förbinder sig att följa ordningsregler som gäller för kollektivet.'
        @pdf.move_down 5
        @pdf.text '• Husdjur: tillåtet samt eventuella villkor: gemensam överrenskommelse'
        @pdf.move_down 5
        @pdf.text '• Försäkring: Hyresgästen ansvarar för att ha hemförsäkring med rättsskydd.'
      end
      @pdf.move_down 10

      @pdf.text 'I övriga frågor kontakta först förstahandshyresgästen enligt uppgifter i punkt 1.'
    end

    @pdf.move_down 20
  end

  def generate_democratic_structure
    # Start new page if needed (background will be applied automatically via on_page_create)
    @pdf.start_new_page if @pdf.cursor < 250

    section_heading('10. Hyresstruktur och demokratisk beslutsgång')

    @pdf.font_size(11) do  # 60% of original dashboard scale
      # 10.1
      @pdf.fill_color COLORS[:text_heading]
      @pdf.text '10.1 Hyresberäkning', style: :bold
      @pdf.fill_color COLORS[:text_primary]
      @pdf.move_down 5
      @pdf.text 'Kallhyran per person baseras på husets totala kallhyra (24,530 kr) delat på ' \
                'antalet boende. Vid fyra boende: 6,132.5 kr per person. Vid fem boende: 4,906 kr per person.',
                align: :justify
      @pdf.move_down 10

      # 10.2
      @pdf.fill_color COLORS[:text_heading]
      @pdf.text '10.2 Rumsjusteringar', style: :bold
      @pdf.fill_color COLORS[:text_primary]
      @pdf.move_down 5
      @pdf.text 'Rumsjusteringar kan förekomma efter demokratisk överenskommelse. Mindre rum eller ' \
                'rum som delas av par kan berättiga till reducerad kallhyra. Sådana justeringar beslutas ' \
                'gemensamt av kollektivets medlemmar.',
                align: :justify
      @pdf.move_down 10

      # 10.3
      @pdf.fill_color COLORS[:text_heading]
      @pdf.text '10.3 Beslutsprocess', style: :bold
      @pdf.fill_color COLORS[:text_primary]
      @pdf.move_down 5
      @pdf.text 'Beslut om hyresstruktur och rumsjusteringar fattas demokratiskt med förstahandshyresgästen ' \
                'som slutgiltig beslutsfattare vid oenighet. Förstahandshyresgästen har ansvarat för ' \
                'kollektivets drift och utveckling sedan 2023 och säkerställer kontinuitet och rättvisa ' \
                'i beslutsprocessen.',
                align: :justify
      @pdf.move_down 10

      # 10.4
      @pdf.fill_color COLORS[:text_heading]
      @pdf.text '10.4 Öppenhet', style: :bold
      @pdf.fill_color COLORS[:text_primary]
      @pdf.move_down 5
      @pdf.text 'Alla hyresberäkningar och beslut dokumenteras transparent och är tillgängliga för ' \
                'kollektivets medlemmar.',
                align: :justify
    end

    @pdf.move_down 25
  end

  # Helper: Format section headings with Horsemen font (like dashboard)
  def section_heading(text)
    @pdf.font 'Horsemen' do
      @pdf.font_size(12) do  # 60% of original dashboard heading scale
        @pdf.fill_color COLORS[:text_heading]  # WHITE like dashboard
        @pdf.text text, style: :bold
        @pdf.fill_color COLORS[:text_primary]
      end
    end
    @pdf.move_down 3

    # Gradient underline
    gradient_line(height: 1.5)
    @pdf.move_down 12
  end

  # Helper: Format currency
  def format_currency(amount)
    whole = amount.to_i
    decimal = ((amount - whole) * 10).round
    formatted = whole.to_s.reverse.gsub(/(\\d{3})(?=\\d)/, '\\\\1 ').reverse

    decimal.zero? ? "#{formatted} kr" : "#{formatted}.#{decimal} kr"
  end
end

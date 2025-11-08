require 'prawn'
require 'prawn/table'
require 'date'

# ContractGenerator creates professionally formatted rental agreement PDFs
#
# Features:
# - Swedish language contract formatting
# - Matches Amanda's template design
# - Proper margins, fonts, and spacing
# - Handles all contract sections
#
# Usage:
#   generator = ContractGenerator.new
#   generator.generate(
#     tenant: {
#       name: "Sanna Juni Benemar",
#       personnummer: "8706220020",
#       email: "sanna_benemar@hotmail.com",
#       phone: "070 289 44 37",
#       move_in_date: Date.new(2025, 11, 1)
#     },
#     output_path: "contracts/generated/Sanna_Benemar_Hyresavtal_2025-11-01.pdf"
#   )
class ContractGenerator
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

  # Dashboard color palette (storm-blue theme from Tailwind config)
  COLORS = {
    primary: '4338ca',    # storm-blue-700 - Headers, titles
    accent: '6366f1',     # storm-blue-500 - Highlights
    light: 'c7d2fe',      # storm-blue-200 - Borders, subtle elements
    gray: '666666',       # Body text
    dark: '312e81'        # storm-blue-900 - Dark accents
  }.freeze

  LOGO_PATH = File.join(File.dirname(__FILE__), '../dashboard/public/logo.png')

  def initialize
    @pdf = nil
  end

  # Generate contract PDF from tenant data
  #
  # @param tenant [Hash] Tenant information
  # @option tenant [String] :name Full name
  # @option tenant [String] :personnummer Swedish personal ID (YYMMDD-XXXX)
  # @option tenant [String] :email Email address
  # @option tenant [String] :phone Phone number
  # @option tenant [Date] :move_in_date Move-in date
  #
  # @param output_path [String] Path to save generated PDF
  #
  # @return [String] Path to generated PDF
  def generate(tenant:, output_path:)
    @tenant = tenant
    @output_path = output_path

    # Create PDF with A4 size and proper margins
    @pdf = Prawn::Document.new(
      page_size: 'A4',
      margin: [80, 50, 70, 50] # [top, right, bottom, left] - extra space for header/footer
    )

    # Setup professional styling
    setup_repeating_elements

    # Add logo to first page (right-aligned with margins)
    add_first_page_logo

    # Generate all sections
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
    generate_signature_section

    # Save PDF
    @pdf.render_file(output_path)
    output_path
  end

  private

  # Setup professional header and footer that repeat on all pages
  def setup_repeating_elements
    # Repeating footer with page numbers
    @pdf.repeat :all do
      @pdf.bounding_box [@pdf.bounds.left, @pdf.bounds.bottom + 20], width: @pdf.bounds.width do
        @pdf.stroke_color COLORS[:light]
        @pdf.stroke_horizontal_rule
        @pdf.move_down 5
        @pdf.fill_color COLORS[:gray]
        @pdf.font_size 9
        @pdf.text "Sida #{@pdf.page_number} av #{@pdf.page_count}", align: :center
        @pdf.fill_color '000000'
      end
    end
  end

  # Add logo to first page only - right-aligned with ample margins
  def add_first_page_logo
    return unless File.exist?(LOGO_PATH)

    # Position logo at top-right with margins
    # Bounding box with right positioning
    @pdf.bounding_box [@pdf.bounds.right - 110, @pdf.bounds.top], width: 110, height: 80 do
      @pdf.image LOGO_PATH, width: 90, position: :right, vposition: :top
    end

    # Add decorative line below logo area
    @pdf.move_down 15
    @pdf.stroke_color COLORS[:light]
    @pdf.stroke_horizontal_rule
    @pdf.stroke_color '000000'
    @pdf.move_down 20
  end

  def generate_title
    # Professional title with color
    @pdf.fill_color COLORS[:primary]
    @pdf.font_size(20) do
      @pdf.text 'HYRESAVTAL – ANDRAHANDSUTHYRNING', align: :center, style: :bold
    end
    @pdf.fill_color '000000'
    @pdf.move_down 8

    @pdf.font_size(9) do
      @pdf.fill_color COLORS[:gray]
      @pdf.text 'BRF Kimonokittens', align: :center, style: :italic
      @pdf.fill_color '000000'
    end
    @pdf.move_down 15

    @pdf.text 'Mellan nedanstående parter har följande avtal slutits:', size: 10
    @pdf.move_down 15
  end

  def generate_parties
    section_heading('1. Parter')

    @pdf.font_size(10) do
      # Landlord
      @pdf.text 'Förstahandshyresgäst (Hyresvärd i detta avtal):', style: :bold
      @pdf.move_down 3
      @pdf.text "Namn: #{LANDLORD[:name]}"
      @pdf.text "Personnummer: #{LANDLORD[:personnummer]}"
      @pdf.text "Telefon: #{LANDLORD[:phone]}"
      @pdf.text "E-post: #{LANDLORD[:email]}"
      @pdf.move_down 10

      # Tenant
      @pdf.text 'Andrahands-hyresgäst (Hyresgäst i detta avtal):', style: :bold
      @pdf.move_down 3
      @pdf.text "Namn: #{@tenant[:name]}"
      @pdf.text "Personnummer: #{@tenant[:personnummer]}"
      @pdf.text "Telefon: #{@tenant[:phone]}"
      @pdf.text "E-post: #{@tenant[:email]}"
    end

    @pdf.move_down 15
  end

  def generate_property
    section_heading('2. Objekt')

    @pdf.font_size(10) do
      @pdf.text "Adress: #{PROPERTY[:address]}"
      @pdf.text "Bostadstyp: #{PROPERTY[:type]}"
    end

    @pdf.move_down 15
  end

  def generate_lease_period
    section_heading('3. Hyrestid')

    move_in = @tenant[:move_in_date].strftime('%Y-%m-%d')

    @pdf.font_size(10) do
      @pdf.text "Avtalet gäller omedelbart med inflytt från och med #{move_in} tills vidare med en " \
                "uppsägningstid om två (2) månader räknat från den dag då uppsägningen skriftligen " \
                "meddelats motparten.", align: :justify
    end

    @pdf.move_down 15
  end

  def generate_rent
    section_heading('4. Hyra')

    @pdf.font_size(10) do
      @pdf.text "4.1 Kall månadshyra: #{format_currency(RENT_DETAILS[:base_rent])}", style: :bold
      @pdf.move_down 5
      @pdf.text '4.2 I hyran ingår ej el- och nätkostnad. Se punkt 5.'
    end

    @pdf.move_down 15
  end

  def generate_utilities
    section_heading('5. Avgifter för el och nät')

    @pdf.font_size(10) do
      @pdf.text 'Hyresgästen åtar sig att dela elkostnad, nätkostnad, vattenavgift, larm, gas och ' \
                "bredband lika med övriga medlemmar i kollektivet. Den genomsnittliga månadskostnaden " \
                "för dessa är ca. #{format_currency(RENT_DETAILS[:utilities_estimate])}.", align: :justify
      @pdf.move_down 8

      @pdf.text 'Observera att totalkostnaden varierar säsongsmässigt beroende på elförbrukning. ' \
                'Den genomsnittliga totala boendekostnaden är cirka 7,300 kr per månad, med ' \
                'maximal kostnad på cirka 7,900 kr under vinterhalvåret (uppvärmningsbehov).',
                align: :justify, style: :italic
    end

    @pdf.move_down 15
  end

  def generate_deposit
    section_heading('6. Deposition')

    @pdf.font_size(10) do
      @pdf.text "Hyresgästen erlägger en deposition om en dryg (1) kall månadshyra, dvs. " \
                "#{format_currency(RENT_DETAILS[:deposit])}, som återbetalas i enlighet med hyreslagens " \
                "bestämmelser efter det att hyresobjektet återlämnats i godtagbart skick.", align: :justify
    end

    @pdf.move_down 15
  end

  def generate_furnishing_deposit
    section_heading('7. Inredningsdeposition')

    @pdf.font_size(10) do
      @pdf.text "7.1 Vid inträde i kollektivet erlägger andrahandsgästen, utöver depositionen, en " \
                "inredningsdeposition om #{format_currency(RENT_DETAILS[:furnishing_deposit])} till den utflyttande parten.",
                align: :justify
      @pdf.move_down 8

      @pdf.text '7.2 Vid utflytt återbetalas denna inredningsdeposition på följande sätt:',
                align: :justify
      @pdf.move_down 3

      @pdf.indent(20) do
        @pdf.text '• Om det finns en efterträdande medlem överlämnar denna 2,200 kr till utflyttande part.',
                  align: :justify
        @pdf.move_down 3
        @pdf.text '• Om kollektivet upplöses återlämnas i stället motsvarande värde i de inventarier som ' \
                  'köptes för depositionens summa när kollektivet bildades.',
                  align: :justify
      end
      @pdf.move_down 8

      @pdf.text '7.3 Inredningsdepositionen utgör en delad investering i gemensamma hushållsartiklar ' \
                '(möbler, växter, prydnadsföremål, porslin, och liknande). Eventuella tvister rörande ' \
                'depositionen hanteras i god ton av kollektivets medlemmar.',
                align: :justify
    end

    @pdf.move_down 15
  end

  def generate_notice_period
    section_heading('8. Uppsägning')

    @pdf.font_size(10) do
      @pdf.text 'Uppsägning ska ske skriftligen med minst två (2) månaders varsel. Uppsägning räknas ' \
                'från den sista dagen i den månad då uppsägningen delges motparten.',
                align: :justify
    end

    @pdf.move_down 15
  end

  def generate_other_terms
    section_heading('9. Övriga villkor')

    @pdf.font_size(10) do
      @pdf.indent(20) do
        @pdf.text '• Hyresgästen förbinder sig att följa ordningsregler som gäller för kollektivet.'
        @pdf.move_down 3
        @pdf.text '• Husdjur: tillåtet samt eventuella villkor: gemensam överrenskommelse'
        @pdf.move_down 3
        @pdf.text '• Försäkring: Hyresgästen ansvarar för att ha hemförsäkring med rättsskydd.'
      end
      @pdf.move_down 8

      @pdf.text 'I övriga frågor kontakta först förstahandshyresgästen enligt uppgifter i punkt 1.'
    end

    @pdf.move_down 15
  end

  def generate_democratic_structure
    # Start new page if needed (this section is long)
    @pdf.start_new_page if @pdf.cursor < 250

    section_heading('10. Hyresstruktur och demokratisk beslutsgång')

    @pdf.font_size(10) do
      # 10.1
      @pdf.text '10.1 Hyresberäkning', style: :bold
      @pdf.move_down 3
      @pdf.text 'Kallhyran per person baseras på husets totala kallhyra (24,530 kr) delat på ' \
                'antalet boende. Vid fyra boende: 6,132.5 kr per person. Vid fem boende: 4,906 kr per person.',
                align: :justify
      @pdf.move_down 8

      # 10.2
      @pdf.text '10.2 Rumsjusteringar', style: :bold
      @pdf.move_down 3
      @pdf.text 'Rumsjusteringar kan förekomma efter demokratisk överenskommelse. Mindre rum eller ' \
                'rum som delas av par kan berättiga till reducerad kallhyra. Sådana justeringar beslutas ' \
                'gemensamt av kollektivets medlemmar.',
                align: :justify
      @pdf.move_down 8

      # 10.3
      @pdf.text '10.3 Beslutsprocess', style: :bold
      @pdf.move_down 3
      @pdf.text 'Beslut om hyresstruktur och rumsjusteringar fattas demokratiskt med förstahandshyresgästen ' \
                'som slutgiltig beslutsfattare vid oenighet. Förstahandshyresgästen har ansvarat för ' \
                'kollektivets drift och utveckling sedan 2023 och säkerställer kontinuitet och rättvisa ' \
                'i beslutsprocessen.',
                align: :justify
      @pdf.move_down 8

      # 10.4
      @pdf.text '10.4 Öppenhet', style: :bold
      @pdf.move_down 3
      @pdf.text 'Alla hyresberäkningar och beslut dokumenteras transparent och är tillgängliga för ' \
                'kollektivets medlemmar.',
                align: :justify
    end

    @pdf.move_down 20
  end

  def generate_signature_section
    # Ensure enough space for signatures (start new page if needed)
    @pdf.start_new_page if @pdf.cursor < 200

    @pdf.stroke_horizontal_rule
    @pdf.move_down 15

    @pdf.font_size(11) do
      @pdf.text 'Ort och datum', style: :bold
      @pdf.move_down 5
      @pdf.text "Huddinge den ____________________"
      @pdf.move_down 30

      @pdf.text 'Underskrifter', style: :bold, align: :center
      @pdf.move_down 30

      # Landlord signature
      @pdf.text 'Förstahandshyresgäst:', style: :bold
      @pdf.move_down 30
      @pdf.stroke do
        @pdf.horizontal_line 0, 250, at: @pdf.cursor
      end
      @pdf.move_down 5
      @pdf.text LANDLORD[:name]
      @pdf.move_down 40

      # Tenant signature
      @pdf.text 'Andrahands-hyresgäst:', style: :bold
      @pdf.move_down 30
      @pdf.stroke do
        @pdf.horizontal_line 0, 250, at: @pdf.cursor
      end
      @pdf.move_down 5
      @pdf.text @tenant[:name]
    end
  end

  # Helper: Format section headings
  def section_heading(text)
    @pdf.font_size(11) do
      @pdf.text text, style: :bold
    end
    @pdf.move_down 8
  end

  # Helper: Format currency (Swedish style with space)
  def format_currency(amount)
    whole = amount.to_i
    decimal = ((amount - whole) * 10).round
    formatted = whole.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1 ').reverse

    decimal.zero? ? "#{formatted} kr" : "#{formatted}.#{decimal} kr"
  end
end

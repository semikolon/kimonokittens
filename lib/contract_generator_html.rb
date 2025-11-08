require 'erb'
require 'ferrum'
require 'fileutils'
require 'kramdown'

class ContractGeneratorHtml
  TEMPLATE_PATH = File.expand_path('contract_template.html.erb', __dir__)
  FONTS_DIR = File.expand_path('../fonts', __dir__)
  LOGO_PATH = File.expand_path('../dashboard/public/logo.png', __dir__)
  SWISH_QR_PATH = File.expand_path('swish-qr.png', __dir__)

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

  def self.generate_from_markdown(markdown_path, output_path)
    new.generate_from_markdown(markdown_path, output_path)
  end

  def generate_from_markdown(markdown_path, output_path)
    # Read markdown
    markdown = File.read(markdown_path)

    # Extract tenant info from markdown
    tenant = extract_tenant_info(markdown)

    # Prepare template data
    template_data = prepare_template_data(tenant, markdown)

    # Render HTML
    html = render_html(template_data)

    # Save temporary HTML file
    html_path = output_path.sub('.pdf', '_temp.html')
    File.write(html_path, html)

    # Generate PDF using Ferrum (headless Chrome)
    generate_pdf(html_path, output_path)

    # Clean up temp HTML
    File.delete(html_path) if File.exist?(html_path)

    puts "✅ Generated dashboard-styled PDF: #{output_path}"
    output_path
  end

  private

  def extract_tenant_info(markdown)
    # Find text after "Andrahands-hyresgäst" and before next "##"
    after_tenant = markdown.split(/Andrahands-hyresgäst/)[1]
    tenant_section = after_tenant ? after_tenant.split(/^##/)[0] : ''

    {
      name: extract_field(tenant_section, 'Namn'),
      personnummer: extract_field(tenant_section, 'Personnummer'),
      phone: extract_field(tenant_section, 'Telefon'),
      email: extract_field(tenant_section, 'E-post')
    }
  end

  def extract_field(text, field_name)
    # Try bullet list format first (- Namn: ...)
    result = text.match(/^-\s*#{field_name}:\s*(.+?)$/i)&.captures&.first&.strip
    return result if result

    # Fall back to bold format (**Namn:** ...)
    text.match(/\*\*#{field_name}:\*\*\s*(.+?)(?:\n|$)/i)&.captures&.first&.strip || 'N/A'
  end

  def prepare_template_data(tenant, markdown)
    # Extract start date from Hyrestid section
    start_date_match = markdown.match(/från och med \*\*(\d{4}-\d{2}-\d{2})\*\*/i)
    start_date = start_date_match&.captures&.first || '2023-02-01'

    # Extract rent amount from Hyra section
    rent_match = markdown.match(/Kall månadshyra:\*\*\s*([\d,\.]+)\s*kr/i)
    rent_amount = rent_match&.captures&.first&.gsub(',', ' ') || '4 500'

    {
      fonts_dir: FONTS_DIR,
      logo_path: LOGO_PATH,
      swish_qr_path: SWISH_QR_PATH,
      landlord: LANDLORD,
      tenant: tenant,
      property: PROPERTY,
      contract_period: "#{start_date} – tills vidare",
      rental_period_text: extract_section(markdown, 'Hyrestid'),
      rent: {
        amount: rent_amount,
        due_day: '27',
        swish: '073-653 60 35'  # House account from Swish QR code
      },
      utilities_text: extract_section(markdown, 'Avgifter för el'),
      deposit_text: extract_section(markdown, 'Deposition'),
      furnishing_deposit_text: extract_section(markdown, 'Inredningsdeposition'),
      notice_period_text: extract_section(markdown, 'Uppsägning'),
      other_terms: extract_list_items(markdown, 'Övriga villkor'),
      democratic_structure_text: extract_section(markdown, 'Hyresstruktur och demokratisk beslutsgång')
    }
  end

  def extract_section(markdown, heading)
    # Match sections like "## 3. Hyrestid" or "## Hyrestid"
    section = markdown.match(/##\s*(?:\d+\.\s*)?#{Regexp.escape(heading)}.*?\n(.+?)(?=##|\z)/m)
    return 'Information saknas' unless section

    # Use kramdown to render markdown properly (handles **bold**, *italic*, etc.)
    markdown_text = section.captures.first.strip
    Kramdown::Document.new(markdown_text).to_html.strip
  end

  def extract_list_items(markdown, heading)
    # Match sections like "## 10. Övriga villkor" or "## Övriga villkor"
    section = markdown.match(/##\s*(?:\d+\.\s*)?#{Regexp.escape(heading)}.*?\n(.+?)(?=##|\z)/m)
    return [] unless section

    # Match both * and - list markers
    section.captures.first.scan(/^[*-]\s*(.+)$/).flatten.map(&:strip)
  end

  def render_html(data)
    template = ERB.new(File.read(TEMPLATE_PATH))
    template.result_with_hash(data)
  end

  def generate_pdf(html_path, pdf_path)
    # Ensure output directory exists
    FileUtils.mkdir_p(File.dirname(pdf_path))

    # Launch headless Chrome via Ferrum with aggressive flags to eliminate white lines
    browser = Ferrum::Browser.new(
      headless: true,
      window_size: [1200, 1600],
      browser_options: {
        'args' => ['--no-pdf-header-footer', '--disable-gpu', '--run-all-compositor-stages-before-draw']
      }
    )

    begin
      # Navigate to HTML file
      browser.goto("file://#{File.absolute_path(html_path)}")

      # Wait for fonts and images to load
      sleep 1

      # Generate PDF with Chrome's print-to-PDF (zero margins + force background rendering)
      browser.pdf(
        path: pdf_path,
        format: :A4,
        margin_top: 0,
        margin_right: 0,
        margin_bottom: 0,
        margin_left: 0,
        printBackground: true,  # Force background colors/images to render
        preferCSSPageSize: false  # Use format parameter, not CSS
      )
    ensure
      browser.quit
    end
  end
end

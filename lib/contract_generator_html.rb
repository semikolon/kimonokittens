require 'erb'
require 'ferrum'
require 'fileutils'
require 'kramdown'
require_relative 'repositories/tenant_repository'
require_relative 'handbook_parser'
require_relative 'landlord_profile'

class ContractGeneratorHtml
  TEMPLATE_PATH = File.expand_path('contract_template.html.erb', __dir__)
  MARKDOWN_TEMPLATE_PATH = File.expand_path('../contracts/templates/base_contract.md.erb', __dir__)
  HANDBOOK_PATH = File.expand_path('../handbook/docs/agreements.md', __dir__)
  FONTS_DIR = File.expand_path('../fonts', __dir__)
  LOGO_PATH = File.expand_path('assets/logo-80pct-saturated-2000w.png', __dir__)  # Optimized 2000px (1.2MB vs 6.8MB, 82% reduction)
  SWISH_QR_PATH = File.expand_path('swish-qr.png', __dir__)

  PROPERTY = {
    address: 'Sördalavägen 26, 141 60 Huddinge',
    type: 'Rum och gemensamma ytor i kollektiv'
  }.freeze

  # Total base rent for the apartment (used in rent calculations)
  TOTAL_BASE_RENT = 24_530

  # Standard deposit amounts (can be overridden by tenant-specific values)
  DEFAULT_DEPOSITS = {
    base_deposit: 6_200,
    furnishing_deposit: 2_200
  }.freeze

  def self.generate_from_markdown(markdown_path, output_path = nil)
    new.generate_from_markdown(markdown_path, output_path)
  end

  # Generate contract from database tenant record
  #
  # @param tenant_id [String] Tenant ID from database
  # @param output_path [String, nil] Optional PDF output path
  # @return [String] Path to generated PDF
  def self.generate_from_tenant_id(tenant_id, output_path: nil)
    new.generate_from_tenant_id(tenant_id, output_path: output_path)
  end

  def generate_from_tenant_id(tenant_id, output_path: nil)
    # Load tenant from database
    repo = TenantRepository.new
    tenant = repo.find_by_id(tenant_id)
    raise ArgumentError, "Tenant not found: #{tenant_id}" unless tenant

    # Default output path: contracts/generated/<Name>_<Surname>_Hyresavtal_<Date>.pdf
    output_path ||= begin
      name_parts = tenant.name.split(' ')
      surname = name_parts.last
      first_name = name_parts.first
      # Sanitize filename: Swedish chars → ASCII (ä→a, ö→o, å→a)
      sanitized_first = first_name.tr('åäöÅÄÖ', 'aaoAAO')
      sanitized_surname = surname.tr('åäöÅÄÖ', 'aaoAAO')
      date = tenant.start_date&.strftime('%Y-%m-%d') || Date.today.strftime('%Y-%m-%d')
      File.expand_path("../contracts/generated/#{sanitized_first}_#{sanitized_surname}_Hyresavtal_#{date}.pdf", __dir__)
    end

    # Prepare template data
    template_data = prepare_database_template_data(tenant)

    # Render markdown from ERB template
    markdown = render_markdown_template(template_data)

    # Prepare HTML data - use pre-calculated rent, convert markdown sections to HTML
    html_data = prepare_html_data_from_template(template_data, markdown, tenant)

    # Render HTML
    html = render_html(html_data)

    # Save temporary HTML file
    html_path = output_path.sub('.pdf', '_temp.html')
    File.write(html_path, html)

    # Generate PDF using Ferrum (headless Chrome)
    generate_pdf(html_path, output_path)

    # Clean up temp HTML
    File.delete(html_path) if File.exist?(html_path)

    puts "✅ Generated contract from database: #{output_path}"
    output_path
  end

  def generate_from_markdown(markdown_path, output_path = nil)
    # Enforce canonical naming: PDF matches markdown filename
    output_path ||= markdown_path.sub(/\.md$/, '.pdf')

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

  # Prepare template data from database tenant record
  def prepare_database_template_data(tenant)
    # Calculate rent amounts
    num_active_tenants = 4  # TODO: Query from database
    base_rent_per_person = TOTAL_BASE_RENT / num_active_tenants.to_f
    base_rent_5_people = TOTAL_BASE_RENT / 5.0

    # Use tenant-specific deposits if available, otherwise defaults
    base_deposit = tenant.deposit || DEFAULT_DEPOSITS[:base_deposit]
    furnishing_deposit = tenant.furnishing_deposit || DEFAULT_DEPOSITS[:furnishing_deposit]

    {
      landlord: landlord_profile,
      tenant: {
        name: tenant.name,
        personnummer: tenant.personnummer || 'N/A',
        phone: tenant.phone || 'N/A',
        email: tenant.email,
        move_in_date: tenant.start_date&.strftime('%Y-%m-%d') || Date.today.strftime('%Y-%m-%d'),
        probation_end_date: ((tenant.start_date || Date.today) >> 3).strftime('%Y-%m-%d')  # 3 months after move-in
      },
      property: PROPERTY,
      rent: {
        base_amount: format_currency(base_rent_per_person),
        total_amount: '7,300',  # Average including utilities
        total_base_rent: format_currency(TOTAL_BASE_RENT),
        base_amount_4_people: format_currency(base_rent_per_person),
        base_amount_5_people: format_currency(base_rent_5_people)
      },
      utilities: {
        average_monthly: '1,200',
        winter_max: '7,900'
      },
      deposits: {
        base_deposit: format_currency(base_deposit),
        furnishing_deposit: format_currency(furnishing_deposit)
      }
    }
  end

  # Render markdown contract from ERB template
  def render_markdown_template(data)
    template = ERB.new(File.read(MARKDOWN_TEMPLATE_PATH))
    template.result_with_hash(data)
  end

  # Prepare HTML data from pre-calculated template data (database-driven generation)
  # Uses rent values from template_data, converts markdown sections to HTML
  def prepare_html_data_from_template(template_data, markdown, tenant)
    {
      fonts_dir: FONTS_DIR,
      logo_path: LOGO_PATH,
      swish_qr_path: SWISH_QR_PATH,
      landlord: template_data[:landlord],
      tenant: template_data[:tenant],
      property: template_data[:property],
      contract_period: "#{template_data[:tenant][:move_in_date]} – tills vidare",
      rental_period_text: extract_section(markdown, 'Hyrestid'),
      rent: {
        amount: template_data[:rent][:base_amount],  # Use pre-calculated value!
        total: template_data[:rent][:total_amount],
        due_day: '27',
        swish: '073-653 60 35'
      },
      utilities_text: extract_section(markdown, 'Avgifter för el'),
      deposit_text: extract_section(markdown, 'Deposition'),
      furnishing_deposit_text: extract_section(markdown, 'Inredningsdeposition'),
      notice_period_text: extract_section(markdown, 'Uppsägning'),
      other_terms: extract_list_items(markdown, 'Övriga villkor'),
      democratic_structure_text: extract_section(markdown, 'Hyresstruktur och demokratisk beslutsgång')
    }
  end

  # Convert rendered markdown to HTML template data
  def prepare_template_data_from_markdown(markdown, tenant)
    # Extract tenant info for consistency
    tenant_info = {
      name: tenant.name,
      personnummer: tenant.personnummer || 'N/A',
      phone: tenant.phone || 'N/A',
      email: tenant.email
    }

    # Extract start date
    start_date_match = markdown.match(/från och med \*\*(\d{4}-\d{2}-\d{2})\*\*/i)
    start_date = start_date_match&.captures&.first || tenant.start_date&.strftime('%Y-%m-%d')

    # Extract rent amounts
    rent_match = markdown.match(/Kall månadshyra:\*\*\s*([\d,\.]+)\s*kr/i)
    rent_amount = rent_match&.captures&.first&.gsub(',', ' ') || '4 500'

    total_rent_match = markdown.match(/Genomsnittlig total månadshyra.*?:\*\*\s*([\d,\.]+)\s*kr/i)
    total_rent = total_rent_match&.captures&.first&.gsub(',', ' ') || '7 300'

    {
      fonts_dir: FONTS_DIR,
      logo_path: LOGO_PATH,
      swish_qr_path: SWISH_QR_PATH,
      landlord: landlord_profile,
      tenant: tenant_info,
      property: PROPERTY,
      contract_period: "#{start_date} – tills vidare",
      rental_period_text: extract_section(markdown, 'Hyrestid'),
      rent: {
        amount: rent_amount,
        total: total_rent,
        due_day: '27',
        swish: '073-653 60 35'
      },
      utilities_text: extract_section(markdown, 'Avgifter för el'),
      deposit_text: extract_section(markdown, 'Deposition'),
      furnishing_deposit_text: extract_section(markdown, 'Inredningsdeposition'),
      notice_period_text: extract_section(markdown, 'Uppsägning'),
      other_terms: extract_list_items(markdown, 'Övriga villkor'),
      democratic_structure_text: extract_section(markdown, 'Hyresstruktur och demokratisk beslutsgång')
    }
  end

  # Format number as Swedish currency (space as thousand separator)
  def format_currency(amount)
    return amount if amount.is_a?(String)
    amount = amount.to_f.round(2)
    integer_part = amount.to_i
    decimal_part = ((amount - integer_part) * 100).round

    formatted = integer_part.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1 ').reverse
    decimal_part > 0 ? "#{formatted},#{decimal_part.to_s.rjust(2, '0')}" : formatted
  end

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

    # Extract total rent (including utilities)
    total_rent_match = markdown.match(/Genomsnittlig total månadshyra.*?:\*\*\s*([\d,\.]+)\s*kr/i)
    total_rent = total_rent_match&.captures&.first&.gsub(',', ' ') || '7 300'

    {
      fonts_dir: FONTS_DIR,
      logo_path: LOGO_PATH,
      swish_qr_path: SWISH_QR_PATH,
      landlord: landlord_profile,
      tenant: tenant,
      property: PROPERTY,
      contract_period: "#{start_date} – tills vidare",
      rental_period_text: extract_section(markdown, 'Hyrestid'),
      rent: {
        amount: rent_amount,
        total: total_rent,
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

  def landlord_profile
    LandlordProfile.info
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

    # Match both * and - list markers and convert markdown to HTML
    section.captures.first.scan(/^[*-]\s*(.+)$/).flatten.map do |item|
      # Convert markdown bold (**text**) to HTML
      Kramdown::Document.new(item.strip).to_html.gsub(/<\/?p>/, '').strip
    end
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

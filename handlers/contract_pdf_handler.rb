# Handler for serving contract PDFs
# Required because browsers block file:// URLs from HTTP pages for security
class ContractPdfHandler
  def initialize
    require_relative '../lib/persistence'
  end

  def call(env)
    req = Rack::Request.new(env)

    # Extract contract ID from path: /api/contracts/:id/pdf
    path_parts = req.path.split('/')
    contract_id = path_parts[-2] # Second to last segment

    return not_found('Contract ID required') unless contract_id

    # Find contract
    contract_repo = Persistence.signed_contracts
    contract = contract_repo.find_by_id(contract_id)

    return not_found('Contract not found') unless contract
    return not_found('PDF not available') unless contract.pdf_url

    # Check if file exists
    pdf_path = contract.pdf_url
    return not_found('PDF file not found on disk') unless File.exist?(pdf_path)

    # Read and serve PDF
    pdf_content = File.binread(pdf_path)

    [
      200,
      {
        'Content-Type' => 'application/pdf',
        'Content-Disposition' => 'inline',
        'Content-Length' => pdf_content.bytesize.to_s,
        'Cache-Control' => 'public, max-age=3600'
      },
      [pdf_content]
    ]
  rescue => e
    puts "❌ Error serving PDF: #{e.message}"
    puts e.backtrace.first(5)
    internal_error(e.message)
  end

  private

  def not_found(message)
    [404, { 'Content-Type' => 'application/json' }, [Oj.dump({ error: message })]]
  end

  def internal_error(message)
    [500, { 'Content-Type' => 'application/json' }, [Oj.dump({ error: message })]]
  end
end

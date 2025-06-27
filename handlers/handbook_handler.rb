require 'agoo'
require 'json'

class HandbookHandler
  def call(req, res)
    res.set_header('Content-Type', 'application/json')
    
    # Mock API for fetching a single page
    if req.path.match(%r{/api/handbook/pages/(\w+)})
      slug = $1
      res.body = {
        title: "Mock Page: #{slug.capitalize}",
        content: "<h1>#{slug.capitalize}</h1><p>This is mock content for the page.</p>"
      }.to_json
      return
    end

    # Mock API for fetching proposals
    if req.path == '/api/handbook/proposals' && req.request_method == 'GET'
      res.body = [
        { id: 1, title: 'Proposal 1', author: 'Fredrik' },
        { id: 2, title: 'Proposal 2', author: 'Rasmus' }
      ].to_json
      return
    end
    
    # Mock API for creating a proposal
    if req.path == '/api/handbook/proposals' && req.request_method == 'POST'
      puts "Received proposal: #{req.body}"
      res.body = { status: 'success', message: 'Proposal received' }.to_json
      return
    end
    
    res.code = 404
    res.body = { error: 'Not Found' }.to_json
  end
end 
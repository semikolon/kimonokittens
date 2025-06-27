require 'rspec'
require 'json'
require 'agoo'
require_relative '../handlers/handbook_handler'

RSpec.describe HandbookHandler do
  let(:handler) { HandbookHandler.new }
  
  # Helper method to create a mock request
  def mock_request(method, path, body = nil, headers = {})
    req = double('Agoo::Request')
    allow(req).to receive(:request_method).and_return(method)
    allow(req).to receive(:path).and_return(path)
    allow(req).to receive(:body).and_return(body) if body
    req
  end
  
  # Helper method to create a mock response
  def mock_response
    res = double('Agoo::Response')
    @response_headers = {}
    @response_body = nil
    @response_code = 200
    
    allow(res).to receive(:set_header) do |key, value|
      @response_headers[key] = value
    end
    allow(res).to receive(:body=) do |value|
      @response_body = value
    end
    allow(res).to receive(:code=) do |value|
      @response_code = value
    end
    allow(res).to receive(:body).and_return(@response_body)
    allow(res).to receive(:code).and_return(@response_code)
    
    res
  end
  
  describe 'Proposal API' do
    it 'starts with an empty list of proposals' do
      req = mock_request('GET', '/api/handbook/proposals')
      res = mock_response
      
      handler.call(req, res)
      
      expect(@response_code).to eq(200)
      expect(JSON.parse(@response_body)).to eq([])
    end

    it 'can create a new proposal' do
      req = mock_request('POST', '/api/handbook/proposals', { content: '<p>New idea!</p>' }.to_json)
      res = mock_response
      
      handler.call(req, res)
      
      expect(@response_code).to eq(200)
      response_body = JSON.parse(@response_body)
      expect(response_body['id']).to eq(1)
      expect(response_body['content']).to eq('<p>New idea!</p>')
      expect(response_body['approvals']).to eq(0)
      expect(response_body['created_at']).not_to be_nil
    end
    
    it 'returns error for invalid JSON in proposal creation' do
      req = mock_request('POST', '/api/handbook/proposals', 'invalid json{')
      res = mock_response
      
      handler.call(req, res)
      
      expect(@response_code).to eq(400)
      expect(JSON.parse(@response_body)['error']).to eq('Invalid JSON')
    end
    
    it 'lists created proposals' do
      # Create a proposal first
      req1 = mock_request('POST', '/api/handbook/proposals', { content: '<p>First proposal</p>' }.to_json)
      res1 = mock_response
      handler.call(req1, res1)
      
      # Then get the list
      req2 = mock_request('GET', '/api/handbook/proposals')
      res2 = mock_response
      handler.call(req2, res2)
      
      expect(@response_code).to eq(200)
      response_body = JSON.parse(@response_body)
      expect(response_body.length).to eq(1)
      expect(response_body[0]['content']).to eq('<p>First proposal</p>')
    end

    it 'can approve a proposal' do
      # Create a proposal
      req1 = mock_request('POST', '/api/handbook/proposals', { content: '<p>Approve me</p>' }.to_json)
      res1 = mock_response
      handler.call(req1, res1)
      proposal_id = JSON.parse(@response_body)['id']

      # Approve it
      req2 = mock_request('POST', "/api/handbook/proposals/#{proposal_id}/approve")
      res2 = mock_response
      handler.call(req2, res2)
      
      expect(@response_code).to eq(200)
      approved_proposal = JSON.parse(@response_body)
      expect(approved_proposal['approvals']).to eq(1)
      
      # Approve it again
      req3 = mock_request('POST', "/api/handbook/proposals/#{proposal_id}/approve")
      res3 = mock_response
      handler.call(req3, res3)
      
      second_approval = JSON.parse(@response_body)
      expect(second_approval['approvals']).to eq(2)
    end
    
    it 'returns 404 for non-existent proposal approval' do
      req = mock_request('POST', '/api/handbook/proposals/999/approve')
      res = mock_response
      
      handler.call(req, res)
      
      expect(@response_code).to eq(404)
      expect(JSON.parse(@response_body)['error']).to eq('Proposal not found')
    end
  end

  describe 'AI Query API' do
    # We will mock the AI and Pinecone interactions to avoid real API calls in tests
    let(:openai_client) { double('OpenAI::Client') }
    let(:pinecone_client) { double('Pinecone::Client') }
    let(:pinecone_index) { double('Pinecone::Index') }

    before do
      # Mock the initialization methods
      allow_any_instance_of(HandbookHandler).to receive(:init_openai).and_return(openai_client)
      allow_any_instance_of(HandbookHandler).to receive(:init_pinecone).and_return(pinecone_client)
      allow(pinecone_client).to receive(:index).and_return(pinecone_index)
    end
    
    it 'handles an AI query successfully' do
      # Mock OpenAI embeddings call
      allow(openai_client).to receive(:embeddings).and_return({
        "data" => [{ "embedding" => Array.new(1536) { rand } }]  # Realistic embedding size
      })
      
      # Mock Pinecone query call
      allow(pinecone_index).to receive(:query).and_return({
        "matches" => [
          { "metadata" => { "text" => "Context from handbook about guests." } }
        ]
      })
      
      # Mock OpenAI chat call
      allow(openai_client).to receive(:chat).and_return({
        "choices" => [{ "message" => { "content" => "Based on the handbook, the guest policy is..." } }]
      })

      req = mock_request('POST', '/api/handbook/query', { question: 'What is the guest policy?' }.to_json)
      res = mock_response
      
      handler.call(req, res)
      
      expect(@response_code).to eq(200)
      response_body = JSON.parse(@response_body)
      expect(response_body['answer']).to eq('Based on the handbook, the guest policy is...')
    end
    
    it 'returns an error if the question is missing' do
      req = mock_request('POST', '/api/handbook/query', {}.to_json)
      res = mock_response
      
      handler.call(req, res)
      
      expect(@response_code).to eq(400)
      expect(JSON.parse(@response_body)['error']).to eq('Question is required')
    end
    
    it 'returns an error if the question is empty' do
      req = mock_request('POST', '/api/handbook/query', { question: '   ' }.to_json)
      res = mock_response
      
      handler.call(req, res)
      
      expect(@response_code).to eq(400)
      expect(JSON.parse(@response_body)['error']).to eq('Question is required')
    end
    
    it 'handles AI processing errors gracefully' do
      # Make the OpenAI call fail
      allow(openai_client).to receive(:embeddings).and_raise('API Error')
      
      req = mock_request('POST', '/api/handbook/query', { question: 'What is the policy?' }.to_json)
      res = mock_response
      
      handler.call(req, res)
      
      expect(@response_code).to eq(200)  # Still returns 200 but with error message
      response_body = JSON.parse(@response_body)
      expect(response_body['answer']).to include('Sorry, I\'m having trouble')
    end
  end
  
  describe 'Page API' do
    it 'returns mock page content' do
      req = mock_request('GET', '/api/handbook/pages/rules')
      res = mock_response
      
      handler.call(req, res)
      
      expect(@response_code).to eq(200)
      response_body = JSON.parse(@response_body)
      expect(response_body['title']).to eq('Mock Page: Rules')
      expect(response_body['content']).to include('<h1>Rules</h1>')
    end
  end
  
  describe 'Unknown routes' do
    it 'returns 404 for unknown paths' do
      req = mock_request('GET', '/api/handbook/unknown')
      res = mock_response
      
      handler.call(req, res)
      
      expect(@response_code).to eq(404)
      expect(JSON.parse(@response_body)['error']).to eq('Not Found')
    end
  end
end 
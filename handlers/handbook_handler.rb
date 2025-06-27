require 'agoo'
require 'json'
require 'pinecone'
require 'openai'

class HandbookHandler
  def initialize
    @proposals = []
    @next_proposal_id = 1
  end

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
      res.body = @proposals.to_json
      return
    end
    
    # Mock API for creating a proposal
    if req.path == '/api/handbook/proposals' && req.request_method == 'POST'
      begin
        parsed_body = JSON.parse(req.body)
        new_proposal = {
          id: @next_proposal_id,
          title: "Proposal for #{Time.now.strftime('%Y-%m-%d')}",
          content: parsed_body['content'],
          approvals: 0,
          created_at: Time.now.strftime('%Y-%m-%d %H:%M:%S')
        }
        @proposals << new_proposal
        @next_proposal_id += 1
        
        puts "Created proposal: #{new_proposal[:title]}"
        res.body = new_proposal.to_json
        return
      rescue JSON::ParserError => e
        res.code = 400
        res.body = { error: 'Invalid JSON' }.to_json
        return
      end
    end
    
    # API for approving a proposal
    if req.path.match(%r{/api/handbook/proposals/(\d+)/approve}) && req.request_method == 'POST'
      proposal_id = $1.to_i
      proposal = @proposals.find { |p| p[:id] == proposal_id }
      
      if proposal
        proposal[:approvals] += 1
        puts "Approved proposal #{proposal_id}. Total approvals: #{proposal[:approvals]}"
        res.body = proposal.to_json
        return
      else
        res.code = 404
        res.body = { error: 'Proposal not found' }.to_json
        return
      end
    end
    
    # AI Query endpoint
    if req.path == '/api/handbook/query' && req.request_method == 'POST'
      begin
        parsed_body = JSON.parse(req.body)
        question = parsed_body['question']
        
        if question.nil? || question.strip.empty?
          res.code = 400
          res.body = { error: 'Question is required' }.to_json
          return
        end
        
        answer = process_ai_query(question)
        res.body = { answer: answer }.to_json
        return
        
      rescue JSON::ParserError => e
        res.code = 400
        res.body = { error: 'Invalid JSON' }.to_json
        return
      rescue => e
        puts "Error processing AI query: #{e.message}"
        res.code = 500
        res.body = { error: 'Internal server error' }.to_json
        return
      end
    end
    
    res.code = 404
    res.body = { error: 'Not Found' }.to_json
  end

  private

  def process_ai_query(question)
    begin
      # Initialize clients
      openai_client = init_openai
      pinecone_client = init_pinecone
      
      # 1. Embed the question
      embedding_response = openai_client.embeddings(
        parameters: {
          model: "text-embedding-3-small",
          input: question
        }
      )
      question_embedding = embedding_response.dig("data", 0, "embedding")
      
      # 2. Query Pinecone for similar content
      index = pinecone_client.index('kimonokittens-handbook')
      search_results = index.query(
        vector: question_embedding,
        top_k: 5,
        include_metadata: true
      )
      
      # 3. Extract context from results
      context_chunks = []
      if search_results && search_results['matches']
        search_results['matches'].each do |match|
          if match['metadata'] && match['metadata']['text']
            context_chunks << match['metadata']['text']
          end
        end
      end
      
      # 4. Construct prompt with context
      if context_chunks.empty?
        context = "No relevant information found in the handbook."
      else
        context = context_chunks.join("\n\n")
      end
      
      prompt = <<~PROMPT
        You are the Kimonokittens house AI assistant. Answer the user's question based ONLY on the context provided below from the collective's handbook. If the context doesn't contain relevant information, say so.

        Context from handbook:
        #{context}

        User question: #{question}

        Answer:
      PROMPT
      
      # 5. Get AI response
      chat_response = openai_client.chat(
        parameters: {
          model: "gpt-4o-mini",
          messages: [
            {
              role: "user",
              content: prompt
            }
          ],
          max_tokens: 500,
          temperature: 0.3
        }
      )
      
      chat_response.dig("choices", 0, "message", "content") || "I couldn't generate an answer."
      
    rescue => e
      puts "Error in AI processing: #{e.message}"
      "Sorry, I'm having trouble processing your question right now. Please try again later."
    end
  end

  def init_openai
    OpenAI.configure do |config|
      config.access_token = ENV['OPENAI_API_KEY']
    end
    OpenAI::Client.new
  end

  def init_pinecone
    Pinecone.configure do |config|
      config.api_key = ENV['PINECONE_API_KEY']
      config.environment = ENV.fetch('PINECONE_ENVIRONMENT', 'gcp-starter')
    end
    Pinecone::Client.new
  end
end 
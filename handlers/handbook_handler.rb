require 'agoo'
require 'json'
require 'pinecone'
require 'openai'
require 'rugged'
require 'uri'

class HandbookHandler
  def initialize
    # Remove the in-memory storage as we'll use Git branches instead
  end

  # Class method to access the Git repository
  def self.repo
    @repo ||= Rugged::Repository.new('.')
  end

  def call(env)
    path = env['PATH_INFO']
    method = env['REQUEST_METHOD']
    
    puts "DEBUG: Received #{method} #{path}"
    
    # Test endpoint
    if path == '/api/handbook/test' && method == 'POST'
      return [200, { 'Content-Type' => 'application/json' }, [{ message: 'Test endpoint works!' }.to_json]]
    end

    # Mock API for fetching a single page
    if path.match(%r{/api/handbook/pages/(\w+)})
      puts "DEBUG: Matched pages endpoint"
      slug = $1
      body = {
        title: "Mock Page: #{slug.capitalize}",
        content: "<h1>#{slug.capitalize}</h1><p>This is mock content for the page.</p>"
      }.to_json
      return [200, { 'Content-Type' => 'application/json' }, [body]]
    end

    # Mock API for fetching proposals
    if path == '/api/handbook/proposals' && method == 'GET'
      puts "DEBUG: Matched GET proposals endpoint"
      proposals = []
      
      # List all proposal branches
      self.class.repo.branches.each do |branch|
        if branch.name.start_with?('proposals/')
          # Parse branch name to extract info
          # Format: proposals/author/timestamp-description
          parts = branch.name.split('/')
          if parts.length >= 3
            author = parts[1]
            description_part = parts[2..-1].join('/')
            
            # Count approvals by looking for .approval.* files
            commit = branch.target
            tree = commit.tree
            approvals = []
            
            tree.each do |entry|
              if entry[:name].start_with?('.approval.')
                approver = entry[:name].sub('.approval.', '')
                approvals << approver
              end
            end
            
            proposals << {
              id: branch.name,
              author: author,
              description: description_part.gsub('-', ' ').capitalize,
              approvals: approvals.length,
              approvers: approvals,
              created_at: commit.time.strftime('%Y-%m-%d %H:%M:%S')
            }
          end
        end
      end
      
      return [200, { 'Content-Type' => 'application/json' }, [proposals.to_json]]
    end
    
    # Mock API for creating a proposal
    if path == '/api/handbook/proposals' && method == 'POST'
      puts "DEBUG: Matched POST proposals endpoint"
      begin
        # Read request body from Rack input
        body_content = env['rack.input'].read
        env['rack.input'].rewind
        
        parsed_body = JSON.parse(body_content)
        content = parsed_body['content']
        page_path = parsed_body['page_path'] || 'handbook/docs/test-page.md'
        author = parsed_body['author'] || 'anonymous'
        
        # Generate a unique branch name
        timestamp = Time.now.to_i
        safe_description = page_path.gsub(/[^a-z0-9\-_]/i, '-').downcase
        branch_name = "proposals/#{author}/#{timestamp}-update-#{safe_description}"
        
        # Get the current master/main branch
        main_branch = self.class.repo.branches['master'] || self.class.repo.branches['main']
        unless main_branch
          return [500, { 'Content-Type' => 'application/json' }, [{ error: 'No master or main branch found' }.to_json]]
        end
        
        # Create a new index based on the main branch
        parent_commit = main_branch.target
        index = self.class.repo.index
        index.read_tree(parent_commit.tree)
        
        # Add or update the file in the index
        oid = self.class.repo.write(content, :blob)
        index.add(path: page_path, oid: oid, mode: 0100644)
        
        # Write the index to create a tree
        tree_oid = index.write_tree(self.class.repo)
        
        # Create a new commit
        commit_message = "Proposal: Update #{page_path}\n\nProposed by: #{author}"
        new_commit_oid = Rugged::Commit.create(self.class.repo,
          message: commit_message,
          author: { name: author, email: "#{author}@kimonokittens.local", time: Time.now },
          committer: { name: author, email: "#{author}@kimonokittens.local", time: Time.now },
          tree: tree_oid,
          parents: [parent_commit]
        )
        
        # Create the new branch pointing to this commit
        self.class.repo.create_branch(branch_name, new_commit_oid)
        
        body = {
          id: branch_name,
          author: author,
          description: "Update #{safe_description}",
          approvals: 0,
          created_at: Time.now.strftime('%Y-%m-%d %H:%M:%S')
        }.to_json
        return [200, { 'Content-Type' => 'application/json' }, [body]]
      rescue JSON::ParserError => e
        return [400, { 'Content-Type' => 'application/json' }, [{ error: 'Invalid JSON' }.to_json]]
      rescue => e
        puts "Error creating proposal: #{e.message}"
        return [500, { 'Content-Type' => 'application/json' }, [{ error: "Failed to create proposal: #{e.message}" }.to_json]]
      end
    end
    
    # API for approving a proposal
    if path.match(%r{^/api/handbook/proposals/(.+)/approve$}) && method == 'POST'
      puts "DEBUG: Matched approval endpoint"
      branch_name = URI.decode_www_form_component($1)
      puts "DEBUG: Approval endpoint matched! Branch name: #{branch_name}"
      
      begin
        # Read request body from Rack input
        body_content = env['rack.input'].read
        env['rack.input'].rewind
        
        parsed_body = JSON.parse(body_content)
        approver = parsed_body['approver'] || 'anonymous'
        
        puts "DEBUG: Approver: #{approver}"
        
        # Find the proposal branch
        branch = self.class.repo.branches[branch_name]
        unless branch
          return [404, { 'Content-Type' => 'application/json' }, [{ error: 'Proposal not found' }.to_json]]
        end
        
        # Get the current commit on the proposal branch
        current_commit = branch.target
        
        # Check if this user already approved
        tree = current_commit.tree
        approval_file = ".approval.#{approver}"
        already_approved = tree.any? { |entry| entry[:name] == approval_file }
        
        if already_approved
          return [400, { 'Content-Type' => 'application/json' }, [{ error: 'You have already approved this proposal' }.to_json]]
        end
        
        # Create a new index based on the current commit
        index = self.class.repo.index
        index.read_tree(current_commit.tree)
        
        # Add the approval file (empty content)
        oid = self.class.repo.write("", :blob)
        index.add(path: approval_file, oid: oid, mode: 0100644)
        
        # Write the index to create a tree
        tree_oid = index.write_tree(self.class.repo)
        
        # Create a new commit with the approval
        commit_message = "Approved by #{approver}"
        new_commit_oid = Rugged::Commit.create(self.class.repo,
          message: commit_message,
          author: { name: approver, email: "#{approver}@kimonokittens.local", time: Time.now },
          committer: { name: approver, email: "#{approver}@kimonokittens.local", time: Time.now },
          tree: tree_oid,
          parents: [current_commit]
        )
        
        # Update the branch to point to the new commit
        self.class.repo.references.update("refs/heads/#{branch_name}", new_commit_oid)
        
        # Count total approvals
        new_tree = self.class.repo.lookup(tree_oid)
        approval_count = 0
        approvers = []
        new_tree.each do |entry|
          if entry[:name].start_with?('.approval.')
            approval_count += 1
            approvers << entry[:name].sub('.approval.', '')
          end
        end
        
        # If we have 2 or more approvals, attempt to merge
        merge_status = nil
        if approval_count >= 2
          main_branch = self.class.repo.branches['master'] || self.class.repo.branches['main']
          if main_branch
            begin
              # Attempt the merge
              merge_index = self.class.repo.merge_commits(main_branch.target, new_commit_oid)
              
              if merge_index.conflicts?
                merge_status = 'conflict'
              else
                # No conflicts, create the merge commit
                merge_tree_oid = merge_index.write_tree(self.class.repo)
                merge_commit_oid = Rugged::Commit.create(self.class.repo,
                  message: "Merge proposal: #{branch_name}\n\nApproved by: #{approvers.join(', ')}",
                  author: { name: 'Handbook System', email: 'system@kimonokittens.local', time: Time.now },
                  committer: { name: 'Handbook System', email: 'system@kimonokittens.local', time: Time.now },
                  tree: merge_tree_oid,
                  parents: [main_branch.target, new_commit_oid]
                )
                
                # Update main branch to the merge commit
                self.class.repo.references.update("refs/heads/#{main_branch.name}", merge_commit_oid)
                
                # Delete the proposal branch
                self.class.repo.branches.delete(branch_name)
                
                merge_status = 'merged'
              end
            rescue => e
              puts "Merge error: #{e.message}"
              merge_status = 'error'
            end
          end
        end
        
        body = {
          id: branch_name,
          approvals: approval_count,
          approvers: approvers,
          merge_status: merge_status
        }.to_json
        return [200, { 'Content-Type' => 'application/json' }, [body]]
        
      rescue JSON::ParserError => e
        return [400, { 'Content-Type' => 'application/json' }, [{ error: 'Invalid JSON' }.to_json]]
      rescue => e
        puts "Error approving proposal: #{e.message}"
        return [500, { 'Content-Type' => 'application/json' }, [{ error: "Failed to approve proposal: #{e.message}" }.to_json]]
      end
    end
    
    # AI Query endpoint
    if path == '/api/handbook/query' && method == 'POST'
      puts "DEBUG: Matched AI query endpoint"
      begin
        # Read request body from Rack input
        body_content = env['rack.input'].read
        env['rack.input'].rewind
        
        parsed_body = JSON.parse(body_content)
        question = parsed_body['question']
        
        if question.nil? || question.strip.empty?
          return [400, { 'Content-Type' => 'application/json' }, [{ error: 'Question is required' }.to_json]]
        end
        
        answer = process_ai_query(question)
        return [200, { 'Content-Type' => 'application/json' }, [{ answer: answer }.to_json]]
        
      rescue JSON::ParserError => e
        return [400, { 'Content-Type' => 'application/json' }, [{ error: 'Invalid JSON' }.to_json]]
      rescue => e
        puts "Error processing AI query: #{e.message}"
        return [500, { 'Content-Type' => 'application/json' }, [{ error: 'Internal server error' }.to_json]]
      end
    end
    
    puts "DEBUG: No endpoint matched, returning 404"
    [404, { 'Content-Type' => 'application/json' }, [{ error: 'Not Found' }.to_json]]
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
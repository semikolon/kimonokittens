require 'pinecone'
require 'openai'
require 'dotenv/load'

# Configuration
PINECONE_INDEX_NAME = 'kimonokittens-handbook'
DOCS_PATH = File.expand_path('../../docs', __FILE__)
# Standard dimension for OpenAI's text-embedding-3-small
VECTOR_DIMENSION = 1536 

def init_pinecone
  Pinecone.configure do |config|
    config.api_key  = ENV.fetch('PINECONE_API_KEY')
    # NOTE: The environment for Pinecone is found in the Pinecone console
    # It's usually something like "gcp-starter" or "us-west1-gcp"
    config.environment = ENV.fetch('PINECONE_ENVIRONMENT', 'gcp-starter') 
  end
end

def init_openai
  OpenAI.configure do |config|
    config.access_token = ENV.fetch('OPENAI_API_KEY')
  end
  OpenAI::Client.new
end

def get_embedding(client, text)
  # Rate limiting - be nice to the API
  sleep(0.1)
  
  begin
    response = client.embeddings(
      parameters: {
        model: "text-embedding-3-small",
        input: text
      }
    )
    
    response.dig("data", 0, "embedding")
  rescue => e
    puts "Error getting embedding for text: #{e.message}"
    puts "Using fallback fake embedding"
    # Fallback to fake embedding if API fails
    Array.new(VECTOR_DIMENSION) { rand(-1.0..1.0) }
  end
end

def main
  init_pinecone
  pinecone = Pinecone::Client.new
  
  # Initialize OpenAI client
  begin
    openai_client = init_openai
    puts "OpenAI client initialized successfully"
    use_real_embeddings = true
  rescue => e
    puts "Warning: OpenAI not available (#{e.message}). Using fake embeddings."
    use_real_embeddings = false
  end
  
  # 1. Create index if it doesn't exist
  begin
    index_list = pinecone.list_indexes
    unless index_list.any? { |idx| idx['name'] == PINECONE_INDEX_NAME }
      puts "Creating Pinecone index '#{PINECONE_INDEX_NAME}'..."
      pinecone.create_index(
        name: PINECONE_INDEX_NAME,
        dimension: VECTOR_DIMENSION,
        metric: 'cosine'
      )
      # Wait for index to be ready
      sleep(5)
    end
  rescue => e
    puts "Error checking/creating index: #{e.message}"
  end
  
  index = pinecone.index(PINECONE_INDEX_NAME)

  # 2. Read documents and prepare vectors
  vectors_to_upsert = []
  Dir.glob("#{DOCS_PATH}/*.md").each do |file_path|
    puts "Processing #{File.basename(file_path)}..."
    content = File.read(file_path)
    
    # Split content into chunks (by paragraph)
    chunks = content.split("\n\n").reject(&:empty?)
    
    chunks.each_with_index do |chunk, i|
      # Skip very short chunks
      next if chunk.strip.length < 50
      
      if use_real_embeddings
        embedding = get_embedding(openai_client, chunk)
      else
        # FAKE EMBEDDING: For development/testing
        embedding = Array.new(VECTOR_DIMENSION) { rand(-1.0..1.0) }
      end
      
      vectors_to_upsert << {
        id: "#{File.basename(file_path, '.md')}-#{i}",
        values: embedding,
        metadata: {
          file: File.basename(file_path),
          text: chunk[0..500] # Store more text for better context
        }
      }
    end
  end
  
  # 3. Upsert vectors to Pinecone
  puts "Upserting #{vectors_to_upsert.length} vectors to Pinecone..."
  index.upsert(vectors: vectors_to_upsert)
  puts "Done!"
  
  if use_real_embeddings
    puts "✅ Used real OpenAI embeddings"
  else
    puts "⚠️  Used fake embeddings - set OPENAI_API_KEY to use real ones"
  end
end

main if __FILE__ == $0 
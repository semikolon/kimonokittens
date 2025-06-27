require 'pinecone'
require 'dotenv/load'

# Configuration
PINECONE_INDEX_NAME = 'kimonokittens-handbook'
DOCS_PATH = File.expand_path('../../docs', __FILE__)
# Standard dimension for OpenAI's text-embedding-ada-002
VECTOR_DIMENSION = 1536 

def init_pinecone
  Pinecone.configure do |config|
    config.api_key  = ENV.fetch('PINECONE_API_KEY')
    # NOTE: The environment for Pinecone is found in the Pinecone console
    # It's usually something like "gcp-starter" or "us-west1-gcp"
    config.environment = ENV.fetch('PINECONE_ENVIRONMENT', 'gcp-starter') 
  end
end

def main
  init_pinecone
  pinecone = Pinecone::Client.new
  
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
      # FAKE EMBEDDING: In a real scenario, you would call an embedding API here.
      # For now, we generate a random vector.
      fake_embedding = Array.new(VECTOR_DIMENSION) { rand(-1.0..1.0) }
      
      vectors_to_upsert << {
        id: "#{File.basename(file_path, '.md')}-#{i}",
        values: fake_embedding,
        metadata: {
          file: File.basename(file_path),
          text: chunk[0..200] # Store a snippet of the text
        }
      }
    end
  end
  
  # 3. Upsert vectors to Pinecone
  puts "Upserting #{vectors_to_upsert.length} vectors to Pinecone..."
  index.upsert(vectors: vectors_to_upsert)
  puts "Done!"
end

main if __FILE__ == $0 
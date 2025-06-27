require 'dotenv/load'
require 'agoo'

# Configure Agoo logging
Agoo::Log.configure(dir: '',
  console: true,
  classic: true,
  colorize: true,
  states: {
    INFO: true,
    DEBUG: false,
    connect: true,
    request: true,
    response: true,
    eval: true,
    push: false
  })

# Development mode - no SSL
Agoo::Server.init(3001, 'root', thread_count: 0,
  bind: ['http://0.0.0.0:3001'],
)

require_relative 'handlers/handbook_handler'

handbook_handler = HandbookHandler.new

# Add Handbook API handlers with more permissive patterns
Agoo::Server.handle(:GET, "/api/handbook/**", handbook_handler)
Agoo::Server.handle(:POST, "/api/handbook/**", handbook_handler)

puts "Starting test server on http://localhost:3001"
Agoo::Server.start() 
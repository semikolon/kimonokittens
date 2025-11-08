source 'https://rubygems.org'

# Web Server
gem 'puma', '~> 6.4' # Primary web server with native WebSocket support
gem 'webrick' # Required for some dependencies

# Scheduling
gem 'rufus-scheduler', '~> 3.9'

# Core
gem 'json'
gem 'oj'
gem 'rack'
gem 'activesupport'
gem 'awesome_print'
gem 'dotenv-rails'
gem 'httparty'
gem 'jwt'
gem 'mutex_m'

# HTTP Client
gem 'faraday', '~> 2.13'
gem 'faraday-excon', '~> 2.2'

# PDF Generation
gem 'prawn', '~> 2.5'
gem 'prawn-table', '~> 0.2'

# Database
gem 'pg', '~> 1.6' # For PostgreSQL - upgraded for PostgreSQL 17 compatibility
gem 'sequel', '~> 5.84' # Database toolkit with connection pooling for thread safety
gem 'sqlite3', '~> 1.7'
gem 'cuid', '~> 1.0' # For Prisma-compatible IDs

# Git Operations
gem 'rugged', '~> 1.7'
gem 'ferrum'

# AI / Vector Search
gem 'pinecone', '~> 1.2' # Corrected gem name
gem 'ruby-openai', '~> 6.4'

# Testing
group :test, :development do
  gem 'rspec', '~> 3.13'
  gem 'rack-test', '~> 2.1'
  gem 'webmock', '~> 3.24'
  gem 'pry'
  gem 'listen', '~> 3.8'
  gem 'foreman', '~> 0.90' # Process management for development
end

# Assets (not required in production)
group :assets do
  gem 'sass-embedded', '~> 1.74'
end

gem "kramdown", "~> 2.5"

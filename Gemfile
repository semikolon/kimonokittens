source 'https://rubygems.org'

# Web Server
gem 'agoo', '~> 2.15.3'
gem 'puma' # Often used in production environments
gem 'webrick' # Required for some dependencies

# Core
gem 'json'
gem 'oj'
gem 'rack'
gem 'activesupport'
gem 'awesome_print'
gem 'dotenv-rails'
gem 'httparty'

# Database
gem 'pg', '~> 1.5' # For PostgreSQL
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
  gem 'pry'
  gem 'listen', '~> 3.8'
end

# Assets (not required in production)
group :assets do
  gem 'sass-embedded', '~> 1.74'
end

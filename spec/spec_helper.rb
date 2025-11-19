# Load test environment configuration FIRST
# This ensures tests NEVER touch development or production databases
require 'dotenv'
Dotenv.load('.env.test')

# ============================================================================
# WebMock Configuration - Global HTTP Control
# ============================================================================
# Industry best practice: Disable external HTTP by default, allow localhost
# This prevents accidental external calls and ensures test determinism
require 'webmock/rspec'

WebMock.enable!

# ============================================================================
# SAFETY GUARDS - Prevent catastrophic database contamination
# ============================================================================

# Safety check 1: Block production database
if ENV['DATABASE_URL']&.include?('production')
  abort "FATAL: Cannot run tests against production database!"
end

# Safety check 2: Enforce test database
unless ENV['DATABASE_URL']&.include?('_test')
  abort "FATAL: Tests must use a _test database. Found: #{ENV['DATABASE_URL']}"
end

# Visual confirmation (helps during development)
puts "=" * 80
puts "🧪 TEST MODE"
puts "=" * 80
puts "Database: #{ENV['DATABASE_URL']}"
puts "=" * 80
puts ""

# Standard RSpec configuration
RSpec.configure do |config|
  # Recommended settings for modern RSpec
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.shared_context_metadata_behavior = :apply_to_host_groups

  # Disable monkey patching (best practice)
  config.disable_monkey_patching!

  # Use documentation format for readable test output
  config.default_formatter = 'doc' if config.files_to_run.one?

  # Print slowest tests
  config.profile_examples = 10

  # Run specs in random order to detect order dependencies
  config.order = :random
  Kernel.srand config.seed

  # ============================================================================
  # WebMock Lifecycle Management
  # ============================================================================
  # Establish baseline: no external HTTP, localhost allowed (for Ferrum/Chrome)
  config.before(:suite) do
    WebMock.disable_net_connect!(allow_localhost: true)
  end

  # After each test: reset stubs AND re-apply baseline
  # CRITICAL: reset! clears allowed hosts, must reapply!
  config.after(:each) do
    WebMock.reset!
    WebMock.disable_net_connect!(allow_localhost: true)
  end

  # Allow specific tests to use real HTTP via :real_http tag
  # Usage: it "calls external API", :real_http do
  config.around(:each, :real_http) do |example|
    WebMock.allow_net_connect!
    example.run
    WebMock.disable_net_connect!(allow_localhost: true)
  end
end

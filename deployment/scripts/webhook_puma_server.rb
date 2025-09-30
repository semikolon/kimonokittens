#!/usr/bin/env ruby
# Smart webhook server using Puma architecture (unified with dashboard)
require 'dotenv/load'
require 'puma'
require 'rack'
require 'json'
require 'openssl'
require 'logger'
require 'fileutils'

# Configure logging
if ENV['RACK_ENV'] == 'production'
  log_dir = '/var/log/kimonokittens'
  FileUtils.mkdir_p(log_dir) unless Dir.exist?(log_dir)
  $logger = Logger.new(File.join(log_dir, 'webhook.log'))
else
  $logger = Logger.new(STDOUT)
end
$logger.level = Logger::INFO

# Smart webhook handler following dashboard pattern
class WebhookHandler
  def initialize
    @webhook_secret = ENV['WEBHOOK_SECRET'] || 'CHANGE_ME_TO_SECURE_SECRET'
    @deployment_handler = DeploymentHandler.new
  end

  def call(env)
    # Handle CORS preflight requests
    if env['REQUEST_METHOD'] == 'OPTIONS'
      return [204, cors_headers, []]
    end

    case env['PATH_INFO']
    when '/webhook'
      handle_github_webhook(env)
    when '/health'
      handle_health_check(env)
    when '/status'
      handle_status_check(env)
    else
      [404, json_headers, [{ error: 'Not Found' }.to_json]]
    end
  rescue => e
    $logger.error("Webhook error: #{e.message}")
    $logger.error(e.backtrace.join("\n"))
    [500, json_headers, [{ error: 'Internal server error' }.to_json]]
  end

  private

  def handle_github_webhook(env)
    return [405, json_headers, [{ error: 'Method not allowed' }.to_json]] unless env['REQUEST_METHOD'] == 'POST'

    # Read payload
    input = env['rack.input']
    input.rewind
    payload = input.read

    # Verify GitHub signature
    signature = env['HTTP_X_HUB_SIGNATURE_256']
    if signature && !verify_signature(payload, signature)
      $logger.warn("❌ Invalid webhook signature from #{env['REMOTE_ADDR']}")
      return [401, json_headers, [{ error: 'Invalid signature' }.to_json]]
    end

    # Parse JSON payload
    begin
      event_data = JSON.parse(payload)
    rescue JSON::ParserError => e
      $logger.error("❌ Invalid JSON payload: #{e.message}")
      return [400, json_headers, [{ error: 'Invalid JSON' }.to_json]]
    end

    # Only process pushes to master
    unless event_data['ref'] == 'refs/heads/master'
      $logger.info("ℹ️ Ignoring push to #{event_data['ref']} (not master)")
      return [200, json_headers, [{ status: 'ignored', message: 'Not master branch' }.to_json]]
    end

    # Analyze and deploy changes
    result = @deployment_handler.process_webhook(event_data)

    if result[:success]
      $logger.info("🎉 Deployment completed successfully!")
      [200, json_headers, [{ status: 'success', message: result[:message] }.to_json]]
    else
      $logger.error("💥 Deployment failed: #{result[:message]}")
      [500, json_headers, [{ status: 'error', message: result[:message] }.to_json]]
    end
  end

  def handle_health_check(env)
    [200, text_headers, ['OK']]
  end

  def handle_status_check(env)
    deployment_status = @deployment_handler.deployment_status
    status = {
      status: 'running',
      timestamp: Time.now.iso8601,
      uptime: Process.clock_gettime(Process::CLOCK_MONOTONIC),
      webhook_secret_configured: !@webhook_secret.include?('CHANGE_ME'),
      debounce_seconds: ENV.fetch('WEBHOOK_DEBOUNCE_SECONDS', '120').to_i,
      webhook_port: ENV.fetch('WEBHOOK_PORT', 9001).to_i,
      deployment: deployment_status
    }
    [200, json_headers, [status.to_json]]
  end

  def verify_signature(payload, signature)
    expected = 'sha256=' + OpenSSL::HMAC.hexdigest('sha256', @webhook_secret, payload)
    # Use secure comparison to prevent timing attacks
    signature.length == expected.length &&
      signature.bytes.zip(expected.bytes).all? { |a, b| a == b }
  end

  def cors_headers
    {
      'Access-Control-Allow-Origin' => '*',
      'Access-Control-Allow-Methods' => 'GET, POST, OPTIONS',
      'Access-Control-Allow-Headers' => 'Content-Type, Authorization, X-Hub-Signature-256'
    }
  end

  def json_headers
    { 'Content-Type' => 'application/json' }.merge(cors_headers)
  end

  def text_headers
    { 'Content-Type' => 'text/plain' }.merge(cors_headers)
  end
end

# Smart deployment handler with change analysis and debouncing
class DeploymentHandler
  def initialize
    @project_dir = '/home/kimonokittens/Projects/kimonokittens'
    @deployment_timer = nil
    @debounce_seconds = ENV.fetch('WEBHOOK_DEBOUNCE_SECONDS', '120').to_i
    @pending_event = nil
    @deployment_mutex = Mutex.new
  end

  def process_webhook(event_data)
    changes = analyze_changes(event_data['commits'] || [])

    unless changes[:any_changes]
      return {
        success: true,
        message: 'No deployment needed - only docs/config changes detected'
      }
    end

    $logger.info("📝 Change summary: Frontend=#{changes[:frontend]}, Backend=#{changes[:backend]}, Deployment=#{changes[:deployment]}")

    # Store the latest event data and changes for debounced deployment
    @deployment_mutex.synchronize do
      @pending_event = { event_data: event_data, changes: changes }

      # Cancel existing timer if running
      if @deployment_timer && @deployment_timer.alive?
        @deployment_timer.kill
        $logger.info("🔄 Cancelled previous deployment timer - new push detected")
      end

      # Start new deployment timer
      @deployment_timer = Thread.new do
        begin
          sleep(@debounce_seconds)
          @deployment_mutex.synchronize do
            if @pending_event
              $logger.info("⏰ Debounce period finished - starting deployment")
              perform_actual_deployment(@pending_event[:changes])
              @pending_event = nil
            end
          end
        rescue => e
          $logger.error("Deployment timer error: #{e.message}")
        end
      end

      commit_sha = event_data.dig('head_commit', 'id')&.slice(0, 7) || 'unknown'
      {
        success: true,
        message: "Deployment queued for commit #{commit_sha} (#{@debounce_seconds}s debounce)"
      }
    end
  end

  private

  def perform_actual_deployment(changes)
    deployment_success = true
    deployed_components = []

    # Deploy backend if needed
    if changes[:backend]
      if deploy_backend
        deployed_components << 'backend'
      else
        $logger.error("Backend deployment failed")
        return false
      end
    end

    # Deploy frontend if needed
    if changes[:frontend]
      if deploy_frontend
        deployed_components << 'frontend'
      else
        $logger.error("Frontend deployment failed")
        return false
      end
    end

    # Restart kiosk if frontend changed (to reload the page)
    if changes[:frontend] && deployment_success
      restart_kiosk
    end

    $logger.info("🎉 Deployment completed: #{deployed_components.join(', ')}")
    true
  end

  def deployment_status
    @deployment_mutex.synchronize do
      if @pending_event
        {
          pending: true,
          time_remaining: [@debounce_seconds - (Time.now - @deployment_timer.created_at).to_i, 0].max,
          commit_sha: @pending_event[:event_data].dig('head_commit', 'id')&.slice(0, 7)
        }
      else
        { pending: false }
      end
    end
  rescue
    { pending: false, error: 'Status unavailable' }
  end

  private

  def analyze_changes(commits)
    frontend_changed = false
    backend_changed = false
    deployment_changed = false

    commits.each do |commit|
      # Check modified files
      (commit['modified'] || []).each do |file|
        case file
        when /^dashboard\//
          frontend_changed = true
          $logger.info("Frontend change detected: #{file}")
        when /\.(rb|ru|gemspec|Gemfile)$/
          backend_changed = true
          $logger.info("Backend change detected: #{file}")
        when /^deployment\//
          deployment_changed = true
          $logger.info("Deployment config change detected: #{file}")
        end
      end

      # Check added files
      (commit['added'] || []).each do |file|
        case file
        when /^dashboard\//
          frontend_changed = true
          $logger.info("Frontend addition detected: #{file}")
        when /\.(rb|ru|gemspec|Gemfile)$/
          backend_changed = true
          $logger.info("Backend addition detected: #{file}")
        end
      end
    end

    {
      frontend: frontend_changed,
      backend: backend_changed,
      deployment: deployment_changed,
      any_changes: frontend_changed || backend_changed || deployment_changed
    }
  end

  def deploy_backend
    $logger.info("🔄 Starting backend deployment...")

    # Change to project directory
    Dir.chdir(@project_dir)

    # Pull latest changes
    unless system('git pull origin master')
      $logger.error("❌ Git pull failed")
      return false
    end
    $logger.info("✅ Git pull successful")

    # Install Ruby dependencies
    unless system('bundle install --deployment --quiet')
      $logger.error("❌ Bundle install failed")
      return false
    end
    $logger.info("✅ Bundle install successful")

    # Restart backend service
    unless system('sudo systemctl restart kimonokittens-dashboard')
      $logger.error("❌ Backend service restart failed")
      return false
    end
    $logger.info("✅ Backend service restarted")

    true
  end

  def deploy_frontend
    $logger.info("🔄 Starting frontend deployment...")

    frontend_dir = File.join(@project_dir, 'dashboard')

    # Change to frontend directory
    Dir.chdir(frontend_dir)

    # Install Node dependencies and build
    commands = [
      'npm ci --only=production',
      'npm run build'
    ]

    commands.each do |cmd|
      unless system(cmd)
        $logger.error("❌ #{cmd} failed")
        return false
      end
      $logger.info("✅ #{cmd} successful")
    end

    # Copy built files to nginx directory
    unless system('sudo rsync -av dist/ /var/www/kimonokittens/')
      $logger.error("❌ Frontend file deployment failed")
      return false
    end
    $logger.info("✅ Frontend files deployed")

    true
  end

  def restart_kiosk
    $logger.info("🔄 Restarting kiosk browser...")

    # Restart user service (modern approach)
    if system('sudo -u kimonokittens systemctl --user restart kimonokittens-kiosk')
      $logger.info("✅ Kiosk browser restarted")
      true
    else
      $logger.error("❌ Kiosk browser restart failed")
      false
    end
  end
end

# Create Rack application following dashboard pattern
app = Rack::Builder.new do
  # Webhook routes
  map "/webhook" do
    run WebhookHandler.new
  end

  map "/health" do
    run WebhookHandler.new
  end

  map "/status" do
    run WebhookHandler.new
  end

  # Catch-all
  run lambda { |env|
    [404, { 'Content-Type' => 'application/json' },
     [{ error: 'Not Found', available_endpoints: ['/webhook', '/health', '/status'] }.to_json]]
  }
end

# Configure Puma
port = ENV.fetch('WEBHOOK_PORT', 9001).to_i

# If this file is run directly, start the server manually for testing
if __FILE__ == $0
  puts "🚀 Smart webhook receiver starting on http://0.0.0.0:#{port}"
  puts "📊 Endpoints: /webhook, /health, /status"
  puts "🔒 Webhook secret configured: #{ENV['WEBHOOK_SECRET'] ? !ENV['WEBHOOK_SECRET'].include?('CHANGE_ME') : false}"

  require 'puma'
  Puma::Server.new(app).tap do |server|
    server.add_tcp_listener('0.0.0.0', port)
    server.run.join
  end
end
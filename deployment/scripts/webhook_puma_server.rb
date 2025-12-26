#!/usr/bin/env ruby
# Smart webhook server using Puma architecture (unified with dashboard)
require 'dotenv/load'
require 'puma'
require 'rack'
require 'json'
require 'openssl'
require 'logger'
require 'fileutils'
require 'time'

# Enable thread exception reporting (critical for debugging deployment thread failures)
Thread.report_on_exception = true
Thread.abort_on_exception = false  # Don't kill entire process, just report

# Disable IO buffering for immediate log visibility (critical for debugging)
$stdout.sync = true
$stderr.sync = true

# Configure logging
if ENV['RACK_ENV'] == 'production'
  log_dir = '/var/log/kimonokittens'
  FileUtils.mkdir_p(log_dir) unless Dir.exist?(log_dir)
  # Daily rotation, keep 14 days
  $logger = Logger.new(File.join(log_dir, 'webhook.log'), 'daily', 14)
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
      [404, json_headers, [{ error: 'Not Found', available_endpoints: ['/webhook', '/health', '/status'] }.to_json]]
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

    # Check event type
    event_type = env['HTTP_X_GITHUB_EVENT']

    # Handle ping events (GitHub webhook test)
    if event_type == 'ping'
      $logger.info("✅ Received GitHub webhook ping")
      return [200, json_headers, [{ status: 'pong', message: 'Webhook configured correctly' }.to_json]]
    end

    # Parse payload based on content type
    # GitHub sends either application/json or application/x-www-form-urlencoded
    content_type = env['CONTENT_TYPE'] || env['HTTP_CONTENT_TYPE'] || ''

    if content_type.include?('application/x-www-form-urlencoded')
      # Form-encoded: JSON is in 'payload' parameter
      require 'cgi'
      params = CGI.parse(payload)
      json_payload = params['payload']&.first

      unless json_payload
        $logger.error("❌ No 'payload' parameter in form data")
        return [400, json_headers, [{ error: 'Missing payload parameter' }.to_json]]
      end
    else
      # application/json: payload is raw JSON
      json_payload = payload
    end

    # Verify GitHub signature (use original payload for signature verification)
    signature = env['HTTP_X_HUB_SIGNATURE_256']
    if signature && !verify_signature(payload, signature)
      $logger.warn("❌ Invalid webhook signature from #{env['REMOTE_ADDR']}")
      return [401, json_headers, [{ error: 'Invalid signature' }.to_json]]
    end

    # Parse JSON payload
    begin
      event_data = JSON.parse(json_payload)
    rescue JSON::ParserError => e
      $logger.error("❌ Invalid JSON payload: #{e.message}")
      return [400, json_headers, [{ error: 'Invalid JSON' }.to_json]]
    end

    # Only process push events to master
    unless event_type == 'push' && event_data['ref'] == 'refs/heads/master'
      $logger.info("ℹ️ Ignoring #{event_type} event to #{event_data['ref']} (not push to master)")
      return [200, json_headers, [{ status: 'ignored', message: 'Not a push to master' }.to_json]]
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
    # Silent success - this endpoint is polled frequently, logging pollutes the log
    # Only log errors
    begin
      deployment_status = @deployment_handler.deployment_status
      status = {
        status: 'running',
        timestamp: Time.now.iso8601,
        uptime: Process.clock_gettime(Process::CLOCK_MONOTONIC),
        webhook_secret_configured: !@webhook_secret.include?('CHANGE_ME'),
        debounce_seconds: ENV.fetch('WEBHOOK_DEBOUNCE_SECONDS', '120').to_i,
        webhook_port: ENV.fetch('WEBHOOK_PORT', 49123).to_i,
        deployment: deployment_status
      }

      response_json = status.to_json

      [200, json_headers, [response_json]]
    rescue => e
      $logger.error("Status check failed: #{e.message}")
      $logger.error("Backtrace: #{e.backtrace.join("\n")}")
      [500, json_headers, [{ error: "Status check failed: #{e.message}" }.to_json]]
    end
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
    @deployment_start_time = nil
    @debounce_seconds = ENV.fetch('WEBHOOK_DEBOUNCE_SECONDS', '120').to_i
    @pending_event = nil
    @deployment_mutex = Mutex.new
  end

  def process_webhook(event_data)
    # ALWAYS pull latest code first (including data files like handbook/docs/household_todos.md)
    unless pull_latest_code
      return {
        success: false,
        message: 'Git pull failed - deployment aborted'
      }
    end

    # Analyze what changed to determine if deployment is needed
    changes = analyze_changes(event_data['commits'] || [])

    # If only data files changed (no code), git pull is enough
    unless changes[:frontend] || changes[:backend] || changes[:deployment] || changes[:config] || changes[:static_root]
      $logger.info("✅ Data files updated via git pull, no deployment needed")
      return {
        success: true,
        message: 'Data files updated (handbook/docs/household_todos.md, electricity_bills_history.txt, etc)'
      }
    end

    $logger.info("📝 Change summary: Frontend=#{changes[:frontend]}, Backend=#{changes[:backend]}, Deployment=#{changes[:deployment]}, Config=#{changes[:config]}, StaticRoot=#{changes[:static_root]}")

    # Store the latest event data and changes for debounced deployment
    @deployment_mutex.synchronize do
      # Accumulate changes from cancelled deployments (OR logic)
      # If previous push had frontend=true and new one has config=true, deploy BOTH
      if @pending_event
        changes = {
          frontend: changes[:frontend] || @pending_event[:changes][:frontend],
          backend: changes[:backend] || @pending_event[:changes][:backend],
          deployment: changes[:deployment] || @pending_event[:changes][:deployment],
          config: changes[:config] || @pending_event[:changes][:config],
          static_root: changes[:static_root] || @pending_event[:changes][:static_root]
        }
        $logger.info("🔄 Accumulated changes from cancelled deployment: Frontend=#{changes[:frontend]}, Backend=#{changes[:backend]}, Deployment=#{changes[:deployment]}, Config=#{changes[:config]}, StaticRoot=#{changes[:static_root]}")
      end

      @pending_event = { event_data: event_data, changes: changes }

      # Cancel existing timer if running
      if @deployment_timer && @deployment_timer.alive?
        @deployment_timer.kill
        $logger.info("🔄 Cancelled previous deployment timer - new push detected")
      end

      # Start new deployment timer
      @deployment_start_time = Time.now
      @deployment_timer = Thread.new do
        begin
          sleep(@debounce_seconds)
          @deployment_mutex.synchronize do
            if @pending_event
              $logger.info("⏰ Debounce period finished - starting deployment")
              perform_actual_deployment(@pending_event[:changes])
              @pending_event = nil
              @deployment_start_time = nil
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

  def deployment_status
    @deployment_mutex.synchronize do
      if @pending_event && @deployment_start_time
        elapsed = (Time.now - @deployment_start_time).to_i
        remaining = [@debounce_seconds - elapsed, 0].max
        {
          pending: true,
          time_remaining: remaining,
          debounce_seconds: @debounce_seconds,
          commit_sha: @pending_event[:event_data].dig('head_commit', 'id')&.slice(0, 7)
        }
      else
        { pending: false }
      end
    end
  rescue => e
    { pending: false, error: "Status unavailable: #{e.message}" }
  end

  private

  def perform_actual_deployment(changes)
    deployment_success = true
    deployed_components = []

    # Warn if deployment files changed (requires manual restart)
    if changes[:deployment]
      $logger.warn("⚠️  Webhook deployment files changed - MANUAL RESTART REQUIRED!")
      $logger.warn("⚠️  Run: sudo systemctl restart kimonokittens-webhook")
    end

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

    # Deploy static root if needed
    if changes[:static_root]
      if deploy_static_root
        deployed_components << 'static_root'
      else
        $logger.error("Static root deployment failed")
        return false
      end
    end

    # Restart kiosk if frontend or config changed (to reload the page and fetch new config)
    if (changes[:frontend] || changes[:config]) && deployment_success
      restart_kiosk
      if changes[:config]
        $logger.info("🔄 Kiosk restarted to load new sleep schedule config")
      end
    end

    $logger.info("🎉 Deployment completed: #{deployed_components.join(', ')}")
    true
  end

  private

  def pull_latest_code
    $logger.info("🔄 Pulling latest code from git...")

    # Change to project directory
    Dir.chdir(@project_dir)

    # Ensure git working tree is clean before pulling
    return false unless ensure_clean_git_state

    # Pull latest changes
    unless system('git pull origin master')
      $logger.error("❌ Git pull failed")
      return false
    end
    $logger.info("✅ Git pull successful - all files updated on disk")
    true
  end

  def analyze_changes(commits)
    frontend_changed = false
    backend_changed = false
    deployment_changed = false
    config_changed = false
    static_root_changed = false

    commits.each do |commit|
      # Check modified files
      (commit['modified'] || []).each do |file|
        case file
        when /^dashboard\//
          frontend_changed = true
          $logger.info("Frontend change detected: #{file}")
        when /^www\//
          static_root_changed = true
          $logger.info("Static root change detected: #{file}")
        when /\.(rb|ru|gemspec)$|^Gemfile$/
          backend_changed = true
          $logger.info("Backend change detected: #{file}")
        when /^deployment\//
          deployment_changed = true
          $logger.info("Deployment config change detected: #{file}")
        when /^config\/sleep_schedule\.json$/
          config_changed = true
          $logger.info("Sleep schedule config change detected: #{file}")
        end
      end

      # Check added files
      (commit['added'] || []).each do |file|
        case file
        when /^dashboard\//
          frontend_changed = true
          $logger.info("Frontend addition detected: #{file}")
        when /^www\//
          static_root_changed = true
          $logger.info("Static root addition detected: #{file}")
        when /\.(rb|ru|gemspec)$|^Gemfile$/
          backend_changed = true
          $logger.info("Backend addition detected: #{file}")
        when /^config\/sleep_schedule\.json$/
          config_changed = true
          $logger.info("Sleep schedule config added: #{file}")
        end
      end
    end

    {
      frontend: frontend_changed,
      backend: backend_changed,
      deployment: deployment_changed,
      config: config_changed,
      static_root: static_root_changed,
      any_changes: frontend_changed || backend_changed || deployment_changed || config_changed || static_root_changed
    }
  end

  def deploy_backend
    $logger.info("🔄 Starting backend deployment...")

    # Change to project directory
    Dir.chdir(@project_dir)

    # Note: Git pull already done in pull_latest_code() before deployment

    # Install Ruby dependencies (industry standard Capistrano/Heroku approach)
    # CRITICAL: Gemfile.lock MUST be committed to version control
    # Development workflow: change Gemfile → bundle install → commit BOTH files
    # If deployment fails here, fix in development and commit updated Gemfile.lock
    output = `bundle install --deployment --without development test 2>&1`
    unless $?.success?
      $logger.error("❌ Bundle install failed - Gemfile.lock may not match Gemfile")
      $logger.error("Error output: #{output.lines.last(15).join}")
      $logger.error("Fix: Run 'bundle install' in development and commit updated Gemfile.lock")
      return false
    end
    $logger.info("✅ Bundle install successful")

    # Reload backend service (graceful restart via USR1 signal to Puma)
    # NOTE: If webhook code itself changed (deployment/*.rb), this runs OLD code!
    # Webhook CANNOT self-restart - requires manual: sudo systemctl restart kimonokittens-webhook
    # Find PID from systemd service
    pid_output = `systemctl show kimonokittens-dashboard --property=MainPID --value`.strip
    if pid_output.empty? || pid_output == "0"
      $logger.error("❌ Could not find dashboard service PID")
      return false
    end

    pid = pid_output.to_i
    unless system("kill -USR1 #{pid}")
      $logger.error("❌ Backend service reload failed")
      return false
    end
    $logger.info("✅ Backend service reloaded (PID #{pid})")

    # Run post-deployment hooks
    run_post_deploy_hooks

    true
  end

  def run_post_deploy_hooks
    $logger.info("🔄 Running post-deployment hooks...")

    # Create Adam's deposit agreement (idempotent - only creates once)
    deposit_script = File.join(@project_dir, 'bin/create_adam_deposit_agreement')
    if File.exist?(deposit_script)
      Dir.chdir(@project_dir)
      output = `bundle exec #{deposit_script} 2>&1`
      if $?.success?
        # Only log summary (the script handles detailed output)
        if output.include?('Skipping creation')
          $logger.info("ℹ️  Deposit agreement already exists (idempotent skip)")
        elsif output.include?('created successfully')
          $logger.info("✨ Deposit agreement created and sent for signing!")
        end
      else
        $logger.error("⚠️  Deposit agreement script failed (non-critical):")
        $logger.error(output.lines.last(5).join)
        # Don't fail deployment - this is a non-critical hook
      end
    end
  end

  def deploy_frontend
    $logger.info("🔄 Starting frontend deployment...")

    # Change to project directory
    Dir.chdir(@project_dir)

    # Note: Git pull already done in pull_latest_code() before deployment

    # Install workspace dependencies from root (monorepo setup)
    # CRITICAL: Unset NODE_ENV during install to ensure devDependencies are installed
    # NODE_ENV=production in .env would otherwise silently skip devDeps (including vite)
    # devDependencies are REQUIRED for the build process (vite, rollup, etc.)
    # MUST use Ruby hash syntax to actually unset env var (system('NODE_ENV=') doesn't work!)
    unless system({'NODE_ENV' => nil}, 'npm ci --legacy-peer-deps')
      $logger.error("❌ npm ci (workspace root) failed")
      return false
    end
    $logger.info("✅ npm ci (workspace root) successful")

    frontend_dir = File.join(@project_dir, 'dashboard')
    Dir.chdir(frontend_dir)

    # Build frontend
    commands = [
      'npx vite build'
    ]

    commands.each do |cmd|
      unless system(cmd)
        $logger.error("❌ #{cmd} failed")
        return false
      end
      $logger.info("✅ #{cmd} successful")
    end

    # Copy built files to nginx directory (no sudo needed, kimonokittens owns the directory)
    unless system('rsync -av dist/ /var/www/kimonokittens/dashboard/')
      $logger.error("❌ Frontend file deployment failed")
      return false
    end
    $logger.info("✅ Frontend files deployed")

    true
  end

  def deploy_static_root
    $logger.info("🔄 Starting static root deployment...")

    # Change to project directory
    Dir.chdir(@project_dir)

    # Note: Git pull already done in pull_latest_code() before deployment

    # Copy www/ files to nginx static root (no sudo needed, kimonokittens owns the directory)
    # Trailing slash on source means "copy contents of www/" not "copy www/ itself"
    # --exclude dashboard to avoid overwriting the dashboard directory
    unless system('rsync -av --exclude dashboard www/ /var/www/kimonokittens/')
      $logger.error("❌ Static root file deployment failed")
      return false
    end
    $logger.info("✅ Static root files deployed (favicon.ico, index.html, etc.)")

    true
  end

  def ensure_clean_git_state
    # Check if working tree is clean
    git_status = `git status --porcelain 2>&1`.strip

    if git_status.empty?
      $logger.info("✅ Git working tree is clean")
      return true
    end

    # Categorize changes: source code vs build artifacts
    source_files = []
    build_artifacts = []

    git_status.lines.each do |line|
      # Parse git status format: "XY filename"
      file = line.strip.split(/\s+/, 2)[1]
      next unless file

      if file =~ /\.(rb|tsx?|jsx?|vue|css|html|md|yml|yaml)$/
        source_files << file
      elsif file =~ /(package.*\.json|node_modules|dist|\.lock|Gemfile\.lock)/
        build_artifacts << file
      else
        source_files << file  # Unknown files = treat as source (safe)
      end
    end

    # ABORT if source code modified (requires manual intervention)
    unless source_files.empty?
      $logger.error("❌ SOURCE CODE MODIFIED - deployment aborted for safety!")
      $logger.error("Production checkout has uncommitted changes to:")
      source_files.each { |f| $logger.error("  #{f}") }
      $logger.error("")
      $logger.error("Resolution options:")
      $logger.error("  1. Commit changes: git add . && git commit && git push")
      $logger.error("  2. Discard changes: git reset --hard origin/master")
      $logger.error("  3. Investigate manually before deciding")
      return false
    end

    # Auto-reset only build artifacts (safe, common from npm/bundle operations)
    $logger.warn("⚠️  Build artifacts modified - auto-resetting (safe)")
    build_artifacts.each { |f| $logger.warn("  #{f}") }

    unless system('git fetch origin master && git reset --hard origin/master')
      $logger.error("❌ Git reset failed - deployment aborted")
      return false
    end

    $logger.info("✅ Git working tree reset to origin/master")
    true
  end

  def restart_kiosk
    $logger.info("🔄 Triggering frontend reload...")

    # Trigger reload via dashboard API (broadcasts WebSocket message to all clients)
    require 'net/http'
    require 'uri'

    uri = URI('http://localhost:3001/api/reload')
    begin
      response = Net::HTTP.post(uri, '', {'Content-Type' => 'application/json'})

      if response.is_a?(Net::HTTPSuccess)
        $logger.info("✅ Frontend reload triggered")
        true
      else
        $logger.error("❌ Frontend reload failed: #{response.code}")
        false
      end
    rescue => e
      $logger.error("❌ Frontend reload error: #{e.message}")
      false
    end
  end
end

# Create Rack application with single handler for all routes
app = Rack::Builder.new do
  # Single handler handles all routing internally
  run WebhookHandler.new
end

# Configure Puma
port = ENV.fetch('WEBHOOK_PORT', 49123).to_i

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
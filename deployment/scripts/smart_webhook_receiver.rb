#!/usr/bin/env ruby
# Smart webhook receiver that only deploys what changed
require 'dotenv/load'
require 'sinatra'
require 'json'
require 'openssl'
require 'logger'

# Configure logging
logger = Logger.new(STDOUT)
logger.level = Logger::INFO

# Webhook secret from environment
WEBHOOK_SECRET = ENV['WEBHOOK_SECRET'] || 'CHANGE_ME_TO_SECURE_SECRET'

def verify_signature(payload, signature)
  expected = 'sha256=' + OpenSSL::HMAC.hexdigest('sha256', WEBHOOK_SECRET, payload)
  Rack::Utils.secure_compare(expected, signature)
end

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
        logger.info("Frontend change detected: #{file}")
      when /\.(rb|ru|gemspec|Gemfile)$/
        backend_changed = true
        logger.info("Backend change detected: #{file}")
      when /^deployment\//
        deployment_changed = true
        logger.info("Deployment config change detected: #{file}")
      end
    end

    # Check added files
    (commit['added'] || []).each do |file|
      case file
      when /^dashboard\//
        frontend_changed = true
        logger.info("Frontend addition detected: #{file}")
      when /\.(rb|ru|gemspec|Gemfile)$/
        backend_changed = true
        logger.info("Backend addition detected: #{file}")
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
  logger.info("🔄 Starting backend deployment...")

  # Change to project directory
  Dir.chdir('/home/kimonokittens/Projects/kimonokittens')

  # Pull latest changes
  if system('git pull origin master')
    logger.info("✅ Git pull successful")
  else
    logger.error("❌ Git pull failed")
    return false
  end

  # Install Ruby dependencies
  if system('bundle install --deployment --quiet')
    logger.info("✅ Bundle install successful")
  else
    logger.error("❌ Bundle install failed")
    return false
  end

  # Restart backend service
  if system('sudo systemctl restart kimonokittens-dashboard')
    logger.info("✅ Backend service restarted")
    return true
  else
    logger.error("❌ Backend service restart failed")
    return false
  end
end

def deploy_frontend
  logger.info("🔄 Starting frontend deployment...")

  frontend_dir = '/home/kimonokittens/Projects/kimonokittens/dashboard'

  # Change to frontend directory
  Dir.chdir(frontend_dir)

  # Install Node dependencies and build
  commands = [
    'npm ci --only=production',
    'npm run build'
  ]

  commands.each do |cmd|
    if system(cmd)
      logger.info("✅ #{cmd} successful")
    else
      logger.error("❌ #{cmd} failed")
      return false
    end
  end

  # Copy built files to nginx directory
  if system('sudo rsync -av dist/ /var/www/kimonokittens/')
    logger.info("✅ Frontend files deployed")
    return true
  else
    logger.error("❌ Frontend file deployment failed")
    return false
  end
end

def restart_kiosk
  logger.info("🔄 Restarting kiosk browser...")

  # Restart user service (new approach)
  if system('sudo -u kimonokittens systemctl --user restart kimonokittens-kiosk')
    logger.info("✅ Kiosk browser restarted")
    return true
  else
    logger.error("❌ Kiosk browser restart failed")
    return false
  end
end

# Main webhook endpoint
post '/webhook' do
  # Get raw payload
  payload = request.body.read
  signature = request.env['HTTP_X_HUB_SIGNATURE_256']

  # Verify signature if provided
  if signature && !verify_signature(payload, signature)
    logger.warn("❌ Invalid webhook signature")
    halt 401, 'Invalid signature'
  end

  # Parse JSON payload
  begin
    event_data = JSON.parse(payload)
  rescue JSON::ParserError
    logger.error("❌ Invalid JSON payload")
    halt 400, 'Invalid JSON'
  end

  # Only process pushes to master
  unless event_data['ref'] == 'refs/heads/master'
    logger.info("ℹ️ Ignoring push to #{event_data['ref']} (not master)")
    return 'OK - not master branch'
  end

  # Analyze what changed
  changes = analyze_changes(event_data['commits'] || [])

  if changes[:any_changes]
    logger.info("📝 Change summary: Frontend=#{changes[:frontend]}, Backend=#{changes[:backend]}, Deployment=#{changes[:deployment]}")

    deployment_success = true

    # Deploy backend if needed
    if changes[:backend]
      deployment_success &= deploy_backend
    end

    # Deploy frontend if needed
    if changes[:frontend]
      deployment_success &= deploy_frontend
    end

    # Restart kiosk if frontend changed (to reload the page)
    if changes[:frontend] && deployment_success
      restart_kiosk
    end

    if deployment_success
      logger.info("🎉 Deployment completed successfully!")
      'Deployment successful'
    else
      logger.error("💥 Deployment failed!")
      status 500
      'Deployment failed'
    end
  else
    logger.info("ℹ️ No deployment needed - only docs/config changes detected")
    'OK - no deployment needed'
  end
end

# Health check endpoint
get '/health' do
  'OK'
end

# Start server
if __FILE__ == $0
  logger.info("🚀 Smart webhook receiver starting on port #{ENV['PORT'] || 9001}")
  set :port, ENV['PORT'] || 9001
  set :bind, '0.0.0.0'
end
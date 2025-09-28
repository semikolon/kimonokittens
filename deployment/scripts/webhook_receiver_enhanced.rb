#!/usr/bin/env ruby

require 'sinatra'
require 'json'
require 'openssl'
require 'logger'
require 'fileutils'

# Configure logging
logger = Logger.new('/var/log/kimonokittens/webhook.log')
logger.level = Logger::INFO

configure do
  set :port, ENV['PORT'] || 9001
  set :bind, '0.0.0.0'
  set :environment, :production
end

# Health check endpoint
get '/health' do
  content_type :json
  { status: 'ok', timestamp: Time.now.iso8601 }.to_json
end

# GitHub webhook endpoint
post '/webhook' do
  payload = request.body.read
  signature = request.env['HTTP_X_HUB_SIGNATURE_256']
  event_type = request.env['HTTP_X_GITHUB_EVENT']

  # Verify GitHub signature
  expected = 'sha256=' + OpenSSL::HMAC.hexdigest(
    OpenSSL::Digest.new('sha256'),
    ENV['WEBHOOK_SECRET'] || 'default-secret',
    payload
  )

  unless Rack::Utils.secure_compare(signature.to_s, expected)
    logger.warn "Invalid webhook signature from #{request.ip}"
    halt 403, { error: 'Invalid signature' }.to_json
  end

  begin
    event_data = JSON.parse(payload)

    # Log all events for debugging
    logger.info "Received #{event_type} event from GitHub"

    case event_type
    when 'push'
      handle_push_event(event_data, logger)

    when 'pull_request'
      handle_pull_request_event(event_data, logger)

    when 'release'
      handle_release_event(event_data, logger)

    when 'workflow_run'
      handle_workflow_event(event_data, logger)

    when 'deployment'
      handle_deployment_event(event_data, logger)

    when 'ping'
      logger.info "Ping received - webhook configured successfully"
      { status: 'pong', message: 'Webhook configured successfully' }.to_json

    else
      logger.info "Ignoring #{event_type} event"
      { status: 'ignored', event: event_type }.to_json
    end

  rescue JSON::ParserError => e
    logger.error "Invalid JSON payload: #{e.message}"
    halt 400, { error: 'Invalid JSON' }.to_json
  rescue => e
    logger.error "Webhook error: #{e.message}"
    logger.error e.backtrace.join("\n")
    halt 500, { error: 'Internal server error' }.to_json
  end
end

def handle_push_event(data, logger)
  ref = data['ref']
  branch = ref.sub('refs/heads/', '') if ref

  # Deploy only on push to master/main
  if branch == 'master' || branch == 'main'
    commit = data['after']
    author = data['pusher']['name'] rescue 'unknown'

    logger.info "Deploying from push to #{branch} by #{author} (#{commit})"

    # Check if it's a force push
    if data['forced']
      logger.warn "Force push detected - running full deployment"
      deploy_with_options(logger, full: true)
    else
      deploy_with_options(logger, full: false)
    end

    { status: 'deploying', branch: branch, commit: commit }.to_json
  else
    logger.info "Ignoring push to branch #{branch}"
    { status: 'ignored', reason: 'not master branch', branch: branch }.to_json
  end
end

def handle_pull_request_event(data, logger)
  action = data['action']
  pr_number = data['number']

  case action
  when 'closed'
    if data['pull_request']['merged']
      base_branch = data['pull_request']['base']['ref']
      if base_branch == 'master' || base_branch == 'main'
        logger.info "PR ##{pr_number} merged to #{base_branch} - deploying"
        deploy_with_options(logger, full: false)
        { status: 'deploying', reason: 'PR merged', pr: pr_number }.to_json
      else
        { status: 'ignored', reason: 'PR not merged to master' }.to_json
      end
    else
      { status: 'ignored', reason: 'PR closed without merge' }.to_json
    end
  else
    { status: 'ignored', reason: "PR action #{action} not relevant" }.to_json
  end
end

def handle_release_event(data, logger)
  action = data['action']

  if action == 'published'
    release_tag = data['release']['tag_name']
    logger.info "New release published: #{release_tag} - deploying"

    # For releases, do a full deployment with backup
    deploy_with_options(logger, full: true, tag: release_tag)

    { status: 'deploying', release: release_tag }.to_json
  else
    { status: 'ignored', reason: "Release action #{action} not relevant" }.to_json
  end
end

def handle_workflow_event(data, logger)
  # Deploy only if workflow completed successfully
  if data['workflow_run']['conclusion'] == 'success'
    workflow_name = data['workflow_run']['name']
    branch = data['workflow_run']['head_branch']

    # Only deploy if it's a deployment workflow on master
    if workflow_name.downcase.include?('deploy') && (branch == 'master' || branch == 'main')
      logger.info "Deployment workflow '#{workflow_name}' succeeded - deploying"
      deploy_with_options(logger, full: false)
      { status: 'deploying', workflow: workflow_name }.to_json
    else
      { status: 'ignored', reason: 'Not a deployment workflow' }.to_json
    end
  else
    { status: 'ignored', reason: 'Workflow did not succeed' }.to_json
  end
end

def handle_deployment_event(data, logger)
  # GitHub deployment API event
  environment = data['deployment']['environment']

  if environment == 'production'
    logger.info "Production deployment requested - deploying"
    deploy_with_options(logger, full: true)
    { status: 'deploying', environment: environment }.to_json
  else
    { status: 'ignored', reason: "Non-production environment: #{environment}" }.to_json
  end
end

def deploy_with_options(logger, options = {})
  script_path = '/home/kimonokittens/Projects/kimonokittens/deployment/scripts/deploy.sh'

  # Build command with options
  cmd = script_path
  cmd += ' --full' if options[:full]
  cmd += " --tag #{options[:tag]}" if options[:tag]

  # Create a status file for monitoring
  File.write('/tmp/kimonokittens-deploy-status', 'running')

  # Trigger deploy in background
  pid = spawn(cmd,
              out: '/var/log/kimonokittens/deploy.log',
              err: '/var/log/kimonokittens/deploy.log')

  # Monitor process in background
  Thread.new do
    Process.wait(pid)
    status = $?.success? ? 'success' : 'failed'
    File.write('/tmp/kimonokittens-deploy-status', status)
    logger.info "Deployment completed with status: #{status}"

    # Send notification if configured
    notify_deployment_status(status) if ENV['SLACK_WEBHOOK_URL']
  end

  Process.detach(pid)
end

def notify_deployment_status(status)
  # Could send to Slack, Discord, email, etc.
  # Example for Slack:
  require 'net/http'
  require 'uri'

  if ENV['SLACK_WEBHOOK_URL']
    uri = URI.parse(ENV['SLACK_WEBHOOK_URL'])
    payload = {
      text: "Deployment #{status} on Kimonokittens Dashboard",
      color: status == 'success' ? 'good' : 'danger'
    }

    Net::HTTP.post(uri, payload.to_json, 'Content-Type' => 'application/json')
  end
rescue => e
  logger.error "Failed to send notification: #{e.message}"
end

# Status endpoint to check deployment progress
get '/deploy/status' do
  content_type :json

  if File.exist?('/tmp/kimonokittens-deploy-status')
    status = File.read('/tmp/kimonokittens-deploy-status').strip
    { status: status, timestamp: File.mtime('/tmp/kimonokittens-deploy-status').iso8601 }.to_json
  else
    { status: 'idle', message: 'No deployment in progress' }.to_json
  end
end
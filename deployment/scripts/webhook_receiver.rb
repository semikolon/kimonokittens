#!/usr/bin/env ruby

require 'sinatra'
require 'json'
require 'openssl'
require 'logger'

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

    # Only deploy on push to master
    if event_data['ref'] == 'refs/heads/master'
      logger.info "Deploying from commit #{event_data['after']}"

      # Trigger deploy in background
      pid = spawn('/home/kimonokittens/Projects/kimonokittens/deployment/scripts/deploy.sh',
                  out: '/var/log/kimonokittens/deploy.log',
                  err: '/var/log/kimonokittens/deploy.log')
      Process.detach(pid)

      { status: 'deploying', commit: event_data['after'] }.to_json
    else
      logger.info "Ignoring push to #{event_data['ref']}"
      { status: 'ignored', ref: event_data['ref'] }.to_json
    end

  rescue JSON::ParserError => e
    logger.error "Invalid JSON payload: #{e.message}"
    halt 400, { error: 'Invalid JSON' }.to_json
  rescue => e
    logger.error "Webhook error: #{e.message}"
    halt 500, { error: 'Internal server error' }.to_json
  end
end
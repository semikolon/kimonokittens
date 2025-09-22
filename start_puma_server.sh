#!/bin/bash

# Kill any existing Ruby server processes
echo "Stopping any existing server processes..."
pkill -f ruby || true
sleep 2

# Ensure we're in the right directory
cd "$(dirname "$0")"

# Set environment variables
export ENABLE_BROADCASTER=1

# Load RVM or rbenv if available
[[ -s "$HOME/.rvm/scripts/rvm" ]] && source "$HOME/.rvm/scripts/rvm"
[[ -s "$HOME/.rbenv/bin/rbenv" ]] && eval "$($HOME/.rbenv/bin/rbenv init -)"

echo "Starting Puma server..."
echo "Dashboard will be available at: http://localhost:3001"
echo "Press Ctrl+C to stop the server"
echo ""

# Start the Puma server
ruby puma_server.rb
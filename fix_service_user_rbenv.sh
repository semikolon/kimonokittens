#!/bin/bash
# Immediate fix script for kimonokittens service user rbenv setup
# Run with: sudo bash fix_service_user_rbenv.sh

set -e  # Exit on error

echo "=== Setting up rbenv for kimonokittens service user ==="
echo

SERVICE_USER="kimonokittens"
PROJECT_DIR="/home/$SERVICE_USER/Projects/kimonokittens"

# Step 1: Create .profile with rbenv initialization
echo "Creating .profile for $SERVICE_USER..."
sudo -u "$SERVICE_USER" tee "/home/$SERVICE_USER/.profile" > /dev/null << 'EOF'
# Basic shell configuration for service user
# This file is sourced by login shells (including systemd with bash -l)

# Initialize rbenv
export PATH="$HOME/.rbenv/bin:$PATH"
eval "$(rbenv init -)"

# Useful aliases (safe to include)
alias python=python3
alias ll='ls -alF'
alias la='ls -A'
alias l='ls -CF'

# Set default editor
export EDITOR=nano
EOF

# Step 2: Also create .bashrc for interactive sessions
echo "Creating .bashrc for $SERVICE_USER..."
sudo -u "$SERVICE_USER" tee "/home/$SERVICE_USER/.bashrc" > /dev/null << 'EOF'
# If not running interactively, don't do anything
case $- in
    *i*) ;;
      *) return;;
esac

# Source .profile to get rbenv
if [ -f ~/.profile ]; then
    . ~/.profile
fi

# History settings
HISTCONTROL=ignoreboth
HISTSIZE=1000
HISTFILESIZE=2000

# Enable color support
if [ -x /usr/bin/dircolors ]; then
    test -r ~/.dircolors && eval "$(dircolors -b ~/.dircolors)" || eval "$(dircolors -b)"
    alias ls='ls --color=auto'
    alias grep='grep --color=auto'
fi
EOF

# Step 3: Set proper permissions
echo "Setting file permissions..."
chmod 600 "/home/$SERVICE_USER/.profile"
chmod 600 "/home/$SERVICE_USER/.bashrc"
chown "$SERVICE_USER:$SERVICE_USER" "/home/$SERVICE_USER/.profile"
chown "$SERVICE_USER:$SERVICE_USER" "/home/$SERVICE_USER/.bashrc"

# Step 4: Verify rbenv works
echo
echo "=== Verifying rbenv installation ==="
if sudo -u "$SERVICE_USER" bash -l -c 'rbenv version'; then
    echo "✅ rbenv is working!"
else
    echo "❌ rbenv not found - may need installation"
fi

# Step 5: Check Ruby version
echo
echo "=== Checking Ruby version ==="
if sudo -u "$SERVICE_USER" bash -l -c 'ruby --version'; then
    echo "✅ Ruby is accessible!"
else
    echo "❌ Ruby not found - may need installation"
fi

# Step 6: Install bundler and project dependencies
echo
echo "=== Installing Ruby dependencies ==="
cd "$PROJECT_DIR"

# Install bundler if not present
echo "Installing bundler gem..."
sudo -u "$SERVICE_USER" bash -l -c "gem install bundler" || echo "bundler may already be installed"

# Run bundle install
echo "Running bundle install..."
if sudo -u "$SERVICE_USER" bash -l -c "cd $PROJECT_DIR && bundle install --without development test"; then
    echo "✅ Bundle install completed!"
else
    echo "❌ Bundle install failed - check Gemfile and network connection"
    exit 1
fi

# Step 7: Verify key gems are installed
echo
echo "=== Verifying gem installation ==="
if sudo -u "$SERVICE_USER" bash -l -c "cd $PROJECT_DIR && bundle show faraday"; then
    echo "✅ Faraday gem found!"
else
    echo "❌ Faraday gem not found"
fi

echo
echo "=== Setup complete! ==="
echo "Next steps:"
echo "1. Restart the systemd service: sudo systemctl restart kimonokittens-dashboard"
echo "2. Check service status: sudo systemctl status kimonokittens-dashboard"
echo "3. View logs if needed: sudo journalctl -u kimonokittens-dashboard -f"
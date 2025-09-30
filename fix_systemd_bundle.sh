#!/bin/bash
# Quick fix to update systemd service to use bundle exec

echo "Fixing systemd service to use bundle exec..."

# Update the service file
sudo sed -i 's/&& ruby puma_server.rb/&& bundle exec ruby puma_server.rb/' /etc/systemd/system/kimonokittens-dashboard.service

echo "Reloading systemd daemon..."
sudo systemctl daemon-reload

echo "Restarting service..."
sudo systemctl restart kimonokittens-dashboard

echo "Checking status..."
sleep 2
sudo systemctl status kimonokittens-dashboard

echo ""
echo "If the service is still failing, check logs with:"
echo "  sudo journalctl -u kimonokittens-dashboard -f"
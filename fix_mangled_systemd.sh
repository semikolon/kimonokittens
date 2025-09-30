#!/bin/bash
# Fix the mangled ExecStart line in systemd service

echo "Fixing mangled systemd service ExecStart line..."

# Create a clean service file
sudo tee /etc/systemd/system/kimonokittens-dashboard.service > /dev/null << 'EOF'
[Unit]
Description=Kimonokittens Dashboard Backend
After=network.target postgresql.service
Requires=network.target
Wants=postgresql.service

[Service]
Type=simple
User=kimonokittens
Group=kimonokittens
WorkingDirectory=/home/kimonokittens/Projects/kimonokittens
Environment="PATH=/home/kimonokittens/.rbenv/bin:/home/kimonokittens/.rbenv/shims:/usr/local/bin:/usr/bin:/bin"
Environment="PORT=3001"
Environment="ENABLE_BROADCASTER=1"
Environment="NODE_ENV=production"
Environment="API_BASE_URL=http://localhost:3001"
EnvironmentFile=-/home/kimonokittens/.env
ExecStart=/bin/bash -c 'eval "$(/home/kimonokittens/.rbenv/bin/rbenv init - bash)" && bundle exec ruby puma_server.rb'
ExecReload=/bin/kill -USR1 $MAINPID
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

# Security hardening (defense in depth with least privilege)
NoNewPrivileges=yes
PrivateTmp=yes
PrivateDevices=yes
ProtectSystem=strict
ProtectHome=read-only
ProtectControlGroups=yes
ProtectKernelModules=yes
ProtectKernelTunables=yes
ReadWritePaths=/home/kimonokittens/Projects/kimonokittens /var/log/kimonokittens /home/kimonokittens/backups /var/www/kimonokittens /tmp /home/kimonokittens/.rbenv

[Install]
WantedBy=multi-user.target
EOF

echo "Reloading systemd daemon..."
sudo systemctl daemon-reload

echo "Stopping service..."
sudo systemctl stop kimonokittens-dashboard

echo "Starting service..."
sudo systemctl start kimonokittens-dashboard

echo "Checking status..."
sleep 3
sudo systemctl status kimonokittens-dashboard --no-pager

echo ""
echo "Service should now be running with proper bundle exec!"
echo "Check logs if needed: sudo journalctl -u kimonokittens-dashboard -f"
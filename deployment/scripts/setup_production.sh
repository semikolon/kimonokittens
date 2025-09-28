#!/bin/bash
# Production Setup Script for Dell Optiplex Kiosk (SINGLE USER VERSION)
# Simplified approach using only one service user for both backend and kiosk

set -e

echo "=== Kimonokittens Production Setup Script (single user version) ==="
echo "This script will set up the Dell Optiplex as a production kiosk server"
echo "Using simplified single-user architecture with rbenv Ruby"
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then
   echo "Please run this script with sudo"
   exit 1
fi

# Get the real user (in case of sudo)
REAL_USER=${SUDO_USER:-$USER}
REAL_HOME=$(eval echo ~$REAL_USER)

echo "Setting up for user: $REAL_USER"
echo "Home directory: $REAL_HOME"

# Step 1: Install required packages (excluding Ruby since we have rbenv)
echo "Step 1: Installing required packages..."
apt update
apt install -y \
  postgresql postgresql-contrib \
  nginx \
  build-essential \
  libpq-dev \
  chromium-browser \
  lightdm \
  xorg \
  xfce4 \
  rsync

echo "✅ Packages installed"

# Step 2: Create single service user (handles both backend and kiosk)
echo "Step 2: Creating service user..."
if ! id -u kimonokittens > /dev/null 2>&1; then
    useradd -m -d /home/kimonokittens -s /bin/bash kimonokittens
    usermod -a -G video kimonokittens  # Add video group for display access
    echo "Created user: kimonokittens (backend + kiosk)"
else
    echo "User kimonokittens already exists"
fi

# Step 3: Setup PostgreSQL database
echo "Step 3: Setting up PostgreSQL database..."
sudo -u postgres psql -c "SELECT 1 FROM pg_user WHERE usename = 'kimonokittens'" | grep -q 1 || {
    echo "Creating database user..."
    echo "Enter a password for the kimonokittens database user:"
    read -s DB_PASSWORD
    sudo -u postgres psql -c "CREATE USER kimonokittens WITH PASSWORD '$DB_PASSWORD';"
    sudo -u postgres createdb kimonokittens_production -O kimonokittens
    echo "Database created successfully"
}

# Step 4: Create directory structure
echo "Step 4: Creating directory structure..."
mkdir -p /var/www/kimonokittens/dashboard
mkdir -p /var/log/kimonokittens
mkdir -p /home/kimonokittens/Projects
mkdir -p /home/kimonokittens/backups

# Set permissions
chown -R kimonokittens:kimonokittens /home/kimonokittens
chown -R www-data:www-data /var/www/kimonokittens
chown kimonokittens:adm /var/log/kimonokittens
chmod 755 /var/log/kimonokittens

echo "✅ Directory structure created"

# Step 5: Copy project to production location
echo "Step 5: Setting up repository..."
if [ -d "/home/kimonokittens/Projects/kimonokittens" ]; then
    echo "Repository already exists, updating..."
    cd /home/kimonokittens/Projects/kimonokittens
    sudo -u kimonokittens git pull origin master || echo "Git pull failed, continuing..."
else
    echo "Copying repository..."
    cp -r "$REAL_HOME/Projects/kimonokittens" /home/kimonokittens/Projects/
fi
chown -R kimonokittens:kimonokittens /home/kimonokittens/Projects/kimonokittens

# Step 6: Create environment file
echo "Step 6: Creating environment configuration..."
if [ ! -f /home/kimonokittens/.env ]; then
    if [ -z "$DB_PASSWORD" ]; then
        echo "Enter the database password you set earlier:"
        read -s DB_PASSWORD
    fi
    cat > /home/kimonokittens/.env <<EOF
DATABASE_URL=postgresql://kimonokittens:${DB_PASSWORD}@localhost/kimonokittens_production
NODE_ENV=production
PORT=3001
ENABLE_BROADCASTER=1
API_BASE_URL=http://localhost:3001
EOF
    chown kimonokittens:kimonokittens /home/kimonokittens/.env
    chmod 600 /home/kimonokittens/.env
    echo "Environment file created"
fi

# Step 7: Setup rbenv for kimonokittens user
echo "Step 7: Setting up rbenv for service user..."
if [ ! -d /home/kimonokittens/.rbenv ]; then
    echo "Copying rbenv installation to kimonokittens user..."
    cp -r "$REAL_HOME/.rbenv" /home/kimonokittens/
    chown -R kimonokittens:kimonokittens /home/kimonokittens/.rbenv
fi

# Install Ruby dependencies as kimonokittens user
echo "Installing Ruby dependencies..."
sudo -u kimonokittens bash -c "
    export PATH=\"/home/kimonokittens/.rbenv/bin:\$PATH\"
    eval \"\$(rbenv init -)\"
    cd /home/kimonokittens/Projects/kimonokittens
    rbenv local 3.3.8 || rbenv local 3.3.0
    gem install bundler puma sinatra dotenv pg
    bundle install --deployment --without development test
"

echo "✅ Ruby environment configured"

# Step 8: Build and deploy frontend
echo "Step 8: Building and deploying frontend..."
cd /home/kimonokittens/Projects/kimonokittens/dashboard
sudo -u kimonokittens npm install
sudo -u kimonokittens npm run build || sudo -u kimonokittens npx vite build

# Deploy frontend
cp -r dist/* /var/www/kimonokittens/dashboard/
chown -R www-data:www-data /var/www/kimonokittens

echo "✅ Frontend deployed"

# Step 9: Run database migrations
echo "Step 9: Running database migrations..."
cd /home/kimonokittens/Projects/kimonokittens
sudo -u kimonokittens npx prisma migrate deploy
sudo -u kimonokittens npx prisma generate

# Import production data
echo "Importing production data..."
sudo -u kimonokittens bash -c "
    export PATH=\"/home/kimonokittens/.rbenv/bin:\$PATH\"
    eval \"\$(rbenv init -)\"
    cd /home/kimonokittens/Projects/kimonokittens
    ruby deployment/production_migration.rb
"

echo "✅ Database configured and data imported"

# Step 10: Install systemd services (simplified for single user)
echo "Step 10: Installing systemd services..."

# Create simplified dashboard service
cat > /etc/systemd/system/kimonokittens-dashboard.service <<EOF
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
ExecStart=/home/kimonokittens/.rbenv/shims/ruby puma_server.rb
ExecReload=/bin/kill -USR1 \$MAINPID
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

# Security hardening
NoNewPrivileges=yes
PrivateTmp=yes
ProtectSystem=strict
ReadWritePaths=/home/kimonokittens
ProtectHome=yes

[Install]
WantedBy=multi-user.target
EOF

# Create simplified kiosk service (same user)
cat > /etc/systemd/system/kimonokittens-kiosk.service <<EOF
[Unit]
Description=Kimonokittens Kiosk Browser
After=graphical.target kimonokittens-dashboard.service
Wants=kimonokittens-dashboard.service

[Service]
Type=simple
User=kimonokittens
Group=kimonokittens
Environment="DISPLAY=:0"
Environment="XAUTHORITY=/home/kimonokittens/.Xauthority"
ExecStartPre=/bin/sleep 15
ExecStart=/usr/bin/chromium-browser --kiosk --disable-infobars --disable-session-crashed-bubble --disable-web-security --disable-features=TranslateUI --noerrdialogs --incognito --no-first-run --enable-gpu --app=http://localhost
Restart=always
RestartSec=30
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=graphical.target
EOF

# Copy webhook service (simplified)
sed 's|ExecStart=/usr/bin/ruby|ExecStart=/home/kimonokittens/.rbenv/shims/ruby|g' \
    deployment/configs/systemd/kimonokittens-webhook.service > \
    /etc/systemd/system/kimonokittens-webhook.service

systemctl daemon-reload

echo "✅ SystemD services configured"

# Step 11: Configure nginx
echo "Step 11: Configuring nginx..."
cp deployment/configs/nginx/kimonokittens.conf /etc/nginx/sites-available/
ln -sf /etc/nginx/sites-available/kimonokittens.conf /etc/nginx/sites-enabled/default
nginx -t
systemctl restart nginx

echo "✅ Nginx configured"

# Step 12: Configure LightDM for auto-login (single user)
echo "Step 12: Configuring kiosk display..."
sed -i 's/#autologin-user=/autologin-user=kimonokittens/' /etc/lightdm/lightdm.conf
sed -i 's/#autologin-user-timeout=0/autologin-user-timeout=0/' /etc/lightdm/lightdm.conf

# Create autostart for kimonokittens user
mkdir -p /home/kimonokittens/.config/autostart
cat > /home/kimonokittens/.config/autostart/kiosk.desktop <<EOF
[Desktop Entry]
Type=Application
Name=Kiosk Browser
Exec=/bin/sleep 10 && chromium-browser --kiosk --disable-infobars --disable-session-crashed-bubble --noerrdialogs --incognito --no-first-run --enable-gpu --app=http://localhost
Hidden=false
NoDisplay=false
X-GNOME-Autostart-enabled=true
EOF
chown -R kimonokittens:kimonokittens /home/kimonokittens/.config

echo "✅ Kiosk mode configured"

# Step 13: Enable and start services
echo "Step 13: Starting services..."
systemctl enable kimonokittens-dashboard
systemctl enable nginx
systemctl start kimonokittens-dashboard
systemctl start nginx

# Step 14: Verify installation
echo ""
echo "=== Verifying Installation ==="
sleep 3

# Check database
echo -n "Database connection: "
sudo -u kimonokittens bash -c "
    export PATH=\"/home/kimonokittens/.rbenv/bin:\$PATH\"
    eval \"\$(rbenv init -)\"
    cd /home/kimonokittens/Projects/kimonokittens
    ruby -e \"require 'dotenv/load'; require_relative 'lib/rent_db'; puts RentDb.instance.get_tenants.length.to_s + ' tenants found'\"
" 2>/dev/null || echo "FAILED - check logs"

# Check API
echo -n "API endpoint: "
curl -s http://localhost:3001/api/rent/friendly_message | grep -q "message" && echo "OK" || echo "FAILED"

# Check nginx
echo -n "Nginx status: "
systemctl is-active nginx

echo ""
echo "=== Setup Complete! ==="
echo ""
echo "🎉 SIMPLIFIED SINGLE-USER ARCHITECTURE:"
echo "✅ User 'kimonokittens' handles both backend and kiosk display"
echo "✅ Using rbenv Ruby $(sudo -u kimonokittens /home/kimonokittens/.rbenv/shims/ruby --version 2>/dev/null || echo '3.3.x')"
echo "✅ Dashboard deployed to /var/www/kimonokittens/dashboard"
echo "✅ Services configured and running"
echo "✅ Chromium kiosk mode configured for optimal GPU performance"
echo ""
echo "Next steps:"
echo "1. Configure GitHub webhook secret: sudo systemctl edit kimonokittens-webhook"
echo "2. Add webhook URL in GitHub: http://YOUR_IP/webhook"
echo "3. Reboot to activate kiosk mode: sudo reboot"
echo ""
echo "To check service status: systemctl status kimonokittens-dashboard"
echo "To view logs: journalctl -u kimonokittens-dashboard -f"
echo ""
echo "🔧 ARCHITECTURE SIMPLIFIED:"
echo "- One service user instead of two"
echo "- Same security isolation from your main account"
echo "- Easier debugging and maintenance"
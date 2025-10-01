# Dell Optiplex 7010 Kiosk Dashboard Deployment Guide

**Target Hardware**: Dell Optiplex 7010 running PopOS Linux
**Purpose**: Dedicated kiosk server hosting real-time dashboard
**Display**: Chromium fullscreen kiosk with GPU acceleration and auto-updates

> **📋 Quick Deploy**: See `deployment/` folder for streamlined setup process.

---

## 📋 Overview

Transform the Dell Optiplex into a production-ready kiosk server that:
- Displays dashboard in fullscreen kiosk mode
- Hosts both dashboard and handbook applications
- Auto-updates from GitHub pushes
- Runs reliably with minimal maintenance
- Uses separate processes for security and stability

## 🏗️ Architecture

```
Internet ──→ GitHub Webhook ──→ Dell Optiplex
                │
                ├─ Dashboard Backend (Puma :3001)
                ├─ Smart Webhook Receiver (:9001)
                ├─ Nginx Frontend (:80)
                └─ Google Chrome Kiosk Display
```

### Modern User Service Strategy (2024 Best Practice)
- **Single User**: `kimonokittens` runs all services for security and simplicity
- **User Services**: systemd `--user` services with persistent linger
- **Dashboard Process**: Puma server on port 3001 (real-time WebSocket data)
- **Smart Webhook**: Puma server on port 9001 (unified architecture, concurrent-ready)
- **Frontend Delivery**: Nginx on port 80 serving React SPA
- **Kiosk Display**: Google Chrome with user service auto-launch
- **X11 Permissions**: Proper xhost configuration for display access
- **Unified Stack**: Both servers use Puma + Rack for consistency and performance

---

## 🗄️ Production Database Setup

### Database Migration Strategy

**CRITICAL**: Complete this section before starting application services.

#### Prerequisites
```bash
# Install PostgreSQL
sudo apt update
sudo apt install postgresql postgresql-contrib

# Create production database and user
sudo -u postgres createuser -P kimonokittens
sudo -u postgres createdb kimonokittens_production -O kimonokittens
```

#### Environment Configuration
Create `/home/kimonokittens/.env` with production settings:
```bash
DATABASE_URL=postgresql://kimonokittens:YOUR_PASSWORD@localhost/kimonokittens_production
NODE_ENV=production
RAILS_ENV=production
PORT=3001
```

#### Database Migration Process

**Step 1: Transfer Migration Files**
```bash
# Copy migration files to production server
scp deployment/production_database_20250928.json user@optiplex:/home/kimonokittens/
scp deployment/production_migration.rb user@optiplex:/home/kimonokittens/
```

**Step 2: Install Ruby Dependencies**
```bash
cd /home/kimonokittens
# Install required Ruby gems (including sequel, pg, etc.)
bundle install --deployment --without development test assets
```

**Step 3: Run Prisma Migration**
```bash
cd /home/kimonokittens
npx prisma migrate deploy
npx prisma generate
```

**Step 4: Import Production Data**
```bash
# Load initial production data (rent configs, tenants, historical data)
ruby deployment/production_migration.rb
```

#### Data Verification
```bash
# Verify database state
ruby -e "
require 'dotenv/load'
require_relative 'lib/rent_db'
db = RentDb.instance
puts 'RentConfig: ' + db.class.rent_configs.count.to_s
puts 'Tenants: ' + db.class.tenants.count.to_s
puts 'RentLedger: ' + db.class.rent_ledger.count.to_s
"
```

**Expected Output**:
```
RentConfig: 7
Tenants: 8
RentLedger: 0
```

#### Historical Data (Backup Only)
The corrected historical JSON files in `data/rent_history/` serve as:
- **Disaster recovery backup**
- **Data integrity reference**
- **Audit trail for rent calculations**

These files use **CONFIG PERIOD MONTH** semantics:
- `month: 7` → August rent calculation
- `month: 10` → November rent calculation

**Note**: Database is the production source of truth; JSON files are backup only.

---

## 🖥️ Kiosk Display Setup

### System Users
```bash
# Create unified service and kiosk user
sudo useradd -m -s /bin/bash kimonokittens
sudo usermod -a -G video,audio kimonokittens

# Enable persistent user sessions for remote management
sudo loginctl enable-linger kimonokittens
```

### Display Manager Configuration

**GDM3 Auto-login Setup** (`/etc/gdm3/custom.conf`):
```ini
[daemon]
AutomaticLoginEnable=True
AutomaticLogin=kimonokittens
```

**X11 GPU Acceleration** (`/home/kimonokittens/.xsessionrc`):
```bash
#!/bin/bash
export DISPLAY=:0
export GPU_MAX_HEAP_SIZE=100
export GPU_MAX_ALLOC_PERCENT=100
```

### Browser Kiosk Mode (Modern User Service Approach)

**Chrome Kiosk User Service** (`~/.config/systemd/user/kimonokittens-kiosk.service`):
```ini
[Unit]
Description=Kimonokittens Kiosk Browser (User Service)
After=graphical-session.target
Wants=graphical-session.target

[Service]
Type=simple
Environment="XDG_RUNTIME_DIR=/run/user/1001"
ExecStartPre=/bin/sleep 15
ExecStart=/usr/bin/google-chrome --kiosk \
          --no-first-run \
          --disable-infobars \
          --disable-session-crashed-bubble \
          --disable-web-security \
          --disable-features=TranslateUI \
          --noerrdialogs \
          --incognito \
          --no-default-browser-check \
          --password-store=basic \
          --start-maximized \
          --app=http://localhost
Restart=always
RestartSec=30
StartLimitBurst=5
StartLimitIntervalSec=300

[Install]
WantedBy=default.target
```

**Setup Commands**:
```bash
# Create user service directory
sudo -u kimonokittens mkdir -p /home/kimonokittens/.config/systemd/user

# Copy service file
sudo cp modern-kiosk-user.service /home/kimonokittens/.config/systemd/user/kimonokittens-kiosk.service
sudo chown kimonokittens:kimonokittens /home/kimonokittens/.config/systemd/user/kimonokittens-kiosk.service

# Enable and start user service
sudo -u kimonokittens systemctl --user daemon-reload
sudo -u kimonokittens systemctl --user enable kimonokittens-kiosk.service
sudo -u kimonokittens systemctl --user start kimonokittens-kiosk.service
```

### X11 Display Permissions (Critical for Remote Management)

**For Cross-User Display Access** (if needed):
```bash
# Allow kimonokittens to access display (run as display owner)
xhost +SI:localuser:kimonokittens

# Make permanent by adding to user's .bashrc
echo "xhost +SI:localuser:kimonokittens 2>/dev/null" >> ~/.bashrc
```

**User Session Management**:
```bash
# Enable persistent user sessions (allows SSH management)
sudo loginctl enable-linger kimonokittens

# Check user session status
sudo loginctl user-status kimonokittens

# Manage user service remotely via SSH
sudo -u kimonokittens systemctl --user restart kimonokittens-kiosk
```

**Alternative: Firefox Kiosk** (if Chrome issues):
```bash
firefox --kiosk --private-window http://localhost
```
**Note**: We now use Chromium by default for better GPU performance.

---

## 🔄 Auto-Update System

### GitHub Smart Webhook Setup

**1. Smart Webhook Server** (`deployment/scripts/webhook_puma_server.rb`):

The smart webhook server uses **Puma architecture** (unified with dashboard) and analyzes changed files to only deploy what's needed:

- **Frontend changes** → Frontend rebuild + kiosk refresh
- **Backend changes** → Backend restart only
- **Docs/config only** → No deployment (saves unnecessary restarts)

**Puma Architecture Benefits:**
- **Multi-threaded**: Handles concurrent webhook requests efficiently
- **Unified stack**: Same server technology as dashboard (Puma + Rack)
- **Extensible**: Easy to add new endpoints for multiple projects
- **Future-proof**: Scales with concurrent git push hooks

**Key endpoints:**
- `/webhook` - GitHub webhook receiver
- `/health` - Simple health check
- `/status` - Detailed status with uptime and configuration

**Smart Analysis Logic:**
```ruby
def analyze_changes(commits)
  frontend_changed = false
  backend_changed = false

  commits.each do |commit|
    (commit['modified'] || []).each do |file|
      case file
      when /^dashboard\//
        frontend_changed = true
      when /\.(rb|ru|gemspec|Gemfile)$/
        backend_changed = true
      end
    end
  end

  { frontend: frontend_changed, backend: backend_changed }
end
```

**Unified Architecture Features:**
- **Rack::Builder**: Same routing pattern as dashboard
- **Handler classes**: Consistent `call(env)` pattern
- **Error handling**: Comprehensive logging and CORS support
- **Concurrent processing**: Puma's multi-threading for webhook bursts

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
      pid = spawn('/home/kimonokittens/deploy.sh',
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
```

**2. Smart Webhook systemd Service** (`/etc/systemd/system/kimonokittens-webhook.service`):
```ini
[Unit]
Description=Kimonokittens Smart Webhook Receiver
After=network.target

[Service]
Type=simple
User=kimonokittens
Group=kimonokittens
WorkingDirectory=/home/kimonokittens/Projects/kimonokittens
Environment="PATH=/home/kimonokittens/.rbenv/bin:/home/kimonokittens/.rbenv/shims:/usr/local/bin:/usr/bin:/bin"
Environment="WEBHOOK_SECRET=your-secret-here"
Environment="PORT=9001"
EnvironmentFile=-/home/kimonokittens/.env
ExecStart=/bin/bash -c 'eval "$(/home/kimonokittens/.rbenv/bin/rbenv init - bash)" && bundle exec ruby deployment/scripts/webhook_puma_server.rb'
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
```

### Deploy Script

**Master Deploy Script** (`/home/kimonokittens/deploy.sh`):
```bash
#!/bin/bash
set -e

# Configuration
REPO_DIR="/home/kimonokittens/Projects/kimonokittens"
WEB_ROOT="/var/www/kimonokittens"
LOG_FILE="/var/log/kimonokittens/deploy.log"
BACKUP_DIR="/home/kimonokittens/backups"

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Error handling
cleanup() {
    if [ $? -ne 0 ]; then
        log "ERROR: Deploy failed, check logs"
        # Could trigger rollback here
    fi
}
trap cleanup EXIT

log "=== Starting deployment ==="

cd "$REPO_DIR"

# Backup current version
BACKUP_NAME="backup-$(date +%Y%m%d-%H%M%S)"
log "Creating backup: $BACKUP_NAME"
mkdir -p "$BACKUP_DIR"
cp -r "$WEB_ROOT" "$BACKUP_DIR/$BACKUP_NAME" || true

# Pull latest code
log "Pulling latest code from GitHub"
git fetch origin
git reset --hard origin/master
git clean -fd

# Install/update dependencies
log "Installing Ruby dependencies"
cd "$REPO_DIR"
bundle install --deployment --without development test

# Build dashboard frontend
log "Building dashboard frontend"
cd "$REPO_DIR/dashboard"
npm ci --production
npm run build

# Copy dashboard build to web root
log "Deploying dashboard build"
mkdir -p "$WEB_ROOT/dashboard"
rsync -av --delete dist/ "$WEB_ROOT/dashboard/"

# Build handbook frontend (when ready)
if [ -d "$REPO_DIR/handbook/frontend" ]; then
    log "Building handbook frontend"
    cd "$REPO_DIR/handbook/frontend"
    npm ci --production
    npm run build

    log "Deploying handbook build"
    mkdir -p "$WEB_ROOT/handbook"
    rsync -av --delete dist/ "$WEB_ROOT/handbook/"
fi

# Set correct permissions
log "Setting file permissions"
chown -R www-data:www-data "$WEB_ROOT"
chmod -R 755 "$WEB_ROOT"

# Restart backend services
log "Restarting backend services"
systemctl restart kimonokittens-dashboard
systemctl restart kimonokittens-handbook || true

# Wait for services to start
sleep 5

# Health check
log "Performing health checks"
if curl -f http://localhost:3001/health > /dev/null 2>&1; then
    log "Dashboard backend: OK"
else
    log "WARNING: Dashboard backend health check failed"
fi

if curl -f http://localhost:3002/health > /dev/null 2>&1; then
    log "Handbook backend: OK"
else
    log "INFO: Handbook backend not running (may not be deployed yet)"
fi

# Signal browser to refresh
log "Signaling browser refresh"
echo "$(date +%s)" > /tmp/kimonokittens-updated

# Cleanup old backups (keep last 5)
log "Cleaning up old backups"
ls -t "$BACKUP_DIR" | tail -n +6 | xargs -r -I {} rm -rf "$BACKUP_DIR/{}"

log "=== Deployment completed successfully ==="
```

**Make deploy script executable**:
```bash
chmod +x /home/kimonokittens/deploy.sh
chown kimonokittens:kimonokittens /home/kimonokittens/deploy.sh
```

---

## 🔧 Backend Services

### Dashboard Backend Service

**Service File** (`/etc/systemd/system/kimonokittens-dashboard.service`):
```ini
[Unit]
Description=Kimonokittens Dashboard Backend
After=network.target
Requires=network.target

[Service]
Type=simple
User=kimonokittens
Group=kimonokittens
WorkingDirectory=/home/kimonokittens/Projects/kimonokittens
Environment="PORT=3001"
Environment="ENABLE_BROADCASTER=1"
Environment="RAILS_ENV=production"
ExecStart=/usr/local/bin/ruby puma_server.rb
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
ReadWritePaths=/home/kimonokittens/Projects/kimonokittens /var/log/kimonokittens /home/kimonokittens/backups /var/www/kimonokittens /tmp

[Install]
WantedBy=multi-user.target
```

### Handbook Backend Service

**Service File** (`/etc/systemd/system/kimonokittens-handbook.service`):
```ini
[Unit]
Description=Kimonokittens Handbook Backend
After=network.target
Requires=network.target

[Service]
Type=simple
User=kimonokittens
Group=kimonokittens
WorkingDirectory=/home/kimonokittens/Projects/kimonokittens
Environment="PORT=3002"
Environment="RAILS_ENV=production"
Environment="OPENAI_API_KEY=your-key-here"
Environment="PINECONE_API_KEY=your-key-here"
Environment="PINECONE_ENVIRONMENT=your-env-here"
ExecStart=/usr/local/bin/ruby handbook_server.rb
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
ReadWritePaths=/home/kimonokittens/Projects/kimonokittens /var/log/kimonokittens /home/kimonokittens/backups /var/www/kimonokittens /tmp

[Install]
WantedBy=multi-user.target
```

### Enable Services
```bash
sudo systemctl daemon-reload
sudo systemctl enable kimonokittens-dashboard
sudo systemctl enable kimonokittens-handbook
sudo systemctl enable kimonokittens-webhook
sudo systemctl enable kimonokittens-kiosk
```

---

## 🌐 Nginx Frontend Configuration

**Main Config** (`/etc/nginx/sites-available/kimonokittens`):
```nginx
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name _;

    # Security headers
    add_header X-Frame-Options DENY;
    add_header X-Content-Type-Options nosniff;
    add_header X-XSS-Protection "1; mode=block";

    # Main dashboard SPA
    location / {
        root /var/www/kimonokittens/dashboard;
        try_files $uri /index.html;

        # Cache static assets
        location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg)$ {
            expires 1y;
            add_header Cache-Control "public, immutable";
        }
    }

    # Handbook SPA
    location /handbook {
        alias /var/www/kimonokittens/handbook;
        try_files $uri /handbook/index.html;

        # Cache static assets
        location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg)$ {
            expires 1y;
            add_header Cache-Control "public, immutable";
        }
    }

    # Dashboard API endpoints
    location /api {
        proxy_pass http://127.0.0.1:3001;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        # WebSocket support
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";

        # Timeouts
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }

    # Handbook API endpoints
    location /api/handbook {
        proxy_pass http://127.0.0.1:3002;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        # Longer timeout for AI operations
        proxy_connect_timeout 120s;
        proxy_send_timeout 120s;
        proxy_read_timeout 120s;
    }

    # WebSocket endpoint for real-time updates
    location /ws {
        proxy_pass http://127.0.0.1:3001;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    # Health check endpoint
    location /health {
        access_log off;
        return 200 "healthy\n";
        add_header Content-Type text/plain;
    }

    # Webhook endpoint (external access)
    location /webhook {
        proxy_pass http://127.0.0.1:9001;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}

# Redirect HTTP to HTTPS (when SSL is configured)
# server {
#     listen 80;
#     server_name your-domain.com;
#     return 301 https://$server_name$request_uri;
# }
```

**Enable Nginx Site**:
```bash
sudo ln -sf /etc/nginx/sites-available/kimonokittens /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl reload nginx
```

---

## 🔄 Browser Auto-Refresh System

### Method 1: WebSocket Notification (Recommended)

**Frontend Refresh Handler** (add to dashboard `main.ts`):
```typescript
// Auto-refresh on deployment
function setupAutoRefresh() {
  const ws = new WebSocket(`ws://${window.location.host}/ws`);

  ws.onmessage = (event) => {
    const data = JSON.parse(event.data);

    if (data.type === 'deployment_complete') {
      console.log('New deployment detected, refreshing...');
      setTimeout(() => window.location.reload(), 2000);
    }
  };

  // Fallback: check for update file every 5 minutes
  setInterval(() => {
    fetch('/api/version')
      .then(res => res.json())
      .then(data => {
        if (data.updated_at && data.updated_at > window.deploymentTime) {
          window.location.reload();
        }
      })
      .catch(console.error);
  }, 300000); // 5 minutes
}

// Store deployment time
window.deploymentTime = Date.now();
setupAutoRefresh();
```

### Method 2: File-Based Detection

**Backend Version Endpoint** (add to puma_server.rb):
```ruby
class VersionHandler < WEBrick::HTTPServlet::AbstractServlet
  def do_GET(req, res)
    update_file = '/tmp/kimonokittens-updated'

    if File.exist?(update_file)
      updated_at = File.mtime(update_file).to_i
    else
      updated_at = 0
    end

    res['Content-Type'] = 'application/json'
    res.body = {
      updated_at: updated_at,
      version: `git rev-parse HEAD`.chomp,
      timestamp: Time.now.to_i
    }.to_json
  end
end

# Mount in server
server.mount "/api/version", VersionHandler
```

### Method 3: Meta Refresh Fallback

**HTML Fallback** (add to index.html):
```html
<!-- Fallback refresh every hour -->
<meta http-equiv="refresh" content="3600">
```

---

## 🚀 Installation Procedure

### 1. System Preparation

```bash
# Update system
sudo apt update && sudo apt upgrade -y

# Install base dependencies (Pop!_OS 22.04 optimized)
sudo apt install -y \
  nginx \
  google-chrome-stable \
  postgresql-17 \
  postgresql-contrib-17 \
  build-essential \
  libpq-dev \
  git \
  curl \
  rsync \
  jq \
  software-properties-common

# Install Ruby gems
gem install bundler puma sinatra

# Create directories
sudo mkdir -p /var/www/kimonokittens
sudo mkdir -p /var/log/kimonokittens
sudo mkdir -p /home/kimonokittens/Projects
sudo mkdir -p /home/kimonokittens/backups

# Set permissions
sudo chown -R kimonokittens:kimonokittens /home/kimonokittens
sudo chown -R www-data:www-data /var/www/kimonokittens
sudo chown kimonokittens:adm /var/log/kimonokittens

# Setup group-based permissions for development access
# Add your admin user (e.g., fredrik) to kimonokittens group for read access
ADMIN_USER="fredrik"  # Change to your admin username
sudo usermod -a -G kimonokittens $ADMIN_USER
sudo chmod -R g+rX /home/kimonokittens/Projects
# Note: Admin user needs to logout/login for group membership to take effect

# Protect sensitive files (owner-only access)
sudo chmod 600 /home/kimonokittens/Projects/kimonokittens/.env
```

**Why group-based permissions?**
- Allows admin user read access for debugging without sudo
- Service user (kimonokittens) maintains ownership
- Only Projects directory exposed, not entire home
- Sensitive files (.env) remain protected (600 = owner-only)
- Standard Unix development practice

### 2. Clone and Setup Repository

```bash
# Clone as kimonokittens user
sudo -u kimonokittens git clone https://github.com/yourusername/kimonokittens.git \
  /home/kimonokittens/Projects/kimonokittens

cd /home/kimonokittens/Projects/kimonokittens

# Install dependencies
sudo -u kimonokittens bundle install
sudo -u kimonokittens npm install --prefix dashboard

# Initial build
sudo -u kimonokittens npm run build --prefix dashboard
sudo cp -r dashboard/dist/* /var/www/kimonokittens/dashboard/
```

### 3. Configure Services

```bash
# Copy service files (created above)
sudo cp configs/systemd/*.service /etc/systemd/system/

# Copy nginx config
sudo cp configs/nginx/kimonokittens /etc/nginx/sites-available/
sudo ln -sf /etc/nginx/sites-available/kimonokittens /etc/nginx/sites-enabled/default

# Copy scripts
sudo cp scripts/deploy.sh /home/kimonokittens/
sudo cp scripts/webhook_receiver.rb /home/kimonokittens/
sudo chmod +x /home/kimonokittens/deploy.sh

# Enable services
sudo systemctl daemon-reload
sudo systemctl enable kimonokittens-dashboard
sudo systemctl enable kimonokittens-webhook
sudo systemctl enable kimonokittens-kiosk
sudo systemctl enable nginx
```

### 4. Configure GDM3 Auto-login

```bash
# Enable autologin for unified user (GDM3 - Pop!_OS default)
sudo sed -i '/\[daemon\]/a AutomaticLoginEnable=True' /etc/gdm3/custom.conf
sudo sed -i "/AutomaticLoginEnable=True/a AutomaticLogin=kimonokittens" /etc/gdm3/custom.conf

# Enable persistent user sessions for remote management
sudo loginctl enable-linger kimonokittens

# Set up xhost permissions for display access
sudo -u kimonokittens bash -c 'echo "xhost +SI:localuser:kimonokittens 2>/dev/null" >> ~/.bashrc'
```

### 5. GitHub Webhook Configuration

1. **In GitHub repository settings**:
   - Go to Settings → Webhooks → Add webhook
   - Payload URL: `http://your-optiplex-ip:9001/webhook`
   - Content type: `application/json`
   - Secret: Set a secure random string
   - Events: Just the `push` event

2. **Update webhook service with secret**:
```bash
sudo systemctl edit kimonokittens-webhook
```

Add:
```ini
[Service]
Environment="WEBHOOK_SECRET=your-secret-from-github"
```

### 6. Start Services

```bash
# Start all services
sudo systemctl start nginx
sudo systemctl start kimonokittens-dashboard
sudo systemctl start kimonokittens-webhook

# Check status
sudo systemctl status kimonokittens-dashboard
sudo systemctl status kimonokittens-webhook
sudo systemctl status nginx

# Test webhook
curl -X POST http://localhost:9001/health
```

### 7. Install Custom Fonts

**Required fonts for dashboard:**
- **Galvji** - Primary sans-serif font
- **Horsemen** - Decorative font for widget titles
- **JetBrains Mono** - Monospace font (auto-installed)

**Step 1: Copy fonts from Mac to Linux machine**

On your Mac:
```bash
# Create font directory on Linux
ssh pop "mkdir -p /tmp/kimonokittens-fonts"

# Copy Galvji fonts
scp ~/Library/Fonts/Galvji* pop:/tmp/kimonokittens-fonts/

# Copy Horsemen fonts
scp ~/Library/Fonts/Horsemen* pop:/tmp/kimonokittens-fonts/
```

If you can't find the fonts:
```bash
# Search on Mac
find ~/Library/Fonts /Library/Fonts -name "*Galvji*" -o -name "*Horsemen*" 2>/dev/null
```

**Step 2: Install fonts on Linux**

On the Dell Optiplex:
```bash
# Run font installation script
sudo /home/kimonokittens/Projects/kimonokittens/deployment/scripts/install_fonts.sh

# Verify fonts installed
fc-list | grep -i galvji
fc-list | grep -i horsemen
fc-list | grep -i jetbrains
```

**Step 3: Restart browser to load fonts**
```bash
sudo -u kimonokittens systemctl --user restart kimonokittens-kiosk
```

### 8. Configure Screen Rotation (Portrait Mode)

The dashboard is designed for portrait mode (monitor rotated 90° clockwise).

**Step 1: Configure rotation in user session**

1. Log in as `kimonokittens` user
2. Open **Settings** → **Displays**
3. Set **Orientation** to **Portrait Right** (90° clockwise)
4. Click **Apply** and **Keep Changes**

This creates `~/.config/monitors.xml` with the display configuration.

**Step 2: Apply to GDM3 login screen and all users**

```bash
# Run screen rotation configuration script
sudo /home/kimonokittens/Projects/kimonokittens/deployment/scripts/configure_screen_rotation.sh kimonokittens

# Restart GDM3 to apply (closes all graphical sessions!)
sudo systemctl restart gdm3
```

This makes rotation persistent across:
- ✅ GDM3 login screen
- ✅ All user sessions
- ✅ Reboots

**Alternative manual method:**
```bash
# Create GDM config directory
sudo mkdir -p /var/lib/gdm3/.config

# Copy user's monitor config to GDM3
sudo cp ~/.config/monitors.xml /var/lib/gdm3/.config/monitors.xml

# Set proper ownership
sudo chown gdm:gdm /var/lib/gdm3/.config/monitors.xml

# Restart display manager
sudo systemctl restart gdm3
```

### 9. Configure Kiosk Power Management (Always-On Display)

The kiosk display must stay on 24/7 without dimming, blanking, or locking.

**Run the power management configuration script:**

```bash
sudo /home/kimonokittens/Projects/kimonokittens/deployment/scripts/configure_kiosk_power.sh kimonokittens
```

**This script configures:**
- ✅ Disables screen blanking (never turns off)
- ✅ Disables automatic brightness dimming
- ✅ Disables screensaver activation
- ✅ Disables automatic screen locking
- ✅ Disables automatic sleep/suspend
- ✅ Sets idle delay to 0 (never idle)

**Settings are applied via gsettings and affect:**
- `org.gnome.desktop.session` - idle behavior
- `org.gnome.settings-daemon.plugins.power` - power management
- `org.gnome.desktop.screensaver` - screensaver and lock screen
- `org.gnome.desktop.lockdown` - lock screen lockdown

**Verification:**

The script automatically verifies all settings. Changes take effect immediately for active sessions, but a logout/login or reboot ensures full effect.

**Manual brightness adjustment (if needed):**
```bash
# Via Settings GUI
Settings → Displays → Brightness slider

# Via command line
xrandr --output <display-name> --brightness 1.0
```

### 10. Configure Boot to Kiosk

```bash
# Set default target to graphical
sudo systemctl set-default graphical.target

# Enable kiosk service
sudo systemctl enable kimonokittens-kiosk

# Reboot to test
sudo reboot
```

---

## 🔍 Monitoring & Maintenance

### Service Monitoring

```bash
# Check service status
sudo systemctl status kimonokittens-*

# View logs
sudo journalctl -u kimonokittens-dashboard -f
sudo journalctl -u kimonokittens-webhook -f

# Check deployment logs
tail -f /var/log/kimonokittens/deploy.log

# Check nginx logs
sudo tail -f /var/log/nginx/access.log
sudo tail -f /var/log/nginx/error.log
```

### Health Checks

**System Health Script** (`/home/kimonokittens/health-check.sh`):
```bash
#!/bin/bash

check_service() {
    if systemctl is-active --quiet "$1"; then
        echo "✓ $1 is running"
    else
        echo "✗ $1 is not running"
        systemctl restart "$1"
    fi
}

check_url() {
    if curl -f -s "$1" > /dev/null; then
        echo "✓ $1 is responding"
    else
        echo "✗ $1 is not responding"
    fi
}

echo "=== Health Check $(date) ==="

check_service kimonokittens-dashboard
check_service kimonokittens-webhook
check_service nginx

check_url http://localhost:3001/health
check_url http://localhost:9001/health
check_url http://localhost/health

echo "=== End Health Check ==="
```

**Add to cron** (`sudo crontab -e`):
```cron
# Health check every 5 minutes
*/5 * * * * /home/kimonokittens/health-check.sh >> /var/log/kimonokittens/health.log 2>&1
```

### Log Rotation

**Configure logrotate** (`/etc/logrotate.d/kimonokittens`):
```
/var/log/kimonokittens/*.log {
    daily
    rotate 30
    compress
    delaycompress
    missingok
    notifempty
    copytruncate
    su kimonokittens adm
}
```

---

## 🔒 Security Considerations

### SystemD Service Hardening

The service configurations use **defense in depth** security hardening:

- **`ProtectSystem=strict`**: Entire filesystem read-only except `/dev`, `/proc`, `/sys`
- **`ProtectHome=read-only`**: Prevents writes to home directories, allows config reads
- **`ReadWritePaths=`**: Grants write access **only** to required directories:
  - `/home/kimonokittens/Projects/kimonokittens` - Application code and data
  - `/var/log/kimonokittens` - Service logs only
  - `/home/kimonokittens/backups` - Deployment backups
  - `/var/www/kimonokittens` - Web content deployment
  - `/tmp` - Temporary files and update signals
- **Additional protections**: `PrivateDevices`, `ProtectKernelModules`, `NoNewPrivileges`

This prevents:
- Modification of system files or other users' data
- Hardware device access or kernel tampering
- Privilege escalation attacks
- Writing to 95% of the filesystem

### Firewall Rules

```bash
# Basic UFW setup
sudo ufw default deny incoming
sudo ufw default allow outgoing

# Allow SSH (change port if using non-standard)
sudo ufw allow 22

# Allow HTTP (for kiosk display)
sudo ufw allow 80

# Allow webhook (restrict to GitHub IPs if possible)
sudo ufw allow 9001

# Enable firewall
sudo ufw enable
```

### Process Security

- **Dedicated users**: Each service runs as limited user
- **No root access**: Services don't run as root
- **Restricted file access**: systemd security features enabled
- **Secret management**: Environment variables for API keys

### Network Security

- **Local-only APIs**: Backend services only listen on localhost
- **Nginx proxy**: External access only through nginx
- **Webhook validation**: GitHub signature verification
- **HTTPS ready**: Configuration prepared for SSL certificates

---

## ⚡ Performance Optimizations

### System Optimization

```bash
# Disable unnecessary services
sudo systemctl disable bluetooth
sudo systemctl disable cups
sudo systemctl disable ModemManager

# Optimize for kiosk performance
echo 'vm.swappiness=10' | sudo tee -a /etc/sysctl.conf
echo 'net.core.netdev_max_backlog=5000' | sudo tee -a /etc/sysctl.conf
```

### Browser Performance

**Chromium GPU Acceleration** (`/home/kiosk/.config/chromium-flags.conf`):
```
--enable-gpu-rasterization
--enable-zero-copy
--enable-features=VaapiVideoDecoder
--disable-features=VizDisplayCompositor
--max-tiles-for-interest-area=512
--default-tile-width=512
--default-tile-height=512
```

### Nginx Optimization

**Add to nginx config**:
```nginx
# Gzip compression
gzip on;
gzip_vary on;
gzip_min_length 1024;
gzip_comp_level 6;
gzip_types text/css application/javascript application/json image/svg+xml;

# Connection optimization
sendfile on;
tcp_nopush on;
tcp_nodelay on;
keepalive_timeout 30;
```

---

## 🚨 Troubleshooting

### Common Issues

**1. Kiosk not starting**:
```bash
# Check X11 session
sudo -u kiosk DISPLAY=:0 xrandr

# Check service status
systemctl status kimonokittens-kiosk

# Manual start for debugging
sudo -u kiosk DISPLAY=:0 chromium --kiosk http://localhost
```

**2. Services failing to start**:
```bash
# Check logs
journalctl -u kimonokittens-dashboard -n 50

# Check permissions
ls -la /home/kimonokittens/Projects/kimonokittens

# Test manual start
cd /home/kimonokittens/Projects/kimonokittens
ruby puma_server.rb
```

**3. Deployment not triggering**:
```bash
# Check webhook logs
journalctl -u kimonokittens-webhook -f

# Test webhook manually
curl -X POST -d '{"ref":"refs/heads/master"}' \
     -H "Content-Type: application/json" \
     http://localhost:9001/webhook
```

**4. Browser not refreshing**:
```bash
# Check WebSocket connection in browser DevTools
# Check for update signal file
ls -la /tmp/kimonokittens-updated

# Manual refresh trigger
echo $(date +%s) > /tmp/kimonokittens-updated
```

### Emergency Recovery

**Reset to last known good state**:
```bash
# Stop services
sudo systemctl stop kimonokittens-*

# Restore from backup
BACKUP=$(ls -t /home/kimonokittens/backups | head -n 1)
sudo cp -r "/home/kimonokittens/backups/$BACKUP"/* /var/www/kimonokittens/

# Restart services
sudo systemctl start kimonokittens-*
```

---

## 🤖 Claude Code Automation Analysis

### **Automation Feasibility Breakdown**

This deployment guide can be **85-90% automated** with Claude Code, but requires understanding of manual intervention points:

#### **✅ Fully Automatable (No Manual Intervention)**
- File creation (systemd services, nginx configs, scripts)
- Ruby/Node.js dependency installation via package managers
- Git repository cloning and setup
- Application builds (`npm run build`)
- Basic directory structure creation

#### **🔐 Requires Sudo/Root Access (But Scriptable)**
Most sudo operations can be automated if Claude Code has sudo access:

```bash
# These need sudo but are scriptable:
sudo apt install nginx chromium-browser ruby nodejs npm
sudo systemctl enable/start services
sudo ufw firewall configuration
sudo mkdir /var/www/kimonokittens
sudo chown operations
sudo cp service files to /etc/systemd/system/
```

#### **👤 Manual Operations Required**

**1. User Account Setup:**
```bash
# These need manual setup or careful scripting:
sudo useradd kimonokittens
sudo useradd kiosk
sudo usermod -a -G video kiosk
```

**2. GDM3 Configuration** (Scriptable):
```bash
# GDM3 auto-login setup (Pop!_OS default display manager):
sudo sed -i '/\[daemon\]/a AutomaticLoginEnable=True' /etc/gdm3/custom.conf
sudo sed -i "/AutomaticLoginEnable=True/a AutomaticLogin=kimonokittens" /etc/gdm3/custom.conf
```

**3. GitHub Webhook Configuration:**
- Go to GitHub repo settings → Webhooks
- Add webhook URL manually: `http://your-optiplex-ip:9001/webhook`
- Set secret token

#### **🔄 Physical Operations Required**
- **At least 1 reboot** after LightDM configuration
- **Keyboard/mouse removal** (after testing)
- **Monitor connection verification**

### **💡 What is GDM3?**

**GDM3** = **"GNOME Display Manager 3"** - Pop!_OS default **login screen controller**:

- **Normal desktop**: Shows login screen → user logs in → desktop loads
- **Kiosk mode**: **Automatically logs in** → **starts user services** → **launches browser fullscreen**

```
Boot → GDM3 → Auto-login 'kimonokittens' user → User services → Browser kiosk
```

**Modern approaches** (fully automation-friendly):

#### **Option A: Docker Kiosk** (95% Automated)
```bash
# Could run everything in containers
docker-compose up -d  # Fully scriptable
```

#### **Option B: Systemd User Services** (90% Automated)
```bash
# Skip LightDM, use systemd --user services instead
systemctl --user enable kiosk-browser
```

#### **Option C: X11 Auto-start** (Simpler)
```bash
# Add to .xinitrc instead of LightDM
echo "chromium --kiosk http://localhost" >> ~/.xinitrc
```

### **🚀 Recommended Automation Strategy**

**Phase 1: Claude Code Automated** (90% of setup)
- Install all packages with `sudo apt install`
- Create all config files and scripts
- Setup systemd services and nginx configuration
- Build and deploy applications
- Configure firewall and security settings

**Phase 2: Manual Finish** (10% remaining)
- Run one command to enable autologin: `sudo sed -i 's/#autologin-user=/autologin-user=kiosk/' /etc/lightdm/lightdm.conf`
- Set GitHub webhook in browser (5 minutes)
- Reboot once: `sudo reboot`
- Remove keyboard/mouse physically

**Phase 3: Test & Verify**
- System should boot to kiosk automatically
- Dashboard should auto-update from GitHub pushes

### **📋 Manual Checklist for Human**

After Claude Code completes automated setup:

```bash
# 1. Enable kiosk autologin (fully scripted in setup script)
sudo sed -i '/\[daemon\]/a AutomaticLoginEnable=True' /etc/gdm3/custom.conf
sudo sed -i "/AutomaticLoginEnable=True/a AutomaticLogin=kimonokittens" /etc/gdm3/custom.conf

# 2. Set webhook secret in service
sudo systemctl edit kimonokittens-webhook
# Add: Environment="WEBHOOK_SECRET=your-github-webhook-secret"

# 3. Reboot to activate kiosk mode
sudo reboot

# 4. Add GitHub webhook in browser
# Settings → Webhooks → Add webhook
# URL: http://your-optiplex-ip:9001/webhook
# Secret: match the one from step 2

# 5. Test deployment
git push origin master
# Should trigger smart deployment (only deploys what changed)
```

### **💭 Automation Verdict**

**Claude Code can handle 85-90% automatically** with sudo access. The remaining manual steps are:
1. **GDM3 auto-login configuration** (fully scriptable)
2. **GitHub webhook setup** (5 minutes in browser)
3. **One reboot** to activate kiosk mode
4. **Physical hardware** (unplug keyboard/mouse)

**Total manual time after Claude Code**: ~15 minutes + 1 reboot

---

## 📚 TODO Integration

Add this deployment as the top priority in TODO.md:

```markdown
- [ ] **PRIORITY: Dell Optiplex Kiosk Deployment**
  - [ ] Complete system setup following DELL_OPTIPLEX_KIOSK_DEPLOYMENT.md
  - [ ] Configure GitHub webhook for auto-updates
  - [ ] Test full deployment and browser kiosk mode
  - [ ] Set up monitoring and health checks
  - [ ] Document production deployment and rollback procedures
```

---

## 🎯 Success Criteria

- ✅ Dell Optiplex boots directly to fullscreen dashboard in portrait mode
- ✅ Screen rotation applied to GDM3 login screen and all user sessions
- ✅ Custom fonts (Galvji, Horsemen, JetBrains Mono) installed and rendering correctly
- ✅ Display stays on 24/7 without dimming, blanking, or locking (kiosk power management)
- ✅ Dashboard updates automatically on GitHub pushes
- ✅ Both dashboard and handbook hosted on same server
- ✅ System runs reliably without keyboard/mouse
- ✅ Services auto-restart on failure
- ✅ Comprehensive logging and monitoring
- ✅ Easy rollback on deployment issues

---

*This deployment guide provides industrial-grade reliability with automated updates - perfect for a hands-off kiosk display that stays current with your latest improvements!*
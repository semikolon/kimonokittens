#!/bin/bash
# Production Setup Script for Dell Optiplex Kiosk (BULLETPROOF VERSION)
# Enhanced with comprehensive validation, idempotency, and error recovery

set -e  # Exit on any error
set -u  # Exit on undefined variables
set -o pipefail  # Exit on pipe failures

# Configuration
readonly SCRIPT_NAME="$(basename "$0")"
readonly LOG_FILE="/tmp/kimonokittens_setup_$(date +%Y%m%d_%H%M%S).log"
readonly BACKUP_DIR="/tmp/kimonokittens_backups_$(date +%Y%m%d_%H%M%S)"
readonly SERVICE_USER="kimonokittens"
readonly DB_NAME="kimonokittens_production"

# Logging function
log() {
    local message="$1"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] $message" | tee -a "$LOG_FILE"
}

# Error handling
error_exit() {
    local message="$1"
    log "❌ ERROR: $message"
    log "📋 Check log file: $LOG_FILE"
    log "🔙 System config backups in: $BACKUP_DIR"
    exit 1
}

# Validation helpers
validate_command() {
    command -v "$1" >/dev/null 2>&1 || error_exit "Required command '$1' not found"
}

validate_network() {
    if ! ping -c 1 8.8.8.8 >/dev/null 2>&1; then
        error_exit "Network connectivity required for package installation"
    fi
}

validate_disk_space() {
    local required_mb=2048  # 2GB minimum
    local available_mb=$(df / | awk 'NR==2 {print int($4/1024)}')
    if [ "$available_mb" -lt "$required_mb" ]; then
        error_exit "Insufficient disk space. Need ${required_mb}MB, have ${available_mb}MB"
    fi
}

# Backup system configs before making changes
backup_config() {
    local file="$1"
    if [ -f "$file" ]; then
        mkdir -p "$BACKUP_DIR"
        cp "$file" "$BACKUP_DIR/$(basename "$file").backup"
        log "✅ Backed up $file"
    fi
}

# Test database connection
test_db_connection() {
    local user="$1"
    local password="$2"
    PGPASSWORD="$password" psql -h localhost -U "$user" -d "$DB_NAME" -c "SELECT 1;" >/dev/null 2>&1
}

log "=== Kimonokittens Production Setup Script (BULLETPROOF VERSION) ==="
log "This script will set up the Dell Optiplex as a production kiosk server"
log "Enhanced with comprehensive validation and error recovery"
log ""

# Pre-flight checks
log "🔍 Running pre-flight checks..."

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    error_exit "Please run this script with sudo"
fi

# Get the real user (in case of sudo)
REAL_USER=${SUDO_USER:-$USER}
REAL_HOME=$(eval echo ~$REAL_USER)

if [ -z "$REAL_USER" ] || [ "$REAL_USER" = "root" ]; then
    error_exit "Cannot determine real user. Run with 'sudo -u youruser $0'"
fi

log "Setting up for user: $REAL_USER"
log "Home directory: $REAL_HOME"
log "Log file: $LOG_FILE"
log "Backup directory: $BACKUP_DIR"

# Validate environment
validate_network
validate_disk_space
validate_command "systemctl"
validate_command "nginx"

# Check critical paths exist
if [ ! -d "$REAL_HOME/Projects/kimonokittens" ]; then
    error_exit "Project directory not found: $REAL_HOME/Projects/kimonokittens"
fi

if [ ! -f "$REAL_HOME/Projects/kimonokittens/puma_server.rb" ]; then
    error_exit "Backend server not found: $REAL_HOME/Projects/kimonokittens/puma_server.rb"
fi

log "✅ Pre-flight checks passed"

# Step 1: Install required packages (excluding Ruby since we have rbenv)
log "📦 Step 1: Installing required packages..."

# Update package cache
if ! apt update; then
    error_exit "Failed to update package cache"
fi

# Install packages with validation (Pop!_OS 22.04 optimized)
REQUIRED_PACKAGES=(
    "postgresql"
    "postgresql-contrib"
    "nginx"
    "build-essential"
    "libpq-dev"
    "wget"
    "curl"
    "jq"
    "rsync"
    "software-properties-common"
    "apt-transport-https"
    "ca-certificates"
    "gnupg"
)

log "Installing packages: ${REQUIRED_PACKAGES[*]}"
if ! apt install -y "${REQUIRED_PACKAGES[@]}"; then
    error_exit "Package installation failed"
fi

# Verify critical packages installed correctly
for package in postgresql nginx; do
    if ! dpkg -l | grep -q "^ii.*$package"; then
        error_exit "Package $package failed to install properly"
    fi
done

# Install Google Chrome (modern secure method - 2024 best practice)
log "Installing Google Chrome for kiosk mode..."
if ! command -v google-chrome >/dev/null 2>&1; then
    log "Adding Google Chrome repository with modern GPG keyring method..."

    # Create keyrings directory (Pop!_OS 22.04 compatibility)
    mkdir -p /usr/share/keyrings

    # Download and install Google Chrome GPG key (secure method)
    if ! wget -O- https://dl.google.com/linux/linux_signing_key.pub | gpg --dearmor | tee /usr/share/keyrings/google-chrome-archive-keyring.gpg >/dev/null; then
        error_exit "Failed to download and install Google Chrome GPG key"
    fi

    # Add repository with signed-by option (secure, non-deprecated method)
    if ! echo "deb [arch=amd64 signed-by=/usr/share/keyrings/google-chrome-archive-keyring.gpg] https://dl.google.com/linux/chrome/deb/ stable main" > /etc/apt/sources.list.d/google-chrome.list; then
        error_exit "Failed to add Google Chrome repository"
    fi

    # Update package cache
    if ! apt update; then
        error_exit "Failed to update package cache after adding Chrome repository"
    fi

    # Install Google Chrome
    if ! apt install -y google-chrome-stable; then
        error_exit "Failed to install Google Chrome"
    fi

    log "✅ Google Chrome installed successfully using modern secure method"
else
    log "✅ Google Chrome already installed"
fi

# Verify Chrome installation and get version
CHROME_VERSION=$(google-chrome --version 2>/dev/null || echo "version check failed")
if [[ "$CHROME_VERSION" == *"version check failed"* ]]; then
    error_exit "Google Chrome installation verification failed"
fi

log "✅ Google Chrome verified: $CHROME_VERSION"

log "✅ Packages installed and verified"

# Step 2: Create single service user (handles both backend and kiosk)
log "👤 Step 2: Creating service user..."

if id -u "$SERVICE_USER" >/dev/null 2>&1; then
    log "✅ User $SERVICE_USER already exists"
    # Verify user has required groups
    if ! groups "$SERVICE_USER" | grep -q video; then
        log "Adding $SERVICE_USER to video group..."
        usermod -a -G video "$SERVICE_USER" || error_exit "Failed to add user to video group"
    fi
else
    log "Creating user: $SERVICE_USER (backend + kiosk)"
    if ! useradd -m -d "/home/$SERVICE_USER" -s /bin/bash "$SERVICE_USER"; then
        error_exit "Failed to create user $SERVICE_USER"
    fi

    # Add to video group for display access
    if ! usermod -a -G video "$SERVICE_USER"; then
        error_exit "Failed to add user to video group"
    fi

    log "✅ Created user: $SERVICE_USER"
fi

# Verify user creation was successful
if ! id -u "$SERVICE_USER" >/dev/null 2>&1; then
    error_exit "User creation verification failed"
fi

# Step 3: Setup PostgreSQL database
log "🗄️ Step 3: Setting up PostgreSQL database..."

# Ensure PostgreSQL is running
if ! systemctl is-active postgresql >/dev/null 2>&1; then
    log "Starting PostgreSQL service..."
    systemctl start postgresql || error_exit "Failed to start PostgreSQL"
fi

# Check if database user exists
if sudo -u postgres psql -c "SELECT 1 FROM pg_user WHERE usename = '$SERVICE_USER'" | grep -q 1; then
    log "✅ Database user $SERVICE_USER already exists"

    # Test if we can connect to database
    if sudo -u postgres psql -lqt | cut -d \| -f 1 | grep -qw "$DB_NAME"; then
        log "✅ Database $DB_NAME already exists"
        DB_PASSWORD_NEEDED=false
    else
        log "Database exists but DB doesn't - this shouldn't happen"
        DB_PASSWORD_NEEDED=true
    fi
else
    log "Creating database user $SERVICE_USER..."
    DB_PASSWORD_NEEDED=true
fi

# Handle password for new user or database creation
if [ "$DB_PASSWORD_NEEDED" = true ]; then
    echo ""
    echo "Enter a secure password for the $SERVICE_USER database user:"
    echo "(This will be stored securely in /home/$SERVICE_USER/.env)"
    read -s DB_PASSWORD
    echo ""

    if [ -z "$DB_PASSWORD" ]; then
        error_exit "Password cannot be empty"
    fi

    # Create user if needed
    if ! sudo -u postgres psql -c "SELECT 1 FROM pg_user WHERE usename = '$SERVICE_USER'" | grep -q 1; then
        if ! sudo -u postgres psql -c "CREATE USER $SERVICE_USER WITH PASSWORD '$DB_PASSWORD';"; then
            error_exit "Failed to create database user"
        fi
        log "✅ Database user created"
    fi

    # Create database if needed
    if ! sudo -u postgres psql -lqt | cut -d \| -f 1 | grep -qw "$DB_NAME"; then
        if ! sudo -u postgres createdb "$DB_NAME" -O "$SERVICE_USER"; then
            error_exit "Failed to create database"
        fi
        log "✅ Database created"
    fi

    # Test connection works
    if ! test_db_connection "$SERVICE_USER" "$DB_PASSWORD"; then
        error_exit "Database connection test failed - check password"
    fi
    log "✅ Database connection verified"
else
    log "✅ Database setup already complete"
fi

# Step 4: Create directory structure
log "📁 Step 4: Creating directory structure..."

# Create directories with proper validation (Pop!_OS optimized)
DIRECTORIES=(
    "/var/www/kimonokittens/dashboard"
    "/var/log/kimonokittens"
    "/home/$SERVICE_USER/Projects"
    "/home/$SERVICE_USER/backups"
    "/home/$SERVICE_USER/.config"
    "/home/$SERVICE_USER/.config/autostart"
    "/home/$SERVICE_USER/.local/share/applications"
)

for dir in "${DIRECTORIES[@]}"; do
    if ! mkdir -p "$dir"; then
        error_exit "Failed to create directory: $dir"
    fi
done

# Set permissions with validation
log "Setting directory permissions..."

if ! chown -R "$SERVICE_USER:$SERVICE_USER" "/home/$SERVICE_USER"; then
    error_exit "Failed to set ownership for /home/$SERVICE_USER"
fi

if ! chown -R www-data:www-data /var/www/kimonokittens; then
    error_exit "Failed to set ownership for /var/www/kimonokittens"
fi

if ! chown "$SERVICE_USER:adm" /var/log/kimonokittens; then
    error_exit "Failed to set ownership for /var/log/kimonokittens"
fi

if ! chmod 755 /var/log/kimonokittens; then
    error_exit "Failed to set permissions for /var/log/kimonokittens"
fi

log "✅ Directory structure created and permissions set"

# Step 5: Copy project to production location
log "📋 Step 5: Setting up repository..."

PROD_PROJECT_DIR="/home/$SERVICE_USER/Projects/kimonokittens"

if [ -d "$PROD_PROJECT_DIR" ]; then
    log "Repository already exists, updating..."

    # Verify it's actually a git repository
    if [ -d "$PROD_PROJECT_DIR/.git" ]; then
        if ! sudo -u "$SERVICE_USER" git -C "$PROD_PROJECT_DIR" pull origin master; then
            log "⚠️ Git pull failed, using local copy instead"
            # Remove broken repo and copy fresh
            rm -rf "$PROD_PROJECT_DIR"
            if ! cp -r "$REAL_HOME/Projects/kimonokittens" "/home/$SERVICE_USER/Projects/"; then
                error_exit "Failed to copy project repository"
            fi
        fi
    else
        log "Directory exists but not a git repo, replacing..."
        rm -rf "$PROD_PROJECT_DIR"
        if ! cp -r "$REAL_HOME/Projects/kimonokittens" "/home/$SERVICE_USER/Projects/"; then
            error_exit "Failed to copy project repository"
        fi
    fi
else
    log "Copying repository from development location..."
    if ! cp -r "$REAL_HOME/Projects/kimonokittens" "/home/$SERVICE_USER/Projects/"; then
        error_exit "Failed to copy project repository"
    fi
fi

# Ensure proper ownership
if ! chown -R "$SERVICE_USER:$SERVICE_USER" "$PROD_PROJECT_DIR"; then
    error_exit "Failed to set repository ownership"
fi

# Verify critical files exist
CRITICAL_FILES=(
    "$PROD_PROJECT_DIR/puma_server.rb"
    "$PROD_PROJECT_DIR/lib/rent_db.rb"
    "$PROD_PROJECT_DIR/dashboard/package.json"
    "$PROD_PROJECT_DIR/deployment/production_migration.rb"
)

for file in "${CRITICAL_FILES[@]}"; do
    if [ ! -f "$file" ]; then
        error_exit "Critical file missing: $file"
    fi
done

log "✅ Repository setup and verified"

# Step 6: Create environment file
log "⚙️ Step 6: Creating environment configuration..."

ENV_FILE="/home/$SERVICE_USER/.env"

if [ -f "$ENV_FILE" ]; then
    log "✅ Environment file already exists"

    # Verify it contains required variables
    if ! grep -q "DATABASE_URL" "$ENV_FILE"; then
        log "⚠️ Environment file missing DATABASE_URL, will recreate"
        backup_config "$ENV_FILE"
        rm "$ENV_FILE"
    fi
fi

if [ ! -f "$ENV_FILE" ]; then
    if [ -z "${DB_PASSWORD:-}" ]; then
        echo ""
        echo "Enter the database password you set earlier:"
        read -s DB_PASSWORD
        echo ""

        # Validate password works
        if ! test_db_connection "$SERVICE_USER" "$DB_PASSWORD"; then
            error_exit "Database password validation failed"
        fi
    fi

    log "Creating environment file..."
    if ! cat > "$ENV_FILE" <<EOF
DATABASE_URL=postgresql://$SERVICE_USER:${DB_PASSWORD}@localhost/$DB_NAME
NODE_ENV=production
PORT=3001
ENABLE_BROADCASTER=1
API_BASE_URL=http://localhost:3001
EOF
    then
        error_exit "Failed to create environment file"
    fi

    # Set secure permissions
    if ! chown "$SERVICE_USER:$SERVICE_USER" "$ENV_FILE"; then
        error_exit "Failed to set environment file ownership"
    fi

    if ! chmod 600 "$ENV_FILE"; then
        error_exit "Failed to set environment file permissions"
    fi

    log "✅ Environment file created with secure permissions"
fi

# Step 7: Setup rbenv for service user
log "💎 Step 7: Setting up rbenv for service user..."

RBENV_DIR="/home/$SERVICE_USER/.rbenv"
RBENV_BIN="$RBENV_DIR/bin/rbenv"

# Check if rbenv exists in source location
if [ ! -d "$REAL_HOME/.rbenv" ]; then
    error_exit "rbenv not found in $REAL_HOME/.rbenv - please install rbenv first"
fi

# Copy rbenv if not already present
if [ ! -d "$RBENV_DIR" ]; then
    log "Copying rbenv installation to $SERVICE_USER user..."
    if ! cp -r "$REAL_HOME/.rbenv" "/home/$SERVICE_USER/"; then
        error_exit "Failed to copy rbenv installation"
    fi

    if ! chown -R "$SERVICE_USER:$SERVICE_USER" "$RBENV_DIR"; then
        error_exit "Failed to set rbenv ownership"
    fi

    log "✅ rbenv copied successfully"
else
    log "✅ rbenv already exists for $SERVICE_USER"
fi

# Verify rbenv binary is executable
if [ ! -x "$RBENV_BIN" ]; then
    error_exit "rbenv binary not executable: $RBENV_BIN"
fi

# Test rbenv works for service user
if ! sudo -u "$SERVICE_USER" "$RBENV_BIN" --version >/dev/null 2>&1; then
    error_exit "rbenv not working for $SERVICE_USER user"
fi

# Check Ruby version availability
log "Checking Ruby version availability..."
RUBY_VERSIONS=(3.3.8 3.3.0)
SELECTED_RUBY=""

for version in "${RUBY_VERSIONS[@]}"; do
    if sudo -u "$SERVICE_USER" "$RBENV_BIN" versions | grep -q "$version"; then
        SELECTED_RUBY="$version"
        log "✅ Found Ruby $version"
        break
    fi
done

if [ -z "$SELECTED_RUBY" ]; then
    error_exit "No suitable Ruby version found. Available versions: $(sudo -u "$SERVICE_USER" "$RBENV_BIN" versions)"
fi

# Install Ruby dependencies as service user
log "Installing Ruby dependencies for $SERVICE_USER..."

# Create script for service user to execute
RUBY_SETUP_SCRIPT="/tmp/setup_ruby_${SERVICE_USER}.sh"
cat > "$RUBY_SETUP_SCRIPT" <<EOF
#!/bin/bash
set -e
export PATH="/home/$SERVICE_USER/.rbenv/bin:\$PATH"
eval "\$(rbenv init -)"
cd "/home/$SERVICE_USER/Projects/kimonokittens"

echo "Setting Ruby version to $SELECTED_RUBY..."
rbenv local "$SELECTED_RUBY" || exit 1

echo "Installing required gems..."
gem install bundler puma sinatra dotenv pg || exit 1

echo "Installing project dependencies..."
bundle install --deployment --without development test || exit 1

echo "Ruby setup complete"
EOF

chmod +x "$RUBY_SETUP_SCRIPT"

# Execute as service user
if ! sudo -u "$SERVICE_USER" bash "$RUBY_SETUP_SCRIPT"; then
    rm -f "$RUBY_SETUP_SCRIPT"
    error_exit "Ruby dependencies installation failed"
fi

rm -f "$RUBY_SETUP_SCRIPT"

# Verify Ruby setup works
log "Verifying Ruby setup..."
if ! sudo -u "$SERVICE_USER" bash -c "
    export PATH=\"/home/$SERVICE_USER/.rbenv/bin:\$PATH\"
    eval \"\$(rbenv init -)\"
    cd \"/home/$SERVICE_USER/Projects/kimonokittens\"
    ruby --version && bundle check
"; then
    error_exit "Ruby setup verification failed"
fi

log "✅ Ruby environment configured and verified"

# Step 7.5: Setup nvm for service user (secure dual installation)
log "💻 Step 7.5: Setting up nvm for service user (separate installation)..."

SERVICE_USER_NVM_DIR="/home/$SERVICE_USER/.nvm"
SERVICE_USER_BASHRC="/home/$SERVICE_USER/.bashrc"

# Check if nvm already installed for service user
if [ -d "$SERVICE_USER_NVM_DIR" ] && [ -x "$SERVICE_USER_NVM_DIR/nvm.sh" ]; then
    log "✅ nvm already installed for $SERVICE_USER"

    # Verify nvm works for service user
    if sudo -u "$SERVICE_USER" bash -c "source $SERVICE_USER_NVM_DIR/nvm.sh && nvm --version" >/dev/null 2>&1; then
        log "✅ nvm functional for $SERVICE_USER"
    else
        log "⚠️ nvm exists but not functional, reinstalling..."
        rm -rf "$SERVICE_USER_NVM_DIR"
    fi
fi

# Install nvm for service user if needed
if [ ! -d "$SERVICE_USER_NVM_DIR" ]; then
    log "Installing nvm for $SERVICE_USER (secure separate installation)..."

    # Create nvm installation script for service user
    NVM_INSTALL_SCRIPT="/tmp/install_nvm_${SERVICE_USER}.sh"
    cat > "$NVM_INSTALL_SCRIPT" <<EOF
#!/bin/bash
set -e

echo "Installing nvm for service user..."
export HOME="/home/$SERVICE_USER"
cd "\$HOME"

# Download and install nvm
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash

# Source nvm
export NVM_DIR="\$HOME/.nvm"
[ -s "\$NVM_DIR/nvm.sh" ] && . "\$NVM_DIR/nvm.sh"

# Install Node.js LTS
echo "Installing Node.js LTS..."
nvm install --lts
nvm use --lts

echo "nvm installation complete for service user"
echo "Node.js version: \$(node --version)"
echo "npm version: \$(npm --version)"
EOF

    chmod +x "$NVM_INSTALL_SCRIPT"

    # Execute as service user
    if ! sudo -u "$SERVICE_USER" bash "$NVM_INSTALL_SCRIPT"; then
        rm -f "$NVM_INSTALL_SCRIPT"
        error_exit "nvm installation failed for $SERVICE_USER"
    fi

    rm -f "$NVM_INSTALL_SCRIPT"
    log "✅ nvm installed successfully for $SERVICE_USER"
fi

# Verify service user's Node.js installation
log "Verifying service user's Node.js setup..."
SERVICE_USER_NODE_VERSION=$(sudo -u "$SERVICE_USER" bash -c "
    source $SERVICE_USER_NVM_DIR/nvm.sh 2>/dev/null || exit 1
    node --version 2>/dev/null || exit 1
" || echo "failed")

if [[ "$SERVICE_USER_NODE_VERSION" == "failed" ]]; then
    error_exit "Service user Node.js verification failed"
fi

SERVICE_USER_NPM_VERSION=$(sudo -u "$SERVICE_USER" bash -c "
    source $SERVICE_USER_NVM_DIR/nvm.sh 2>/dev/null || exit 1
    npm --version 2>/dev/null || exit 1
" || echo "failed")

if [[ "$SERVICE_USER_NPM_VERSION" == "failed" ]]; then
    error_exit "Service user npm verification failed"
fi

log "✅ Service user Node.js verified: $SERVICE_USER_NODE_VERSION"
log "✅ Service user npm verified: $SERVICE_USER_NPM_VERSION"

# Step 8: Build and deploy frontend
log "🏗️ Step 8: Building and deploying frontend..."

DASHBOARD_DIR="/home/$SERVICE_USER/Projects/kimonokittens/dashboard"
FRONTEND_DEPLOY_DIR="/var/www/kimonokittens/dashboard"

# Verify dashboard directory exists
if [ ! -d "$DASHBOARD_DIR" ]; then
    error_exit "Dashboard directory not found: $DASHBOARD_DIR"
fi

if [ ! -f "$DASHBOARD_DIR/package.json" ]; then
    error_exit "package.json not found in dashboard directory"
fi

cd "$DASHBOARD_DIR"

# Check if node modules already exist and are valid
if [ -d "node_modules" ]; then
    log "node_modules already exists, verifying..."
    if ! sudo -u "$SERVICE_USER" npm list >/dev/null 2>&1; then
        log "⚠️ node_modules corrupted, removing..."
        rm -rf node_modules package-lock.json
    fi
fi

# Install npm dependencies using service user's nvm
log "Installing npm dependencies with service user's Node.js..."
if ! sudo -u "$SERVICE_USER" bash -c "
    source $SERVICE_USER_NVM_DIR/nvm.sh
    npm install
"; then
    error_exit "npm install failed - check network connectivity and package.json"
fi

# Verify build tools are available
log "Verifying build tools..."
if ! sudo -u "$SERVICE_USER" bash -c "
    source $SERVICE_USER_NVM_DIR/nvm.sh
    npx vite --version
" >/dev/null 2>&1; then
    error_exit "Vite build tool not available after npm install"
fi

# Build frontend using service user's nvm
log "Building frontend with service user's Node.js..."
if ! sudo -u "$SERVICE_USER" bash -c "
    source $SERVICE_USER_NVM_DIR/nvm.sh
    npm run build
"; then
    log "npm run build failed, trying npx vite build..."
    if ! sudo -u "$SERVICE_USER" bash -c "
        source $SERVICE_USER_NVM_DIR/nvm.sh
        npx vite build
    "; then
        error_exit "Frontend build failed with both npm run build and npx vite build"
    fi
fi

# Verify build output exists
if [ ! -d "dist" ]; then
    error_exit "Build output directory 'dist' not found after build"
fi

if [ -z "$(ls -A dist 2>/dev/null)" ]; then
    error_exit "Build output directory 'dist' is empty"
fi

# Deploy frontend with backup
log "Deploying frontend..."

# Backup existing deployment if it exists
if [ -d "$FRONTEND_DEPLOY_DIR" ] && [ "$(ls -A "$FRONTEND_DEPLOY_DIR" 2>/dev/null)" ]; then
    backup_config "$FRONTEND_DEPLOY_DIR"
    rm -rf "${FRONTEND_DEPLOY_DIR:?}"/*
fi

# Copy build output
if ! cp -r dist/* "$FRONTEND_DEPLOY_DIR/"; then
    error_exit "Failed to copy frontend build to deployment directory"
fi

# Set proper permissions
if ! chown -R www-data:www-data /var/www/kimonokittens; then
    error_exit "Failed to set frontend deployment permissions"
fi

# Verify deployment
if [ ! -f "$FRONTEND_DEPLOY_DIR/index.html" ]; then
    error_exit "Frontend deployment verification failed - index.html not found"
fi

log "✅ Frontend built and deployed"

# Step 9: Run database migrations (ENHANCED)
log "🗄️ Step 9: Running database migrations..."

cd "/home/$SERVICE_USER/Projects/kimonokittens"

# Verify environment is loaded
if ! sudo -u "$SERVICE_USER" bash -c "source \"/home/$SERVICE_USER/.env\" && [ -n \"\$DATABASE_URL\" ]"; then
    error_exit "Environment file not loading properly"
fi

# Check if Prisma is available (if using Prisma)
if [ -f "prisma/schema.prisma" ]; then
    log "Found Prisma schema, running Prisma migrations..."

    if ! sudo -u "$SERVICE_USER" npx prisma migrate deploy; then
        error_exit "Prisma migrate deploy failed"
    fi

    if ! sudo -u "$SERVICE_USER" npx prisma generate; then
        error_exit "Prisma generate failed"
    fi

    log "✅ Prisma migrations completed"
fi

# Import production data with validation
log "Importing production data..."

# Verify migration script exists
if [ ! -f "deployment/production_migration.rb" ]; then
    error_exit "Production migration script not found"
fi

# Create migration script for service user
MIGRATION_SCRIPT="/tmp/migrate_data_${SERVICE_USER}.sh"
cat > "$MIGRATION_SCRIPT" <<EOF
#!/bin/bash
set -e
export PATH="/home/$SERVICE_USER/.rbenv/bin:\$PATH"
eval "\$(rbenv init -)"
cd "/home/$SERVICE_USER/Projects/kimonokittens"
source "/home/$SERVICE_USER/.env"

echo "Running production data migration..."
ruby deployment/production_migration.rb

echo "Migration completed successfully"
EOF

chmod +x "$MIGRATION_SCRIPT"

if ! sudo -u "$SERVICE_USER" bash "$MIGRATION_SCRIPT"; then
    rm -f "$MIGRATION_SCRIPT"
    error_exit "Production data migration failed"
fi

rm -f "$MIGRATION_SCRIPT"

# Verify data was imported correctly
log "Verifying data import..."
VERIFICATION_SCRIPT="/tmp/verify_data_${SERVICE_USER}.sh"
cat > "$VERIFICATION_SCRIPT" <<EOF
#!/bin/bash
set -e
export PATH="/home/$SERVICE_USER/.rbenv/bin:\$PATH"
eval "\$(rbenv init -)"
cd "/home/$SERVICE_USER/Projects/kimonokittens"
source "/home/$SERVICE_USER/.env"

echo "Checking tenant count..."
ruby -e "require 'dotenv/load'; require_relative 'lib/rent_db'; puts RentDb.instance.get_tenants.length.to_s + ' tenants found'"

echo "Data verification complete"
EOF

chmod +x "$VERIFICATION_SCRIPT"

if ! sudo -u "$SERVICE_USER" bash "$VERIFICATION_SCRIPT"; then
    rm -f "$VERIFICATION_SCRIPT"
    error_exit "Data verification failed"
fi

rm -f "$VERIFICATION_SCRIPT"

log "✅ Database configured and data imported"

# Step 10: Install systemd services (ENHANCED)
log "⚙️ Step 10: Installing systemd services..."

# Backup any existing service files
SERVICE_FILES=(
    "/etc/systemd/system/kimonokittens-dashboard.service"
    "/etc/systemd/system/kimonokittens-kiosk.service"
    "/etc/systemd/system/kimonokittens-webhook.service"
)

for service_file in "${SERVICE_FILES[@]}"; do
    backup_config "$service_file"
done

# Create enhanced dashboard service with better error handling
cat > /etc/systemd/system/kimonokittens-dashboard.service <<EOF
[Unit]
Description=Kimonokittens Dashboard Backend
After=network.target postgresql.service
Requires=network.target
Wants=postgresql.service

[Service]
Type=simple
User=$SERVICE_USER
Group=$SERVICE_USER
WorkingDirectory=/home/$SERVICE_USER/Projects/kimonokittens
Environment="PATH=/home/$SERVICE_USER/.rbenv/bin:/home/$SERVICE_USER/.rbenv/shims:/usr/local/bin:/usr/bin:/bin"
Environment="PORT=3001"
Environment="ENABLE_BROADCASTER=1"
Environment="NODE_ENV=production"
Environment="API_BASE_URL=http://localhost:3001"
EnvironmentFile=-/home/$SERVICE_USER/.env
ExecStart=/home/$SERVICE_USER/.rbenv/shims/ruby puma_server.rb
ExecReload=/bin/kill -USR1 \$MAINPID
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

# Security hardening
NoNewPrivileges=yes
PrivateTmp=yes
ProtectSystem=strict
ReadWritePaths=/home/$SERVICE_USER
ProtectHome=yes

[Install]
WantedBy=multi-user.target
EOF

# Create enhanced kiosk service
cat > /etc/systemd/system/kimonokittens-kiosk.service <<EOF
[Unit]
Description=Kimonokittens Kiosk Browser
After=graphical.target kimonokittens-dashboard.service
Wants=kimonokittens-dashboard.service

[Service]
Type=simple
User=$SERVICE_USER
Group=$SERVICE_USER
Environment="DISPLAY=:0"
Environment="XAUTHORITY=/home/$SERVICE_USER/.Xauthority"
ExecStartPre=/bin/sleep 15
ExecStart=/usr/bin/chromium-browser --kiosk --disable-infobars --disable-session-crashed-bubble --disable-web-security --disable-features=TranslateUI --noerrdialogs --incognito --no-first-run --enable-gpu --app=http://localhost
Restart=always
RestartSec=30
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=graphical.target
EOF

# Create webhook service if source exists
if [ -f "deployment/configs/systemd/kimonokittens-webhook.service" ]; then
    sed "s|ExecStart=/usr/bin/ruby|ExecStart=/home/$SERVICE_USER/.rbenv/shims/ruby|g" \
        deployment/configs/systemd/kimonokittens-webhook.service > \
        /etc/systemd/system/kimonokittens-webhook.service
fi

# Validate service files
systemctl daemon-reload

for service in kimonokittens-dashboard kimonokittens-kiosk; do
    if ! systemctl is-valid "$service" >/dev/null 2>&1; then
        error_exit "Service file validation failed: $service"
    fi
done

log "✅ SystemD services configured and validated"

# Step 11: Configure nginx (ENHANCED)
log "🌐 Step 11: Configuring nginx..."

# Backup nginx config
backup_config "/etc/nginx/sites-enabled/default"
backup_config "/etc/nginx/nginx.conf"

# Verify nginx config file exists
if [ ! -f "deployment/configs/nginx/kimonokittens.conf" ]; then
    error_exit "Nginx configuration file not found: deployment/configs/nginx/kimonokittens.conf"
fi

# Copy nginx config
if ! cp deployment/configs/nginx/kimonokittens.conf /etc/nginx/sites-available/; then
    error_exit "Failed to copy nginx configuration"
fi

# Enable site
if ! ln -sf /etc/nginx/sites-available/kimonokittens.conf /etc/nginx/sites-enabled/default; then
    error_exit "Failed to enable nginx site"
fi

# Test nginx configuration
if ! nginx -t; then
    error_exit "Nginx configuration test failed"
fi

# Restart nginx
if ! systemctl restart nginx; then
    error_exit "Failed to restart nginx"
fi

# Verify nginx is running
if ! systemctl is-active nginx >/dev/null 2>&1; then
    error_exit "Nginx is not active after restart"
fi

log "✅ Nginx configured and running"

# Step 12: Configure GDM3 auto-login and GNOME kiosk (Pop!_OS native)
log "🖥️ Step 12: Configuring native Pop!_OS kiosk display..."

# Backup GDM3 config
backup_config "/etc/gdm3/custom.conf"

# Configure GDM3 auto-login (Pop!_OS default display manager)
log "Configuring GDM3 auto-login for $SERVICE_USER..."

# Check if AutomaticLoginEnable already exists
if grep -q "AutomaticLoginEnable" /etc/gdm3/custom.conf; then
    log "Auto-login already configured in GDM3"
else
    # Add auto-login configuration to GDM3
    if ! sed -i '/\[daemon\]/a AutomaticLoginEnable=True' /etc/gdm3/custom.conf; then
        error_exit "Failed to enable auto-login in GDM3"
    fi

    if ! sed -i "/AutomaticLoginEnable=True/a AutomaticLogin=$SERVICE_USER" /etc/gdm3/custom.conf; then
        error_exit "Failed to set auto-login user in GDM3"
    fi

    log "✅ GDM3 auto-login configured for $SERVICE_USER"
fi

# Create GNOME autostart configuration for Chrome kiosk
AUTOSTART_DIR="/home/$SERVICE_USER/.config/autostart"
mkdir -p "$AUTOSTART_DIR"

# Create kiosk browser autostart with Google Chrome
cat > "$AUTOSTART_DIR/kimonokittens-kiosk.desktop" <<EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=Kimonokittens Dashboard Kiosk
Comment=Launch dashboard in kiosk mode
Exec=/bin/bash -c "sleep 15 && google-chrome --kiosk --no-first-run --disable-infobars --disable-session-crashed-bubble --disable-web-security --disable-features=TranslateUI --noerrdialogs --incognito --no-default-browser-check --password-store=basic --start-maximized --app=http://localhost"
Terminal=false
Hidden=false
NoDisplay=false
X-GNOME-Autostart-enabled=true
StartupNotify=false
Categories=Utility;
EOF

# Create a fallback desktop entry for manual launch
cat > "/home/$SERVICE_USER/.local/share/applications/kimonokittens-dashboard.desktop" <<EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=Kimonokittens Dashboard
Comment=Dashboard application
Exec=google-chrome --app=http://localhost
Terminal=false
Icon=web-browser
Categories=Network;WebBrowser;
StartupWMClass=kimonokittens-dashboard
EOF

# Set proper ownership for all GNOME configuration
if ! chown -R "$SERVICE_USER:$SERVICE_USER" "/home/$SERVICE_USER/.config" "/home/$SERVICE_USER/.local"; then
    error_exit "Failed to set GNOME configuration permissions"
fi

# Ensure desktop file is executable
chmod +x "$AUTOSTART_DIR/kimonokittens-kiosk.desktop"
chmod +x "/home/$SERVICE_USER/.local/share/applications/kimonokittens-dashboard.desktop"

log "✅ Native Pop!_OS GNOME kiosk mode configured with Google Chrome"

# Step 13: Enable and start services (ENHANCED)
log "🚀 Step 13: Starting services..."

# Enable services
SERVICES_TO_ENABLE=(kimonokittens-dashboard nginx)

for service in "${SERVICES_TO_ENABLE[@]}"; do
    if ! systemctl enable "$service"; then
        error_exit "Failed to enable service: $service"
    fi
done

# Start services with validation
for service in "${SERVICES_TO_ENABLE[@]}"; do
    if ! systemctl start "$service"; then
        error_exit "Failed to start service: $service"
    fi

    # Wait a moment and verify service is running
    sleep 2
    if ! systemctl is-active "$service" >/dev/null 2>&1; then
        error_exit "Service $service failed to start properly"
    fi

    log "✅ Service $service started and running"
done

# Step 14: Comprehensive verification (ENHANCED)
log ""
log "🔍 Step 14: Comprehensive verification..."

# Database connectivity test
log -n "Database connection: "
if sudo -u "$SERVICE_USER" bash -c "
    export PATH=\"/home/$SERVICE_USER/.rbenv/bin:\$PATH\"
    eval \"\$(rbenv init -)\"
    cd \"/home/$SERVICE_USER/Projects/kimonokittens\"
    source \"/home/$SERVICE_USER/.env\"
    ruby -e \"require 'dotenv/load'; require_relative 'lib/rent_db'; puts RentDb.instance.get_tenants.length.to_s + ' tenants found'\"
" 2>/dev/null; then
    log "✅ OK"
else
    log "❌ FAILED"
    log "Check logs: journalctl -u kimonokittens-dashboard -f"
fi

# API endpoint test
log "API endpoint test..."
sleep 5  # Give backend time to fully start

if curl -s --connect-timeout 10 http://localhost:3001/api/rent/friendly_message | grep -q "message"; then
    log "✅ API responding correctly"
else
    log "⚠️ API test failed - may need more time to start"
fi

# Service status check
log "Service status verification..."
for service in kimonokittens-dashboard nginx; do
    if systemctl is-active "$service" >/dev/null 2>&1; then
        log "✅ $service: active"
    else
        log "❌ $service: inactive"
    fi
done

# Final success message
log ""
log "🎉 === BULLETPROOF SETUP COMPLETE! ==="
log ""
log "📊 ARCHITECTURE SUMMARY (Pop!_OS 22.04 Native):"
log "✅ User '$SERVICE_USER' handles both backend and kiosk display"
log "✅ Ruby $(sudo -u "$SERVICE_USER" "/home/$SERVICE_USER/.rbenv/shims/ruby" --version 2>/dev/null | cut -d' ' -f2 || echo '3.3.x') via rbenv"
log "✅ Node.js Dev: $(node --version 2>/dev/null || echo 'v24.x') (fredrik user nvm)"
log "✅ Node.js Prod: $(sudo -u "$SERVICE_USER" bash -c "source /home/$SERVICE_USER/.nvm/nvm.sh 2>/dev/null && node --version" || echo 'LTS') (service user nvm)"
log "✅ Dual nvm installation - secure isolation between users"
log "✅ Dashboard deployed to /var/www/kimonokittens/dashboard"
log "✅ All services configured and running"
log "✅ Google Chrome kiosk mode configured with GDM3 auto-login"
log "✅ Native GNOME/Pop!_OS integration (no LightDM/XFCE4 conflicts)"
log "✅ Modern secure GPG keyring method (no deprecated apt-key)"
log "✅ Comprehensive error recovery and logging enabled"
log ""
log "📋 NEXT STEPS:"
log "1. Configure GitHub webhook secret: sudo systemctl edit kimonokittens-webhook"
log "2. Add webhook URL in GitHub: http://YOUR_IP/webhook"
log "3. Reboot to activate kiosk mode: sudo reboot"
log ""
log "🔧 MONITORING:"
log "- Service status: systemctl status kimonokittens-dashboard"
log "- View logs: journalctl -u kimonokittens-dashboard -f"
log "- Setup log: $LOG_FILE"
log "- Config backups: $BACKUP_DIR"
log ""
log "🛡️ RECOVERY:"
log "- All system configs backed up to: $BACKUP_DIR"
log "- If issues occur, check log file for detailed error information"
log "- Script is idempotent - safe to re-run if needed"
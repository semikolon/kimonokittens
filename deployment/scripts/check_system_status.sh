#!/bin/bash
# System status checker for production deployment

echo "=== Dell Optiplex Production Deployment Status ==="
echo ""

# Function to check if command exists
check_command() {
    if command -v "$1" >/dev/null 2>&1; then
        echo "✅ $1 is installed"
        return 0
    else
        echo "❌ $1 is NOT installed"
        return 1
    fi
}

# Function to check if service exists
check_service() {
    if systemctl list-unit-files | grep -q "$1"; then
        echo "✅ $1 service is configured"
        return 0
    else
        echo "❌ $1 service is NOT configured"
        return 1
    fi
}

# Function to check if user exists
check_user() {
    if id "$1" >/dev/null 2>&1; then
        echo "✅ User $1 exists"
        return 0
    else
        echo "❌ User $1 does NOT exist"
        return 1
    fi
}

# Function to check if directory exists
check_directory() {
    if [ -d "$1" ]; then
        echo "✅ Directory $1 exists"
        return 0
    else
        echo "❌ Directory $1 does NOT exist"
        return 1
    fi
}

echo "📦 PACKAGE INSTALLATION STATUS:"
check_command postgresql
check_command psql
check_command nginx
check_command ruby
check_command chromium-browser
check_command systemctl

echo ""
echo "👥 USER ACCOUNTS:"
check_user kimonokittens
check_user kiosk

echo ""
echo "📁 DIRECTORY STRUCTURE:"
check_directory /var/www/kimonokittens
check_directory /var/log/kimonokittens
check_directory /home/kimonokittens/Projects/kimonokittens

echo ""
echo "⚙️ SYSTEM SERVICES:"
check_service kimonokittens-dashboard
check_service nginx

echo ""
echo "🗄️ DATABASE STATUS:"
if command -v psql >/dev/null 2>&1; then
    if sudo -u postgres psql -c "SELECT 1 FROM pg_user WHERE usename = 'kimonokittens'" 2>/dev/null | grep -q 1; then
        echo "✅ PostgreSQL user 'kimonokittens' exists"
    else
        echo "❌ PostgreSQL user 'kimonokittens' does NOT exist"
    fi

    if sudo -u postgres psql -l | grep -q kimonokittens_production; then
        echo "✅ Database 'kimonokittens_production' exists"
    else
        echo "❌ Database 'kimonokittens_production' does NOT exist"
    fi
else
    echo "❌ PostgreSQL not installed, cannot check database"
fi

echo ""
echo "🌐 NGINX STATUS:"
if [ -f /etc/nginx/sites-enabled/kimonokittens.conf ]; then
    echo "✅ Nginx configuration is enabled"
else
    echo "❌ Nginx configuration is NOT enabled"
fi

echo ""
echo "🖥️ KIOSK CONFIGURATION:"
if grep -q "autologin-user=kiosk" /etc/lightdm/lightdm.conf 2>/dev/null; then
    echo "✅ Kiosk autologin is configured"
else
    echo "❌ Kiosk autologin is NOT configured"
fi

echo ""
echo "📂 PROJECT FILES:"
if [ -f /home/fredrik/Projects/kimonokittens/dashboard/dist/index.html ]; then
    echo "✅ Dashboard is built"
else
    echo "❌ Dashboard is NOT built"
fi

if [ -f /home/fredrik/Projects/kimonokittens/deployment/production_migration.rb ]; then
    echo "✅ Migration scripts are ready"
else
    echo "❌ Migration scripts are NOT ready"
fi

echo ""
echo "🔧 RUBY ENVIRONMENT:"
if RBENV_ROOT=~/.rbenv ~/.rbenv/bin/rbenv exec ruby --version 2>/dev/null | grep -q "ruby 3.3"; then
    echo "✅ Ruby 3.3.x is available"
else
    echo "❌ Ruby 3.3.x is NOT available"
fi

if RBENV_ROOT=~/.rbenv ~/.rbenv/bin/rbenv exec bundle check >/dev/null 2>&1; then
    echo "✅ Ruby dependencies are installed"
else
    echo "❌ Ruby dependencies are NOT installed"
fi

echo ""
echo "=== DEPLOYMENT READINESS SUMMARY ==="

# Count what's ready vs what's needed
ready_count=0
total_count=15  # Approximate number of checks

# Quick overall assessment
if command -v postgresql >/dev/null 2>&1 && command -v nginx >/dev/null 2>&1; then
    echo "🟢 BASIC PACKAGES: Ready"
    ((ready_count++))
else
    echo "🔴 BASIC PACKAGES: Need installation"
fi

if id kimonokittens >/dev/null 2>&1 && id kiosk >/dev/null 2>&1; then
    echo "🟢 USER ACCOUNTS: Ready"
    ((ready_count++))
else
    echo "🔴 USER ACCOUNTS: Need creation"
fi

if [ -d /var/www/kimonokittens ] && [ -d /var/log/kimonokittens ]; then
    echo "🟢 DIRECTORIES: Ready"
    ((ready_count++))
else
    echo "🔴 DIRECTORIES: Need creation"
fi

echo ""
if [ $ready_count -eq 3 ]; then
    echo "🎉 SYSTEM IS PRODUCTION READY!"
    echo "Run: sudo systemctl start kimonokittens-dashboard nginx"
else
    echo "⚠️  SETUP REQUIRED"
    echo "Follow the commands in: deployment/MANUAL_SETUP_COMMANDS.md"
fi

echo ""
echo "Next steps:"
echo "1. Run manual setup commands if needed"
echo "2. Configure GitHub webhook"
echo "3. sudo reboot (to activate kiosk mode)"
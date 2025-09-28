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

# Set correct permissions
log "Setting file permissions"
chown -R www-data:www-data "$WEB_ROOT"
chmod -R 755 "$WEB_ROOT"

# Restart backend services
log "Restarting backend services"
systemctl restart kimonokittens-dashboard
systemctl restart kimonokittens-webhook || true

# Wait for services to start
sleep 5

# Health check
log "Performing health checks"
if curl -f http://localhost:3001/health > /dev/null 2>&1; then
    log "Dashboard backend: OK"
else
    log "WARNING: Dashboard backend health check failed"
fi

# Signal browser to refresh
log "Signaling browser refresh"
echo "$(date +%s)" > /tmp/kimonokittens-updated

# Cleanup old backups (keep last 5)
log "Cleaning up old backups"
ls -t "$BACKUP_DIR" | tail -n +6 | xargs -r -I {} rm -rf "$BACKUP_DIR/{}"

log "=== Deployment completed successfully ==="
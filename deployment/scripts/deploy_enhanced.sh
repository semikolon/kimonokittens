#!/bin/bash
# Enhanced deployment script with multiple deployment strategies

set -e

# Configuration
REPO_DIR="/home/kimonokittens/Projects/kimonokittens"
WEB_ROOT="/var/www/kimonokittens"
LOG_FILE="/var/log/kimonokittens/deploy.log"
BACKUP_DIR="/home/kimonokittens/backups"
LOCK_FILE="/tmp/kimonokittens-deploy.lock"

# Parse command line arguments
FULL_DEPLOY=false
TAG=""
SKIP_TESTS=false
SKIP_BACKUP=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --full)
            FULL_DEPLOY=true
            shift
            ;;
        --tag)
            TAG="$2"
            shift 2
            ;;
        --skip-tests)
            SKIP_TESTS=true
            shift
            ;;
        --skip-backup)
            SKIP_BACKUP=true
            shift
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Logging function with levels
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$1] $2" | tee -a "$LOG_FILE"
}

# Check for concurrent deployments
acquire_lock() {
    local timeout=60
    local elapsed=0

    while [ -f "$LOCK_FILE" ] && [ $elapsed -lt $timeout ]; do
        log "WARN" "Another deployment is running, waiting..."
        sleep 5
        elapsed=$((elapsed + 5))
    done

    if [ -f "$LOCK_FILE" ]; then
        log "ERROR" "Timeout waiting for deployment lock"
        exit 1
    fi

    echo $$ > "$LOCK_FILE"
}

release_lock() {
    rm -f "$LOCK_FILE"
}

# Error handling with rollback
cleanup() {
    local exit_code=$?
    if [ $exit_code -ne 0 ]; then
        log "ERROR" "Deploy failed with exit code $exit_code"

        # Attempt rollback
        if [ -n "$BACKUP_NAME" ] && [ -d "$BACKUP_DIR/$BACKUP_NAME" ]; then
            log "INFO" "Attempting rollback to $BACKUP_NAME"
            rsync -av --delete "$BACKUP_DIR/$BACKUP_NAME/" "$WEB_ROOT/"
            systemctl restart kimonokittens-dashboard
            log "INFO" "Rollback completed"
        fi
    fi

    release_lock
}
trap cleanup EXIT

# Main deployment starts here
log "INFO" "=== Starting deployment ==="
acquire_lock

cd "$REPO_DIR"

# Store current version for rollback
CURRENT_VERSION=$(git rev-parse HEAD)
log "INFO" "Current version: $CURRENT_VERSION"

# Create backup unless skipped
if [ "$SKIP_BACKUP" = false ]; then
    BACKUP_NAME="backup-$(date +%Y%m%d-%H%M%S)-${CURRENT_VERSION:0:7}"
    log "INFO" "Creating backup: $BACKUP_NAME"
    mkdir -p "$BACKUP_DIR"
    cp -r "$WEB_ROOT" "$BACKUP_DIR/$BACKUP_NAME" || true
fi

# Pull latest code
log "INFO" "Pulling latest code from GitHub"
git fetch origin

if [ -n "$TAG" ]; then
    log "INFO" "Checking out tag: $TAG"
    git checkout "tags/$TAG"
elif [ "$FULL_DEPLOY" = true ]; then
    log "INFO" "Full deployment - resetting to origin/master"
    git reset --hard origin/master
    git clean -fd
else
    log "INFO" "Fast deployment - pulling changes"
    git pull origin master
fi

NEW_VERSION=$(git rev-parse HEAD)
log "INFO" "New version: $NEW_VERSION"

# Check if there are actual changes
if [ "$CURRENT_VERSION" = "$NEW_VERSION" ] && [ "$FULL_DEPLOY" = false ]; then
    log "INFO" "No changes detected, skipping deployment"
    exit 0
fi

# Run database migrations if needed
if git diff --name-only "$CURRENT_VERSION" "$NEW_VERSION" | grep -q "prisma/schema.prisma"; then
    log "INFO" "Database schema changed, running migrations"
    npx prisma migrate deploy
    npx prisma generate
fi

# Check what changed
FRONTEND_CHANGED=false
BACKEND_CHANGED=false

if git diff --name-only "$CURRENT_VERSION" "$NEW_VERSION" | grep -q "^dashboard/"; then
    FRONTEND_CHANGED=true
fi

if git diff --name-only "$CURRENT_VERSION" "$NEW_VERSION" | grep -E "\.rb$|^lib/|^handlers/|Gemfile"; then
    BACKEND_CHANGED=true
fi

# Update dependencies if needed
if [ "$BACKEND_CHANGED" = true ] || [ "$FULL_DEPLOY" = true ]; then
    log "INFO" "Installing Ruby dependencies"
    bundle install --deployment --without development test
fi

# Build and deploy frontend if needed
if [ "$FRONTEND_CHANGED" = true ] || [ "$FULL_DEPLOY" = true ]; then
    log "INFO" "Building dashboard frontend"
    cd "$REPO_DIR/dashboard"

    # Check if package.json changed
    if git diff --name-only "$CURRENT_VERSION" "$NEW_VERSION" | grep -q "dashboard/package.json"; then
        log "INFO" "Package.json changed, running clean install"
        rm -rf node_modules
        npm ci --production
    fi

    # Build frontend
    npm run build || npx vite build

    # Run tests unless skipped
    if [ "$SKIP_TESTS" = false ] && [ -f "package.json" ] && grep -q "\"test\"" package.json; then
        log "INFO" "Running frontend tests"
        npm test --if-present || log "WARN" "Frontend tests failed or not configured"
    fi

    # Deploy frontend
    log "INFO" "Deploying dashboard build"
    mkdir -p "$WEB_ROOT/dashboard"
    rsync -av --delete dist/ "$WEB_ROOT/dashboard/"
fi

# Set correct permissions
log "INFO" "Setting file permissions"
chown -R www-data:www-data "$WEB_ROOT"
chmod -R 755 "$WEB_ROOT"

# Restart services if backend changed
if [ "$BACKEND_CHANGED" = true ] || [ "$FULL_DEPLOY" = true ]; then
    log "INFO" "Restarting backend services"
    systemctl restart kimonokittens-dashboard

    # Also restart webhook if it changed
    if git diff --name-only "$CURRENT_VERSION" "$NEW_VERSION" | grep -q "webhook"; then
        systemctl restart kimonokittens-webhook || true
    fi
fi

# Wait for services to start
sleep 5

# Health checks
log "INFO" "Performing health checks"
HEALTH_CHECK_PASSED=true

# Backend health check
if curl -f -s http://localhost:3001/health > /dev/null 2>&1; then
    log "INFO" "Dashboard backend: OK"
else
    log "ERROR" "Dashboard backend health check failed"
    HEALTH_CHECK_PASSED=false
fi

# API functionality check
if curl -f -s http://localhost:3001/api/rent/friendly_message | grep -q "message"; then
    log "INFO" "API endpoint: OK"
else
    log "ERROR" "API endpoint check failed"
    HEALTH_CHECK_PASSED=false
fi

# Frontend check
if curl -f -s http://localhost/ | grep -q "</html>"; then
    log "INFO" "Frontend: OK"
else
    log "ERROR" "Frontend check failed"
    HEALTH_CHECK_PASSED=false
fi

# Fail deployment if health checks failed
if [ "$HEALTH_CHECK_PASSED" = false ]; then
    log "ERROR" "Health checks failed - deployment unsuccessful"
    exit 1
fi

# Signal browser to refresh
log "INFO" "Signaling browser refresh"
echo "$(date +%s)" > /tmp/kimonokittens-updated

# WebSocket notification for immediate refresh
if command -v node >/dev/null 2>&1; then
    node -e "
    const ws = require('ws');
    const wss = new ws.WebSocket('ws://localhost:3001');
    wss.on('open', () => {
        wss.send(JSON.stringify({ type: 'deployment_complete' }));
        wss.close();
    });
    " 2>/dev/null || true
fi

# Cleanup old backups (keep last 10)
if [ "$SKIP_BACKUP" = false ]; then
    log "INFO" "Cleaning up old backups"
    ls -t "$BACKUP_DIR" | tail -n +11 | xargs -r -I {} rm -rf "$BACKUP_DIR/{}"
fi

# Log deployment metrics
DEPLOY_TIME=$(($(date +%s) - $(stat -c %Y "$LOCK_FILE")))
log "INFO" "Deployment completed in ${DEPLOY_TIME} seconds"
log "INFO" "=== Deployment completed successfully ==="

# Create deployment record
cat >> /var/log/kimonokittens/deployments.json <<EOF
{"timestamp":"$(date -Iseconds)","from":"$CURRENT_VERSION","to":"$NEW_VERSION","duration":$DEPLOY_TIME,"success":true}
EOF
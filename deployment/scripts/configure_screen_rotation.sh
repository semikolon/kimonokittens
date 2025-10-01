#!/bin/bash
# Screen Rotation Configuration Script for Pop!_OS GDM3
# Applies screen rotation to GDM3 login screen and all users

set -e  # Exit on any error

# Configuration
SERVICE_USER="${1:-kimonokittens}"
USER_HOME="/home/$SERVICE_USER"
MONITORS_CONFIG="$USER_HOME/.config/monitors.xml"
GDM_CONFIG_DIR="/var/lib/gdm3/.config"
GDM_MONITORS_CONFIG="$GDM_CONFIG_DIR/monitors.xml"

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] WARNING:${NC} $1"
}

error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1"
    exit 1
}

# Check if running with sudo
if [ "$EUID" -ne 0 ]; then
    error "Please run this script with sudo"
fi

log "=== Screen Rotation Configuration for Pop!_OS ==="
log "Configuring for user: $SERVICE_USER"
log ""

# Step 1: Check if user's monitors.xml exists
log "Checking for user monitor configuration..."

if [ ! -f "$MONITORS_CONFIG" ]; then
    error "Monitor configuration not found: $MONITORS_CONFIG

Please configure screen rotation first:
  1. Log in as $SERVICE_USER
  2. Open Settings → Displays
  3. Set Orientation to 'Portrait Right' (90° clockwise)
  4. Click Apply and Keep Changes
  5. Then run this script again: sudo $0

This will create $MONITORS_CONFIG which this script will copy to GDM3."
fi

log "✅ Found user monitor configuration"

# Step 2: Display monitor configuration info
log ""
log "Current monitor configuration:"
if grep -q "rotation" "$MONITORS_CONFIG"; then
    ROTATION=$(grep -oP '(?<=<rotation>)[^<]+' "$MONITORS_CONFIG" | head -1)
    log "  Rotation: $ROTATION"

    # Decode rotation value
    case "$ROTATION" in
        "0") log "  Mode: Normal (0°)" ;;
        "1") log "  Mode: Portrait Left (90° counter-clockwise)" ;;
        "2") log "  Mode: Inverted (180°)" ;;
        "3") log "  Mode: Portrait Right (90° clockwise)" ;;
        *) log "  Mode: Unknown ($ROTATION)" ;;
    esac
else
    log "  Rotation: Normal (not explicitly set)"
fi

# Step 3: Create GDM config directory if needed
log ""
log "Preparing GDM3 configuration directory..."
mkdir -p "$GDM_CONFIG_DIR"
log "✅ GDM3 config directory ready"

# Step 4: Backup existing GDM monitors config if exists
if [ -f "$GDM_MONITORS_CONFIG" ]; then
    BACKUP_FILE="$GDM_MONITORS_CONFIG.backup.$(date +%Y%m%d_%H%M%S)"
    log "Backing up existing GDM monitor config to: $BACKUP_FILE"
    cp "$GDM_MONITORS_CONFIG" "$BACKUP_FILE"
fi

# Step 5: Copy user's monitor config to GDM
log ""
log "Applying monitor configuration to GDM3..."
cp "$MONITORS_CONFIG" "$GDM_MONITORS_CONFIG"

# Set proper ownership (gdm user must own the file)
chown gdm:gdm "$GDM_MONITORS_CONFIG"
chmod 644 "$GDM_MONITORS_CONFIG"

log "✅ Monitor configuration copied to GDM3"

# Step 6: Verify
log ""
log "Verifying GDM3 configuration..."

if [ -f "$GDM_MONITORS_CONFIG" ] && [ -r "$GDM_MONITORS_CONFIG" ]; then
    if [ "$(stat -c '%U' "$GDM_MONITORS_CONFIG")" = "gdm" ]; then
        log "✅ GDM3 configuration verified"
    else
        warn "Configuration file exists but ownership is incorrect"
    fi
else
    error "GDM3 configuration file not readable"
fi

# Step 7: Instructions for applying changes
log ""
log "🎉 Screen rotation configured successfully!"
log ""
log "Configuration applied to:"
log "  ✅ User $SERVICE_USER session"
log "  ✅ GDM3 login screen"
log "  ✅ All future user sessions"
log ""
log "⚠️  To apply changes, you must restart GDM3:"
log ""
log "  sudo systemctl restart gdm3"
log ""
log "WARNING: This will close all graphical sessions!"
log "         Save your work before running this command."
log ""

#!/bin/bash
# Kiosk Power Management Configuration Script
# Disables screen blanking, dimming, screensaver, and lock screen for 24/7 kiosk display

set -e  # Exit on any error

# Configuration
SERVICE_USER="${1:-kimonokittens}"
USER_HOME="/home/$SERVICE_USER"

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

log "=== Kiosk Power Management Configuration ==="
log "Configuring for user: $SERVICE_USER"
log ""

# Check if user exists
if ! id -u "$SERVICE_USER" >/dev/null 2>&1; then
    error "User $SERVICE_USER does not exist"
fi

# Get user's UID for proper dbus/runtime directory
USER_UID=$(id -u "$SERVICE_USER")
USER_RUNTIME_DIR="/run/user/$USER_UID"

if [ ! -d "$USER_RUNTIME_DIR" ]; then
    warn "User runtime directory not found. User may need to log in at least once."
    error "Cannot configure settings without active user session"
fi

log "User runtime directory: $USER_RUNTIME_DIR"

# Function to run gsettings as the service user
run_gsettings() {
    local schema="$1"
    local key="$2"
    local value="$3"

    sudo -u "$SERVICE_USER" \
        DBUS_SESSION_BUS_ADDRESS="unix:path=$USER_RUNTIME_DIR/bus" \
        XDG_RUNTIME_DIR="$USER_RUNTIME_DIR" \
        gsettings set "$schema" "$key" "$value"
}

# Function to verify gsettings
verify_gsettings() {
    local schema="$1"
    local key="$2"
    local expected="$3"

    local actual=$(sudo -u "$SERVICE_USER" \
        DBUS_SESSION_BUS_ADDRESS="unix:path=$USER_RUNTIME_DIR/bus" \
        XDG_RUNTIME_DIR="$USER_RUNTIME_DIR" \
        gsettings get "$schema" "$key")

    if [ "$actual" = "$expected" ]; then
        log "  ✅ $schema.$key = $expected"
        return 0
    else
        warn "  ❌ $schema.$key = $actual (expected $expected)"
        return 1
    fi
}

log ""
log "Configuring power management settings..."

# Disable screen blanking and sleep
log ""
log "1. Disabling screen blank and sleep..."
run_gsettings org.gnome.desktop.session idle-delay "uint32 0"
run_gsettings org.gnome.settings-daemon.plugins.power sleep-inactive-ac-type "'nothing'"
run_gsettings org.gnome.settings-daemon.plugins.power sleep-inactive-battery-type "'nothing'"

# Disable idle dimming
log ""
log "2. Disabling automatic brightness dimming..."
run_gsettings org.gnome.settings-daemon.plugins.power idle-dim false
run_gsettings org.gnome.settings-daemon.plugins.power idle-brightness 100

# Disable screensaver
log ""
log "3. Disabling screensaver..."
run_gsettings org.gnome.desktop.screensaver idle-activation-enabled false
run_gsettings org.gnome.desktop.screensaver lock-enabled false
run_gsettings org.gnome.desktop.screensaver lock-delay "uint32 0"

# Disable automatic screen lock
log ""
log "4. Disabling automatic screen lock..."
run_gsettings org.gnome.desktop.lockdown disable-lock-screen true

# Disable power button action (prevent accidental shutdown)
log ""
log "5. Configuring power button (suspend instead of shutdown)..."
run_gsettings org.gnome.settings-daemon.plugins.power power-button-action "'suspend'"

# Set screen brightness to max (if possible)
log ""
log "6. Setting screen brightness..."
run_gsettings org.gnome.settings-daemon.plugins.power ambient-enabled false

# Disable automatic suspend
log ""
log "7. Disabling automatic suspend..."
run_gsettings org.gnome.settings-daemon.plugins.power sleep-inactive-ac-timeout 0
run_gsettings org.gnome.settings-daemon.plugins.power sleep-inactive-battery-timeout 0

log ""
log "✅ Power management configuration complete!"

# Verification
log ""
log "Verifying settings..."
VERIFY_PASS=true

verify_gsettings org.gnome.desktop.session idle-delay "uint32 0" || VERIFY_PASS=false
verify_gsettings org.gnome.settings-daemon.plugins.power sleep-inactive-ac-type "'nothing'" || VERIFY_PASS=false
verify_gsettings org.gnome.settings-daemon.plugins.power idle-dim "false" || VERIFY_PASS=false
verify_gsettings org.gnome.desktop.screensaver idle-activation-enabled "false" || VERIFY_PASS=false
verify_gsettings org.gnome.desktop.screensaver lock-enabled "false" || VERIFY_PASS=false
verify_gsettings org.gnome.desktop.lockdown disable-lock-screen "true" || VERIFY_PASS=false

log ""
if [ "$VERIFY_PASS" = true ]; then
    log "🎉 All power management settings verified successfully!"
    log ""
    log "Kiosk display configuration:"
    log "  ✅ Screen will never turn off"
    log "  ✅ Brightness will not dim automatically"
    log "  ✅ No screensaver activation"
    log "  ✅ No automatic screen locking"
    log "  ✅ No automatic sleep/suspend"
    log ""
    log "Note: Settings take effect immediately for active sessions."
    log "      May require logout/login or reboot for full effect."
else
    warn "Some settings verification failed. Check output above."
    log ""
    log "Settings have been applied but some may not have taken effect."
    log "Try logging out and back in, or rebooting the system."
fi

log ""
log "Optional: To manually adjust screen brightness:"
log "  Settings → Displays → Brightness slider"
log "  Or use: xrandr --output <display> --brightness 1.0"

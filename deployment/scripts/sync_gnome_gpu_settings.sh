#!/bin/bash
# Sync GNOME GPU Settings from Source User to Kiosk User
# Copies GPU/compositor settings to ensure smooth desktop experience

set -e

SOURCE_USER="${1:-fredrik}"
TARGET_USER="${2:-kimonokittens}"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=== Sync GNOME GPU Settings ===${NC}"
echo "From: $SOURCE_USER → To: $TARGET_USER"
echo ""

# Check if running with sudo
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}ERROR: Please run this script with sudo${NC}"
    exit 1
fi

# Check both users exist
if ! id "$SOURCE_USER" >/dev/null 2>&1; then
    echo -e "${RED}ERROR: Source user $SOURCE_USER does not exist${NC}"
    exit 1
fi

if ! id "$TARGET_USER" >/dev/null 2>&1; then
    echo -e "${RED}ERROR: Target user $TARGET_USER does not exist${NC}"
    exit 1
fi

# Get user UIDs
SOURCE_UID=$(id -u "$SOURCE_USER")
TARGET_UID=$(id -u "$TARGET_USER")
SOURCE_RUNTIME="/run/user/$SOURCE_UID"
TARGET_RUNTIME="/run/user/$TARGET_UID"

echo "Checking if users have active sessions..."
if [ ! -d "$SOURCE_RUNTIME" ]; then
    echo -e "${YELLOW}WARNING: $SOURCE_USER not logged in, reading from dconf database${NC}"
fi

if [ ! -d "$TARGET_RUNTIME" ]; then
    echo -e "${RED}ERROR: $TARGET_USER must be logged in to apply settings${NC}"
    exit 1
fi

# Function to copy gsetting from source to target
copy_gsetting() {
    local schema="$1"
    local key="$2"

    # Get value from source user
    local value=$(sudo -u "$SOURCE_USER" \
        DBUS_SESSION_BUS_ADDRESS="unix:path=$SOURCE_RUNTIME/bus" \
        XDG_RUNTIME_DIR="$SOURCE_RUNTIME" \
        gsettings get "$schema" "$key" 2>/dev/null || echo "")

    if [ -z "$value" ]; then
        echo -e "  ${YELLOW}⚠️  $schema.$key - not set in source${NC}"
        return
    fi

    # Set value for target user
    sudo -u "$TARGET_USER" \
        DBUS_SESSION_BUS_ADDRESS="unix:path=$TARGET_RUNTIME/bus" \
        XDG_RUNTIME_DIR="$TARGET_RUNTIME" \
        gsettings set "$schema" "$key" "$value" 2>/dev/null

    echo -e "  ${GREEN}✅ $schema.$key = $value${NC}"
}

echo ""
echo "Copying Mutter (compositor) settings..."

# Mutter experimental features (may enable better GPU usage)
copy_gsetting org.gnome.mutter experimental-features

# Desktop interface settings
echo ""
echo "Copying desktop interface settings..."
copy_gsetting org.gnome.desktop.interface enable-animations
copy_gsetting org.gnome.desktop.interface gtk-enable-animations

# Performance settings
echo ""
echo "Copying performance settings..."
copy_gsetting org.gnome.mutter check-alive-timeout

# Shell settings
echo ""
echo "Copying shell settings..."
copy_gsetting org.gnome.shell enable-hot-corners
copy_gsetting org.gnome.shell.overrides workspaces-only-on-primary

echo ""
echo -e "${GREEN}✅ Settings copied successfully${NC}"
echo ""
echo -e "${YELLOW}Changes will take effect immediately for active session.${NC}"
echo "If desktop still feels choppy, try:"
echo "  1. Log out and back in"
echo "  2. Check chrome://gpu in browser (when kiosk running)"
echo "  3. Run: nvidia-settings (to verify GPU is active)"

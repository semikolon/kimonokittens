#!/bin/bash
# Fix GPU Acceleration for Kiosk - Force X11 over Wayland
# NVIDIA GPUs work much better with X11 than Wayland

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}=== GPU Acceleration Fix for Kiosk ===${NC}"
echo ""

# Check if running with sudo
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}ERROR: Please run this script with sudo${NC}"
    exit 1
fi

# Backup GDM config
BACKUP_FILE="/etc/gdm3/custom.conf.backup.$(date +%Y%m%d_%H%M%S)"
echo "Creating backup: $BACKUP_FILE"
cp /etc/gdm3/custom.conf "$BACKUP_FILE"

# Check current state
if grep -q "^WaylandEnable=false" /etc/gdm3/custom.conf; then
    echo -e "${GREEN}✅ X11 already forced - no changes needed${NC}"
    exit 0
fi

# Uncomment WaylandEnable=false
echo "Disabling Wayland (forcing X11)..."
sed -i 's/^#.*WaylandEnable=false/WaylandEnable=false/' /etc/gdm3/custom.conf
sed -i 's/^# WaylandEnable=false/WaylandEnable=false/' /etc/gdm3/custom.conf

# If the line doesn't exist at all, add it
if ! grep -q "WaylandEnable" /etc/gdm3/custom.conf; then
    sed -i '/\[daemon\]/a WaylandEnable=false' /etc/gdm3/custom.conf
fi

echo -e "${GREEN}✅ Configuration updated${NC}"
echo ""
echo -e "${YELLOW}Changes made:${NC}"
echo "  - Forced X11 (disabled Wayland)"
echo "  - NVIDIA GPU acceleration will now work properly"
echo ""
echo -e "${YELLOW}⚠️  To apply changes, restart GDM3:${NC}"
echo "  sudo systemctl restart gdm3"
echo ""
echo -e "${RED}WARNING: This will close all graphical sessions!${NC}"

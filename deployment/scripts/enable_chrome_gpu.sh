#!/bin/bash
# Enable Chrome GPU Acceleration for Kiosk
# Adds hardware acceleration flags to Chrome kiosk service

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

SERVICE_USER="${1:-kimonokittens}"
USER_SERVICE_FILE="/home/$SERVICE_USER/.config/systemd/user/kimonokittens-kiosk.service"

echo -e "${GREEN}=== Enable Chrome GPU Acceleration ===${NC}"
echo ""

# Check if running with sudo
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}ERROR: Please run this script with sudo${NC}"
    exit 1
fi

# Check if service file exists
if [ ! -f "$USER_SERVICE_FILE" ]; then
    echo -e "${RED}ERROR: Kiosk service file not found: $USER_SERVICE_FILE${NC}"
    exit 1
fi

# Backup service file
BACKUP_FILE="$USER_SERVICE_FILE.backup.$(date +%Y%m%d_%H%M%S)"
echo "Creating backup: $BACKUP_FILE"
cp "$USER_SERVICE_FILE" "$BACKUP_FILE"

# Check if GPU flags already exist
if grep -q "enable-gpu-rasterization" "$USER_SERVICE_FILE"; then
    echo -e "${GREEN}✅ GPU acceleration flags already present${NC}"
    exit 0
fi

echo "Adding GPU acceleration flags to Chrome..."

# Add GPU acceleration flags to ExecStart line
sed -i '/ExecStart=.*google-chrome/s|--kiosk|--enable-gpu-rasterization --enable-zero-copy --ignore-gpu-blocklist --enable-features=VaapiVideoDecoder --use-gl=desktop --kiosk|' "$USER_SERVICE_FILE"

echo -e "${GREEN}✅ GPU acceleration flags added${NC}"
echo ""
echo "Flags added:"
echo "  --enable-gpu-rasterization   (GPU-accelerated 2D canvas)"
echo "  --enable-zero-copy           (Efficient GPU memory usage)"
echo "  --ignore-gpu-blocklist       (Override GPU blocklist)"
echo "  --enable-features=VaapiVideoDecoder  (Hardware video decode)"
echo "  --use-gl=desktop             (Use desktop OpenGL)"
echo ""
echo -e "${YELLOW}To apply changes:${NC}"
echo "  1. Reload systemd: sudo -u $SERVICE_USER systemctl --user daemon-reload"
echo "  2. Restart kiosk: sudo XDG_RUNTIME_DIR=/run/user/\$(id -u $SERVICE_USER) -u $SERVICE_USER systemctl --user restart kimonokittens-kiosk"
echo ""
echo "Or simply reboot the system."

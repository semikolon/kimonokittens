#!/bin/bash
# Configure Chrome Kiosk Flags
# Idempotent script to ensure stable Chrome configuration
# Replaces: enable_chrome_gpu.sh (which had problematic GPU flags)

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

SERVICE_USER="${1:-kimonokittens}"
USER_SERVICE_FILE="/home/$SERVICE_USER/.config/systemd/user/kimonokittens-kiosk.service"

echo -e "${GREEN}=== Fix Chrome Kiosk Flags ===${NC}"
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

# Backup service file (only if not already backed up today)
BACKUP_DIR="/home/$SERVICE_USER/.config/systemd/user/backups"
mkdir -p "$BACKUP_DIR"
TODAY=$(date +%Y%m%d)
BACKUP_FILE="$BACKUP_DIR/kimonokittens-kiosk.service.backup.$TODAY"

if [ ! -f "$BACKUP_FILE" ]; then
    echo "Creating backup: $BACKUP_FILE"
    cp "$USER_SERVICE_FILE" "$BACKUP_FILE"
else
    echo "Backup already exists for today: $BACKUP_FILE"
fi

# Define the correct Chrome flags (2024 NVIDIA GPU acceleration + 110% zoom)
# GTX 1650 has 4GB VRAM
CORRECT_FLAGS='--ignore-gpu-blocklist --enable-features=AcceleratedVideoDecodeLinuxZeroCopyGL,AcceleratedVideoDecodeLinuxGL,VaapiIgnoreDriverChecks,VaapiOnNvidiaGPUs --force-gpu-mem-available-mb=4096 --force-device-scale-factor=1.1 --kiosk --no-first-run --disable-infobars --disable-session-crashed-bubble --disable-web-security --disable-features=TranslateUI --noerrdialogs --incognito --no-default-browser-check --password-store=basic --start-maximized --app=http://localhost'

# Check if flags are already correct
CURRENT_FLAGS=$(grep "ExecStart=" "$USER_SERVICE_FILE" | sed 's/ExecStart=\/usr\/bin\/google-chrome //')

if [ "$CURRENT_FLAGS" = "$CORRECT_FLAGS" ]; then
    echo -e "${GREEN}✅ Chrome flags are already correct (stable configuration)${NC}"
    exit 0
fi

echo "Fixing Chrome flags to stable configuration..."
echo ""
echo -e "${YELLOW}Updating to 2024 NVIDIA-optimized GPU acceleration flags:${NC}"
echo "  ✅ --ignore-gpu-blocklist (override software rendering)"
echo "  ✅ --enable-features=AcceleratedVideoDecodeLinuxZeroCopyGL,AcceleratedVideoDecodeLinuxGL"
echo "  ✅ --enable-features=VaapiIgnoreDriverChecks,VaapiOnNvidiaGPUs (NVIDIA-specific)"
echo "  ✅ --force-gpu-mem-available-mb=4096 (match GTX 1650 4GB VRAM)"
echo "  ✅ --force-device-scale-factor=1.1 (110% zoom for readability)"
echo ""
echo -e "${RED}Removed problematic flags (caused crash loops):${NC}"
echo "  ❌ --enable-gpu-rasterization"
echo "  ❌ --enable-zero-copy"
echo "  ❌ --enable-features=VaapiVideoDecoder (outdated)"
echo "  ❌ --use-gl=desktop (conflicts)"
echo ""

# Replace the entire ExecStart line with correct flags
sed -i "/^ExecStart=/c\ExecStart=/usr/bin/google-chrome $CORRECT_FLAGS" "$USER_SERVICE_FILE"

echo -e "${GREEN}✅ Chrome flags fixed - using stable configuration${NC}"
echo ""
echo -e "${YELLOW}To apply changes:${NC}"
echo "  1. Reload systemd:"
echo "     machinectl shell $SERVICE_USER@ /usr/bin/systemctl --user daemon-reload"
echo ""
echo "  2. Start kiosk:"
echo "     machinectl shell $SERVICE_USER@ /usr/bin/systemctl --user start kimonokittens-kiosk"
echo ""
echo "Or simply reboot the system."
echo ""
echo -e "${GREEN}Note: These minimal flags prevent Chrome crashes and reduce CPU usage${NC}"

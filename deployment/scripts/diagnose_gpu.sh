#!/bin/bash
# GPU Acceleration Diagnostics for Kimonokittens Kiosk
# Checks if users are using X11 vs Wayland and GPU acceleration status

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== GPU Acceleration Diagnostics ===${NC}"
echo ""

# Check GPU hardware
echo -e "${BLUE}1. GPU Hardware:${NC}"
lspci | grep -i vga
echo ""

# Check NVIDIA driver
echo -e "${BLUE}2. NVIDIA Driver Status:${NC}"
if command -v nvidia-smi >/dev/null 2>&1; then
    nvidia-smi --query-gpu=name,driver_version,memory.total --format=csv,noheader
    echo -e "${GREEN}✅ NVIDIA drivers installed${NC}"
else
    echo -e "${RED}❌ NVIDIA drivers not found${NC}"
fi
echo ""

# Check GDM3 Wayland setting
echo -e "${BLUE}3. GDM3 Wayland Configuration:${NC}"
if grep -q "^WaylandEnable=false" /etc/gdm3/custom.conf; then
    echo -e "${GREEN}✅ Wayland DISABLED (X11 forced) - GPU acceleration enabled${NC}"
elif grep -q "^#.*WaylandEnable=false\|^# WaylandEnable=false" /etc/gdm3/custom.conf; then
    echo -e "${YELLOW}⚠️  Wayland setting commented out - likely using Wayland${NC}"
    echo -e "${YELLOW}   This may cause poor GPU performance on NVIDIA${NC}"
    echo -e "${YELLOW}   Run fix script to enable X11${NC}"
else
    echo -e "${YELLOW}⚠️  No explicit Wayland setting - using system default${NC}"
fi
echo ""

# Check active sessions
echo -e "${BLUE}4. Active User Sessions:${NC}"
loginctl list-sessions --no-legend | while read session uid user seat tty; do
    session_type=$(loginctl show-session "$session" -p Type --value 2>/dev/null)
    echo "  User: $user | Session: $session | Type: $session_type"
done
echo ""

# Check if users have X11 or Wayland sessions
echo -e "${BLUE}5. Session Type Check:${NC}"
for user in fredrik kimonokittens; do
    if id "$user" >/dev/null 2>&1; then
        # Try to detect session type from environment
        user_uid=$(id -u "$user" 2>/dev/null)
        if [ -n "$user_uid" ]; then
            runtime_dir="/run/user/$user_uid"
            if [ -d "$runtime_dir" ]; then
                if [ -S "$runtime_dir/wayland-0" ]; then
                    echo -e "  ${YELLOW}$user: Using Wayland (slower on NVIDIA)${NC}"
                elif [ -f "/tmp/.X11-unix/X0" ]; then
                    echo -e "  ${GREEN}$user: Likely using X11 (GPU accelerated)${NC}"
                else
                    echo -e "  ${YELLOW}$user: Session type unknown${NC}"
                fi
            else
                echo -e "  $user: Not currently logged in"
            fi
        fi
    fi
done
echo ""

# Recommendations
echo -e "${BLUE}6. Recommendations:${NC}"
if ! grep -q "^WaylandEnable=false" /etc/gdm3/custom.conf; then
    echo -e "${YELLOW}To fix GPU acceleration for kiosk:${NC}"
    echo "  1. Run the fix script:"
    echo "     sudo /home/fredrik/Projects/kimonokittens/deployment/scripts/fix_gpu_acceleration.sh"
    echo "  2. Or manually:"
    echo "     sudo sed -i 's/# WaylandEnable=false/WaylandEnable=false/' /etc/gdm3/custom.conf"
    echo "     sudo systemctl restart gdm3"
else
    echo -e "${GREEN}✅ Configuration looks good!${NC}"
    echo "   X11 is forced, NVIDIA GPU acceleration should work properly"
fi

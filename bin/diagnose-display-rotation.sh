#!/bin/bash
# Diagnose display rotation issue after system upgrade
# Run as: sudo -u kimonokittens bash diagnose-display-rotation.sh
# Or: machinectl shell kimonokittens@.host /path/to/diagnose-display-rotation.sh

echo "=== Display Rotation Diagnostic ==="
echo ""

echo "1. Current xrandr configuration:"
DISPLAY=:0 xrandr --query | grep -A5 "connected"
echo ""

echo "2. NVIDIA driver version:"
nvidia-smi --query-gpu=driver_version --format=csv,noheader
echo ""

echo "3. Orientation sensor status:"
if command -v iio-sensor-proxy &> /dev/null; then
    echo "iio-sensor-proxy is installed"
    systemctl --user status iio-sensor-proxy 2>&1 | head -5
else
    echo "iio-sensor-proxy not installed (good - no auto-rotation)"
fi
echo ""

echo "4. GNOME display settings (monitors.xml):"
if [ -f ~/.config/monitors.xml ]; then
    echo "Found monitors.xml:"
    cat ~/.config/monitors.xml
else
    echo "No monitors.xml found (using defaults)"
fi
echo ""

echo "5. Chrome kiosk service configuration:"
systemctl --user cat kimonokittens-kiosk.service | grep -A2 -B2 "ExecStart"
echo ""

echo "6. Check for X11 configuration files:"
if [ -d /etc/X11/xorg.conf.d/ ]; then
    ls -la /etc/X11/xorg.conf.d/
else
    echo "No /etc/X11/xorg.conf.d/ directory"
fi
echo ""

echo "7. NVIDIA X Server Settings (if available):"
if [ -f ~/.nvidia-settings-rc ]; then
    echo "Found NVIDIA settings:"
    cat ~/.nvidia-settings-rc | grep -i rotation
else
    echo "No ~/.nvidia-settings-rc found"
fi
echo ""

echo "=== Fix Recommendations ==="
echo ""
echo "To permanently fix rotation, add to kiosk service:"
echo "ExecStartPre=/usr/bin/xrandr --output <OUTPUT> --rotate normal"
echo ""
echo "Or create ~/.config/monitors.xml with correct orientation"
echo ""
echo "Current connected output(s):"
DISPLAY=:0 xrandr --query | grep " connected" | awk '{print $1}'

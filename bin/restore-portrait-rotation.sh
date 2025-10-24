#!/bin/bash
# Restore portrait rotation (left rotation is CORRECT for vertically mounted monitor)
# Run as: machinectl shell kimonokittens@.host /path/to/restore-portrait-rotation.sh

MONITORS_XML="$HOME/.config/monitors.xml"
BACKUP="$HOME/.config/monitors.xml.backup-20251009-160847"

echo "=== Restoring Portrait Rotation ==="
echo ""

if [ ! -f "$BACKUP" ]; then
    echo "ERROR: Backup not found at $BACKUP"
    exit 1
fi

echo "1. Restoring monitors.xml from backup..."
cp "$BACKUP" "$MONITORS_XML"
echo "   Restored"
echo ""

echo "2. Current rotation setting:"
grep -A2 "<transform>" "$MONITORS_XML"
echo ""

echo "3. Applying portrait rotation with xrandr..."
DISPLAY=:0 xrandr --output HDMI-0 --rotate left
echo "   Portrait rotation applied"
echo ""

echo "=== Restoration Complete ==="
echo ""
echo "The monitor is now back in portrait (vertical) orientation."
echo "This configuration is CORRECT for a physically rotated monitor."

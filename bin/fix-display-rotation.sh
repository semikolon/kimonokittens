#!/bin/bash
# Fix display rotation permanently by updating monitors.xml
# Run as: machinectl shell kimonokittens@.host /path/to/fix-display-rotation.sh

MONITORS_XML="$HOME/.config/monitors.xml"

echo "=== Fixing Display Rotation ==="
echo ""

if [ ! -f "$MONITORS_XML" ]; then
    echo "ERROR: monitors.xml not found at $MONITORS_XML"
    exit 1
fi

echo "1. Backing up current monitors.xml..."
cp "$MONITORS_XML" "$MONITORS_XML.backup-$(date +%Y%m%d-%H%M%S)"
echo "   Backup created"
echo ""

echo "2. Current rotation setting:"
grep -A2 "<transform>" "$MONITORS_XML"
echo ""

echo "3. Fixing rotation to 'normal'..."
sed -i 's/<rotation>left<\/rotation>/<rotation>normal<\/rotation>/g' "$MONITORS_XML"
sed -i 's/<rotation>right<\/rotation>/<rotation>normal<\/rotation>/g' "$MONITORS_XML"
sed -i 's/<rotation>upside_down<\/rotation>/<rotation>normal<\/rotation>/g' "$MONITORS_XML"
echo "   Updated monitors.xml"
echo ""

echo "4. New rotation setting:"
grep -A2 "<transform>" "$MONITORS_XML"
echo ""

echo "5. Applying rotation immediately with xrandr..."
DISPLAY=:0 xrandr --output HDMI-0 --rotate normal
echo "   Rotation applied"
echo ""

echo "=== Fix Complete ==="
echo ""
echo "The display should now be in landscape orientation."
echo "This fix will persist across reboots."
echo ""
echo "If you need to revert, restore from:"
ls -lh "$MONITORS_XML.backup-"* 2>/dev/null | tail -1

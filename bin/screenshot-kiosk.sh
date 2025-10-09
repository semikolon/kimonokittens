#!/bin/bash
# Take screenshot of kiosk display and copy back to Mac
# Run from Mac: ./bin/screenshot-kiosk.sh

TIMESTAMP=$(date +%Y%m%d-%H%M%S)
SCREENSHOT_PATH="/tmp/kiosk-screenshot-$TIMESTAMP.png"

echo "Taking screenshot of kiosk display..."
ssh pop "machinectl shell kimonokittens@.host /usr/bin/bash -c 'DISPLAY=:0 scrot $SCREENSHOT_PATH && echo Screenshot saved: $SCREENSHOT_PATH'"

echo ""
echo "Copying screenshot to Mac..."
scp pop:$SCREENSHOT_PATH ~/Desktop/

if [ $? -eq 0 ]; then
    echo ""
    echo "✅ Screenshot saved to: ~/Desktop/kiosk-screenshot-$TIMESTAMP.png"
    open ~/Desktop/kiosk-screenshot-$TIMESTAMP.png
else
    echo ""
    echo "❌ Failed to copy screenshot"
    echo "Run manually: scp pop:$SCREENSHOT_PATH ~/Desktop/"
fi

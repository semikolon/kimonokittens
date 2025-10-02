#!/bin/bash
# Update kiosk service with improved restart limits to prevent loops

SERVICE_FILE="/home/kimonokittens/.config/systemd/user/kimonokittens-kiosk.service"

echo "Updating kiosk service restart limits..."

# Update the service file
machinectl shell kimonokittens@.host /bin/bash -c "
  sed -i 's/^Restart=always$/# Prevent rapid restart loops - only restart on crashes\/failures, not manual stops\nRestart=on-failure/' '$SERVICE_FILE'
  sed -i 's/^RestartSec=30$/RestartSec=10s/' '$SERVICE_FILE'
  sed -i 's/^StartLimitBurst=5$/StartLimitBurst=3/' '$SERVICE_FILE'
  sed -i 's/^StartLimitIntervalSec=300$/StartLimitIntervalSec=60s/' '$SERVICE_FILE'
"

echo "Reloading systemd daemon..."
machinectl shell kimonokittens@.host /usr/bin/systemctl --user daemon-reload

echo ""
echo "✅ Service restart limits updated"
echo "Changes:"
echo "  - Restart=on-failure (was: always) - only restart on crashes"
echo "  - RestartSec=10s (was: 30) - faster recovery from crashes"
echo "  - StartLimitBurst=3 (was: 5) - fewer restart attempts"
echo "  - StartLimitIntervalSec=60s (was: 300) - shorter window"
echo ""
echo "If Chrome crashes 3 times in 60 seconds, systemd will stop trying to restart it."
echo ""
echo "To apply changes to running service, restart it:"
echo "  machinectl shell kimonokittens@.host /usr/bin/systemctl --user restart kimonokittens-kiosk"

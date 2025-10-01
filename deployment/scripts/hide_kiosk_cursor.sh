#!/bin/bash
# Hide mouse cursor in kiosk mode using unclutter

set -e

SERVICE_USER="${SERVICE_USER:-kimonokittens}"

echo "📦 Installing unclutter..."
apt-get update -qq
apt-get install -y unclutter

echo "🖱️  Configuring cursor hiding for kiosk user..."

# Create autostart directory
AUTOSTART_DIR="/home/$SERVICE_USER/.config/autostart"
mkdir -p "$AUTOSTART_DIR"

# Create unclutter desktop entry
cat > "$AUTOSTART_DIR/unclutter.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Unclutter
Comment=Hide mouse cursor when idle
Exec=unclutter -idle 0.1 -root
Terminal=false
NoDisplay=true
X-GNOME-Autostart-enabled=true
EOF

# Set ownership
chown -R "$SERVICE_USER:$SERVICE_USER" "$AUTOSTART_DIR"

echo "✅ Cursor hiding configured"
echo "⚠️  Note: Cursor will be hidden immediately on mouse idle in kiosk session"

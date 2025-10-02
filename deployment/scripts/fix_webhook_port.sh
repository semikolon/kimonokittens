#!/bin/bash
# Configure webhook to use port 49123
# Pattern: Default in systemd + Override in .env
# Run with: sudo bash fix_webhook_port.sh

set -e

ENV_FILE="/home/kimonokittens/.env"
SERVICE_FILE="/etc/systemd/system/kimonokittens-webhook.service"

echo "🔧 Configuring webhook for port 49123..."
echo ""

# 1. Ensure systemd has default port (for fresh installs)
echo "📝 Setting default WEBHOOK_PORT=9001 in systemd service..."
if grep -q "^Environment=\"WEBHOOK_PORT=" "$SERVICE_FILE"; then
    sed -i 's/^Environment="WEBHOOK_PORT=.*/Environment="WEBHOOK_PORT=9001"/' "$SERVICE_FILE"
    echo "✅ Default port in systemd: 9001"
else
    # Add after the other Environment lines
    sed -i '/^Environment="PATH=/a Environment="WEBHOOK_PORT=9001"' "$SERVICE_FILE"
    echo "✅ Added default port to systemd: 9001"
fi

echo ""

# 2. Set override in .env (this takes precedence)
echo "📝 Setting override WEBHOOK_PORT=49123 in .env..."
if grep -q "^WEBHOOK_PORT=" "$ENV_FILE"; then
    sed -i "s/^WEBHOOK_PORT=.*/WEBHOOK_PORT=49123/" "$ENV_FILE"
    echo "✅ Override in .env: 49123 (this is what will be used)"
else
    echo "WEBHOOK_PORT=49123" >> "$ENV_FILE"
    echo "✅ Override added to .env: 49123 (this is what will be used)"
fi

echo ""

# 3. Reload and restart
echo "🔄 Reloading systemd and restarting webhook..."
systemctl daemon-reload
systemctl restart kimonokittens-webhook

sleep 2

# 4. Verify
if systemctl is-active --quiet kimonokittens-webhook; then
    echo "✅ Webhook service running"

    if ss -tuln | grep -q ":49123"; then
        echo "✅ CONFIRMED: Listening on port 49123"
    else
        echo "❌ ERROR: Not listening on port 49123!"
        echo "Checking what port it's actually using..."
        ss -tuln | grep ruby || echo "No ruby process found listening"
        exit 1
    fi
else
    echo "❌ Service failed to start"
    journalctl -u kimonokittens-webhook -n 20 --no-pager
    exit 1
fi

echo ""
echo "✅ SUCCESS! Webhook configured for port 49123"
echo ""
echo "Configuration:"
echo "  • Default (systemd):  9001 (fallback)"
echo "  • Override (.env):    49123 (active)"
echo "  • GitHub webhook:     http://kimonokittens.com:49123/webhook"
echo "  • Port forwarding:    49123 → 192.168.4.84:49123"

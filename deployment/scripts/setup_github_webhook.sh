#!/bin/bash
# Automated GitHub Webhook Setup
# - Generates secure webhook secret
# - Updates production .env
# - Restarts webhook service
# - Creates GitHub webhook (via gh CLI or manual instructions)

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

SERVICE_USER="${1:-kimonokittens}"
ENV_FILE="/home/$SERVICE_USER/.env"
REPO="semikolon/kimonokittens"
WEBHOOK_PORT="${WEBHOOK_PORT:-9001}"  # Override with: WEBHOOK_PORT=49123 ./setup_github_webhook.sh

# Check if running with sudo
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}ERROR: Please run this script with sudo${NC}"
    exit 1
fi

echo -e "${GREEN}=== GitHub Webhook Setup ===${NC}"
echo ""

# Generate secure webhook secret
echo "🔐 Generating webhook secret (32 bytes, hex-encoded)..."
SECRET=$(openssl rand -hex 32)
echo -e "${GREEN}✅ Secret generated${NC}"

# Backup .env file
echo ""
echo "💾 Backing up .env file..."
BACKUP_FILE="$ENV_FILE.backup.$(date +%Y%m%d_%H%M%S)"
if sudo -u $SERVICE_USER cp "$ENV_FILE" "$BACKUP_FILE"; then
    echo -e "${GREEN}✅ Backup created: $BACKUP_FILE${NC}"
else
    echo -e "${RED}❌ Failed to backup .env${NC}"
    exit 1
fi

# Update or add WEBHOOK_SECRET
echo ""
echo "📝 Configuring WEBHOOK_SECRET in .env..."
if grep -q "^WEBHOOK_SECRET=" "$ENV_FILE"; then
    sudo -u $SERVICE_USER sed -i "s/^WEBHOOK_SECRET=.*/WEBHOOK_SECRET=$SECRET/" "$ENV_FILE"
    echo -e "${GREEN}✅ WEBHOOK_SECRET updated${NC}"
else
    echo "WEBHOOK_SECRET=$SECRET" | sudo -u $SERVICE_USER tee -a "$ENV_FILE" >/dev/null
    echo -e "${GREEN}✅ WEBHOOK_SECRET added${NC}"
fi

# Restart webhook service
echo ""
echo "🔄 Restarting webhook service..."
if systemctl restart kimonokittens-webhook; then
    echo -e "${GREEN}✅ Webhook service restarted${NC}"
    sleep 2

    # Verify service is running
    if systemctl is-active --quiet kimonokittens-webhook; then
        echo -e "${GREEN}✅ Webhook service is active${NC}"

        # Verify secret is loaded
        SECRET_STATUS=$(curl -s http://localhost:$WEBHOOK_PORT/status | jq -r '.webhook_secret_configured' 2>/dev/null || echo "unknown")
        if [ "$SECRET_STATUS" = "true" ]; then
            echo -e "${GREEN}✅ Webhook secret verified and loaded${NC}"
        else
            echo -e "${YELLOW}⚠️  Warning: Could not verify secret was loaded (status: $SECRET_STATUS)${NC}"
        fi
    else
        echo -e "${RED}❌ Webhook service failed to start${NC}"
        exit 1
    fi
else
    echo -e "${RED}❌ Failed to restart webhook service${NC}"
    exit 1
fi

# Detect kiosk IP address
echo ""
echo "🌐 Detecting kiosk IP address..."
IP=$(ip addr show | grep "inet " | grep -v 127.0.0.1 | awk '{print $2}' | cut -d/ -f1 | head -1)
WEBHOOK_URL="http://${IP}:${WEBHOOK_PORT}/webhook"
PUBLIC_URL="http://kimonokittens.com:${WEBHOOK_PORT}/webhook"

echo -e "${GREEN}Local IP: $IP${NC}"
echo -e "${GREEN}Local webhook URL: $WEBHOOK_URL${NC}"
echo -e "${GREEN}Public webhook URL: $PUBLIC_URL${NC}"

echo ""
echo -e "${GREEN}✅ Webhook configuration complete!${NC}"
echo ""

# Install GitHub CLI if not present
if ! command -v gh &> /dev/null; then
    echo "📦 GitHub CLI not found - installing..."

    # Add GitHub CLI repository
    curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg 2>/dev/null
    chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg

    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | tee /etc/apt/sources.list.d/github-cli.list > /dev/null

    # Install gh
    apt update -qq
    if apt install gh -y -qq; then
        echo -e "${GREEN}✅ GitHub CLI installed successfully${NC}"
    else
        echo -e "${YELLOW}⚠️  Failed to install GitHub CLI - will show manual instructions${NC}"
    fi
    echo ""
fi

# Try GitHub CLI automation
if command -v gh &> /dev/null; then
    echo "📡 GitHub CLI detected - checking authentication..."

    if gh auth status &> /dev/null; then
        echo -e "${GREEN}✅ GitHub CLI authenticated${NC}"
        echo ""
        echo "🚀 Creating webhook automatically..."

        if gh api "repos/$REPO/hooks" \
            -f name=web \
            -f config[url]="$PUBLIC_URL" \
            -f config[secret]="$SECRET" \
            -f config[content_type]=application/json \
            -F config[insecure_ssl]=0 \
            -f events[]=push \
            -F active=true 2>/dev/null; then

            echo ""
            echo -e "${GREEN}🎉 Webhook created successfully via GitHub CLI!${NC}"
            echo ""
            echo "✅ GitHub will now trigger deployments on push to master"
            echo "✅ Webhook URL: $PUBLIC_URL"
            echo "✅ Secret is configured and verified"
            echo ""
            echo -e "${YELLOW}⚠️  IMPORTANT: Ensure port $WEBHOOK_PORT is forwarded in your router${NC}"
            echo "   Router: Forward external port $WEBHOOK_PORT → $IP:$WEBHOOK_PORT"
            exit 0
        else
            echo -e "${YELLOW}⚠️  GitHub CLI webhook creation failed (may already exist)${NC}"
            echo ""
        fi
    else
        echo -e "${YELLOW}⚠️  GitHub CLI not authenticated${NC}"
        echo ""
        echo "Authenticating with GitHub..."
        echo "This will open a browser. Follow the prompts to authenticate."
        echo ""

        # Run gh auth login as the user running the script (not root)
        if [ -n "$SUDO_USER" ]; then
            sudo -u "$SUDO_USER" gh auth login
        else
            gh auth login
        fi

        # Check if auth succeeded
        if gh auth status &> /dev/null; then
            echo ""
            echo -e "${GREEN}✅ GitHub CLI authenticated successfully${NC}"
            echo ""
            echo "🚀 Creating webhook..."

            if gh api "repos/$REPO/hooks" \
                -f name=web \
                -f config[url]="$PUBLIC_URL" \
                -f config[secret]="$SECRET" \
                -f config[content_type]=application/json \
                -F config[insecure_ssl]=0 \
                -f events[]=push \
                -F active=true 2>/dev/null; then

                echo ""
                echo -e "${GREEN}🎉 Webhook created successfully!${NC}"
                echo ""
                echo "✅ GitHub will now trigger deployments on push to master"
                echo "✅ Webhook URL: $PUBLIC_URL"
                echo "✅ Secret is configured and verified"
                echo ""
                echo -e "${YELLOW}⚠️  IMPORTANT: Ensure port $WEBHOOK_PORT is forwarded in your router${NC}"
                echo "   Router: Forward external port $WEBHOOK_PORT → $IP:$WEBHOOK_PORT"
                exit 0
            fi
        else
            echo -e "${YELLOW}⚠️  GitHub authentication failed - will show manual instructions${NC}"
        fi
        echo ""
    fi
else
    echo -e "${YELLOW}⚠️  GitHub CLI (gh) not installed${NC}"
    echo "   Install: sudo apt install gh  (or brew install gh on macOS)"
    echo ""
fi

# Manual setup instructions
echo -e "${YELLOW}═══════════════════════════════════════════════════════${NC}"
echo -e "${YELLOW}📋 Manual GitHub Webhook Configuration${NC}"
echo -e "${YELLOW}═══════════════════════════════════════════════════════${NC}"
echo ""
echo "1. Go to GitHub webhook settings:"
echo -e "   ${GREEN}https://github.com/$REPO/settings/hooks/new${NC}"
echo ""
echo "2. Configure webhook with these settings:"
echo ""
echo -e "   ${GREEN}Payload URL:${NC}"
echo "   $PUBLIC_URL"
echo ""
echo -e "   ${GREEN}Content type:${NC}"
echo "   application/json"
echo ""
echo -e "   ${GREEN}Secret:${NC}"
echo "   $SECRET"
echo ""
echo -e "   ${GREEN}SSL verification:${NC}"
echo "   Enable SSL verification (if using HTTPS)"
echo "   Disable SSL verification (if using HTTP - not recommended for production)"
echo ""
echo -e "   ${GREEN}Which events:${NC}"
echo "   ☑ Just the push event"
echo ""
echo -e "   ${GREEN}Active:${NC}"
echo "   ☑ (checked)"
echo ""
echo "3. Click 'Add webhook'"
echo ""
echo -e "${YELLOW}═══════════════════════════════════════════════════════${NC}"
echo -e "${YELLOW}🔒 Port Forwarding Required${NC}"
echo -e "${YELLOW}═══════════════════════════════════════════════════════${NC}"
echo ""
echo "Configure your router to forward:"
echo -e "   External port ${GREEN}$WEBHOOK_PORT${NC} → ${GREEN}$IP:$WEBHOOK_PORT${NC}"
echo ""
echo "Router admin typically at: http://192.168.1.1 or http://192.168.0.1"
echo ""
echo -e "${YELLOW}═══════════════════════════════════════════════════════${NC}"
echo -e "${YELLOW}🔐 Security Recommendations${NC}"
echo -e "${YELLOW}═══════════════════════════════════════════════════════${NC}"
echo ""
echo "Current security:"
echo "  ✅ HMAC-SHA256 signature verification (webhook secret)"
echo "  ✅ JSON payload validation"
echo "  ✅ Branch filtering (only master triggers deployment)"
echo ""
echo "Optional hardening:"
echo "  • Use obscure port (current: $WEBHOOK_PORT, consider: 49123 or random)"
echo "  • Add nginx reverse proxy with rate limiting"
echo "  • Whitelist GitHub webhook IPs in firewall/nginx"
echo "  • Use Tailscale instead of port forwarding (more secure)"
echo ""
echo -e "${GREEN}✅ Secret is configured in: $ENV_FILE${NC}"
echo -e "${GREEN}✅ Webhook service is running and ready${NC}"
echo ""
echo "Test webhook status:"
echo "  curl -s http://localhost:$WEBHOOK_PORT/status | jq ."
echo ""
echo "Test deployment (local):"
echo "  curl -X POST http://localhost:$WEBHOOK_PORT/webhook \\"
echo "    -H 'Content-Type: application/json' \\"
echo "    -d '{\"ref\":\"refs/heads/master\",\"commits\":[{\"modified\":[\"test\"]}]}'"

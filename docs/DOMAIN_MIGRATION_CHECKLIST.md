# Domain Migration Checklist - kimonokittens.com → Dell

**Goal**: Migrate kimonokittens.com from Pi Agoo server to Dell production, with clean URLs and proper SSL.

**Status**: 🚀 **IN PROGRESS** (Nov 10, 2025 - SSL obtained, nginx configured, ready for port forwarding)

**Timeline**: Ready when ready (BRF-Auto timeline no longer blocking)

**Detailed Analysis**: See `PI_TO_DELL_MIGRATION_ANALYSIS.md` for complete dependency mapping and "what breaks if..." scenarios.

---

## Pre-Flight Checks ✅

- [x] Dell handles all dashboard data endpoints
- [x] Node-RED proxying configured (192.168.4.66:1880 fallback)
- [x] Deploy webhook functional (port 49123)
- [x] Main API functional (port 3001)
- [x] Kiosk display working perfectly
- [x] Environment variables configured on Dell (ZIGNED_API_KEY test mode)
- [x] SSL certificates generated on Dell (manual DNS-01, expires 2026-02-08)
- [x] Nginx configured for public HTTPS access
- [x] Local testing passed (HTTP→HTTPS redirect, API endpoints, webhooks)
- [ ] Port forwarding updated (Pi → Dell)
- [ ] External testing from different network
- [ ] GitHub webhook URL updated to use domain

---

## Step 1: Configure Environment Variables on Dell

**Critical for webhook functionality!**

SSH to Dell and edit production `.env`:
```bash
ssh pop
nano /home/kimonokittens/.env
```

**Required variables:**
```bash
# Zigned API credentials
ZIGNED_API_KEY='your_api_key_here'
ZIGNED_WEBHOOK_SECRET_REAL='your_real_webhook_secret'
ZIGNED_WEBHOOK_SECRET_TEST='your_test_webhook_secret'

# Database
DATABASE_URL='postgresql://user:pass@localhost:5432/kimonokittens_production'
```

**Optional variables:**
```bash
# Only needed if NOT using Zigned admin interface webhooks
# WEBHOOK_BASE_URL=https://kimonokittens.com
```

**Verification:**
```bash
# Check required vars exist
grep -E 'ZIGNED' /home/kimonokittens/.env
```

**About WEBHOOK_BASE_URL:**
- **NOT REQUIRED** if you configured webhooks in Zigned admin interface (recommended approach)
- Zigned will use dashboard URL for all contracts
- Only needed for: local development testing, ngrok tunnels, or multi-tenant systems
- **For production**: Leave unset, use dashboard webhooks

---

## Step 2: Generate SSL Certificates on Dell

**Three approaches for SSL certificates - choose based on automation needs:**

### Option A: Manual DNS-01 Challenge (USED - Nov 10, 2025)

**Best for:** Getting domain live quickly without API bureaucracy
**Renewal:** Manual every 90 days (5 minutes)

```bash
ssh pop
sudo apt update
sudo apt install certbot

# Start DNS challenge
sudo certbot certonly --manual --preferred-challenges dns -d kimonokittens.com

# Certbot will display TXT record to add:
# _acme-challenge.kimonokittens.com → [random-token]

# 1. Log into Namecheap → Advanced DNS
# 2. Add TXT record with given value
# 3. Wait 2 minutes for propagation
# 4. Press Enter in certbot
```

**Result**: Certificates at `/etc/letsencrypt/live/kimonokittens.com/`

**Renewal reminder**: Certificates expire in 90 days. Set calendar reminder to repeat process.

---

### Option B: Cloudflare DNS Delegation (RECOMMENDED for automation)

**Best for:** Automated renewals without Namecheap API restrictions
**Renewal:** Fully automated via certbot timer

**Setup (one-time):**
1. Create free Cloudflare account at cloudflare.com
2. Add kimonokittens.com to Cloudflare
3. Cloudflare provides nameservers (e.g., `ns1.cloudflare.com`)
4. Update nameservers at Namecheap (domain stays registered there)
5. Wait 1-2 hours for DNS propagation

**Install plugin:**
```bash
sudo apt install python3-pip
pip3 install certbot-dns-cloudflare
```

**Create credentials file:**
```bash
sudo nano /root/.secrets/cloudflare.ini
# Add:
# dns_cloudflare_api_token = YOUR_CLOUDFLARE_API_TOKEN
sudo chmod 600 /root/.secrets/cloudflare.ini
```

**Generate certificate (automated renewals):**
```bash
sudo certbot certonly \
  --dns-cloudflare \
  --dns-cloudflare-credentials /root/.secrets/cloudflare.ini \
  -d kimonokittens.com
```

**Auto-renewal**: Certbot systemd timer handles renewals automatically
```bash
sudo systemctl status certbot.timer
```

---

### Option C: Namecheap API (NOT RECOMMENDED - bureaucracy)

**Requirements:**
- $50+ account balance OR 20+ domains OR $50+ spent in last 2 years
- Namecheap support approval (can take days)
- IP whitelisting setup

**Only use if:** You already meet requirements and want to avoid Cloudflare migration

---

## Step 3: Configure Nginx for Public Access

**File**: `/etc/nginx/sites-available/kimonokittens.com`

```nginx
# Redirect HTTP → HTTPS
server {
    listen 80;
    server_name kimonokittens.com;
    return 301 https://$server_name$request_uri;
}

# Main HTTPS server
server {
    listen 443 ssl http2;
    server_name kimonokittens.com;

    # SSL certificates
    ssl_certificate /etc/letsencrypt/live/kimonokittens.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/kimonokittens.com/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;

    # Security headers
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;

    # Logs
    access_log /var/log/nginx/kimonokittens-access.log;
    error_log /var/log/nginx/kimonokittens-error.log;

    # Homepage & Dashboard static files
    location / {
        root /var/www/kimonokittens/dashboard;
        try_files $uri $uri/ /index.html;
    }

    # Deploy webhook - proxied to separate Puma instance
    location /api/webhooks/deploy {
        proxy_pass http://localhost:49123;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    # Zigned webhook - proxied to main Puma
    location /api/webhooks/zigned {
        proxy_pass http://localhost:3001;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    # All other API endpoints - main Puma
    location /api/ {
        proxy_pass http://localhost:3001;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    # Data endpoints (temperature, etc.) - main Puma
    location /data/ {
        proxy_pass http://localhost:3001;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    # WebSocket - main Puma
    location /dashboard/ws {
        proxy_pass http://localhost:3001;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "Upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

**Enable site:**
```bash
sudo ln -s /etc/nginx/sites-available/kimonokittens.com /etc/nginx/sites-enabled/
sudo nginx -t  # Test configuration
sudo systemctl reload nginx
```

---

## Step 4: Migrate Homepage Content

**Option A: Reuse Pi Homepage** (Simple static page)
```bash
# On Mac, copy from Pi
scp pi:/var/www/html/index.html /tmp/pi-homepage.html
scp pi:/var/www/html/assets/* /tmp/pi-assets/

# Copy to Dell
scp /tmp/pi-homepage.html kimonokittens@pop:/tmp/
ssh pop "sudo cp /tmp/pi-homepage.html /var/www/kimonokittens/index.html"
```

**Option B: New Homepage via Magic MCP** (Future)
- Design new homepage with `/ui-prototype` command
- Deploy to `/var/www/kimonokittens/`
- Update nginx root if needed

**For now**: Copy Pi's simple static page (logo + Swish QR)

---

## Step 5: Update Port Forwarding (Deco App)

**Current rule (Pi):**
- External port 80 → 192.168.4.66:6464 (Pi Agoo)
- External port 443 → 192.168.4.66:6465 (Pi Agoo HTTPS)

**New rule (Dell):**
- External port 80 → 192.168.4.84:80 (Dell nginx)
- External port 443 → 192.168.4.84:443 (Dell nginx)

**Steps in Deco app:**
1. Open TP-Link Deco app on iPhone
2. More → Advanced → NAT Forwarding → Port Forwarding
3. Edit existing rule for port 80:
   - Change IP from Pi (192.168.4.66) to Dell (192.168.4.84)
   - Change internal port from 6464 to 80
4. Edit existing rule for port 443:
   - Change IP from Pi (192.168.4.66) to Dell (192.168.4.84)
   - Change internal port from 6465 to 443
5. Save changes

**Result**: `https://kimonokittens.com` now points to Dell nginx

---

## Step 6: Test Everything

**External access (from phone/different network):**
```bash
# Test HTTPS redirect
curl -I http://kimonokittens.com
# Should return: 301 Moved Permanently → https://kimonokittens.com

# Test homepage
curl https://kimonokittens.com/
# Should return: HTML content

# Test API endpoints
curl https://kimonokittens.com/api/rent/friendly_message
curl https://kimonokittens.com/data/temperature
curl https://kimonokittens.com/data/weather

# Test webhook endpoints (GET should return 405 Method Not Allowed)
curl https://kimonokittens.com/api/webhooks/zigned
curl https://kimonokittens.com/api/webhooks/deploy
```

**Local testing (on Dell):**
```bash
# Verify services running
sudo systemctl status kimonokittens-dashboard
sudo systemctl status kimonokittens-webhook
sudo systemctl status nginx

# Check logs
journalctl -u kimonokittens-dashboard -f
journalctl -u kimonokittens-webhook -f
tail -f /var/log/nginx/kimonokittens-access.log
```

**Dashboard functionality:**
- Open `https://kimonokittens.com` in browser
- Verify WebSocket connects (check browser console)
- Verify widgets load (rent, weather, trains, etc.)
- Verify temperature data appears (Node-RED proxy working)

---

## Step 7: Configure Webhook Services

**Zigned webhook:**
1. Log into Zigned admin dashboard
2. Navigate to webhook settings
3. Set URL: `https://kimonokittens.com/api/webhooks/zigned`
4. Set secret: Value from `ENV['ZIGNED_WEBHOOK_SECRET']` on Dell
5. Enable webhook events: `case.created`, `case.signed`, `case.completed`

**GitHub deploy webhook:**
1. Already configured at: `POST http://YOUR_HOME_IP:49123/webhook`
2. Update to: `https://kimonokittens.com/api/webhooks/deploy`
3. Verify signature secret matches Dell config

---

## Step 8: Stop Pi Agoo Server

**Only after verifying Dell is fully operational!**

```bash
ssh pi
sudo systemctl stop json_server_daemon
sudo systemctl disable json_server_daemon

# Verify Node-RED still running (keep this!)
sudo systemctl status nodered

# Verify Mosquitto still running (keep this!)
sudo systemctl status mosquitto

# Verify DDClient still running (keep this!)
sudo systemctl status ddclient
```

**What stays on Pi:**
- DDClient (dynamic DNS updates)
- Node-RED (port 1880, temperature data)
- Mosquitto (port 1883, MQTT broker)
- Pycalima (Bluetooth fan control)

**What's decommissioned on Pi:**
- Agoo server (ports 6464/6465)
- Public homepage serving

---

## Step 9: Monitor & Verify

**First 24 hours:**
- Monitor Dell logs for errors
- Check webhook deliveries (GitHub, Zigned)
- Verify temperature widget still works (Node-RED proxy)
- Verify kiosk display stability
- Check SSL certificate auto-renewal timer

**If issues arise:**
- Revert port forwarding in Deco app (point back to Pi)
- Restart Pi Agoo server temporarily
- Debug Dell nginx/Puma issues
- Re-attempt when ready

---

## Rollback Plan

**If something breaks:**
1. Change Deco port forwarding back to Pi
2. Restart Pi Agoo server: `ssh pi "sudo systemctl start json_server_daemon"`
3. Debug Dell issues offline
4. Re-attempt migration when fixed

**Pi Agoo server remains available** for emergency rollback until Dell is proven stable (suggest 1 week monitoring period).

---

## Success Criteria

- ✅ `https://kimonokittens.com` loads homepage
- ✅ Dashboard widgets all functional
- ✅ WebSocket connected
- ✅ Temperature data appears (Node-RED proxy working)
- ✅ Zigned webhook receives test events
- ✅ Deploy webhook triggers on GitHub push
- ✅ SSL certificate valid and auto-renews
- ✅ No console errors in browser
- ✅ Kiosk display stable for 24+ hours

---

## Timeline

**Estimated effort**: 1-2 hours focused work

**Breakdown**:
- SSL certificates: 5-10 minutes
- Nginx configuration: 15-20 minutes
- Homepage migration: 5-10 minutes
- Port forwarding update: 5 minutes
- Testing: 30-45 minutes
- Webhook configuration: 10 minutes
- Monitoring: Ongoing (24-48 hours)

**Best time**: Weekend morning when you can monitor for several hours

---

## Post-Migration Cleanup (1 week later)

**After Dell proven stable:**
- Remove Pi Agoo server completely
- Archive `/var/www/html/` on Pi (backup)
- Update documentation (CLAUDE.md)
- Consider moving electricity cron jobs to Dell
- Design new homepage with Magic MCP (optional)

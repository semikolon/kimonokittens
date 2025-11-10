# CRITICAL ANALYSIS: Kimonokittens Pi→Dell Migration Status
## Impact Assessment: What Breaks if Pi Stops Serving kimonokittens.com NOW?

**Analysis Date:** November 10, 2025  
**Current Status:** Pi currently serves kimonokittens.com (port 80/443) via Agoo JSON server  
**Dell Current State:** Fully operational internally, NOT publicly accessible

---

## EXECUTIVE SUMMARY

**SHORT ANSWER: Several critical things will break if kimonokittens.com points to Dell RIGHT NOW.**

The handlers are READY for domain migration, but the infrastructure is NOT. The code has fallback logic, but configuration and DNS setup are blocking issues.

---

## CRITICAL BLOCKERS (In Priority Order)

### 1. ❌ ZIGNED WEBHOOK URL - HARDCODED DOMAIN DEPENDENCY (BLOCKER)

**Status:** WILL BREAK  
**Severity:** CRITICAL - Contract signing completely broken

**Problem:**
- Zigned expects webhooks at `https://kimonokittens.com/api/webhooks/zigned`
- Current code uses `ENV['WEBHOOK_BASE_URL']` to construct webhook URL (lines 108, 220 in contract_signer.rb)
- If Pi stops responding, Zigned cannot notify Dell of signature updates
- Signed contracts won't be downloaded, statuses won't update

**Code Flow:**
```ruby
# lib/contract_signer.rb:108, 220
webhook_url = ENV['WEBHOOK_BASE_URL'] ? "#{ENV['WEBHOOK_BASE_URL']}/api/webhooks/zigned" : nil
```

**Where Set:**
- `.env` file has `API_BASE_URL='http://localhost:3001'` (development only)
- Production `.env` on Dell likely NOT configured for WEBHOOK_BASE_URL
- Handler exists at `/api/webhooks/zigned` in puma_server.rb (line 302-318)

**What Must Happen:**
1. Set `WEBHOOK_BASE_URL=https://kimonokittens.com` on production Dell
2. Update Zigned admin dashboard to point webhook to: `https://kimonokittens.com/api/webhooks/zigned`
3. Verify ZIGNED_WEBHOOK_SECRET matches between Zigned admin interface and Dell `.env`
4. Test webhook delivery with Zigned API test endpoint

**Status:** READY (code exists), NEEDS CONFIG (environment variables + Zigned admin update)

---

### 2. ❌ SSL CERTIFICATES - NOT YET GENERATED (BLOCKER)

**Status:** WILL BREAK  
**Severity:** CRITICAL - HTTPS will fail

**Problem:**
- Dell nginx needs SSL certificates for `https://kimonokittens.com`
- Certificates don't exist yet on Dell
- Browsers will refuse HTTPS connections

**What Must Happen:**
```bash
# On Dell as root
sudo certbot certonly --standalone -d kimonokittens.com
# OR
sudo certbot --nginx -d kimonokittens.com
```

**Current State:**
- Pi has certs at `/etc/letsencrypt/live/kimonokittens.com/`
- Dell nginx config exists (DOMAIN_MIGRATION_CHECKLIST.md line 65-66) but certs not yet in place
- Auto-renewal timer needs setup

**Status:** NEEDS SETUP (documented, not yet executed)

---

### 3. ❌ NGINX CONFIGURATION - INCOMPLETE (BLOCKER)

**Status:** WILL BREAK  
**Severity:** HIGH - 404 errors on all public access

**Problem:**
- DOMAIN_MIGRATION_CHECKLIST.md has complete nginx config (lines 50-137)
- Config assumes Dell has /var/www/kimonokittens/dashboard/ with built frontend
- If nginx not properly configured, port forwarding will go to wrong place

**What Must Happen:**
1. Create `/etc/nginx/sites-available/kimonokittens.com` (from checklist)
2. Verify `/var/www/kimonokittens/dashboard/` exists with built frontend
3. Enable site: `sudo ln -s ... /etc/nginx/sites-enabled/`
4. Test config: `sudo nginx -t`
5. Reload: `sudo systemctl reload nginx`

**Status:** DOCUMENTED (checklist complete), NOT YET DEPLOYED

---

### 4. ⚠️ PORT FORWARDING - NOT YET UPDATED (BLOCKER)

**Status:** WILL BREAK  
**Severity:** HIGH - External access won't reach Dell

**Problem:**
- TP-Link router currently forwards port 80/443 → Pi (192.168.4.66:6464/6465)
- Must be updated to → Dell (192.168.4.84:80/443)
- Done via TP-Link Deco app (lines 171-189 in DOMAIN_MIGRATION_CHECKLIST.md)

**What Must Happen:**
1. Open TP-Link Deco app on iPhone
2. Edit port forwarding rules (port 80 and 443)
3. Change IP from 192.168.4.66 to 192.168.4.84
4. Change ports from 6464/6465 to 80/443

**Status:** MANUAL STEP (not automated, critical for external access)

---

## HANDLER & CODE STATUS

### ✅ TEMPERATURE ENDPOINT - READY
**Location:** `handlers/temperature_handler.rb`

**Current Implementation:**
```ruby
# Lines 9-11: Fallback logic is PERFECT
endpoints = [
  "https://kimonokittens.com/data/temperature",
  "http://192.168.4.66:1880/data/temperature"  # Pi fallback
]
```

**Status:** READY  
**Why Works:** Handler tries kimonokittens.com first, falls back to Pi IP. If domain points to Dell, request will be local (192.168.4.84 loopback), hitting Dell's own `/data/temperature` endpoint which proxies to Node-RED.

**ISSUE:** SSL verification is DISABLED for kimonokittens.com (line 26-27), which is a security concern but necessary for self-signed certs during testing.

---

### ✅ PROXY HANDLER - READY
**Location:** `handlers/proxy_handler.rb`

**Current Implementation:**
```ruby
# Lines 6-9: Identical fallback logic
endpoints = [
  "https://kimonokittens.com",
  "http://192.168.4.66:1880"  # Pi fallback
]
```

**Status:** READY  
**Why Works:** Generic proxy for any `/data/*` endpoints. Falls back to Pi Node-RED if kimonokittens.com unavailable.

---

### ✅ ELECTRICITY PRICE HANDLER - READY
**Location:** `handlers/electricity_price_handler.rb`

**Status:** READY  
**Why Works:** Fetches from `elprisetjustnu.se` (external API), NO DOMAIN DEPENDENCY. Dell fully self-contained.

**Note:** Pi's stale Tibber data (5 months old) is NOT used by this handler. If Node-RED uses Tibber, that's separate concern (see below).

---

### ✅ ZIGNED WEBHOOK HANDLER - READY (BUT CONFIG NEEDED)
**Location:** `puma_server.rb` lines 301-318

```ruby
map "/api/webhooks/zigned" do
  run lambda { |env|
    req = Rack::Request.new(env)
    if req.post?
      handler = ZignedWebhookHandler.new
      result = handler.handle(req)
      [status, {'Content-Type' => 'application/json'}, [body]]
    end
  }
end
```

**Status:** CODE READY, CONFIG BLOCKED  
**Requirement:** WEBHOOK_BASE_URL environment variable must be set on Dell  
**Action Needed:** Set in production `.env`:
```
WEBHOOK_BASE_URL=https://kimonokittens.com
```

---

### ✅ ALL OTHER HANDLERS - READY
- Train departures: External SL API, no domain dependency ✓
- Weather: External API, no domain dependency ✓
- Strava: External API + stored data, no domain dependency ✓
- Rent calculator: Database-driven, no domain dependency ✓
- Todos: Database-driven, no domain dependency ✓
- Display control: Local, no domain dependency ✓
- Sleep schedule: Local, no domain dependency ✓

---

## INFRASTRUCTURE DEPENDENCIES

### ✅ NODE-RED (Pi) - CAN STAY ON PI
**Status:** READY (no change needed)

**Current Configuration:**
- Runs on Pi at `192.168.4.66:1880`
- Handlers have hardcoded fallback to this IP
- Dell has NO dependency on kimonokittens.com for Node-RED access

**Temperature Widget Will Work:** YES
- Dell's `/data/temperature` handler:
  1. First tries `https://kimonokittens.com/data/temperature` (local, loops back)
  2. Falls back to `http://192.168.4.66:1880/data/temperature` (Pi direct)
  3. Both work independently of domain migration

**Action Needed:** None. Keep Node-RED on Pi as-is.

---

### ✅ MOSQUITTO MQTT (Pi) - CAN STAY ON PI
**Status:** READY (no change needed)

**Current Configuration:**
- Runs on Pi at port 1883
- Node-RED subscribes locally (no external access)
- Dashboard has no direct MQTT dependency

**Action Needed:** None. Keep MQTT on Pi as-is.

---

### ✅ ELECTRICITY DATA CRON JOBS
**Status:** READY

**Current Configuration:**
- `vattenfall.rb` scraper: Already working on Pi
- `tibber.rb` scraper: BROKEN (5 months stale, per PI_MIGRATION_MAP.md line 114-118)
- Dell's `/data/electricity_prices` handler uses elprisetjustnu.se instead

**Decision:** 
- Keep working `vattenfall.rb` on Pi (migrating later)
- Ignore broken `tibber.rb` (deprecated in favor of elprisetjustnu.se)
- Dell's handler is INDEPENDENT of domain migration

**Action Needed:** Eventually migrate cron jobs to Dell, but NOT BLOCKING for domain migration.

---

### ⚠️ HEATPUMP SCHEDULE DATA SOURCE - UNKNOWN CRITICAL DEPENDENCY
**Status:** UNCERTAIN - NEEDS INVESTIGATION

**Problem:** PI_MIGRATION_MAP.md lines 310-314 identify this as CRITICAL unknown:
```
4. 🚨 CRITICAL: Heatpump schedule data source - What does Node-RED actually use?
   - Stale Tibber data (5 months old)?
   - Dell's elprisetjustnu.se endpoint?
   - Hardcoded schedule?
```

**Impact:** If Node-RED heatpump schedule depends on Pi data that moves to Dell, heating could break.

**How to Check:**
```bash
# SSH to Pi
ssh pi
cat /home/pi/.node-red/flows.json | jq '.[] | select(.type=="http request") | .url'
# OR look for "Tibber" or "elprisetjustnu" references
```

**Action Needed:** 
1. SSH to Pi and examine Node-RED flows
2. Identify electricity price data source
3. If it uses Tibber: Update to elprisetjustnu.se before migration
4. If it uses elprisetjustnu.se: No change needed (works externally)

---

## DOMAIN MIGRATION READINESS CHECKLIST

### ❌ NOT READY (Blocking Items)

- [ ] SSL certificates generated on Dell (`/etc/letsencrypt/live/kimonokittens.com/`)
- [ ] Nginx configuration deployed (`/etc/nginx/sites-available/kimonokittens.com`)
- [ ] Port forwarding updated in TP-Link Deco app (port 80/443 → Dell IP)
- [ ] WEBHOOK_BASE_URL set on Dell production `.env`
- [ ] Zigned admin dashboard webhook URL updated to `https://kimonokittens.com/api/webhooks/zigned`
- [ ] Node-RED heatpump schedule data source verified and migrated if needed
- [ ] Dell nginx verified running and accessible
- [ ] HTTPS redirect working (HTTP → HTTPS)
- [ ] API endpoints tested via domain (not IP)

### ✅ ALREADY READY (No Action Needed)

- [x] Handlers support domain fallback (temperature, proxy)
- [x] Webhook endpoint code exists and functional
- [x] Zigned webhook handler implemented
- [x] All data endpoints operational on Dell
- [x] WebSocket functional
- [x] Temperature fallback logic in place
- [x] Dashboard frontend built and ready
- [x] Database operational on Dell

---

## DETAILED IMPACT IF DOMAIN POINTS TO DELL NOW

### WHAT WORKS (Immediately)

1. **Dashboard loads** - Served by nginx at port 80/443
2. **Local API endpoints** - All work (rent, weather, trains, todos, etc.)
3. **Temperature widget** - Falls back to Pi Node-RED (192.168.4.66:1880)
4. **WebSocket connection** - Works (proxied via nginx)
5. **Electricity prices** - Works (external elprisetjustnu.se API)
6. **Strava data** - Works (external API)

### WHAT BREAKS (Critical Issues)

1. **SSL/HTTPS** - Certificate error (certs don't exist on Dell)
   - Error: `ERR_CERT_AUTHORITY_INVALID` in browser
   - External access impossible
   - Only workaround: `https://DELL_IP` with self-signed cert acceptance

2. **Zigned contract signing** - Webhook fails silently
   - Contracts created but webhooks can't be received
   - Signature updates won't trigger
   - Signed PDFs won't download automatically
   - Error: Webhook URL unreachable / certificate error

3. **External access (Home network)** - Won't work until port forwarding updated
   - Home IP still points to Pi (192.168.4.66:6464)
   - Must update Deco app port forwarding rules
   - Until updated: Domain resolves but traffic goes to wrong server

4. **Localhost Certificates for kimonokittens.com** - SSL verification disabled in handlers
   - Current code: `options[:verify] = false` for kimonokittens.com
   - SECURITY ISSUE: Disables HTTPS validation
   - Must be fixed once proper certs installed

---

## STEP-BY-STEP TO MAKE DOMAIN MIGRATION WORK

### Phase 1: Infrastructure (2-3 hours, must do first)

```bash
# 1. SSH to Dell as kimonokittens user
ssh pop

# 2. Generate SSL certificates
sudo certbot certonly --standalone -d kimonokittens.com -d www.kimonokittens.com
# (domain must resolve to Dell first, OR use DNS challenge)

# 3. Create nginx config from DOMAIN_MIGRATION_CHECKLIST.md
sudo vi /etc/nginx/sites-available/kimonokittens.com
# Copy config from lines 50-137

# 4. Enable site and test
sudo ln -s /etc/nginx/sites-available/kimonokittens.com /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl reload nginx

# 5. Verify nginx running
sudo systemctl status nginx
```

### Phase 2: Environment Configuration (5 minutes)

```bash
# On Dell, edit production .env
vi /home/kimonokittens/.env

# Add these lines:
WEBHOOK_BASE_URL=https://kimonokittens.com
API_BASE_URL=https://kimonokittens.com

# Restart backend service
sudo systemctl restart kimonokittens-dashboard
sudo systemctl restart kimonokittens-webhook
```

### Phase 3: Router Configuration (5 minutes)

```
1. Open TP-Link Deco app on iPhone
2. Navigate: More → Advanced → NAT Forwarding → Port Forwarding
3. Edit Port 80 rule:
   - Change IP: 192.168.4.66 → 192.168.4.84
   - Change internal port: 6464 → 80
4. Edit Port 443 rule:
   - Change IP: 192.168.4.66 → 192.168.4.84
   - Change internal port: 6465 → 443
5. Save and wait 1-2 minutes for changes to apply
```

### Phase 4: DNS & Verification (immediate)

```bash
# Verify domain resolves to your home IP (should already be doing this via DDClient on Pi)
nslookup kimonokittens.com

# Test HTTPS redirect
curl -I http://kimonokittens.com
# Should return: 301 Moved Permanently → https://kimonokittens.com

# Test API endpoints
curl https://kimonokittens.com/api/rent/friendly_message
curl https://kimonokittens.com/data/temperature

# Test dashboard loads
open https://kimonokittens.com
# Check browser console for WebSocket connection
```

### Phase 5: Zigned Configuration (10 minutes)

```
1. Log into Zigned admin dashboard
2. Go to Webhook settings
3. Set webhook URL: https://kimonokittens.com/api/webhooks/zigned
4. Set webhook secret: (verify matches ZIGNED_WEBHOOK_SECRET in Dell .env)
5. Enable events: case.created, case.signed, case.completed
6. Test webhook (Zigned has test button)
```

### Phase 6: Monitoring (24-48 hours)

```bash
# Monitor Dell logs
sudo journalctl -u kimonokittens-dashboard -f
sudo journalctl -u kimonokittens-webhook -f
tail -f /var/log/nginx/kimonokittens-access.log
tail -f /var/log/nginx/kimonokittens-error.log

# Watch for:
- Nginx 200 responses (working)
- Nginx 502 responses (Puma not responding)
- SSL certificate validation errors
- Webhook delivery failures
```

---

## DEPENDENCY SUMMARY TABLE

| Component | Current | Status | Domain Dependent? | Action for Migration |
|-----------|---------|--------|-------------------|----------------------|
| **Frontend** | Dell nginx | ✅ Ready | NO | Deploy nginx config |
| **API (port 3001)** | Dell Puma | ✅ Ready | NO | Set WEBHOOK_BASE_URL env var |
| **Temperature Widget** | Pi Node-RED | ✅ Ready | NO (fallback) | None needed |
| **Weather** | External API | ✅ Ready | NO | None needed |
| **Train/Bus** | SL API | ✅ Ready | NO | None needed |
| **Strava** | External API | ✅ Ready | NO | None needed |
| **Rent/Finances** | Dell DB | ✅ Ready | NO | None needed |
| **Todos** | Dell DB | ✅ Ready | NO | None needed |
| **Electricity Prices** | External API | ✅ Ready | NO | None needed |
| **Zigned Webhook** | Dell handler | ⚠️ Code OK | YES | Set env var + update Zigned |
| **SSL Certificates** | None on Dell | ❌ NEEDED | YES | Run certbot |
| **Nginx Config** | Not deployed | ❌ NEEDED | YES | Deploy from checklist |
| **Port Forwarding** | Points to Pi | ❌ NEEDED | YES | Update Deco app |
| **Node-RED** | Pi 1880 | ✅ Ready | NO (fallback) | None needed |
| **MQTT** | Pi 1883 | ✅ Ready | NO | None needed |
| **Electricity Cron** | Pi | ⚠️ Stale | Maybe | Investigate tibber.rb |
| **Heatpump Schedule** | Pi | ❓ Unknown | Maybe | SSH Pi → check flows.json |

---

## CRITICAL WARNINGS

### ⚠️ DO NOT MIGRATE DOMAIN IF YOU CAN'T:
1. Update router port forwarding (requires Deco app access)
2. SSH to Dell and run certbot
3. Monitor logs for 24-48 hours
4. Quickly revert (rollback: update Deco app back to Pi)

### ⚠️ ROLLBACK PROCEDURE (If Something Breaks)
```bash
# 1. In Deco app, change port forwarding back:
#    Port 80 → 192.168.4.66:6464
#    Port 443 → 192.168.4.66:6465
# 2. Wait 1-2 minutes for DNS cache to clear
# 3. Restart Pi Agoo server (if stopped)
ssh pi "sudo systemctl start json_server_daemon"
# 4. Debug Dell issues offline
```

### ⚠️ ZIGNED WEBHOOK SECURITY NOTE
- Current code disables SSL verification for kimonokittens.com (line 26)
- This is a SECURITY RISK that must be addressed post-migration
- Once proper SSL certs exist, change: `options[:verify] = true`
- Commit fix to handlers/temperature_handler.rb and handlers/proxy_handler.rb

---

## CONCLUSION

**Can you migrate RIGHT NOW?** 
- **No.** Several critical infrastructure pieces missing.

**What needs to happen first?**
1. SSL certificates on Dell (certbot, ~5 min)
2. Nginx configuration (copy from checklist, ~15 min)
3. Port forwarding update (Deco app, ~5 min)
4. WEBHOOK_BASE_URL environment variable on Dell (~2 min)
5. Verify Zigned webhook settings (~5 min)
6. Test domain access before committing to migration

**Total Time to Ready:** 1-2 hours (mostly certbot waiting)

**Risk Level:** LOW if you follow the DOMAIN_MIGRATION_CHECKLIST.md (which is comprehensive)

**Recommendation:** Block migration until you've completed ALL steps in the checklist. The code is ready; the infrastructure is not.

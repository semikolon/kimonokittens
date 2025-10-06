# Raspberry Pi 3B+ Migration Map
**Created:** October 6, 2025
**Pi Model:** Raspberry Pi 3 Model B Plus Rev 1.3
**OS:** Raspbian GNU/Linux 11 (bullseye)
**Architecture:** ARMv7l (32-bit) - **Claude Code NOT compatible**
**Disk Usage:** 9.9GB / 29GB (36%)

---

## 🎯 Migration Strategy

**Primary approach:** Work from Mac/Dell with Claude Code via SSH
**Reason:** Pi is ARM32 - Claude Code requires ARM64

---

## 📦 Core Services (MUST MIGRATE)

### 1. Node-RED ⭐ HIGH PRIORITY
**Status:** Running (PID 341)
**Service:** `nodered.service` (systemd, enabled)
**Port:** 1880
**Data Directory:** `/home/pi/.node-red/`

**Key Files:**
- `flows.json` - Main Node-RED flows (34KB, last modified Sep 28 18:35)
- `flows_cred.json` - Encrypted credentials
- `settings.js` - Node-RED configuration
- `package.json` / `node_modules/` - 234 installed packages

**What it does:**
- Temperature sensor data aggregation (`/data/temperature` endpoint)
- Heatpump schedule generation from Tibber electricity prices
- MQTT message processing and flow logic
- Various home automation integrations

**Migration Notes:**
- Export flows via Node-RED UI or copy `flows.json` + `flows_cred.json`
- Review `settings.js` for custom configurations
- Document MQTT topics subscribed to
- Test `/data/temperature` endpoint after migration

---

### 2. Mosquitto MQTT Broker ⭐ HIGH PRIORITY
**Status:** Running (PID 493)
**Service:** `mosquitto.service` (systemd, enabled)
**Port:** 1883
**Config:** `/etc/mosquitto/mosquitto.conf`

**Configuration:**
```conf
listener 1883
allow_anonymous true
persistence true
persistence_location /var/lib/mosquitto/
log_dest file /var/log/mosquitto/mosquitto.log
```

**Known Topics:**
- `ThermIQ/ThermIQ-room2-jj/#` - Heatpump data

**Migration Notes:**
- Simple config - can recreate on Dell
- Check `/var/lib/mosquitto/` for persisted messages
- Update Node-RED to point to new MQTT broker address

---

### 3. Ruby JSON Server (Legacy) ⚠️ REVIEW NEEDED
**Status:** Running (PID varies)
**Service:** `json_server_daemon.service` (systemd, enabled)
**File:** `/home/pi/kimonokittens/json_server.rb` (19KB, May 31 2024)
**Ports:** 6464 (HTTP), 6465 (HTTPS)

**What it does:**
- Agoo-based web server
- Serves electricity stats, train departures, Strava data
- SSL certificates: `/etc/letsencrypt/live/kimonokittens.com/`
- Proxies some requests to Node-RED

**Dependencies:**
- Ruby 3.1.0 (via rbenv)
- Gems: agoo, faraday, oj, awesome_print, pry, pry-nav, dotenv

**Migration Decision Needed:**
- ❓ Is this still needed? Dell runs Puma server at `puma_server.rb`
- ❓ Are there unique endpoints not in Dell version?
- ⚠️ SSL certificates will need renewal/transfer

---

### 4. Cron Jobs (Electricity Data Fetching)
**User:** pi
**Configuration:** `/home/pi/kimonokittens/config/schedule.rb` (Whenever gem)

**Active Jobs:**
```bash
# Every 2 hours: Vattenfall scraper
0 0,2,4,6,8,10,12,14,16,18,20,22 * * * bundle exec ruby vattenfall.rb

# Every 2 hours: Tibber API
0 0,2,4,6,8,10,12,14,16,18,20,22 * * * bundle exec ruby tibber.rb

# Every 30 minutes: Autohotspot (WiFi fallback)
*/30 * * * * sudo /usr/bin/autohotspot

# Hourly: Pycalima fan control
0 * * * * python3 /home/pi/pycalima/cmdline.py --hourlyschedule
```

**Scripts to migrate:**
- `/home/pi/kimonokittens/vattenfall.rb` (9.4KB, Jan 16 2024)
- `/home/pi/kimonokittens/tibber.rb` (2.3KB, Aug 11 2023)

**Migration Notes:**
- Update Ruby paths (rbenv on Dell vs Pi)
- Verify database/file write locations
- Check if Dell already has these scripts (likely yes, based on repo)

---

## 🗂️ Data Files (BACKUP & SYNC)

### Electricity Data
- `/home/pi/kimonokittens/electricity_usage.json` (712KB, Oct 6 2025) ⚠️ **LARGE, ACTIVE**
- `/home/pi/kimonokittens/tibber_price_data.json` (26KB, May 2 2025)
- `/home/pi/kimonokittens/cron_log.log` (44MB!, Oct 6 2025) ⚠️ **HUGE LOG FILE**

### Authentication Tokens
- `/home/pi/kimonokittens/.env` (465 bytes) - **CRITICAL: API keys & credentials**
  - Vattenfall credentials
  - SL API key
  - Strava OAuth tokens
  - Tibber API key
  - Admin SSN
- `/home/pi/kimonokittens/.refresh_token` (40 bytes, Sep 27 2025) - Strava OAuth

### Node-RED Data
- `/home/pi/.node-red/flows.json` (35KB, Sep 28 2025)
- `/home/pi/.node-red/flows_cred.json` (encrypted credentials)

---

## 🔧 Configuration Files

### Environment & Ruby
- `/home/pi/kimonokittens/.bashrc` (60 bytes, Mar 13 2023) - Custom rbenv setup
- `/home/pi/kimonokittens/.ruby-version` - Ruby 3.1.0
- `/home/pi/kimonokittens/Gemfile` + `Gemfile.lock`

### Systemd Services
- `/lib/systemd/system/json_server_daemon.service`
- `/lib/systemd/system/nodered.service`
- `/lib/systemd/system/mosquitto.service`

### Web Server (lighttpd)
- `/etc/lighttpd/lighttpd.conf`
- Document root: `/var/www/html/` (contains DakBoard-related PHP files)
- **Note:** Dell uses nginx, not lighttpd - likely irrelevant for migration

---

## 🐍 Python Services

### Pycalima (Bathroom Fan Control)
**Directory:** `/home/pi/pycalima/`
**Function:** Bluetooth-based bathroom fan speed control
**Cron:** Hourly schedule updates
**Dependencies:** `pip3 install Calima==2.0.0`

**Migration Decision:**
- ❓ Does Dell need this? (Bluetooth hardware proximity required)
- ❓ Keep on Pi if Bluetooth hardware stays with Pi?

---

## 🌐 Network Services (REVIEW FOR MIGRATION)

### DDClient (Dynamic DNS)
**Service:** `ddclient.service` (enabled)
**Config:** `/etc/ddclient.conf` (permission denied - requires sudo)
**Function:** Updates kimonokittens.com DNS when IP changes

**Migration Decision:**
- ❓ Should run on Dell if Dell becomes primary server
- ⚠️ Need to read config (requires sudo or www-data access)

### Lighttpd Web Server
**Service:** `lighttpd.service` (enabled)
**Port:** 80
**Document Root:** `/var/www/html/`
**Purpose:** Serving DakBoard-related PHP interface (legacy?)

**Files in /var/www/html/:**
- `index.php`, `api.php`, `dakos-lib.php`
- Various DakBoard configuration files
- Fonts, CSS, JS directories

**Migration Decision:**
- ❓ Is DakBoard still used? (Documentation suggests no)
- ❌ Likely NOT needed on Dell - dashboard replaced DakBoard

---

## 🖥️ Display Services (Pi-Specific, DO NOT MIGRATE)

### Chromium Kiosk Mode
**Startup Script:** `/home/pi/startup/chromium.sh`
**URL:** `http://localhost/screenload.php` (DakBoard)
**Purpose:** Pi was previously used as a display kiosk

**Status:** ❌ **Not relevant** - Dell OptiPlex is now the kiosk display

### VNC Server
**Service:** `vncserver-x11-serviced.service` (running)
**Purpose:** Remote desktop access to Pi

**Migration Decision:**
- ❓ Keep if Pi remains headless in your room
- Useful for debugging/maintenance

---

## 📝 Scripts & Utilities (Archive/Review)

### Job Scrapers (Pi-specific experiments)
- `/home/pi/kimonokittens/job_scraper_example.rb`
- `/home/pi/kimonokittens/job_scraper_simple_example.rb`

**Status:** ❌ Archived in monorepo at `scripts/pi_utils/` - not active

### Process Monitoring
- `/home/pi/kimonokittens/count_chromium.sh`
- `/home/pi/kimonokittens/count_processes.rb`

**Status:** ❌ Archived in monorepo - not needed

### TV Streaming
- `/home/pi/kimonokittens/tv-stream.js`
- `/home/pi/kimonokittens/tv-cast/` directory

**Status:** ❓ Separate project? Review if still needed

### MQTT Logger
- `/home/pi/kimonokittens/mqtt_logger.sh`
- Logs `ThermIQ/ThermIQ-room2-jj/#` topics to `/home/pi/mqtt_logs.txt`

**Status:** ❓ Debugging tool - keep if useful

---

## 🚨 Critical Migration Priorities

### Phase 1: Backup & Verify (DO FIRST)
1. **Backup all data files:**
   ```bash
   rsync -av pi@192.168.4.66:/home/pi/kimonokittens/ ./pi_backup/
   rsync -av pi@192.168.4.66:/home/pi/.node-red/ ./pi_backup/.node-red/
   ```

2. **Copy critical configs:**
   - `.env` file (API keys)
   - `.refresh_token` (Strava)
   - Node-RED flows
   - Cron schedules

### Phase 2: Service Migration (Core Functionality)
1. **Install Mosquitto on Dell**
   - Copy `/etc/mosquitto/mosquitto.conf`
   - Start service, test with `mosquitto_sub`

2. **Install Node-RED on Dell**
   - Import `flows.json` + `flows_cred.json`
   - Update MQTT broker IP (localhost on Dell)
   - Test `/data/temperature` endpoint

3. **Update Cron Jobs on Dell**
   - Move `vattenfall.rb` and `tibber.rb` execution to Dell
   - Verify file paths and database connections
   - Check if Dell repo already has these (likely yes)

4. **Update Handler Proxies**
   - Change `handlers/proxy_handler.rb` on Dell from `192.168.4.66:1880` to `localhost:1880`
   - Change `handlers/temperature_handler.rb` similarly
   - Test dashboard temperature widget

### Phase 3: DNS & Networking (Final Cutover)
1. **Move DDClient to Dell** (if Pi currently updates DNS)
2. **Update SSL certificates** if json_server needs to run on Dell
3. **Test full dashboard** with all widgets
4. **Monitor for 24-48 hours** before decommissioning Pi

---

## 🔍 Open Questions for User

1. **json_server.rb:** Is the Agoo server on Pi still serving any unique endpoints not covered by Dell's Puma server?
2. **DDClient:** Should dynamic DNS updates move to Dell?
3. **Pycalima fan control:** Does Dell need this, or should Pi keep it due to Bluetooth hardware location?
4. **DakBoard/lighttpd:** Can we safely ignore this? (Appears to be legacy dashboard system)
5. **TV-cast project:** Still in use or archive?

---

## 📊 Estimated Migration Effort

| Task | Effort | Risk | Priority |
|------|--------|------|----------|
| Backup data files | 30 min | Low | 🔥 Critical |
| Install Mosquitto on Dell | 15 min | Low | High |
| Migrate Node-RED | 1-2 hrs | Medium | 🔥 Critical |
| Update handler proxies | 15 min | Low | High |
| Test cron scripts on Dell | 30 min | Low | Medium |
| Move DDClient config | 15 min | Medium | Low |
| Full dashboard testing | 1 hr | Medium | High |

**Total estimated time:** 4-5 hours over 2-3 sessions

---

## 🎯 Success Criteria

- [ ] Temperature widget shows live data on dashboard
- [ ] Heatpump schedule updates correctly
- [ ] Electricity data continues to update every 2 hours
- [ ] No errors in Dell backend logs related to Node-RED
- [ ] MQTT broker accessible from all services
- [ ] All API endpoints respond correctly
- [ ] 24-hour stability test passes

---

## 📚 Related Documentation

- `docs/server_migration.md` - Original migration plan (2023)
- `docs/archive/migration-plans/PI_MERGE_NOTES.md` - June 2020 Pi backup merge
- `CLAUDE.md` - Process management and deployment protocols
- `TODO.md` - Dell OptiPlex kiosk deployment status

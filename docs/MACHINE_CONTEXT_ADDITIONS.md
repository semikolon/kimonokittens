# Machine Context Additions for CLAUDE.md Files

**Purpose:** Add machine identification to each system's CLAUDE.md for context awareness

**Created:** November 8, 2025

---

## 1. Mac Mini M2 (Development Machine)

**File location:** `~/.claude/CLAUDE.md` (or `~/dotfiles/current/.claude/CLAUDE.md` - hard-linked, same file)

**Add at the top, after the `# Global Claude Code Rules` heading:**

```markdown
## 🖥️ Machine Context

**This is Fredrik's Mac Mini M2 (2023) - Primary Development Machine**
- **Role:** Software development, testing, prototyping
- **NOT the production server:** Dell Optiplex handles production (kimonokittens.com)
- **NOT the infrastructure server:** Raspberry Pi 3B+ handles DNS, MQTT, Node-RED, sensors
- **Database:** Local development databases (kimonokittens, kimonokittens_test)
- **Deployment:** Code changes are pushed to GitHub → webhook auto-deploys to Dell
```

---

## 2. Dell Optiplex 7010 (Production Server)

**File location:** `/home/kimonokittens/.claude/CLAUDE.md` (or project-specific CLAUDE.md)

**Add at the top, after the `# Global Claude Code Rules` heading:**

```markdown
## 🖥️ Machine Context

**This is the Dell Optiplex 7010 - Production Server**
- **Role:** Production web server, dashboard, API, database (kimonokittens_production)
- **Public hostname:** kimonokittens.com (via home WAN IP)
- **Location:** Physical display in hallway downstairs
- **NOT for development:** Fredrik's Mac Mini M2 handles code development
- **NOT for infrastructure:** Raspberry Pi 3B+ handles DNS, MQTT, sensors
- **Deployment:** Automatic via webhook (receives pushes from GitHub)
- **Services:** Puma (port 3001), Nginx, PostgreSQL, Chrome kiosk
```

---

## 3. Raspberry Pi 3B+ (Infrastructure Server)

**File location:** `/home/pi/.claude/CLAUDE.md` (or wherever Claude Code runs on Pi)

**Add at the top, after the `# Global Claude Code Rules` heading:**

```markdown
## 🖥️ Machine Context

**This is the Raspberry Pi 3B+ - Infrastructure & Automation Server**
- **Role:** Network infrastructure, home automation, sensor aggregation
- **Public hostname:** kimonokittens.com DNS (via DDClient) - but Agoo server being sunset
- **Services:**
  - DDClient (dynamic DNS updates)
  - Pycalima (Bluetooth bathroom fan control)
  - Node-RED (temperature sensors, heatpump schedules, port 1880)
  - Mosquitto MQTT (ThermIQ heatpump data, port 1883)
- **NOT for development:** Fredrik's Mac Mini M2 handles code development
- **NOT for production dashboard:** Dell Optiplex serves kimonokittens dashboard
- **Migration note:** Electricity data cron jobs moved to Dell (Oct 2025)
```

---

## Machine Summary Table

| Machine | Role | Hostname | Key Services | SSH Access |
|---------|------|----------|--------------|------------|
| **Mac Mini M2** | Development | localhost | Code editing, testing, git push | (local) |
| **Dell Optiplex** | Production | kimonokittens.com | Dashboard, API, database, kiosk | `ssh pop` |
| **Raspberry Pi 3B+** | Infrastructure | (DNS host) | Node-RED, MQTT, sensors, DDClient | (to be configured) |

---

## Implementation Steps

### On Mac Mini M2 (Now)
```bash
# Open CLAUDE.md
nano ~/.claude/CLAUDE.md

# Add the "Machine Context" section after "# Global Claude Code Rules"
# Save and exit
```

### On Dell Optiplex (Later)
```bash
# SSH to Dell
ssh pop

# Open CLAUDE.md (check if it exists first)
ls -la ~/.claude/CLAUDE.md
# or
ls -la /home/kimonokittens/Projects/kimonokittens/CLAUDE.md

# Add the "Machine Context" section
nano [appropriate path]
```

### On Raspberry Pi 3B+ (Later)
```bash
# SSH to Pi
ssh [pi-hostname]

# Open or create CLAUDE.md
nano ~/.claude/CLAUDE.md

# Add the "Machine Context" section
```

---

## Notes

- **Hard link on Mac:** `~/.claude/CLAUDE.md` and `~/dotfiles/current/.claude/CLAUDE.md` are the SAME file (inode 134217834). Editing one updates both.
- **Dell location:** May be in global `~/.claude/` or project-specific location. Check both.
- **Pi setup:** Claude Code may not be installed yet. Create file when needed.
- **Purpose:** Prevents confusion about which machine is which, especially when deploying contracts or managing services.

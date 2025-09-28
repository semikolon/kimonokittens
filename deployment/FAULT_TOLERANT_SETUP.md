# Fault-Tolerant Production Setup Strategy

## 🎯 **Problem with Current Script**

The current `setup_production.sh` is an **all-or-nothing** monolithic script:
- ❌ No resumability if it fails halfway
- ❌ No state tracking of completed steps
- ❌ Network failures require complete restart
- ❌ No rollback if you want to undo changes

## 🔧 **Better Approach: Modular & Resumable**

### **Step-by-Step Scripts with State Tracking**

```bash
# Each script creates a marker file when complete
deployment/scripts/
├── 01_install_packages.sh      # Creates: .step01_complete
├── 02_create_users.sh          # Creates: .step02_complete
├── 03_setup_database.sh        # Creates: .step03_complete
├── 04_configure_rbenv.sh       # Creates: .step04_complete
├── 05_build_frontend.sh        # Creates: .step05_complete
├── 06_setup_services.sh        # Creates: .step06_complete
├── 07_configure_kiosk.sh       # Creates: .step07_complete
└── master_setup.sh             # Orchestrates all steps
```

### **Master Script with Resume Logic**

```bash
#!/bin/bash
# deployment/scripts/master_setup.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_DIR="/tmp/kimonokittens_setup"
mkdir -p "$STATE_DIR"

run_step() {
    local step_num="$1"
    local step_name="$2"
    local script_file="$3"
    local marker_file="$STATE_DIR/.step${step_num}_complete"

    if [ -f "$marker_file" ]; then
        echo "✅ Step $step_num ($step_name) already completed, skipping"
        return 0
    fi

    echo "🔄 Running Step $step_num: $step_name"
    if bash "$SCRIPT_DIR/$script_file"; then
        touch "$marker_file"
        echo "✅ Step $step_num completed successfully"
    else
        echo "❌ Step $step_num failed. Fix the issue and re-run this script."
        echo "   The script will resume from this step."
        exit 1
    fi
}

# Resume capability - run from where it left off
run_step "01" "Install Packages" "01_install_packages.sh"
run_step "02" "Create Users" "02_create_users.sh"
run_step "03" "Setup Database" "03_setup_database.sh"
run_step "04" "Configure rbenv" "04_configure_rbenv.sh"
run_step "05" "Build Frontend" "05_build_frontend.sh"
run_step "06" "Setup Services" "06_setup_services.sh"
run_step "07" "Configure Kiosk" "07_configure_kiosk.sh"

echo "🎉 All steps completed successfully!"
```

### **Individual Step Scripts (Idempotent)**

**Example: `03_setup_database.sh`**
```bash
#!/bin/bash
set -e

# Check if database already exists
if sudo -u postgres psql -lqt | cut -d \| -f 1 | grep -qw kimonokittens_production; then
    echo "✅ Database kimonokittens_production already exists"
    exit 0
fi

# Check if user already exists
if sudo -u postgres psql -c "SELECT 1 FROM pg_user WHERE usename = 'kimonokittens'" | grep -q 1; then
    echo "✅ Database user kimonokittens already exists"
else
    echo "Creating database user..."
    # Use environment variable or prompt once and store
    if [ -z "$DB_PASSWORD" ]; then
        echo "Enter password for database user 'kimonokittens':"
        read -s DB_PASSWORD
        export DB_PASSWORD
    fi
    sudo -u postgres psql -c "CREATE USER kimonokittens WITH PASSWORD '$DB_PASSWORD';"
fi

# Create database
sudo -u postgres createdb kimonokittens_production -O kimonokittens
echo "✅ Database setup complete"
```

## 🛠️ **Enhanced Features**

### **1. Status Command**
```bash
# deployment/scripts/status.sh
STATE_DIR="/tmp/kimonokittens_setup"

echo "=== Setup Status ==="
for i in {01..07}; do
    if [ -f "$STATE_DIR/.step${i}_complete" ]; then
        echo "✅ Step $i: Complete"
    else
        echo "⏳ Step $i: Pending"
    fi
done
```

### **2. Reset Command**
```bash
# deployment/scripts/reset.sh
echo "⚠️  This will reset all setup progress. Continue? (y/N)"
read -r response
if [[ "$response" =~ ^[Yy]$ ]]; then
    rm -rf /tmp/kimonokittens_setup
    echo "🔄 Setup state reset. Re-run master_setup.sh"
fi
```

### **3. Rollback Command**
```bash
# deployment/scripts/rollback.sh
echo "🚨 Rolling back production changes..."

# Remove auto-login
sudo sed -i 's/autologin-user=kimonokittens/#autologin-user=/' /etc/lightdm/lightdm.conf

# Stop and disable services
sudo systemctl stop kimonokittens-dashboard 2>/dev/null || true
sudo systemctl disable kimonokittens-dashboard 2>/dev/null || true

# Remove service files
sudo rm -f /etc/systemd/system/kimonokittens-*.service

# Optional: Remove user (ask first)
echo "Remove kimonokittens user? (y/N)"
read -r response
if [[ "$response" =~ ^[Yy]$ ]]; then
    sudo userdel -r kimonokittens 2>/dev/null || true
fi

echo "✅ Rollback complete"
```

## 🎯 **For Your Home Dashboard**

### **Recommended Approach:**
1. **Keep current monolithic script** for simplicity
2. **Add basic resumability** with state tracking
3. **Add rollback script** for easy cleanup
4. **Test on a VM first** to identify failure points

### **Quick Wins (15 minutes to implement):**
```bash
# Add to beginning of setup_production.sh:
STATE_FILE="/tmp/kimonokittens_setup_step"

# Before each major step:
echo "STEP_X" > "$STATE_FILE"

# Add resume logic:
if [ -f "$STATE_FILE" ]; then
    RESUME_FROM=$(cat "$STATE_FILE")
    echo "Resuming from: $RESUME_FROM"
fi
```

### **Home Dashboard Reality Check:**
- **Monolithic script**: Probably fine for one-time setup
- **Network failures**: Most likely failure point (npm, git)
- **Database issues**: Second most likely (password, permissions)
- **LightDM changes**: Hardest to debug if something goes wrong

**Recommendation**: Run the script as-is, but have the rollback plan ready in case you need to undo the kiosk boot changes.
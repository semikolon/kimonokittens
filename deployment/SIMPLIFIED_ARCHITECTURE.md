# Simplified Single-User Production Architecture

## 🎯 **Architectural Decision: Single Service User**

Based on security review and complexity concerns, we've simplified the production deployment to use **one service user** instead of two.

## 📊 **Architecture Comparison**

### **❌ Original (Complex): Multi-User**
```
fredrik      → Development user
kimonokittens → Backend service user
kiosk        → Display-only user
www-data     → Nginx static files
```

### **✅ New (Simplified): Single Service User**
```
fredrik      → Development user
kimonokittens → Backend + kiosk service user
www-data     → Nginx static files
```

## 🔧 **What Changed**

### **User Management**
- **Before**: `useradd kimonokittens` + `useradd kiosk`
- **After**: `useradd kimonokittens` (with video group for display)

### **SystemD Services**
- **Before**: Separate users for dashboard vs kiosk services
- **After**: Same user `kimonokittens` runs both services

### **Auto-login Configuration**
- **Before**: `autologin-user=kiosk`
- **After**: `autologin-user=kimonokittens`

### **File Permissions**
- **Before**: Complex cross-user file sharing
- **After**: Single user owns all application files

## ✅ **Benefits of Simplified Approach**

### **Reduced Complexity**
- ✅ **One less user** to manage and debug
- ✅ **Simpler permission model** - no cross-user file access
- ✅ **Easier troubleshooting** - all processes under one user
- ✅ **Cleaner systemd** - consistent user across services

### **Maintained Security**
- ✅ **Still isolated** from development user (`fredrik`)
- ✅ **Service hardening** - NoNewPrivileges, ProtectSystem
- ✅ **Dedicated user** - not running as root or main user
- ✅ **Standard practice** - many production apps use single service user

### **Better Operations**
- ✅ **Log aggregation** - all logs under kimonokittens user
- ✅ **Process monitoring** - easier to track related processes
- ✅ **Resource limits** - can apply systemd limits to one user
- ✅ **Backup strategy** - single home directory to backup

## 🔒 **Security Model**

### **Isolation Layers**
1. **User isolation**: `kimonokittens` ≠ `fredrik` ≠ `root`
2. **SystemD hardening**: NoNewPrivileges, ProtectSystem
3. **Network isolation**: Services bind to localhost only
4. **File permissions**: Minimal required access

### **Attack Surface**
- **Web application**: Ruby backend (isolated to kimonokittens user)
- **Display system**: Firefox kiosk (same user, minimal privileges)
- **Database**: PostgreSQL (separate postgres user)
- **Web server**: Nginx (www-data user)

## 📋 **Deployment Changes**

### **Script Name**
- **Final**: `setup_production.sh` (single consolidated script)
- **Removed**: All previous versions consolidated

### **Command**
```bash
sudo bash deployment/scripts/setup_production.sh
```

### **What It Does**
1. **Install packages**: PostgreSQL, Nginx, Chromium, build tools
2. **Create user**: `kimonokittens` with video group access
3. **Setup rbenv**: Copy Ruby environment to service user
4. **Configure services**: SystemD services for both backend and kiosk
5. **Deploy frontend**: Build and copy to nginx web root
6. **Setup database**: Create DB, run migrations, import data
7. **Configure kiosk**: Auto-login and Firefox kiosk mode

## 🚀 **Production Flow**

### **Boot Sequence**
1. **System boot** → LightDM starts
2. **Auto-login** → `kimonokittens` user logged in
3. **SystemD** → `kimonokittens-dashboard.service` starts Ruby backend
4. **Desktop** → Chromium launches in kiosk mode with GPU acceleration
5. **Display** → Dashboard loads from http://localhost

### **Service Dependencies**
```
postgresql.service
    ↓
kimonokittens-dashboard.service
    ↓
kimonokittens-kiosk.service (Firefox)
```

## 📊 **Monitoring Points**

### **Health Checks**
- `systemctl status kimonokittens-dashboard` - Backend health
- `curl http://localhost:3001/health` - API health
- `curl http://localhost/` - Frontend health
- `ps aux | grep chromium` - Kiosk display

### **Log Locations**
- **Backend**: `journalctl -u kimonokittens-dashboard -f`
- **Kiosk**: `journalctl -u kimonokittens-kiosk -f`
- **Nginx**: `/var/log/nginx/access.log`
- **Application**: `/var/log/kimonokittens/`

## 🎯 **Success Criteria**

**Deployment successful when**:
- ✅ Single `kimonokittens` user created and configured
- ✅ Ruby backend running on port 3001
- ✅ Chromium kiosk displaying dashboard fullscreen with GPU acceleration
- ✅ Auto-login working on boot
- ✅ GitHub webhook ready for configuration

**Ready to deploy!** The simplified approach maintains security while reducing operational complexity.
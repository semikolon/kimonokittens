# Kimonokittens Production Deployment

## 🎯 **Quick Start**

Deploy Kimonokittens dashboard as a production kiosk on Dell Optiplex:

```bash
sudo bash deployment/scripts/setup_production.sh
```

**That's it!** ☝️ This single command handles everything automatically.

## 📚 **Documentation Structure**

### **For Deployment**
- **`DEPLOYMENT_CHECKLIST.md`** - Step-by-step deployment checklist with verification
- **`deployment/scripts/setup_production.sh`** - Automated setup script
- **`MANUAL_SETUP_COMMANDS.md`** - Manual commands (if script fails)

### **For Understanding**
- **`SIMPLIFIED_ARCHITECTURE.md`** - Technical architecture overview
- **`DEPLOYMENT_DECISIONS.md`** - Rationale for key architectural decisions
- **`DOTFILES_SETUP_BLOCKER.md`** - Critical configuration requirements
- **`../DELL_OPTIPLEX_KIOSK_DEPLOYMENT.md`** - Comprehensive reference guide

## 🏗️ **What Gets Deployed**

### **Single Command Creates**
- ✅ **PostgreSQL database** with production data migration
- ✅ **Nginx web server** serving dashboard
- ✅ **Ruby backend** (3.3.8 via rbenv) with real-time data
- ✅ **Google Chrome kiosk** with GPU acceleration (official .deb)
- ✅ **SystemD services** for reliability
- ✅ **GDM3 auto-login** with native GNOME integration

### **Architecture (Pop!_OS 22.04 Native)**
```
Dell Optiplex → GDM3 auto-login → kimonokittens user → Google Chrome kiosk
                                       ↓                        ↓
                               GNOME autostart              Dashboard
                                       ↓
                               Ruby backend (port 3001) ← PostgreSQL
                                       ↓
                               Nginx (port 80) ← Dashboard build
```

## ⚡ **Performance Optimizations**

- **Google Chrome browser** (superior WebGL performance for dashboard animations)
- **Official .deb package** (no snap sandbox overhead)
- **GPU acceleration** enabled for smooth animations
- **Hardware-optimized** kiosk flags
- **Native Pop!_OS integration** (GDM3, GNOME autostart)
- **Modern secure GPG keyring** (no deprecated apt-key warnings)

## 🔒 **Security**

- **Isolated service user** (`kimonokittens`) separate from development user
- **SystemD hardening** (NoNewPrivileges, ProtectSystem)
- **Localhost-only** API binding
- **No root access** for application services

## 🚀 **Post-Deployment**

After script completes:

1. **Configure GitHub webhook** (see checklist)
2. **Reboot** to activate kiosk mode: `sudo reboot`
3. **Verify** dashboard loads fullscreen automatically

## 🆘 **Troubleshooting**

- **Check status**: `bash deployment/scripts/check_system_status.sh`
- **View logs**: `journalctl -u kimonokittens-dashboard -f`
- **Manual fallback**: Follow `MANUAL_SETUP_COMMANDS.md`

---

**Ready to deploy?** Run the script and follow the checklist! 🎯
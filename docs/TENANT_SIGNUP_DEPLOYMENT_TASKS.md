# Deployment Task Breakdown for Tenant Signup PR

## ✅ Serverside CC Agent CAN Do (kimonokittens user)

### 1. Git Operations
- ✅ `git fetch origin master`
- ✅ `git checkout claude/prioritize-todo-tasks-01BismLPp9uGe1itBpQNTSTi`
- ✅ View git status, diffs, logs
- ✅ Read all codebase files

### 2. Database Migration
- ✅ `npx prisma migrate deploy` (runs as kimonokittens user)
- ✅ `npx prisma migrate status` (check migration status)
- ✅ Query database to verify TenantLead table created

### 3. Dependency Installation
- ✅ `bundle install --deployment` (Ruby gems)
- ✅ `npm ci` (Node dependencies from project root)

### 4. Service Management (kimonokittens user services)
- ✅ `systemctl --user restart kimonokittens-kiosk` (kiosk display)
- ✅ `systemctl --user status kimonokittens-kiosk`

### 5. Monitoring & Verification
- ✅ `tail -f /var/log/kimonokittens/*.log`
- ✅ `journalctl -u kimonokittens-dashboard -f`
- ✅ Check for errors in logs
- ✅ Verify nginx config files (read-only)
- ✅ Test API endpoints via curl

### 6. Code Analysis
- ✅ Review handler implementations
- ✅ Verify frontend build output
- ✅ Check WebSocket integration
- ✅ Analyze rate limiting logic

---

## ⚠️ REQUIRES USER/SUDO (fredrik user)

### 1. Git Workflow Decisions
- ❌ Merge PR to master (requires authorization)
- ❌ Push to remote branches
- ❌ Create/delete branches

### 2. System Services (root systemd)
- ❌ `sudo systemctl restart kimonokittens-dashboard` (backend API)
- ❌ `sudo systemctl restart kimonokittens-webhook`
- ❌ `sudo systemctl status kimonokittens-*`

### 3. External Services Setup
- ❌ Register Cloudflare Turnstile account (https://dash.cloudflare.com)
- ❌ Generate Turnstile siteKey + secretKey
- ❌ Update .env with TURNSTILE_SECRET_KEY

### 4. File System Operations (if needed)
- ❌ Nginx config changes (requires sudo)
- ❌ File ownership changes: `sudo chown -R kimonokittens:kimonokittens ...`
- ❌ System font extraction (Horsemen font from /usr/share/fonts)

### 5. Browser Testing
- ❌ Test signup form at https://kimonokittens.com/meow
- ❌ Verify mobile responsive layout
- ❌ Test CAPTCHA widget rendering
- ❌ Verify admin dashboard UI updates

---

## 📋 Recommended Deployment Workflow

### Step 1: Merge & Push (YOU do this)
```bash
# On Mac development machine
cd ~/Projects/kimonokittens
git checkout master
git merge claude/prioritize-todo-tasks-01BismLPp9uGe1itBpQNTSTi
git push origin master  # Triggers webhook deployment
```

### Step 2: Wait for Webhook (AUTOMATIC)
- Webhook pulls latest code
- Runs npm ci + vite build
- Deploys frontend to nginx
- Restarts backend service

### Step 3: Run Migration (CC AGENT)
```bash
cd /home/kimonokittens/Projects/kimonokittens
npx prisma migrate deploy
npx prisma migrate status  # Verify
```

### Step 4: Verify Backend (CC AGENT)
```bash
# Test signup endpoint
curl -X POST http://localhost:3001/api/signup \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Test User",
    "contactMethod": "email",
    "contactValue": "test@example.com",
    "moveInFlexibility": "immediate"
  }'

# Should return rate limit after 2 requests from same IP

# Test admin leads endpoint (requires PIN)
curl http://localhost:3001/api/admin/leads \
  -H "X-Admin-Token: YOUR_PIN"
```

### Step 5: Check Logs (CC AGENT)
```bash
# Monitor for errors
journalctl -u kimonokittens-dashboard -n 50 | grep -E "(error|ERROR|Lead|signup)"

# Check frontend logs
tail -f /var/log/kimonokittens/frontend.log
```

### Step 6: Verify Services (CC AGENT for kiosk, YOU for dashboard)
```bash
# Kiosk (CC agent can do)
systemctl --user status kimonokittens-kiosk

# Dashboard backend (requires sudo - YOU do)
sudo systemctl status kimonokittens-dashboard
```

### Step 7: Browser Testing (YOU do this)
1. Visit https://kimonokittens.com/meow (or /curious, /signup)
2. Verify form renders correctly
3. Test form submission (name + contact method + move-in)
4. Verify success modal appears
5. Check admin dashboard shows new lead
6. Test status changes, notes, delete
7. Test keyboard navigation (arrows, enter, escape)

### Step 8: Cloudflare Turnstile (YOU do this - when ready)
1. Create Cloudflare account
2. Go to Turnstile dashboard
3. Add site: kimonokittens.com
4. Copy siteKey (paste in SignupForm.tsx)
5. Copy secretKey (add to production .env as TURNSTILE_SECRET_KEY)
6. Redeploy frontend (push to trigger webhook)
7. Test CAPTCHA widget appears and validates

### Step 9: Optional Enhancements (DEFERRED)
- ❌ Extract Horsemen font (requires system fonts access)
- ❌ SMS notifications (requires SMS service API keys)
- ❌ Email notifications (requires email service setup)

---

## 🚨 Critical: What NOT to Do

### CC Agent Must NOT:
- ❌ Push to remote branches without explicit user authorization
- ❌ Run sudo commands (will fail with password prompt)
- ❌ Modify nginx configs (requires sudo)
- ❌ Restart root systemd services (requires sudo)
- ❌ Access external web services (Cloudflare, SMS APIs)

### Per CLAUDE.md:
> **🔴 CRITICAL: NEVER PUSH WITHOUT EXPLICIT USER AUTHORIZATION 🔴**
> - **ALWAYS ask "Ready to push to production?" before `git push`**
> - **User must explicitly say "yes" or "push it" or similar**
> - Pushing = Immediate production deployment via webhook

---

## 📊 Task Distribution Summary

| Task Category | CC Agent | User |
|--------------|----------|------|
| Code review & analysis | ✅ | - |
| Database migration | ✅ | - |
| Dependency install | ✅ | - |
| Log monitoring | ✅ | - |
| API testing (curl) | ✅ | - |
| Git merge/push | ❌ | ✅ |
| Sudo systemctl | ❌ | ✅ |
| Browser testing | ❌ | ✅ |
| External service setup | ❌ | ✅ |
| Production deployment decision | ❌ | ✅ |

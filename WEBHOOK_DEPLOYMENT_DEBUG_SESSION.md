# Webhook Deployment Debugging Session - Oct 2, 2025

## CRITICAL DISCOVERIES

### 1. Ruby Thread Silent Death Bug
**Problem:** Deployment thread was crashing silently after rsync with ZERO error logs.

**Root Cause:** Ruby threads die silently when exceptions occur unless `Thread.report_on_exception` is enabled.

**Fix Applied:** Added to `deployment/scripts/webhook_puma_server.rb` (lines 12-14):
```ruby
Thread.report_on_exception = true
Thread.abort_on_exception = false  # Don't kill entire process, just report
```

**Commit:** `22c2157` - "fix: enable Thread.report_on_exception to debug silent deployment failures"

### 2. Backend Reload Used sudo (Failed)
**Problem:** Backend deployment tried `sudo systemctl restart` but `kimonokittens` user not in sudoers.

**Fix Applied:** Changed to `kill -USR1 <pid>` (graceful Puma reload, no sudo needed)
- Gets PID from: `systemctl show kimonokittens-dashboard --property=MainPID --value`
- Sends USR1 signal directly to Puma process

**Commit:** `9cd9de5` - "fix: remove sudo from backend reload, use USR1 signal instead"

### 3. Reload Handler Bug
**Problem:** `handlers/reload_handler.rb` used `req.post?` but received raw Rack env hash.

**Fix Applied:** Changed `call(req)` to `call(env)` and `req.post?` to `env['REQUEST_METHOD'] == 'POST'`

**Commit:** `d4c689d` - "fix: reload handler using wrong Rack interface"

### 4. Frontend Deployment Missing Git Pull
**Problem:** `deploy_frontend` had no git pull step - built from stale code!

**Fix Applied:** Added git pull to frontend deployment (lines 388-393 in webhook_puma_server.rb)

**Commit:** Previous session (already deployed)

### 5. npm Peer Dependency Issues
**Problem:** React 19 canary incompatible with framer-motion without flag.

**Fix Applied:** Added `--legacy-peer-deps` to npm ci command (line 400)

## CURRENT STATE (as of 13:07)

### Production Checkout Status
- **Location:** `/home/kimonokittens/Projects/kimonokittens/`
- **Current commit:** `8ffd512` (just pulled)
- **Includes:**
  - ✅ Thread exception reporting
  - ✅ USR1 backend reload (no sudo)
  - ✅ Reload handler fix
  - ✅ Frontend git pull
  - ✅ npm --legacy-peer-deps
  - ✅ Documentation updates

### Services Status
- **kimonokittens-webhook:** Needs restart to load new code (user already restarted manually)
- **kimonokittens-dashboard:** Running, needs USR1 reload if backend changed
- **Frontend:** Files deployed but kiosk not reloaded yet

## NEXT STEPS TO COMPLETE DEPLOYMENT

### Step 1: Restart Webhook (MANUAL - User must do this)
```bash
sudo systemctl restart kimonokittens-webhook
```

### Step 2: Trigger Test Deployment
Make a trivial frontend change and push:
```bash
# In /home/fredrik/Projects/kimonokittens/
# Edit dashboard/src/index.css - change test comment
git add dashboard/src/index.css
git commit -m "test: final deployment test with all fixes"
git push origin master
```

### Step 3: Watch Deployment Logs (2min debounce + ~30s build)
```bash
# Watch for exceptions (now visible with Thread.report_on_exception!)
journalctl -u kimonokittens-webhook -f

# Check for completion including reload trigger
journalctl -u kimonokittens-webhook --since "2 minutes ago" | grep -E "⏰|Frontend|reload|Deployment completed|exception"
```

### Step 4: Verify Frontend Reloaded
Check kiosk browser reloaded automatically via WebSocket message.

## WEBHOOK SELF-RESTART LIMITATION (PERMANENT)

**The webhook service CANNOT automatically restart itself when its own code changes.**

**Why:** Chicken-and-egg problem - deployment thread runs inside the process that needs to restart.

**Solution:** Always manually restart webhook after deployment script changes:
```bash
sudo systemctl restart kimonokittens-webhook
```

**Detection command:**
```bash
journalctl -u kimonokittens-webhook --since "5 minutes ago" | grep "Backend change detected: deployment"
# If found → restart webhook
```

**Documented in:** CLAUDE.md lines 557-578

## KEY FILES MODIFIED

1. `deployment/scripts/webhook_puma_server.rb`
   - Lines 12-14: Thread exception reporting
   - Lines 365-374: USR1 backend reload (no sudo)
   - Lines 388-393: Frontend git pull
   - Line 400: npm --legacy-peer-deps

2. `handlers/reload_handler.rb`
   - Line 10-12: Fixed Rack env handling

3. `CLAUDE.md`
   - Lines 557-578: Webhook self-restart limitation documentation

## DEBUGGING COMMANDS

### Check if deployment is stuck
```bash
curl -s http://localhost:9001/status | jq .deployment
```

### Check webhook logs for exceptions
```bash
journalctl -u kimonokittens-webhook --since "5 minutes ago" --no-pager
```

### Check dashboard logs for reload broadcasts
```bash
journalctl -u kimonokittens-dashboard --since "1 minute ago" | grep -i reload
```

### Verify files deployed
```bash
ls -lh /var/www/kimonokittens/dashboard/index.html
```

### Check production git status
```bash
git -C /home/kimonokittens/Projects/kimonokittens log -1 --format="%h %s"
git -C /home/kimonokittens/Projects/kimonokittens status
```

## RESOLVED ISSUES

1. ✅ Silent thread death - now reports exceptions
2. ✅ sudo backend restart - now uses USR1 signal
3. ✅ Reload handler crash - fixed Rack interface
4. ✅ Frontend stale code - added git pull
5. ✅ npm peer dependencies - added --legacy-peer-deps
6. ✅ Git ownership errors - fixed with chown + chmod
7. ✅ No sudo usage anywhere - confirmed clean

## STILL UNTESTED

- Complete deployment flow with all fixes
- Frontend auto-reload via WebSocket
- Backend USR1 reload
- Exception reporting actually showing errors

**NEXT SESSION:** Test complete deployment flow end-to-end after webhook restart.

# Screenshot API

Simple API for capturing screenshots of the kiosk display without SSH/sudo gymnastics.

## Setup (One-Time)

Install scrot on production:

```bash
ssh pop "sudo apt-get install -y scrot"
```

Then push this code to master to deploy the API endpoint.

## Usage

### 1. Capture a new screenshot

**From your Mac browser:**
```
http://pop:3001/api/screenshot/capture
```

**From command line:**
```bash
curl http://pop:3001/api/screenshot/capture
```

**Response:**
```json
{
  "success": true,
  "filename": "kiosk-20251009-163045.png",
  "path": "/tmp/kimonokittens-screenshots/kiosk-20251009-163045.png",
  "size": 1234567,
  "download_url": "/api/screenshot/latest?download=kiosk-20251009-163045.png",
  "view_url": "/api/screenshot/latest"
}
```

### 2. View the latest screenshot

**In browser:**
```
http://pop:3001/api/screenshot/latest
```

This displays the most recent screenshot directly in your browser.

### 3. Download to Mac

One-liner to capture, download, and open:
```bash
curl http://pop:3001/api/screenshot/capture && \
curl http://pop:3001/api/screenshot/latest > ~/Desktop/kiosk-latest.png && \
open ~/Desktop/kiosk-latest.png
```

## Features

- ✅ **No SSH required** - Pure HTTP API
- ✅ **No sudo required** - Backend runs as kimonokittens user with display access
- ✅ **Auto-cleanup** - Keeps last 10 screenshots, deletes older ones
- ✅ **Timestamp naming** - Each screenshot has unique filename
- ✅ **Fast** - Direct display capture, no authentication overhead

## Technical Details

- **Handler**: `handlers/screenshot_handler.rb`
- **Endpoints**:
  - `GET /api/screenshot/capture` - Take new screenshot
  - `GET /api/screenshot/latest` - View most recent screenshot
- **Storage**: `/tmp/kimonokittens-screenshots/`
- **Format**: PNG (via scrot)
- **Retention**: Last 10 screenshots only

## Why This Works

The puma_server.rb backend:
1. Runs as `kimonokittens` user
2. Has DISPLAY=:0 environment access (set by systemd)
3. Can execute scrot without privilege escalation
4. Serves files directly via Rack

This eliminates all SSH/sudo/machinectl authentication complexity.

## Troubleshooting

**Error: "scrot command failed"**
```bash
ssh pop "sudo apt-get install -y scrot"
```

**Error: "Screenshot file not created"**
Check DISPLAY environment variable:
```bash
ssh pop 'machinectl shell kimonokittens@.host /usr/bin/bash -c "echo \$DISPLAY"'
```

Should return `:0`. If empty, the systemd service may need `Environment="DISPLAY=:0"`.

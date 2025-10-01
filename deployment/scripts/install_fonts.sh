#!/bin/bash
# Font Installation Script for Kimonokittens Dashboard
# Installs Galvji, Horsemen, and JetBrains Mono fonts system-wide

set -e  # Exit on any error

# Configuration
FONT_SOURCE_DIR="${1:-/tmp/kimonokittens-fonts}"
SYSTEM_FONT_DIR="/usr/local/share/fonts/kimonokittens"

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] WARNING:${NC} $1"
}

error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1"
    exit 1
}

# Check if running with sudo
if [ "$EUID" -ne 0 ]; then
    error "Please run this script with sudo"
fi

log "=== Kimonokittens Font Installation ==="
log "Source directory: $FONT_SOURCE_DIR"
log ""

# Step 1: Install JetBrains Mono from apt (easy)
log "Installing JetBrains Mono from package manager..."
if dpkg -l | grep -q fonts-jetbrains-mono; then
    log "✅ JetBrains Mono already installed"
else
    apt update
    apt install -y fonts-jetbrains-mono
    log "✅ JetBrains Mono installed"
fi

# Step 2: Check if custom fonts exist
log ""
log "Checking for custom fonts (Galvji, Horsemen)..."

FONTS_FOUND=false
GALVJI_FOUND=false
HORSEMEN_FOUND=false

if [ -d "$FONT_SOURCE_DIR" ]; then
    # Check for Galvji
    if find "$FONT_SOURCE_DIR" -iname "*galvji*" -type f | grep -q .; then
        GALVJI_FOUND=true
        log "✅ Found Galvji font files"
    fi

    # Check for Horsemen
    if find "$FONT_SOURCE_DIR" -iname "*horsemen*" -type f | grep -q .; then
        HORSEMEN_FOUND=true
        log "✅ Found Horsemen font files"
    fi

    if [ "$GALVJI_FOUND" = true ] && [ "$HORSEMEN_FOUND" = true ]; then
        FONTS_FOUND=true
    fi
else
    warn "Font source directory not found: $FONT_SOURCE_DIR"
fi

if [ "$FONTS_FOUND" = false ]; then
    warn "Custom fonts not found in $FONT_SOURCE_DIR"
    echo ""
    echo "Please copy font files from your Mac using:"
    echo "  mkdir -p $FONT_SOURCE_DIR"
    echo "  scp ~/Library/Fonts/Galvji* pop:$FONT_SOURCE_DIR/"
    echo "  scp ~/Library/Fonts/Horsemen* pop:$FONT_SOURCE_DIR/"
    echo ""
    echo "Then run this script again: sudo $0"
    exit 1
fi

# Step 3: Install custom fonts
log ""
log "Installing custom fonts system-wide..."

# Create system font directories
mkdir -p "$SYSTEM_FONT_DIR/galvji"
mkdir -p "$SYSTEM_FONT_DIR/horsemen"

# Copy Galvji fonts
log "Installing Galvji..."
find "$FONT_SOURCE_DIR" -iname "*galvji*" -type f -exec cp {} "$SYSTEM_FONT_DIR/galvji/" \;
chmod 644 "$SYSTEM_FONT_DIR/galvji/"*
log "✅ Galvji installed"

# Copy Horsemen fonts
log "Installing Horsemen..."
find "$FONT_SOURCE_DIR" -iname "*horsemen*" -type f -exec cp {} "$SYSTEM_FONT_DIR/horsemen/" \;
chmod 644 "$SYSTEM_FONT_DIR/horsemen/"*
log "✅ Horsemen installed"

# Step 4: Update font cache
log ""
log "Updating system font cache..."
fc-cache -f -v > /dev/null 2>&1
log "✅ Font cache updated"

# Step 5: Verify installation
log ""
log "Verifying font installation..."

VERIFY_PASS=true

if fc-list | grep -iq "galvji"; then
    log "✅ Galvji verified in font cache"
else
    warn "❌ Galvji not found in font cache"
    VERIFY_PASS=false
fi

if fc-list | grep -iq "horsemen"; then
    log "✅ Horsemen verified in font cache"
else
    warn "❌ Horsemen not found in font cache"
    VERIFY_PASS=false
fi

if fc-list | grep -iq "jetbrains"; then
    log "✅ JetBrains Mono verified in font cache"
else
    warn "❌ JetBrains Mono not found in font cache"
    VERIFY_PASS=false
fi

log ""
if [ "$VERIFY_PASS" = true ]; then
    log "🎉 All fonts installed successfully!"
    log ""
    log "Installed fonts:"
    log "  - Galvji (sans-serif primary)"
    log "  - Horsemen (decorative widget titles)"
    log "  - JetBrains Mono (monospace)"
    log ""
    log "Restart browser/kiosk to see fonts in action:"
    log "  sudo -u kimonokittens systemctl --user restart kimonokittens-kiosk"
else
    error "Font verification failed. Check output above."
fi

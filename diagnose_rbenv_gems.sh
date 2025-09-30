#!/bin/bash
# Diagnostic script for rbenv/bundle/gem issues in systemd context
# Run with: sudo bash diagnose_rbenv_gems.sh

echo "=== Kimonokittens Ruby Environment Diagnosis ==="
echo "Date: $(date)"
echo

# Switch to service user context
SERVICE_USER="kimonokittens"
PROJECT_DIR="/home/$SERVICE_USER/Projects/kimonokittens"

echo "=== 1. Service User Environment ==="
sudo -u "$SERVICE_USER" bash -lc 'whoami && pwd'
echo

echo "=== 2. Ruby Version and Location ==="
sudo -u "$SERVICE_USER" bash -lc 'which ruby && ruby --version'
echo

echo "=== 3. rbenv Status ==="
sudo -u "$SERVICE_USER" bash -lc 'which rbenv && rbenv version'
echo

echo "=== 4. Gem Environment ==="
sudo -u "$SERVICE_USER" bash -lc "cd $PROJECT_DIR && gem env | head -15"
echo

echo "=== 5. Bundle Configuration ==="
sudo -u "$SERVICE_USER" bash -lc "cd $PROJECT_DIR && bundle config"
echo

echo "=== 6. Bundle Check Status ==="
sudo -u "$SERVICE_USER" bash -lc "cd $PROJECT_DIR && bundle check" 2>&1
echo

echo "=== 7. Faraday Gem Location ==="
sudo -u "$SERVICE_USER" bash -lc "cd $PROJECT_DIR && bundle show faraday 2>/dev/null || echo 'FARADAY NOT FOUND IN BUNDLE'"
echo

echo "=== 8. All Installed Gems ==="
sudo -u "$SERVICE_USER" bash -lc "cd $PROJECT_DIR && gem list | grep -E '(faraday|puma|sinatra)'"
echo

echo "=== 9. PATH Analysis ==="
sudo -u "$SERVICE_USER" bash -lc 'echo "PATH: $PATH"'
echo

echo "=== 10. Directory Permissions ==="
ls -la "/home/$SERVICE_USER/.rbenv" 2>/dev/null || echo "rbenv directory not accessible"
ls -la "$PROJECT_DIR" | head -5
echo

echo "=== Diagnosis Complete ==="
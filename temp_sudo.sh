#!/bin/bash
# Webhook investigation script

echo "=== 1. CHECK NODE_ENV FIX IN PRODUCTION WEBHOOK CODE ==="
sudo -u kimonokittens grep -A 2 "npm ci" /home/kimonokittens/Projects/kimonokittens/deployment/scripts/webhook_puma_server.rb

echo -e "\n=== 2. WEBHOOK PROCESS ENVIRONMENT VARIABLES (FILTERED) ==="
cat /proc/27165/environ | tr '\0' '\n' | grep -E "^(RACK_ENV|NODE_ENV|PATH|WEBHOOK_|WorkingDirectory)="

echo -e "\n=== 3. KIMONOKITTENS .ENV FILE (FILTERED) ==="
sudo -u kimonokittens grep -E "^(RACK_ENV|NODE_ENV)=" /home/kimonokittens/.env

echo -e "\n=== 4. WEBHOOK SERVICE DEFINITION ==="
cat /etc/systemd/system/kimonokittens-webhook.service

echo -e "\n=== 5. MANUAL WEBHOOK TRIGGER TEST ==="
sudo -u kimonokittens curl -X POST http://localhost:49123/webhook \
  -H "Content-Type: application/json" \
  -d '{"ref":"refs/heads/master","commits":[{"modified":["test.txt"]}]}'

echo -e "\n=== INVESTIGATION COMPLETE ==="

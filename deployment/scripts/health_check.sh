#!/bin/bash

# Health check script for production monitoring

check_service() {
    if systemctl is-active --quiet "$1"; then
        echo "✓ $1 is running"
    else
        echo "✗ $1 is not running"
        systemctl restart "$1"
    fi
}

check_url() {
    if curl -f -s "$1" > /dev/null; then
        echo "✓ $1 is responding"
    else
        echo "✗ $1 is not responding"
    fi
}

echo "=== Health Check $(date) ==="

check_service kimonokittens-dashboard
check_service kimonokittens-webhook
check_service nginx

check_url http://localhost:3001/health
check_url http://localhost:9001/health
check_url http://localhost/health

# Check database
echo -n "Database: "
sudo -u kimonokittens bash -c "cd /home/kimonokittens/Projects/kimonokittens && ruby -e \"require 'dotenv/load'; require_relative 'lib/rent_db'; puts 'OK - ' + RentDb.instance.get_tenants.length.to_s + ' tenants'\"" 2>/dev/null || echo "FAILED"

echo "=== End Health Check ==="
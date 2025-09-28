# Manual Production Setup Commands

Since Claude Code can't provide sudo passwords interactively, here are the essential commands to run manually:

## 1. Install Required Packages
```bash
sudo apt update
sudo apt install -y postgresql postgresql-contrib nginx ruby ruby-dev build-essential libpq-dev chromium-browser lightdm xorg xfce4 rsync
```

## 2. Install Ruby Gems (System-wide)
```bash
sudo gem install bundler puma sinatra dotenv pg
```

## 3. Create System Users
```bash
sudo useradd -r -m -d /home/kimonokittens -s /bin/bash kimonokittens
sudo useradd -m -d /home/kiosk -s /bin/bash kiosk
sudo usermod -a -G video kiosk
```

## 4. Setup PostgreSQL Database
```bash
sudo -u postgres psql -c "CREATE USER kimonokittens WITH PASSWORD 'your_secure_password';"
sudo -u postgres createdb kimonokittens_production -O kimonokittens
```

## 5. Create Directory Structure
```bash
sudo mkdir -p /var/www/kimonokittens/dashboard
sudo mkdir -p /var/log/kimonokittens
sudo mkdir -p /home/kimonokittens/backups

# Set permissions
sudo chown -R kimonokittens:kimonokittens /home/kimonokittens
sudo chown -R www-data:www-data /var/www/kimonokittens
sudo chown kimonokittens:adm /var/log/kimonokittens
sudo chmod 755 /var/log/kimonokittens
```

## 6. Copy Project to Production Location
```bash
sudo cp -r /home/fredrik/Projects/kimonokittens /home/kimonokittens/Projects/
sudo chown -R kimonokittens:kimonokittens /home/kimonokittens/Projects/kimonokittens
```

## 7. Create Environment File
```bash
sudo -u kimonokittens tee /home/kimonokittens/.env << EOF
DATABASE_URL=postgresql://kimonokittens:your_secure_password@localhost/kimonokittens_production
NODE_ENV=production
PORT=3001
ENABLE_BROADCASTER=1
API_BASE_URL=http://localhost:3001
EOF
sudo chmod 600 /home/kimonokittens/.env
```

## 8. Install SystemD Services
```bash
sudo cp deployment/configs/systemd/*.service /etc/systemd/system/
sudo systemctl daemon-reload
```

## 9. Configure Nginx
```bash
sudo cp deployment/configs/nginx/kimonokittens.conf /etc/nginx/sites-available/
sudo ln -sf /etc/nginx/sites-available/kimonokittens.conf /etc/nginx/sites-enabled/default
sudo nginx -t
```

## 10. Configure Kiosk Mode
```bash
sudo sed -i 's/#autologin-user=/autologin-user=kiosk/' /etc/lightdm/lightdm.conf
sudo sed -i 's/#autologin-user-timeout=0/autologin-user-timeout=0/' /etc/lightdm/lightdm.conf

# Create kiosk autostart
sudo mkdir -p /home/kiosk/.config/autostart
sudo tee /home/kiosk/.config/autostart/kiosk.desktop << EOF
[Desktop Entry]
Type=Application
Name=Kiosk Browser
Exec=/bin/sleep 10 && chromium-browser --kiosk --disable-infobars --noerrdialogs --incognito --no-first-run --enable-gpu --app=http://localhost
Hidden=false
NoDisplay=false
X-GNOME-Autostart-enabled=true
EOF
sudo chown -R kiosk:kiosk /home/kiosk/.config
```

## 11. Run Database Migrations
```bash
cd /home/kimonokittens/Projects/kimonokittens
sudo -u kimonokittens npx prisma migrate deploy
sudo -u kimonokittens npx prisma generate
sudo -u kimonokittens ruby deployment/production_migration.rb
```

## 12. Deploy Dashboard
```bash
cd /home/fredrik/Projects/kimonokittens/dashboard
sudo cp -r dist/* /var/www/kimonokittens/dashboard/
sudo chown -R www-data:www-data /var/www/kimonokittens
```

## 13. Enable and Start Services
```bash
sudo systemctl enable kimonokittens-dashboard nginx
sudo systemctl start kimonokittens-dashboard nginx
```

## 14. Final Verification
```bash
# Check services
sudo systemctl status kimonokittens-dashboard nginx

# Check API
curl http://localhost:3001/api/rent/friendly_message

# Check frontend
curl http://localhost/

# Reboot for kiosk mode
sudo reboot
```

---

**After running these commands, your Dell Optiplex will be a production kiosk server!**
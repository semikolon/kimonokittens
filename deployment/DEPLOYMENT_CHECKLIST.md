# Production Deployment Checklist - September 28, 2025

## ✅ Pre-Deployment Verification (COMPLETED)

- [x] **Historical data semantic corrections**
  - Fixed `2025_08_v1.json`: month 8 → 7 (July config → August rent)
  - Fixed `2024_11_v2.json`: month 11 → 10 (October config → November rent)
  - Verified against Swish payment history (7,070 kr August payment matches)

- [x] **Database cleanup and export**
  - Removed test data from development database
  - Exported 7 RentConfig records, 8 Tenant records
  - Created production migration script

- [x] **Documentation updates**
  - Added comprehensive database setup to `DELL_OPTIPLEX_KIOSK_DEPLOYMENT.md`
  - Documented CONFIG PERIOD MONTH semantics
  - Updated process management protocols in `CLAUDE.md`

## 📦 Files to Transfer

```bash
# Core migration files
deployment/production_database_20250928.json
deployment/production_migration.rb

# Historical data (for RentLedger migration)
data/rent_history/

# Documentation
DELL_OPTIPLEX_KIOSK_DEPLOYMENT.md
CLAUDE.md

# Application code (via git)
```

## 🗄️ Database Migration (Dell Optiplex)

### Step 1: PostgreSQL Setup
```bash
sudo apt update
sudo apt install postgresql postgresql-contrib
sudo -u postgres createuser -P kimonokittens
sudo -u postgres createdb kimonokittens_production -O kimonokittens
```

### Step 2: Environment Configuration
Create `/home/kimonokittens/.env`:
```bash
DATABASE_URL=postgresql://kimonokittens:PASSWORD@localhost/kimonokittens_production
NODE_ENV=production
PORT=3001
```

### Step 3: Schema Migration
```bash
cd /home/kimonokittens
npx prisma migrate deploy
npx prisma generate
```

### Step 4: Data Import
```bash
ruby deployment/production_migration.rb
```

**Historical Data Migration**: The migration script automatically processes all JSON files in `data/rent_history/` and creates RentLedger records with:
- Corrected CONFIG PERIOD MONTH semantics (month 7 config → August rent)
- Tenant name to ID mapping for foreign key relationships
- Payment dates from calculation timestamps
- All amounts marked as fully paid for historical data

### Step 5: Verification
Expected output:
```
RentConfig: 7
Tenants: 8
RentLedger: 58 (from historical JSON files)
```

## 🚀 Application Deployment

### Process Management
Use the bin/dev system for all process management:
```bash
npm run dev          # Start all services
npm run dev:status   # Check comprehensive status
npm run dev:restart  # Clean restart (prevents cache bugs)
npm run dev:stop     # Stop all services
```

### Port Configuration
- **Backend**: 3001 (Ruby Puma + WebSocket)
- **Frontend**: 5175 (Vite dev server)
- **Production**: Nginx on port 80/443

## 🏥 Health Checks

### Database Connectivity
```bash
ruby -e "require 'dotenv/load'; require_relative 'lib/rent_db'; puts RentDb.instance.get_tenants.length"
```

### API Endpoints
```bash
curl http://localhost:3001/api/rent/friendly_message
```

### WebSocket Connection
Check browser console for WebSocket connection at `ws://localhost:3001`

## 📊 Production Data Validation

### Current Rent Calculation (September 2025)
- **Expected individual rent**: 7,045 kr per person
- **Electricity cost**: 2,424 kr (September period)
- **Data source**: "Baserad på aktuella elräkningar"

### Historical Verification
- August 2025: 7,070 kr (✅ matches Swish payment July 28)
- November 2024: 5,872 kr (✅ matches Swish payment - different from calc file)

## 🔄 Backup Strategy

### Automatic Backups
- JSON files in `data/rent_history/` serve as disaster recovery
- Use CONFIG PERIOD MONTH semantics (month 7 = August rent)
- Database is source of truth, JSON files are backup reference

### Manual Backup
```bash
# Export current state
ruby deployment/export_production_data.rb
```

## 🚨 Troubleshooting

### Common Issues
1. **Port conflicts**: Use `npm run dev:restart` for aggressive cleanup
2. **Database connection**: Verify DATABASE_URL in .env
3. **Stale processes**: Check `npm run dev:status` for orphaned processes
4. **Cache issues**: Always restart after code changes

### Emergency Recovery
1. Stop all services: `npm run dev:stop`
2. Reset database: Re-run migration script
3. Restore from JSON backup if needed
4. Restart: `npm run dev:restart`

## ✅ Deployment Sign-off

- [ ] PostgreSQL installed and configured
- [ ] Database migrated with correct data counts
- [ ] Application services running on correct ports
- [ ] API endpoints responding correctly
- [ ] WebSocket connections established
- [ ] Kiosk display showing dashboard
- [ ] Process management working (restart/status commands)

**Deployment Date**: ___________
**Deployed By**: ___________
**Verified By**: ___________
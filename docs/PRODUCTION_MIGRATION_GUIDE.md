# Production Migration Guide: Complete Rent Data System

**Date:** October 4, 2025
**Status:** Ready for execution
**Dev Migration:** ✅ Complete and verified
**Estimated Time:** 15-20 minutes
**Risk Level:** Low (full backup + rollback plan)

---

## Table of Contents

1. [Overview](#overview)
2. [Pre-Migration Checklist](#pre-migration-checklist)
3. [Migration Steps](#migration-steps)
4. [Verification](#verification)
5. [Rollback Plan](#rollback-plan)
6. [Post-Migration](#post-migration)

---

## Overview

### What This Migration Does

**Transforms data storage from files → PostgreSQL database:**

**Before:**
- 15 JSON files (rent calculation history)
- 1 text file (electricity bills)
- File parsing required for queries
- Dual maintenance burden

**After:**
- PostgreSQL single source of truth
- Complete audit trail in RentLedger (31 entries)
- Individual bill tracking in ElectricityBill (62 entries)
- Fast database queries
- Files preserved in git history only

### Components Being Migrated

1. **Schema Changes:**
   - Remove `period_month` generated column from RentConfig
   - Add 5 audit trail fields to RentLedger
   - Create ElectricityBill table

2. **Data Migrations:**
   - Populate RentLedger with historical rent data + audit trail
   - Populate ElectricityBill with individual provider bills
   - Aggregate and verify totals

3. **File Cleanup:**
   - Delete JSON files (preserved in git)
   - Delete text file (preserved in git)

---

## Pre-Migration Checklist

### ☑️ Verify Prerequisites

**On your local machine (Mac):**
```bash
# 1. Verify dev migration complete
cd ~/Projects/kimonokittens
git log --oneline -5
# Should show:
# d5eaae1 feat: electricity bill migration - text file to database
# a3e0ac3 refactor: migrate to database-only rent data - delete JSON files
# df6a8b8 feat: complete rent data migration - JSON to RentLedger audit trail
# 7cdf304 feat: extend RentLedger with audit trail fields and fix Prisma drift

# 2. Verify migration scripts exist
ls -la deployment/*migration*.rb
# Should show:
# complete_rent_data_migration.rb
# electricity_bill_migration.rb
# historical_config_migration.rb

# 3. Push to origin (if not already)
git push origin master
```

**On production kiosk:**
```bash
# SSH as kimonokittens user
ssh kimonokittens@<kiosk-ip>

# 1. Verify you're in correct directory
cd ~/Projects/kimonokittens
pwd
# Should show: /home/kimonokittens/Projects/kimonokittens

# 2. Check current git state
git status
git log --oneline -3

# 3. Verify database connection
ruby -e "require 'dotenv/load'; require_relative 'lib/rent_db'; puts 'Connected: ' + RentDb.instance.class.tenants.count.to_s + ' tenants'"
# Should show: Connected: 8 tenants
```

### ☑️ Create Backup Directory

```bash
# On production kiosk as kimonokittens user
mkdir -p ~/backups/migration_20251004
cd ~/backups/migration_20251004
```

---

## Migration Steps

### Step 1: Full Database Backup (CRITICAL)

**Time: ~30 seconds**

```bash
# On production kiosk as kimonokittens user
cd ~/backups/migration_20251004

# Create timestamped backup
timestamp=$(date +"%Y%m%d_%H%M%S")
pg_dump $DATABASE_URL > prod_db_backup_${timestamp}.sql

# Verify backup file created
ls -lh prod_db_backup_*.sql
# Should show file with size (e.g., 25K)

# Test restore capability (dry run - doesn't actually restore)
head -20 prod_db_backup_*.sql
# Should show PostgreSQL dump header and CREATE statements
```

**✅ Checkpoint:** Backup file exists and contains valid SQL

---

### Step 2: Pull Latest Code

**Time: ~10 seconds**

```bash
# On production kiosk as kimonokittens user
cd ~/Projects/kimonokittens

# Pull latest changes (includes migrations)
git pull origin master

# Verify migrations exist
ls -la deployment/*migration*.rb
ls -la prisma/migrations/20251004112744_remove_generated_column_extend_ledger/

# Verify JSON and text files are gone
ls data/rent_history/*.json 2>/dev/null || echo "✅ JSON files deleted (as expected)"
ls electricity_bills_history.txt 2>/dev/null || echo "✅ Text file deleted (as expected)"
```

**✅ Checkpoint:** Code updated, migrations present, files deleted

---

### Step 3: Schema Migration (Database Structure)

**Time: ~5 seconds**

```bash
# On production kiosk as kimonokittens user
cd ~/Projects/kimonokittens

# Apply schema migration manually (Prisma bypass due to generated column)
psql $DATABASE_URL -f prisma/migrations/20251004112744_remove_generated_column_extend_ledger/migration.sql

# Expected output:
# ALTER TABLE
# ALTER TABLE
# ALTER TABLE
# ALTER TABLE
# CREATE TABLE
# CREATE INDEX
# CREATE INDEX

# Mark migration as applied in Prisma
npx prisma migrate resolve --applied 20251004112744_remove_generated_column_extend_ledger

# Verify schema changes
ruby -e "
require 'dotenv/load'
require_relative 'lib/rent_db'
db = RentDb.instance

# Check RentLedger has new columns
schema = db.class.db.schema(:RentLedger)
puts 'RentLedger columns:'
schema.each { |col| puts \"  #{col[0]}\" }
"

# Should show new columns:
# daysStayed
# roomAdjustment
# baseMonthlyRent
# calculationTitle
# calculationDate
```

**✅ Checkpoint:** Schema updated, new columns exist

---

### Step 4: Archive Source Files (Before Migration Deletes Them)

**Time: ~5 seconds**

**IMPORTANT:** Production still has JSON and text files in git history. Archive them locally before data migration processes them.

```bash
# On production kiosk as kimonokittens user
cd ~/backups/migration_20251004

# Archive files from git history (they're deleted from working tree)
git show HEAD~3:electricity_bills_history.txt > electricity_bills_history.txt
mkdir json_files
for file in $(git ls-tree -r --name-only HEAD~3 data/rent_history/ | grep '\.json$'); do
  git show "HEAD~3:$file" > "json_files/$(basename $file)"
done

# Verify archives
ls -la json_files/
cat electricity_bills_history.txt | head -3
```

**✅ Checkpoint:** Files archived for reference

---

### Step 5: Run RentLedger Data Migration

**Time: ~10 seconds**

```bash
# On production kiosk as kimonokittens user
cd ~/Projects/kimonokittens

# Run migration (uses archived files from git history)
ruby deployment/complete_rent_data_migration.rb

# Expected output:
# ================================================================================
# COMPLETE RENT DATA MIGRATION: JSON → RentLedger Audit Trail
# ================================================================================
# ✅ Backup verified: [backup filename]
#
# 📋 Tenant mapping: Elvira, Amanda, Fredrik, Rasmus, Adam, Frans-Lukas, Malin, Astrid
#
# 📄 Processing [N] JSON files...
# ✅ Created/Updated [N] entries
#
# ================================================================================
# ✅ MIGRATION COMPLETE
# ================================================================================
#
# 📊 Statistics:
#    JSON files processed: 8
#    Ledger entries created/updated: 31
```

**✅ Checkpoint:** RentLedger populated with audit trail

---

### Step 6: Run ElectricityBill Data Migration

**Time: ~5 seconds**

```bash
# On production kiosk as kimonokittens user
cd ~/Projects/kimonokittens

# Run electricity bill migration
ruby deployment/electricity_bill_migration.rb

# Expected output:
# ================================================================================
# ELECTRICITY BILL MIGRATION: Text File → Database
# ================================================================================
#
# 📊 Processing Vattenfall bills:
# ✅ [31 bills inserted]
#
# 📊 Processing Fortum bills:
# ✅ [31 bills inserted]
#
# ================================================================================
# ✅ MIGRATION COMPLETE
# ================================================================================
#
# 📊 Statistics:
#    Vattenfall bills: 31
#    Fortum bills: 31
#    Total bills: 62
#    Total amount: 92941 kr
#
# 🔍 Verification - Compare with RentConfig:
#    2025-09: Bills 2424 kr vs Config 2424 kr ✅
#    2025-08: Bills 1738 kr vs Config 1738 kr ✅
```

**✅ Checkpoint:** ElectricityBill table populated, aggregations verified

---

## Verification

### Critical Verification Queries

**Run each query and verify results:**

```bash
# On production kiosk as kimonokittens user
cd ~/Projects/kimonokittens

# 1. Check RentLedger entry counts
ruby -e "
require 'dotenv/load'
require_relative 'lib/rent_db'
db = RentDb.instance

puts '📊 Database Counts:'
puts \"  Tenants: #{db.class.tenants.count}\"
puts \"  RentConfig: #{db.class.rent_configs.count}\"
puts \"  RentLedger: #{db.class.rent_ledger.count}\"
puts \"  ElectricityBill: #{db.class.db[:ElectricityBill].count}\"
"
# Expected:
# Tenants: 8
# RentConfig: 68
# RentLedger: 31
# ElectricityBill: 62

# 2. Verify Adam's partial month (critical test case)
ruby -e "
require 'dotenv/load'
require_relative 'lib/rent_db'
db = RentDb.instance

adam = db.class.tenants.where(name: 'Adam').first
ledger = db.class.rent_ledger.where(tenantId: adam[:id], period: Time.utc(2025, 2, 1)).first

puts '✅ Adam February 2025 (March rent):'
puts \"  Days stayed: #{ledger[:daysStayed]}\"
puts \"  Amount due: #{ledger[:amountDue]} kr\"
puts \"  Title: #{ledger[:calculationTitle]}\"
"
# Expected:
# Days stayed: 15.5
# Amount due: 4526.0 kr
# Title: March 2025 - With Adam (Exact Half Rent)

# 3. Verify electricity bill aggregation
ruby -e "
require 'dotenv/load'
require_relative 'lib/rent_db'
db = RentDb.instance

sept_bills = db.class.db[:ElectricityBill].where(billPeriod: Time.utc(2025, 9, 1))
vattenfall = sept_bills.where(provider: 'vattenfall').sum(:amount)
fortum = sept_bills.where(provider: 'fortum').sum(:amount)
total = vattenfall + fortum

config = db.class.rent_configs.where(key: 'el', period: Time.utc(2025, 9, 1)).first

puts '🔍 September 2025 Electricity:'
puts \"  Vattenfall: #{vattenfall} kr\"
puts \"  Fortum: #{fortum} kr\"
puts \"  Total: #{total} kr\"
puts \"  RentConfig: #{config[:value]} kr\"
puts \"  Match: #{total.to_i == config[:value].to_i ? '✅' : '❌'}\"
"
# Expected: All values match (2424 kr total)

# 4. Check audit trail completeness
ruby -e "
require 'dotenv/load'
require_relative 'lib/rent_db'
db = RentDb.instance

total = db.class.rent_ledger.count
with_title = db.class.rent_ledger.exclude(calculationTitle: nil).count
with_adj = db.class.rent_ledger.exclude(roomAdjustment: nil).count
with_days = db.class.rent_ledger.exclude(daysStayed: nil).count

puts '✅ Audit Trail Completeness:'
puts \"  calculationTitle: #{with_title}/#{total}\"
puts \"  roomAdjustment: #{with_adj}/#{total}\"
puts \"  daysStayed: #{with_days}/#{total} (rest implied full month)\"
"
# Expected:
# calculationTitle: 31/31
# roomAdjustment: 31/31
# daysStayed: 15/31 (rest are full months)
```

**✅ All Checks Pass?** Proceed to Step 7. **❌ Any Failures?** See [Rollback Plan](#rollback-plan).

---

### Step 7: Restart Services

**Time: ~10 seconds**

```bash
# On production kiosk

# Restart backend (picks up schema changes)
sudo systemctl restart kimonokittens-dashboard

# Wait 3 seconds
sleep 3

# Verify service healthy
sudo systemctl status kimonokittens-dashboard
# Should show: active (running)

# Test API endpoint
curl -s http://localhost:3001/api/rent/friendly_message | jq .
# Should return rent data successfully
```

**✅ Checkpoint:** Services running, API responding

---

### Step 8: Final Production Verification

```bash
# On production kiosk
cd ~/Projects/kimonokittens

# Complete verification report
ruby -e "
require 'dotenv/load'
require_relative 'lib/rent_db'

db = RentDb.instance

puts '=' * 80
puts 'PRODUCTION MIGRATION - FINAL VERIFICATION'
puts '=' * 80
puts

puts '📊 Database State:'
puts \"   Tenants: #{db.class.tenants.count}\"
puts \"   RentConfig: #{db.class.rent_configs.count}\"
puts \"   RentLedger: #{db.class.rent_ledger.count}\"
puts \"   ElectricityBill: #{db.class.db[:ElectricityBill].count}\"
puts

puts '📅 RentLedger Coverage:'
periods = db.class.rent_ledger.select(:period).distinct.order(:period).map { |r| r[:period].strftime('%Y-%m') }
puts \"   Periods: #{periods.join(', ')}\"
puts

puts '✅ Critical Checks:'
adam = db.class.tenants.where(name: 'Adam').first
adam_feb = db.class.rent_ledger.where(tenantId: adam[:id], period: Time.utc(2025, 2, 1)).first
puts \"   Adam 15.5 days: #{adam_feb[:daysStayed] == 15.5 ? '✅' : '❌'}\"

sept_total = db.class.db[:ElectricityBill].where(billPeriod: Time.utc(2025, 9, 1)).sum(:amount)
sept_config = db.class.rent_configs.where(key: 'el', period: Time.utc(2025, 9, 1)).first[:value].to_i
puts \"   Sept bills match: #{sept_total == sept_config ? '✅' : '❌'}\"

puts
puts '=' * 80
puts '✅ PRODUCTION MIGRATION COMPLETE'
puts '=' * 80
"
```

**Expected Output:**
```
================================================================================
PRODUCTION MIGRATION - FINAL VERIFICATION
================================================================================

📊 Database State:
   Tenants: 8
   RentConfig: 68
   RentLedger: 31
   ElectricityBill: 62

📅 RentLedger Coverage:
   Periods: 2024-11, 2025-01, 2025-02, 2025-03, 2025-04, 2025-05, 2025-08

✅ Critical Checks:
   Adam 15.5 days: ✅
   Sept bills match: ✅

================================================================================
✅ PRODUCTION MIGRATION COMPLETE
================================================================================
```

---

## Rollback Plan

**If anything goes wrong during migration:**

### Immediate Rollback (Restores Database)

```bash
# On production kiosk as kimonokittens user
cd ~/backups/migration_20251004

# Find latest backup
ls -lth prod_db_backup_*.sql | head -1

# Restore database (CAREFUL - this overwrites current state)
psql $DATABASE_URL < prod_db_backup_TIMESTAMP.sql

# Restart services
sudo systemctl restart kimonokittens-dashboard

# Verify restoration
ruby -e "require 'dotenv/load'; require_relative 'lib/rent_db'; puts RentDb.instance.class.tenants.count.to_s + ' tenants'"
# Should show: 8 tenants
```

**Time to restore: ~30 seconds**

### Git Rollback (Restores Code)

```bash
# On production kiosk as kimonokittens user
cd ~/Projects/kimonokittens

# Revert last 4 commits
git revert --no-commit HEAD~4..HEAD
git commit -m "Rollback: Revert rent data migration"

# Restore files from git history
git checkout HEAD~4 -- data/rent_history/
git checkout HEAD~4 -- electricity_bills_history.txt
git commit -m "Restore: JSON and text files"

# Restart services
sudo systemctl restart kimonokittens-dashboard
```

**Time to rollback code: ~1 minute**

---

## Post-Migration

### ✅ Immediate Actions (After Verification)

1. **Document completion:**
   ```bash
   # On production kiosk
   echo "$(date): Production migration complete" >> ~/backups/migration_20251004/COMPLETION.log
   ```

2. **Monitor logs for 24 hours:**
   ```bash
   # Check backend logs
   journalctl -u kimonokittens-dashboard -f

   # Check for errors
   journalctl -u kimonokittens-dashboard --since "1 hour ago" | grep -i error
   ```

3. **Verify kiosk display:**
   - Check rent amounts shown on kiosk screen
   - Verify no visual regressions

### 🔮 Future Enhancements (Not Part of This Migration)

1. **Update rent.rb to save to database:**
   - Modify `calculate_and_save` method
   - Write to RentLedger + RentConfig directly
   - Remove JSON file creation

2. **API automation for electricity bills:**
   - Integrate with Vattenfall/Fortum APIs
   - Auto-populate ElectricityBill table
   - Deprecate manual text file updates

3. **Dashboard enhancements:**
   - Payment tracking UI
   - Historical rent visualization
   - Audit trail queries

---

## Summary

**Migration achieves:**
- ✅ Single source of truth: PostgreSQL
- ✅ Complete audit trail (who paid what, why)
- ✅ Individual bill tracking (62 bills)
- ✅ Fast database queries (no file parsing)
- ✅ Clean codebase (no dual systems)
- ✅ Full disaster recovery (git history + database backup)

**Estimated total time: 15-20 minutes**

**Risk level: Low**
- Full backup before any changes
- Tested in dev environment
- Step-by-step verification
- Complete rollback plan

---

**Ready to proceed? Follow steps 1-8 in order, verifying each checkpoint.**

-- Schema Migration: RentConfig Composite Key Implementation
-- Based on GPT-5 recommendations for temporal configuration data
--
-- This migration enables proper temporal modeling while maintaining performance
-- and data integrity for the rent calculation system.

BEGIN;

-- Step 1: Add generated month column for month-level uniqueness
-- This ensures one configuration per key per month (business requirement)
ALTER TABLE "RentConfig"
  ADD COLUMN period_month date GENERATED ALWAYS AS (date_trunc('month', period)::date) STORED;

-- Step 2: Create unique constraint on (key, period_month)
-- Prevents contamination: no duplicate configs for same key in same month
CREATE UNIQUE INDEX IF NOT EXISTS rentconfig_key_period_month_uniq
  ON "RentConfig"(key, period_month);

-- Step 3: Add performance index for persistent key lookups
-- Optimizes "most recent value <= target month" queries
CREATE INDEX IF NOT EXISTS rentconfig_key_period_desc_idx
  ON "RentConfig"(key, period DESC);

-- Step 4: Drop the problematic old unique constraint
-- This was preventing multiple periods per key
ALTER TABLE "RentConfig" DROP CONSTRAINT IF EXISTS "RentConfig_key_key";

-- Step 5: Add safety constraint to ensure periods are month-start normalized
-- Prevents accidental mid-month timestamps that break exact matching
ALTER TABLE "RentConfig"
  ADD CONSTRAINT period_is_month_start
  CHECK (date_trunc('month', period) = period);

-- Verification queries (run after migration)
-- Check that all existing data passes the new constraints
-- SELECT key, period, period_month, date_trunc('month', period) = period AS is_normalized
-- FROM "RentConfig"
-- ORDER BY key, period;

COMMIT;
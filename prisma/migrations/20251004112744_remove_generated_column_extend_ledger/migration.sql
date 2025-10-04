-- Remove generated column and use normalized period directly
-- This eliminates Prisma migration drift issues with GENERATED ALWAYS AS columns

-- Drop old unique constraint that used period_month
ALTER TABLE "RentConfig" DROP CONSTRAINT IF EXISTS "rentconfig_key_period_month_uniq";

-- Drop the generated period_month column
-- Note: Generated columns require DROP EXPRESSION, not DROP DEFAULT
ALTER TABLE "RentConfig" DROP COLUMN "period_month";

-- Add new unique constraint on [key, period]
-- This works because application normalizes period to YYYY-MM-01 00:00:00
ALTER TABLE "RentConfig" ADD CONSTRAINT "RentConfig_key_period_key" UNIQUE ("key", "period");

-- Add audit trail fields to RentLedger (immutable ledger pattern)
ALTER TABLE "RentLedger" ADD COLUMN "daysStayed" DOUBLE PRECISION;
ALTER TABLE "RentLedger" ADD COLUMN "roomAdjustment" DOUBLE PRECISION;
ALTER TABLE "RentLedger" ADD COLUMN "baseMonthlyRent" DOUBLE PRECISION;
ALTER TABLE "RentLedger" ADD COLUMN "calculationTitle" TEXT;
ALTER TABLE "RentLedger" ADD COLUMN "calculationDate" TIMESTAMP(3);

-- Create ElectricityBill table for text file migration
CREATE TABLE "ElectricityBill" (
    "id" TEXT NOT NULL,
    "provider" TEXT NOT NULL,
    "billDate" TIMESTAMP(3) NOT NULL,
    "amount" DOUBLE PRECISION NOT NULL,
    "billPeriod" TIMESTAMP(3) NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "ElectricityBill_pkey" PRIMARY KEY ("id")
);

-- Create indexes for ElectricityBill
CREATE INDEX "ElectricityBill_provider_billPeriod_idx" ON "ElectricityBill"("provider", "billPeriod" DESC);
CREATE INDEX "ElectricityBill_billDate_idx" ON "ElectricityBill"("billDate" DESC);

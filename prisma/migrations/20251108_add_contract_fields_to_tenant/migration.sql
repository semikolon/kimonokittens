-- Add contract-required fields to Tenant table

-- Personal identification (CRITICAL for legal contracts)
ALTER TABLE "Tenant" ADD COLUMN "personnummer" TEXT;

-- Contact information
ALTER TABLE "Tenant" ADD COLUMN "phone" TEXT;

-- Financial terms
ALTER TABLE "Tenant" ADD COLUMN "baseRent" DECIMAL(10,2);
ALTER TABLE "Tenant" ADD COLUMN "deposit" DECIMAL(10,2);
ALTER TABLE "Tenant" ADD COLUMN "furnishingDeposit" DECIMAL(10,2);

-- Status tracking
ALTER TABLE "Tenant" ADD COLUMN "status" TEXT DEFAULT 'active';

-- Add constraints after data migration
-- ALTER TABLE "Tenant" ALTER COLUMN "personnummer" SET NOT NULL;
-- ALTER TABLE "Tenant" ALTER COLUMN "phone" SET NOT NULL;

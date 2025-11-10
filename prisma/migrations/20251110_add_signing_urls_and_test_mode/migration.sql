-- Add signing URLs and test mode to SignedContract table
-- Enables SMS reminders, dashboard QR codes, and test/production distinction

ALTER TABLE "SignedContract"
  ADD COLUMN "landlordSigningUrl" TEXT,
  ADD COLUMN "tenantSigningUrl" TEXT,
  ADD COLUMN "testMode" BOOLEAN NOT NULL DEFAULT false;

-- Comment for clarity
COMMENT ON COLUMN "SignedContract"."landlordSigningUrl" IS 'One-time signing URL for landlord (expires after 14 days)';
COMMENT ON COLUMN "SignedContract"."tenantSigningUrl" IS 'One-time signing URL for tenant (expires after 14 days)';
COMMENT ON COLUMN "SignedContract"."testMode" IS 'True if contract was created in Zigned test mode (invalid signatures)';
